// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceiveAllowlist
 * @notice Optional embedded allowlist inspection extension for `IERCProtectedReceiveCore`.
 * @dev Standardizes read/indexing interoperability (`ReceiveSenderAllowlistUpdated` +
 *      `receiveSenderAllowlistedUntil`) without prescribing how allowlist entries are administered
 *      (e.g., direct calls, batching, or delegated managers). All 2-address symbols follow `(from, to)` flow order.
 */
interface IERCProtectedReceiveAllowlist {
    /**
     * @notice Emitted when a recipient updates a sender's embedded allowlist expiration timestamp.
     * @dev `0` revokes access; `type(uint40).max` grants permanent access; any other timestamp
     *      grants timed access (`expiry > block.timestamp`). Applies only to the emitting token.
     * @param from The sender address (`address(0)` for mints) whose allowlist entry changed.
     * @param to The recipient account whose allowlist was updated.
     * @param expiry Unix timestamp until which `from` is allowed.
     */
    event ReceiveSenderAllowlistUpdated(address indexed from, address indexed to, uint40 expiry);

    /**
     * @notice Returns the `uint40` expiration timestamp for `from` on `to`'s embedded allowlist.
     * @dev `0` means not allowed; `type(uint40).max` means permanently allowed; any value
     *      `> block.timestamp` indicates `from` is currently allowlisted.
     * @param from The sender address (`address(0)` for mints).
     * @param to The recipient account.
     * @return The Unix timestamp until which `from` is allowed.
     */
    function receiveSenderAllowlistedUntil(address from, address to) external view returns (uint40);
}
