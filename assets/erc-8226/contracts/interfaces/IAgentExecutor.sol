// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @notice OPTIONAL, non-normative companion interface for the account-side enforcement venues
///         (an EIP-7702 delegate or a standalone executor). The forwarding logic is never part of IAgentMandate.
interface IAgentExecutor {
    /// @dev msg.sender is the agent; the implementer is bound to a principal. The action label is the
    ///      selector bytes4(data); the gated amount is read from `data` at a registered per-action position,
    ///      not supplied by the caller, so gated values match the real call. Calls canExecute and reverts if
    ///      false, records the execution, then forwards the call.
    function execute(address target, bytes calldata data) external returns (bytes memory);
}
