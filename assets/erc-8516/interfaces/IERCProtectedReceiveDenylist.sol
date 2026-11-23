// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceiveDenylist
 * @notice Optional embedded denylist inspection extension for `IERCProtectedReceiveCore`.
 * @dev Standardizes read/indexing interoperability (`ReceiveSenderDenylistUpdated` +
 *      `receiveSenderDenylistedUntil`) without prescribing how denylist entries are administered
 *      (e.g., direct calls, batching, or delegated managers) or how they compose with allowlists,
 *      `permitReceive`, or `protectionLevel`. All 2-address symbols follow `(from, to)` flow order.
 */
interface IERCProtectedReceiveDenylist {
    /**
     * @notice Emitted when a recipient updates a sender's embedded denylist expiration timestamp.
     * @dev `0` (or `expiry <= block.timestamp`) indicates not active; `type(uint40).max` indicates
     *      a permanent block; any timestamp `> block.timestamp` blocks `from` until `expiry`.
     *      Applies only to the emitting token.
     * @param from The sender address (`address(0)` for mints) whose denylist entry changed.
     * @param to The recipient account whose denylist was updated.
     * @param expiry Unix timestamp until which `from` is denylisted.
     */
    event ReceiveSenderDenylistUpdated(address indexed from, address indexed to, uint40 expiry);

    /**
     * @notice Returns the `uint40` expiration timestamp for `from` on `to`'s embedded denylist.
     * @dev `0` or `<= block.timestamp` means not active; `type(uint40).max` means permanently
     *      blocked; any value `> block.timestamp` indicates `from` is currently denylisted.
     * @param from The sender address (`address(0)` for mints).
     * @param to The recipient account.
     * @return The Unix timestamp until which `from` is denylisted.
     */
    function receiveSenderDenylistedUntil(address from, address to) external view returns (uint40);
}
