// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC1404} from "./IERC1404.sol";

/// @title ERC1404 — Whitelist-based reference implementation of EIP-1404.
///
/// Restriction codes:
///   0  No restriction
///   1  Sender not whitelisted
///   2  Recipient not whitelisted
/// Restriction codes 1 and 2 are not include in ERC-1404
contract ERC1404 is ERC20, ERC165, Ownable, IERC1404 {
    /**
     * @notice Restriction code meaning the transfer is unrestricted.
     */
    uint8 public constant TRANSFER_OK = 0;
    /**
     * @notice Restriction code returned when the sender is not whitelisted.
     */
    uint8 public constant SENDER_NOT_WHITELISTED = 1;
    /**
     * @notice Restriction code returned when the recipient is not whitelisted.
     */
    uint8 public constant RECIPIENT_NOT_WHITELISTED = 2;

    /**
     * @notice Human-readable message for `TRANSFER_OK`.
     */
    string public constant MESSAGE_TRANSFER_OK = "No restriction";
    /**
     * @notice Human-readable message for `SENDER_NOT_WHITELISTED`.
     */
    string public constant MESSAGE_SENDER_NOT_WHITELISTED = "Sender not whitelisted";
    /**
     * @notice Human-readable message for `RECIPIENT_NOT_WHITELISTED`.
     */
    string public constant MESSAGE_RECIPIENT_NOT_WHITELISTED = "Recipient not whitelisted";
    /**
     * @notice Human-readable message returned for any unrecognised restriction code.
     */
    string public constant MESSAGE_UNKNOWN_RESTRICTION = "Unknown restriction code";

    /**
     * @notice ERC-165 interface id advertised for ERC-1404.
     * @dev bytes4(keccak256("detectTransferRestriction(address,address,uint256)"))
     *   XOR bytes4(keccak256("messageForTransferRestriction(uint8)"))
     */
    bytes4 private constant _INTERFACE_ID_ERC1404 = 0xab84a5c8;

    /**
     * @notice Whitelist status of each address; true means the address may send and receive.
     */
    mapping(address => bool) public whitelist;

    /**
     * @notice Thrown when a transfer is blocked by the whitelist policy.
     * @param code Restriction code returned by `detectTransferRestriction`.
     * @param message Human-readable explanation of the restriction.
     */
    error TransferRestricted(uint8 code, string message);
    /**
     * @notice Thrown when the zero address is supplied where it is not allowed.
     */
    error AddressZeroNotAllowed();

    /**
     * @notice Emitted when an account's whitelist status changes.
     * @param account Address whose whitelist status changed.
     * @param status New whitelist status.
     */
    event WhitelistUpdated(address indexed account, bool status);

    /**
     * @notice Deploys the token, whitelists the deployer and mints the initial supply to it.
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     * @param initialSupply Amount minted to the deployer at construction.
     */
    constructor(string memory name_, string memory symbol_, uint256 initialSupply)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        whitelist[msg.sender] = true;
        _mint(msg.sender, initialSupply);
    }

    // -------------------------------------------------------------------------
    // Whitelist management
    // -------------------------------------------------------------------------

    /**
     * @notice Add or remove `account` from the transfer whitelist.
     * @param account Address whose whitelist status is being set.
     * @param status True to whitelist, false to remove.
     */
    function setWhitelisted(address account, bool status) external onlyOwner {
        if (account == address(0)) revert AddressZeroNotAllowed();
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    // -------------------------------------------------------------------------
    // Mint / burn
    // -------------------------------------------------------------------------

    /**
     * @notice Mint `amount` tokens to a whitelisted `to` address.
     * @param to Recipient of the newly minted tokens; must be whitelisted.
     * @param amount Amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        if (!whitelist[to]) revert TransferRestricted(RECIPIENT_NOT_WHITELISTED, MESSAGE_RECIPIENT_NOT_WHITELISTED);
        _mint(to, amount);
    }

    /**
     * @notice Burn `amount` tokens from a whitelisted `from` address.
     * @param from Holder whose tokens are burned; must be whitelisted.
     * @param amount Amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        if (!whitelist[from]) revert TransferRestricted(SENDER_NOT_WHITELISTED, MESSAGE_SENDER_NOT_WHITELISTED);
        _burn(from, amount);
    }

    // -------------------------------------------------------------------------
    // ERC-20 overrides — enforce restrictions on every transfer
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc IERC20
     */
    function transfer(address to, uint256 value) public virtual override(ERC20, IERC20) returns (bool) {
        _checkRestriction(msg.sender, to, value);
        return super.transfer(to, value);
    }

    /**
     * @inheritdoc IERC20
     */
    function transferFrom(address from, address to, uint256 value) public virtual override(ERC20, IERC20) returns (bool) {
        _checkRestriction(from, to, value);
        return super.transferFrom(from, to, value);
    }

    // -------------------------------------------------------------------------
    // ERC-1404
    // -------------------------------------------------------------------------

    /**
     * @notice Returns a restriction code for the proposed transfer, or 0 if unrestricted.
     * @dev `value` is unused in this implementation; override to add amount-based restrictions.
     * @param from Sender address.
     * @param to Recipient address.
     * @return Restriction code; 0 means the transfer is allowed.
     */
    function detectTransferRestriction(
        address from,
        address to,
        uint256 /*value*/
    )
        public
        view
        virtual
        override
        returns (uint8)
    {
        if (!whitelist[from]) return SENDER_NOT_WHITELISTED;
        if (!whitelist[to]) return RECIPIENT_NOT_WHITELISTED;
        return TRANSFER_OK;
    }

    /**
     * @notice Returns the human-readable message for a restriction code.
     * @param restrictionCode Code returned by `detectTransferRestriction`.
     * @return Human-readable description of the restriction.
     */
    function messageForTransferRestriction(uint8 restrictionCode) public pure virtual override returns (string memory) {
        if (restrictionCode == TRANSFER_OK) return MESSAGE_TRANSFER_OK;
        if (restrictionCode == SENDER_NOT_WHITELISTED) return MESSAGE_SENDER_NOT_WHITELISTED;
        if (restrictionCode == RECIPIENT_NOT_WHITELISTED) return MESSAGE_RECIPIENT_NOT_WHITELISTED;
        return MESSAGE_UNKNOWN_RESTRICTION;
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    /**
     * @notice Returns true if the contract implements `interfaceId`, including the ERC-1404 id.
     * @param interfaceId Interface identifier, as defined in ERC-165.
     * @return True if the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165) returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC1404 || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    /**
     * @notice Reverts with `TransferRestricted` if the proposed transfer is not allowed.
     * @param from Sender address.
     * @param to Recipient address.
     * @param value Token amount to transfer.
     */
    function _checkRestriction(address from, address to, uint256 value) internal view {
        uint8 code = detectTransferRestriction(from, to, value);
        if (code != TRANSFER_OK) {
            revert TransferRestricted(code, messageForTransferRestriction(code));
        }
    }
}
