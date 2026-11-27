// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

/// @notice Optional interface for the account-side venues. The forwarding logic is never part of IAgentMandate.
interface IAgentExecutor {
    /// @dev msg.sender is the agent; the principal is the account that runs the code. The action label is the
    ///      selector bytes4(data). Calls canExecute and reverts if false, forwards the call, then measures the
    ///      change of the principal's balance in each token that the mandate limits, checks it against the limits
    ///      and records it. An approval moves no funds, so it spends nothing: a mandate that enables approve SHOULD
    ///      constrain the spender.
    function execute(address target, bytes calldata data) external returns (bytes memory);
}
