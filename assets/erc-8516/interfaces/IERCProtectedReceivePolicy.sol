// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IERCProtectedReceivePolicy
 * @notice Optional external `IReceivePolicy` delegation extension for `IERCProtectedReceiveCore`.
 * @dev Allows accounts to delegate incoming transfer checks to a shared registry or smart-account module.
 */
interface IERCProtectedReceivePolicy {
    /**
     * @notice Emitted when an account sets or clears its external `IReceivePolicy` contract.
     * @dev Setting `policy` to `address(0)` disables external policy delegation.
     * @param account The account updating its policy.
     * @param policy The new `IReceivePolicy` address, or `address(0)` if cleared.
     */
    event ReceivePolicyUpdated(address indexed account, address indexed policy);

    /**
     * @notice Returns the external `IReceivePolicy` contract configured for `account`.
     * @dev Returns `address(0)` if no external policy is configured.
     * @param account The account to query.
     * @return The configured `IReceivePolicy` address.
     */
    function receivePolicy(address account) external view returns (address);

    /**
     * @notice Sets or clears the external `IReceivePolicy` contract for `msg.sender`.
     * @dev Emits {ReceivePolicyUpdated}. Pass `address(0)` to clear.
     * @param policy The `IReceivePolicy` contract address.
     */
    function setReceivePolicy(address policy) external;
}

