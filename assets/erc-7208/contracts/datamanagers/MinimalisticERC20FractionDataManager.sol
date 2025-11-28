// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IDataIndex} from "../interfaces/IDataIndex.sol";
import {IDataObject} from "../interfaces/IDataObject.sol";
import {IFungibleFractionsOperations} from "../interfaces/IFungibleFractionsOperations.sol";
import {IFractionTransferEventEmitter} from "../interfaces/IFractionTransferEventEmitter.sol";
import {DataPoint} from "../utils/DataPoints.sol";

/**
 * @title Minimalistic ERC20 Fraction Data Manager
 * @notice Contract for managing ERC20 fractions of an ERC1155 token
 * @dev This contract is used to manage fractions of a MinimalisticERC1155WithERC20FractionsDataManager
 *      contract as a ERC20 token, exposing the ERC20 functionalities and emitting the Transfer event.
 *      NOTE: This implementation is minimalistic and does not include minting and burning functionalities.
 */
contract MinimalisticERC20FractionDataManager is Initializable, IFractionTransferEventEmitter, IERC20, IERC20Metadata, IERC20Errors, OwnableUpgradeable {
    /// @dev Decimals for the ERC20 token (set to 0)
    uint8 private constant DECIMALS = 0;

    /// @dev Error thrown when one or more parameters are wrong
    error WrongParams();

    /// @dev Error thrown when the contract is not initialized
    error ContractNotInitialized();

    /// @dev DataPoint used in the fungibleFractions data object
    DataPoint internal _datapoint;

    /// @dev Fungible Fractions Data Object contract
    IDataObject public fungibleFractionsDO;

    /// @dev Data Index implementation
    IDataIndex public dataIndex;

    /// @dev ERC1155 data manager contract
    address public erc1155dm;

    /// @dev ERC1155 token ID
    uint256 public erc1155ID;

    /// @dev ERC20 token name
    string private _name;

    /// @dev ERC20 token symbol
    string private _symbol;

    /// @dev Struct to store the amount of an allowance
    struct AllowanceAmount {
        uint256 amount;
    }

    /// @dev Mapping of allowances from user to spender to AllowanceAmount
    mapping(address account => mapping(address spender => AllowanceAmount)) private _allowances;

    /// @notice Modifier to check if the caller is the ERC1155 data manager
    modifier onlyTransferNotifier() {
        if (_msgSender() != erc1155dm) revert WrongTransferNotificationSource();
        _;
    }

    /// @dev Initializes the ERC20 Fraction Data Manager
    function initialize(
        bytes32 datapoint_,
        address dataIndex_,
        address fungibleFractionsDO_,
        address erc1155dm_,
        uint256 erc1155ID_,
        string memory name_,
        string memory symbol_
    ) external initializer {
        __Ownable_init_unchained(_msgSender());
        __MinimalisticERC20FractionDataManager_init_unchained(datapoint_, dataIndex_, fungibleFractionsDO_, erc1155dm_, erc1155ID_, name_, symbol_);
    }

    function __MinimalisticERC20FractionDataManager_init_unchained(
        bytes32 datapoint_,
        address dataIndex_,
        address fungibleFractionsDO_,
        address erc1155dm_,
        uint256 erc1155ID_,
        string memory name_,
        string memory symbol_
    ) internal onlyInitializing {
        if (datapoint_ == bytes32(0) || dataIndex_ == address(0) || fungibleFractionsDO_ == address(0) || erc1155dm_ == address(0)) {
            revert WrongParams();
        }

        _datapoint = DataPoint.wrap(datapoint_);
        dataIndex = IDataIndex(dataIndex_);
        fungibleFractionsDO = IDataObject(fungibleFractionsDO_);
        erc1155dm = erc1155dm_;
        erc1155ID = erc1155ID_;
        _name = name_;
        _symbol = symbol_;
    }

    /// @notice ERC20 token decimals
    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    /// @notice ERC20 token name
    function name() external view returns (string memory) {
        return _name;
    }

    /// @notice ERC20 token symbol
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @notice Total supply of the ERC20 token
     * @return The amount of ERC20 tokens in circulation
     * @dev This function reads the total supply from the fungible fractions data object
     *      NOTE: This total supply is equal to the amount of fractions of the ERC1155 token with the id `erc1155ID`
     */
    function totalSupply() external view override returns (uint256) {
        if (address(fungibleFractionsDO) == address(0)) revert ContractNotInitialized();
        return abi.decode(fungibleFractionsDO.read(_datapoint, IFungibleFractionsOperations.totalSupply.selector, abi.encode(erc1155ID)), (uint256));
    }

    /**
     * @notice Balance of an account
     * @param account The account to check the balance of
     * @return The amount of ERC20 tokens the account has
     * @dev This function reads the balance of the account from the fungible fractions data object
     *      NOTE: This balance is equal to the amount of fractions of the ERC1155 token with the id `erc1155ID` the account has
     */
    function balanceOf(address account) external view override returns (uint256) {
        if (address(fungibleFractionsDO) == address(0)) revert ContractNotInitialized();
        return abi.decode(fungibleFractionsDO.read(_datapoint, IFungibleFractionsOperations.balanceOf.selector, abi.encode(account, erc1155ID)), (uint256));
    }

    /// @dev Function only callable by the ERC1155 data manager to notify a fraction transfer
    function fractionTransferredNotify(address from, address to, uint256 amount) external onlyTransferNotifier {
        emit Transfer(from, to, amount);
    }

    /**
     * @notice Allowance of a spender to spend tokens on behalf of an owner
     * @param owner_ The owner of the tokens
     * @param spender The spender of the tokens
     * @return The amount of tokens the spender is allowed to spend
     */
    function allowance(address owner_, address spender) public view returns (uint256) {
        return _allowances[owner_][spender].amount;
    }

    /**
     * @notice Approve a spender to spend a certain amount of tokens on behalf of the caller
     * @param spender The address of the spender
     * @param value The amount of tokens the spender is allowed to spend
     * @return True if the approval was successful
     */
    function approve(address spender, uint256 value) public returns (bool) {
        if (_msgSender() == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[_msgSender()][spender].amount = value;
        emit Approval(_msgSender(), spender, value);
        return true;
    }

    /**
     * @notice Transfer tokens to a specified recipient
     * @param to The recipient of the tokens
     * @param amount The amount of tokens to transfer
     * @return True if the transfer was successful
     * @dev This function performs a transfer operation executing the transfer in the fungible fractions data object
     *      NOTE: This function does not allow transfers to the zero address
     */
    function transfer(address to, uint256 amount) external virtual override returns (bool) {
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _beforeTokenTransfer(_msgSender(), to, amount);

        _writeTransfer(_msgSender(), to, amount);

        emit Transfer(_msgSender(), to, amount);
        return true;
    }

    /**
     * @notice Transfer tokens from one account to another
     * @param from The account to transfer tokens from
     * @param to The account to transfer tokens to
     * @param amount The amount of tokens to transfer
     * @return True if the transfer was successful
     * @dev This function performs a transferFrom operation executing the transferFrom in the fungible fractions data object
     *      NOTE: This function does not allow transfers from or to the zero address
     */
    function transferFrom(address from, address to, uint256 amount) external virtual override returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }

        _writeTransfer(from, to, amount);

        emit Transfer(from, to, amount);
        return true;
    }

    function _spendAllowance(address owner_, address spender, uint256 amount) internal {
        AllowanceAmount storage currentAllowance = _allowances[owner_][spender];
        uint256 currentAllowanceAmount = currentAllowance.amount;
        if (currentAllowanceAmount != type(uint256).max) {
            if (currentAllowanceAmount < amount) {
                revert ERC20InsufficientAllowance(spender, currentAllowanceAmount, amount);
            }
            unchecked {
                currentAllowance.amount = currentAllowanceAmount - amount;
            }
        }
    }

    function _writeTransfer(address from, address to, uint256 amount) internal {
        if (address(dataIndex) == address(0)) revert ContractNotInitialized();

        // In this contract `_writeTransfer()` can not be called with zero `from` or `to` arguments, but if it is changed to allow mint/burn, this is how this operations should be called:
        // dataIndex.write(fungibleFractionsDO, _datapoint, IFungibleFractionsOperations.mint.selector, abi.encode(to, erc1155ID, amount));
        // dataIndex.write(fungibleFractionsDO, _datapoint, IFungibleFractionsOperations.burn.selector, abi.encode(from, erc1155ID, amount));

        dataIndex.write(fungibleFractionsDO, _datapoint, IFungibleFractionsOperations.transferFrom.selector, abi.encode(from, to, erc1155ID, amount));

        IFractionTransferEventEmitter(erc1155dm).fractionTransferredNotify(from, to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}