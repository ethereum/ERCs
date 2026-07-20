// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC1404} from "./ERC1404.sol";
import {IERC1404} from "./IERC1404.sol";
import {IERC1404SpenderAware} from "./IERC1404SpenderAware.sol";

/// @title ERC1404SpenderAware — Whitelist-based ERC1404 with the spender-aware detection extension.
///
/// @notice Extends the base {ERC1404} whitelist token with the OPTIONAL spender-aware extension
///         (`detectTransferRestrictionFrom`). It reuses the base whitelist, mint/burn and message
///         logic unchanged, and only adds the `spender` dimension: a delegated transfer is now also
///         rejected when the operator initiating it is not whitelisted.
///
/// Restriction codes (0–2 are inherited from {ERC1404}):
///   0  No restriction
///   1  Sender not whitelisted
///   2  Recipient not whitelisted
///   3  Spender not whitelisted  (added by this extension)
/// Restriction codes 1, 2 and 3 are not standardised by ERC-1404.
contract ERC1404SpenderAware is ERC1404, IERC1404SpenderAware {
    /**
     * @notice Restriction code returned when the spender initiating a delegated transfer is not whitelisted.
     */
    uint8 public constant SPENDER_NOT_WHITELISTED = 3;

    /**
     * @notice Human-readable message for `SPENDER_NOT_WHITELISTED`.
     */
    string public constant MESSAGE_SPENDER_NOT_WHITELISTED = "Spender not whitelisted";

    /**
     * @notice ERC-165 interface id advertised for the spender-aware ERC-1404 extension.
     * @dev bytes4(keccak256("detectTransferRestriction(address,address,uint256)"))
     *   XOR bytes4(keccak256("messageForTransferRestriction(uint8)"))
     *   XOR bytes4(keccak256("detectTransferRestrictionFrom(address,address,address,uint256)"))
     *   The three-selector value is hardcoded on purpose. `type(IERC1404SpenderAware).interfaceId`
     *   covers only the directly declared `detectTransferRestrictionFrom` (Solidity excludes inherited
     *   selectors), so it does not equal this id. The exclusive-or is recomputed and pinned by
     *   `test_extensionIdIsXorOfThreeSelectors` in ERC1404SpenderAware.t.sol.
     */
    bytes4 private constant _INTERFACE_ID_ERC1404_SPENDER_AWARE = 0x78a8de7d;

    /**
     * @notice Deploys the token, whitelists the deployer and mints the initial supply to it.
     * @param name_ Token name.
     * @param symbol_ Token symbol.
     * @param initialSupply Amount minted to the deployer at construction.
     */
    constructor(string memory name_, string memory symbol_, uint256 initialSupply)
        ERC1404(name_, symbol_, initialSupply)
    {}

    // -------------------------------------------------------------------------
    // ERC-20 override — enforce the spender-aware restriction on delegated transfers
    // -------------------------------------------------------------------------

    /**
     * @inheritdoc IERC20
     * @dev Enforces `detectTransferRestrictionFrom` directly so the enforced code matches the reported
     *      one, then delegates to {ERC20-transferFrom}. The base {ERC1404-transferFrom} check is a
     *      subset of the spender-aware check and is intentionally bypassed to avoid a redundant lookup.
     */
    function transferFrom(address from, address to, uint256 value)
        public
        override(ERC1404, IERC20)
        returns (bool)
    {
        uint8 code = detectTransferRestrictionFrom(msg.sender, from, to, value);
        if (code != TRANSFER_OK) {
            revert TransferRestricted(code, messageForTransferRestriction(code));
        }
        return ERC20.transferFrom(from, to, value);
    }

    // -------------------------------------------------------------------------
    // ERC-1404 spender-aware extension
    // -------------------------------------------------------------------------

    /**
     * @notice Returns a restriction code for a delegated transfer initiated by `spender`, or 0 if unrestricted.
     * @dev Reuses the base `from`/`to` policy and layers the spender check on top. When `spender == from`
     *      the spender check is skipped: this is a safe optimization here because a whitelisted `from`
     *      already implies a whitelisted spender, so the result coincides with
     *      `detectTransferRestriction(from, to, value)` without diverging from `transferFrom` enforcement.
     * @param spender Address initiating the delegated transfer (the `transferFrom` caller).
     * @param from Address the tokens are debited from.
     * @param to Recipient address.
     * @param value Token amount to transfer.
     * @return Restriction code; 0 means the transfer is allowed.
     */
    function detectTransferRestrictionFrom(address spender, address from, address to, uint256 value)
        public
        view
        override
        returns (uint8)
    {
        uint8 code = detectTransferRestriction(from, to, value);
        if (code != TRANSFER_OK) return code;
        if (spender != from && !whitelist[spender]) return SPENDER_NOT_WHITELISTED;
        return TRANSFER_OK;
    }

    /**
     * @notice Returns the human-readable message for a restriction code, including the extension code.
     * @param restrictionCode Code returned by `detectTransferRestriction` or `detectTransferRestrictionFrom`.
     * @return Human-readable description of the restriction.
     */
    function messageForTransferRestriction(uint8 restrictionCode)
        public
        pure
        override(ERC1404, IERC1404)
        returns (string memory)
    {
        if (restrictionCode == SPENDER_NOT_WHITELISTED) return MESSAGE_SPENDER_NOT_WHITELISTED;
        return super.messageForTransferRestriction(restrictionCode);
    }

    // -------------------------------------------------------------------------
    // ERC-165
    // -------------------------------------------------------------------------

    /**
     * @notice Returns true if the contract implements `interfaceId`.
     * @dev Advertises both the mandatory ERC-1404 id (`0xab84a5c8`, via the base) and the spender-aware
     *      extension id (`0x78a8de7d`).
     * @param interfaceId Interface identifier, as defined in ERC-165.
     * @return True if the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC1404) returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC1404_SPENDER_AWARE || super.supportsInterface(interfaceId);
    }
}
