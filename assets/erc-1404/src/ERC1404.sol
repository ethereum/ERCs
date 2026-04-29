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
    uint8 public constant TRANSFER_OK = 0;
    uint8 public constant SENDER_NOT_WHITELISTED = 1;
    uint8 public constant RECIPIENT_NOT_WHITELISTED = 2;

    string public constant MESSAGE_TRANSFER_OK = "No restriction";
    string public constant MESSAGE_SENDER_NOT_WHITELISTED = "Sender not whitelisted";
    string public constant MESSAGE_RECIPIENT_NOT_WHITELISTED = "Recipient not whitelisted";
    string public constant MESSAGE_UNKNOWN_RESTRICTION = "Unknown restriction code";

    // ERC-165 interface ID for ERC-1404: bytes4(keccak256("detectTransferRestriction(address,address,uint256)"))
    //   XOR bytes4(keccak256("messageForTransferRestriction(uint8)"))
    bytes4 private constant _INTERFACE_ID_ERC1404 = 0xab84a5c8;

    mapping(address => bool) public whitelist;

    error TransferRestricted(uint8 code, string message);
    error AddressZeroNotAllowed();

    event WhitelistUpdated(address indexed account, bool status);

    constructor(string memory name, string memory symbol, uint256 initialSupply)
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        whitelist[msg.sender] = true;
        _mint(msg.sender, initialSupply);
    }

    // -------------------------------------------------------------------------
    // Whitelist management
    // -------------------------------------------------------------------------

    /// @notice Add or remove `account` from the transfer whitelist.
    function setWhitelisted(address account, bool status) external onlyOwner {
        if (account == address(0)) revert AddressZeroNotAllowed();
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    // -------------------------------------------------------------------------
    // Mint / burn
    // -------------------------------------------------------------------------

    /// @notice Mint `amount` tokens to a whitelisted `to` address.
    function mint(address to, uint256 amount) external onlyOwner {
        if (!whitelist[to]) revert TransferRestricted(RECIPIENT_NOT_WHITELISTED, MESSAGE_RECIPIENT_NOT_WHITELISTED);
        _mint(to, amount);
    }

    /// @notice Burn `amount` tokens from a whitelisted `from` address.
    function burn(address from, uint256 amount) external onlyOwner {
        if (!whitelist[from]) revert TransferRestricted(SENDER_NOT_WHITELISTED, MESSAGE_SENDER_NOT_WHITELISTED);
        _burn(from, amount);
    }

    // -------------------------------------------------------------------------
    // ERC-1404
    // -------------------------------------------------------------------------

    /// @notice Returns a restriction code for the proposed transfer, or 0 if unrestricted.
    /// @dev `value` is unused in this implementation; override to add amount-based restrictions.
    function detectTransferRestriction(
        address from,
        address to,
        uint256 /*value*/
    )
        public
        view
        override
        returns (uint8)
    {
        if (!whitelist[from]) return SENDER_NOT_WHITELISTED;
        if (!whitelist[to]) return RECIPIENT_NOT_WHITELISTED;
        return TRANSFER_OK;
    }

    /// @notice Returns the human-readable message for a restriction code.
    function messageForTransferRestriction(uint8 restrictionCode) public pure override returns (string memory) {
        if (restrictionCode == TRANSFER_OK) return MESSAGE_TRANSFER_OK;
        if (restrictionCode == SENDER_NOT_WHITELISTED) return MESSAGE_SENDER_NOT_WHITELISTED;
        if (restrictionCode == RECIPIENT_NOT_WHITELISTED) return MESSAGE_RECIPIENT_NOT_WHITELISTED;
        return MESSAGE_UNKNOWN_RESTRICTION;
    }

    // -------------------------------------------------------------------------
    // ERC-20 overrides — enforce restrictions on every transfer
    // -------------------------------------------------------------------------

    function transfer(address to, uint256 value) public override(ERC20, IERC20) returns (bool) {
        _checkRestriction(msg.sender, to, value);
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, IERC20) returns (bool) {
        _checkRestriction(from, to, value);
        return super.transferFrom(from, to, value);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public view override(ERC165) returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC1404 || super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Internal
    // -------------------------------------------------------------------------

    function _checkRestriction(address from, address to, uint256 value) internal view {
        uint8 code = detectTransferRestriction(from, to, value);
        if (code != TRANSFER_OK) {
            revert TransferRestricted(code, messageForTransferRestriction(code));
        }
    }
}
