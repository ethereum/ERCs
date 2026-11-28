// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceiveCore
 * @notice Minimal required interface for opt-in, recipient-gated ERC-20 incoming transfer protection.
 * @dev Integrator-facing core (`MUST`): provides read-only inspection (`isReceiveProtected`, `canReceive`),
 *      the standard status event (`ReceiveProtectionUpdated`), and the standard revert error
 *      (`RecipientTransferNotAllowed`). Compliant tokens SHOULD also implement ERC-165 (`supportsInterface`).
 */
interface IERCProtectedReceiveCore {
    /**
     * @notice Emitted when an account's incoming transfer protection state changes.
     * @dev Fresh accounts SHOULD default to `false` (unprotected) to preserve ERC-20 backwards compatibility.
     * @param account The account whose receive protection setting changed.
     * @param enabled True if receive protection is enabled, false if disabled.
     */
    event ReceiveProtectionUpdated(address indexed account, bool enabled);

    /**
     * @notice Reverted when a transfer to a receive-protected recipient is not authorized.
     * @dev Triggered when all active authorization mechanisms deny the transfer.
     * @param from The economic sender address (`address(0)` for mints).
     * @param to The protected recipient address.
     * @param amount The attempted transfer amount.
     */
    error RecipientTransferNotAllowed(address from, address to, uint256 amount);

    /**
     * @notice Returns whether incoming transfer protection is enabled for `account`.
     * @dev Fresh accounts return `false` in opt-in implementations.
     * @param account The address to query.
     * @return True if `account` has receive protection enabled.
     */
    function isReceiveProtected(address account) external view returns (bool);

    /**
     * @notice Pre-flight view check for whether `to` can currently receive `amount` from `from`.
     * @dev Returns `true` if `to == address(0)` (burn), `from == to` (self-transfer),
     *      `!isReceiveProtected(to)`, or any configured authorization mechanism permits the transfer.
     * @param from The economic sender address (`address(0)` for mints).
     * @param to The recipient address.
     * @param amount The transfer amount.
     * @return True if the transfer would be authorized.
     */
    function canReceive(address from, address to, uint256 amount) external view returns (bool);
}
