// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ------------------------------------ //
//           CUSTOM ERRORS              //
// ------------------------------------ //

/// @notice Thrown when caller is not the owner
error OnlyOwner();

/// @notice Thrown when function is called in a reentrant manner
error ReentrantCall();

/// @notice Thrown when pre-execution hook fails
error PreHookFailed();

/// @notice Thrown when post-execution hook fails
error PostHookFailed();

/// @notice Thrown when address is zero
error ZeroAddress();

/// @notice Thrown when array lengths do not match
error LengthMismatch();

/// @notice Thrown when batch size is invalid
error InvalidBatchSize();

/// @notice Thrown when transaction has expired
error Expired();

/// @notice Thrown when signature is invalid
error InvalidSignature();

/// @notice Thrown when external call fails
error CallFailed();

/// @notice Thrown when insufficient fee balance
error InsufficientFee();

/// @notice Thrown when fee transfer fails
error FeeTransferFailed();

/// @notice Thrown when module has no code
error ModuleIsNotAContract();

// ------------------------------------ //
//           INTERFACES                 //
// ------------------------------------ //

/// @notice Execution‑time guard called before and after a batch.
interface IPolicyModule {
    function preCheck(
        address sender,
        bytes calldata rawData
    ) external view returns (bool);
    function postCheck(
        address sender,
        bytes calldata rawData
    ) external view returns (bool);
}

/// @notice Alternate signature authority.
interface IRecoveryModule {
    function isValidSignature(
        bytes32 hash,
        bytes calldata sig
    ) external view returns (bytes4);
}

/// @title Minimal Avatar Smart Wallet (MASW) with policy module hooks
/// @author MASW Team
/// @notice A smart contract wallet that supports batch execution, meta-transactions, and pluggable ownership
/// @dev This contract implements ERC-721 and ERC-1155 receiver interfaces and supports EIP-712 for meta-transactions
contract MASW is IERC721Receiver, IERC1155Receiver {
    using ECDSA for bytes32;

    // ------------------------------------ //
    //           STORAGE LAYOUT             //
    // ------------------------------------ //

    /// @notice The immutable owner address set at deployment
    address public immutable owner;

    /// @notice EIP-712 domain separator for meta-transaction signatures
    bytes32 public immutable DOMAIN_SEPARATOR;

    /// @notice Current meta-transaction nonce to prevent replay attacks
    uint256 public metaNonce;

    /// @notice Reentrancy guard flag
    uint256 private _entered;

    /// @notice Optional pluggable policy module (can be zero (disabled))
    address public policyModule;

    /// @notice Optional pluggable recovery module (can be zero (disabled))
    address public recoveryModule;

    // ------------------------------------ //
    //           CONSTANTS                  //
    // ------------------------------------ //

    /// @notice EIP-712 typehash for batch execution
    bytes32 private constant _BATCH_TYPEHASH =
        keccak256(
            "Batch(address[] targets,uint256[] values,bytes[] calldatas,address token,uint256 fee,uint256 exp,uint256 metaNonce)"
        );

    // ------------------------------------ //
    //           EVENTS                     //
    // ------------------------------------ //

    /// @notice Emitted when a module is changed
    /// @param kind The type of module (POLICY or RECOVERY)
    /// @param oldModule The previous module address
    /// @param newModule The new module address
    event ModuleChanged(
        bytes32 indexed kind,
        address oldModule,
        address newModule
    );

    /// @notice Emitted when a batch of transactions is executed
    /// @param structHash The hash of the executed batch structure
    event BatchExecuted(bytes32 indexed structHash);

    // ------------------------------------ //
    //           MODIFIERS                  //
    // ------------------------------------ //

    /// @notice Restricts access to the owner only
    modifier onlyOwner() {
        // This can be passed by both the canonical EOA and any valid signer from the recovery module
        // if they call it through executeBatch (which is already signature-checked)
        require(msg.sender == owner, OnlyOwner());
        _;
    }

    /// @notice Prevents reentrancy attacks
    modifier nonReentrant() {
        require(_entered == 0, ReentrantCall());
        _entered = 1;
        _;
        _entered = 0;
    }

    /// @notice Applies policy module pre and post execution hooks if policy module is set
    modifier policyCheck() {
        address _policyModule = policyModule;
        if (_policyModule != address(0)) {
            require(
                IPolicyModule(_policyModule).preCheck(msg.sender, msg.data),
                PreHookFailed()
            );
            _;
            require(
                IPolicyModule(_policyModule).postCheck(msg.sender, msg.data),
                PostHookFailed()
            );
        } else {
            _;
        }
    }

    // ------------------------------------ //
    //           CONSTRUCTOR                //
    // ------------------------------------ //

    /// @notice Initializes the wallet with owner
    /// @param _owner The address that will own this wallet
    /// @dev Sets up EIP-712 domain separator for meta-transaction signatures
    constructor(address _owner) {
        require(_owner != address(0), ZeroAddress());
        owner = _owner;
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("MASW")),
                keccak256(bytes("1")),
                block.chainid,
                _owner
            )
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                             ADMIN FUNCTIONS                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Sets the policy module for the wallet
    /// @param newModule Address of the new policy module (zero address to disable)
    /// @dev Only callable by the wallet owner
    function setPolicyModule(address newModule) external onlyOwner {
        if (newModule != address(0)) {
            require(newModule.code.length != 0, ModuleIsNotAContract());
        }
        emit ModuleChanged(keccak256("POLICY"), policyModule, newModule);
        policyModule = newModule; // zero disables
    }

    /// @notice Sets the recovery module for the wallet
    /// @param newModule Address of the new recovery module (zero address to disable)
    /// @dev Only callable by the wallet owner
    function setRecoveryModule(address newModule) external onlyOwner {
        if (newModule != address(0)) {
            require(newModule.code.length != 0, ModuleIsNotAContract());
        }
        emit ModuleChanged(keccak256("RECOVERY"), recoveryModule, newModule);
        recoveryModule = newModule; // zero disables
    }

    // ------------------------------------ //
    //           EXTERNAL FUNCTIONS         //
    // ------------------------------------ //

    /// @notice Executes a batch of transactions with meta-transaction support
    /// @param targets Array of target contract addresses
    /// @param values Array of ETH values to send with each call
    /// @param calldatas Array of calldata for each transaction
    /// @param token Address of token to pay fees with (zero address for ETH)
    /// @param fee Amount of fee to pay the relayer
    /// @param exp Expiration timestamp for the meta-transaction
    /// @param signature EIP-712 signature authorizing the batch execution
    /// @dev Validates signature, executes calls, and pays relayer fee
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        address token,
        uint256 fee,
        uint256 exp,
        bytes calldata signature
    ) external payable nonReentrant {
        // Validate inputs
        require(targets.length > 0, InvalidBatchSize());
        require(
            targets.length == values.length &&
                values.length == calldatas.length,
            LengthMismatch()
        );
        require(block.timestamp <= exp, Expired());

        // Build EIP-712 structure hash
        bytes32 structHash = keccak256(
            abi.encode(
                _BATCH_TYPEHASH,
                _hashAddressArray(targets),
                _hashUint256Array(values),
                _hashBytesArray(calldatas),
                token,
                fee,
                exp,
                metaNonce
            )
        );

        // Validate signature
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        require(_isValidSig(digest, signature), InvalidSignature());

        // Increment nonce after validation to prevent griefing
        metaNonce++;

        // Execute batch with policy module checks
        _executeBatch(targets, values, calldatas, token, fee);

        // Emit event after successful execution
        emit BatchExecuted(structHash);
    }

    // ------------------------------------ //
    //           INTERNAL FUNCTIONS         //
    // ------------------------------------ //

    /// @notice Internal function that executes the batch with policy module checks
    /// @param targets Array of target contract addresses
    /// @param values Array of ETH values to send with each call
    /// @param calldatas Array of calldata for each transaction
    /// @param token Address of token to pay fees with (zero address for ETH)
    /// @param fee Amount of fee to pay the relayer
    function _executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas,
        address token,
        uint256 fee
    ) internal policyCheck {
        // Execute all calls in the batch
        for (uint256 i; i < targets.length; ++i) {
            (bool success, ) = targets[i].call{value: values[i]}(calldatas[i]);
            require(success, CallFailed());
        }

        // Skip fee payment if no fee required
        if (fee == 0) return;

        // Pay relayer fee
        if (token == address(0)) {
            // Pay with ETH
            require(address(this).balance >= fee, InsufficientFee());
            (bool sent, ) = msg.sender.call{value: fee}("");
            require(sent, FeeTransferFailed());
        } else {
            // Pay with ERC-20 token
            (bool ok, bytes memory data) = token.call(
                abi.encodeWithSelector(
                    IERC20.transfer.selector,
                    msg.sender,
                    fee
                )
            );
            require(
                ok && (data.length == 0 || abi.decode(data, (bool))),
                FeeTransferFailed()
            );
        }
    }

    /// @notice Validates a signature using either ECDSA or the recovery module
    /// @param digest The hash that was signed
    /// @param sig The signature to validate
    /// @return valid Whether the signature is valid
    function _isValidSig(
        bytes32 digest,
        bytes memory sig
    ) internal view returns (bool) {
        address module = recoveryModule;
        if (module == address(0)) {
            // Use ECDSA recovery with immutable owner
            return digest.recover(sig) == owner;
        }

        // Use recovery module for validation
        return
            IRecoveryModule(module).isValidSignature(digest, sig) == 0x1626ba7e;
    }

    /// @notice Helper function to properly hash address arrays for EIP-712 compliance
    /// @param array The address array to hash
    /// @return The EIP-712 compliant hash of the array
    function _hashAddressArray(
        address[] calldata array
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(array));
    }

    /// @notice Helper function to properly hash uint256 arrays for EIP-712 compliance
    /// @param array The uint256 array to hash
    /// @return The EIP-712 compliant hash of the array
    function _hashUint256Array(
        uint256[] calldata array
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(array));
    }

    /// @notice Helper function to properly hash bytes arrays for EIP-712 compliance
    /// @param array The bytes array to hash
    /// @return The EIP-712 compliant hash of the array
    function _hashBytesArray(
        bytes[] calldata array
    ) internal pure returns (bytes32) {
        bytes32[] memory hashedItems = new bytes32[](array.length);
        for (uint256 i = 0; i < array.length; ++i) {
            hashedItems[i] = keccak256(array[i]);
        }
        return keccak256(abi.encodePacked(hashedItems));
    }

    // ------------------------------------ //
    //           TOKEN RECEIVERS            //
    // ------------------------------------ //

    /// @notice Handles the receipt of an ERC-721 token
    /// @return The selector to confirm token transfer
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @notice Handles the receipt of a single ERC-1155 token
    /// @return The selector to confirm token transfer
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice Handles the receipt of multiple ERC-1155 tokens
    /// @return The selector to confirm token transfer
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    // ------------------------------------ //
    //           INTERFACE SUPPORT          //
    // ------------------------------------ //

    /// @notice Checks if the contract implements an interface
    /// @param interfaceId The interface identifier to check
    /// @return Whether the interface is supported
    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }

    /// @notice Allows the contract to receive native token
    receive() external payable {}
}
