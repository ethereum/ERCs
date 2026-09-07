// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IAgentMandate} from "./interfaces/IAgentMandate.sol";

/// @title RamsGated
/// @notice Optional base contract for the token gate venue. A token inherits it and applies gatedByMandate to
///         each function it lets an agent perform for a holder.
abstract contract RamsGated {
    IAgentMandate public immutable rams;

    error ZeroRegistry();
    error MandateBlocked(IAgentMandate.MandateReason reason);

    constructor(IAgentMandate rams_) {
        if (address(rams_) == address(0)) revert ZeroRegistry();
        rams = rams_;
    }

    /// @notice Gates a function against the caller's mandate over `holder`, then records the execution.
    /// @dev A call from the holder is ungated. The label is the gated function's own selector, so it cannot
    ///      drift with the call path.
    /// @param selector The gated function's selector, widened to the mandate's bytes32 label.
    /// @param holder The principal on whose behalf the action runs.
    /// @param amount The value gated against the mandate's caps. 0 for actions carrying no value.
    modifier gatedByMandate(bytes4 selector, address holder, uint256 amount) {
        bytes32 action = bytes32(selector);
        bool agentCall = msg.sender != holder;

        if (agentCall) {
            (bool ok, IAgentMandate.MandateReason reason) =
                rams.canExecute(msg.sender, holder, address(this), action, amount);
            if (!ok) revert MandateBlocked(reason);
        }

        _;

        if (agentCall) rams.recordExecution(msg.sender, holder, action, amount);
    }
}
