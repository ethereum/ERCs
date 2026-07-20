// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC1404} from "./IERC1404.sol";

/// @title IERC1404SpenderAware — Spender-aware restriction detection extension (EIP-1404).
/// @notice OPTIONAL extension adding `detectTransferRestrictionFrom`, so integrators can predict
///         the outcome of a delegated transfer (`transferFrom`) initiated by a `spender` that may
///         differ from `from`. The base three-parameter `detectTransferRestriction` cannot observe
///         the spender and therefore cannot express spender-specific restrictions.
/// @dev The ERC-165 identifier for this extension is `0x78a8de7d`, the exclusive-or of the selectors
///      of all three methods (`detectTransferRestriction`, `messageForTransferRestriction`,
///      `detectTransferRestrictionFrom`). It MUST be hardcoded: `type(IERC1404SpenderAware).interfaceId`
///      would cover only the single declared method and MUST NOT be used for this purpose.
interface IERC1404SpenderAware is IERC1404 {
    /// @notice Returns a restriction code for a delegated transfer initiated by `spender`, or 0 if unrestricted.
    /// @dev Shares the restriction code space and `messageForTransferRestriction` lookup with the base method.
    ///      Consistency with delegated-transfer enforcement is the only invariant EIP-1404 requires. The
    ///      `spender == from` case SHOULD be evaluated through the spender-aware path; an implementation MAY
    ///      instead collapse it to `detectTransferRestriction(from, to, value)` only when its policy does not
    ///      restrict operator identity beyond ownership, so the two are observably equivalent.
    /// @param spender Address initiating the delegated transfer (the `transferFrom` caller).
    /// @param from    Address the tokens are debited from.
    /// @param to      Recipient address.
    /// @param value   Token amount to transfer.
    /// @return        Restriction code; 0 means the transfer is allowed.
    function detectTransferRestrictionFrom(address spender, address from, address to, uint256 value)
        external
        view
        returns (uint8);
}
