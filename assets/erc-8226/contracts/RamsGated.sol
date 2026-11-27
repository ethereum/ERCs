// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IAgentMandate} from "./interfaces/IAgentMandate.sol";

/// @title RamsGated
/// @notice Optional base contract for the token gate venue. A token inherits it and applies gatedByMandate to
///         each function it lets an agent perform for a holder.
abstract contract RamsGated {
    IAgentMandate public immutable rams;

    error ZeroRegistry();

    constructor(IAgentMandate rams_) {
        if (address(rams_) == address(0)) revert ZeroRegistry();
        rams = rams_;
    }

    /// @notice Gates a function against the caller's mandate over `holder`, then records the execution.
    /// @dev A call from the holder is ungated. The label is the gated function's own selector, so it cannot
    ///      drift with the call path. The constraints are checked against the function's own calldata.
    /// @param selector The gated function's selector, widened to the mandate's bytes32 label.
    /// @param holder The principal on whose behalf the action runs.
    /// @param amount The amount of this token spent, counted against its limit. 0 for actions carrying no value.
    modifier gatedByMandate(bytes4 selector, address holder, uint256 amount) {
        bytes32 action = bytes32(selector);
        bool agentCall = msg.sender != holder;
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        flows[0] = IAgentMandate.Flow(address(this), IAgentMandate.Direction.OUTFLOW, amount);

        if (agentCall) {
            (bool ok, IAgentMandate.MandateReason reason) =
                rams.canExecute(msg.sender, holder, address(this), action, msg.data, flows);
            if (!ok) revert IAgentMandate.MandateBlocked(reason);
        }

        _;

        if (agentCall) rams.recordExecution(msg.sender, holder, address(this), action, msg.data, flows);
    }
}
