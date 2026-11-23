// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceiveOptIn
 * @notice Recommended self-service opt-in toggle extension for `IERCProtectedReceiveCore`.
 * @dev Allows any account to enable or disable incoming transfer protection on its own address.
 */
interface IERCProtectedReceiveOptIn {
    /**
     * @notice Enables or disables incoming transfer protection for `msg.sender`.
     * @dev Emits `ReceiveProtectionUpdated(msg.sender, enabled)`.
     * @param enabled True to enable receive protection, false to disable.
     */
    function setReceiveProtection(bool enabled) external;
}

