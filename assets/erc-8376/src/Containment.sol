// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ContainmentAction} from "./LaunchAbuseTypes.sol";

/// @title The containment ladder, as a pure function of score and confidence.
/// @notice Shared by the guard and the remediation contract so that advisory
///         and enforced responses cannot drift apart.
library Containment {
    /// @dev `Refund` is deliberately unreachable here. Taking a deployer's
    ///      proceeds requires an upheld claim with a right to contest, never a
    ///      detection alone, however confident.
    function ladder(uint8 score, uint8 confidence) internal pure returns (ContainmentAction) {
        if (score >= 81) {
            if (confidence >= 80) return ContainmentAction.Freeze;
            if (confidence >= 50) return ContainmentAction.SuspendRelease;
            return ContainmentAction.Flag;
        }
        if (score >= 61) {
            if (confidence >= 80) return ContainmentAction.SuspendRelease;
            if (confidence >= 50) return ContainmentAction.ExtendSchedule;
            return ContainmentAction.Flag;
        }
        if (score >= 41) {
            if (confidence >= 80) return ContainmentAction.ExtendSchedule;
            if (confidence >= 50) return ContainmentAction.Flag;
            return ContainmentAction.None;
        }
        if (confidence >= 80) return ContainmentAction.Flag;
        return ContainmentAction.None;
    }
}
