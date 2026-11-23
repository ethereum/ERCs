// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceiveLevel
 * @notice Optional granular protection-level extension for `IERCProtectedReceiveCore`.
 * @dev Allows wallets and smart accounts to configure a token-defined `bytes32` bitmask or tier
 *      (`bytes32(0)` = unprotected, `bytes32(uint256(1))` = default protection, any other non-zero =
 *      custom protection level). Updating between two non-zero levels MUST emit
 *      `ReceiveProtectionLevelUpdated` without re-emitting `ReceiveProtectionUpdated`.
 */
interface IERCProtectedReceiveLevel {
    /**
     * @notice Emitted when an account's granular `bytes32` protection level changes.
     * @dev Intended for wallet UIs to render specific protection flags or tiers.
     * @param account The account whose protection level changed.
     * @param protectionLevel The new `bytes32` protection level (`bytes32(0)` if disabled).
     */
    event ReceiveProtectionLevelUpdated(address indexed account, bytes32 protectionLevel);

    /**
     * @notice Returns the granular `bytes32` protection level configured for `account`.
     * @dev Returns `bytes32(0)` when unprotected, `bytes32(uint256(1))` when enabled via
     *      `setReceiveProtection(true)`, or the custom `bytes32` level set via `setReceiveProtection(bytes32)`.
     * @param account The address to query.
     * @return The configured `bytes32` protection level.
     */
    function receiveProtectionLevel(address account) external view returns (bytes32);

    /**
     * @notice Sets a granular `bytes32` protection level for `msg.sender`.
     * @dev `bytes32(0)` disables protection; any non-zero value enables protection with that level.
     *      Emits {ReceiveProtectionLevelUpdated} on change, and emits `ReceiveProtectionUpdated`
     *      only if the binary protected state (`level != bytes32(0)`) transitions.
     * @param protectionLevel The `bytes32` protection level or feature bitmask.
     */
    function setReceiveProtection(bytes32 protectionLevel) external;
}

