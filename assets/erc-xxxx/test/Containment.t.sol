// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {Containment} from "../src/Containment.sol";
import {ContainmentAction} from "../src/LaunchAbuseTypes.sol";

/// @dev The ladder decides what a detection is allowed to trigger, so every
///      cell and every boundary is asserted rather than sampled. A wrong cell
///      would silently downgrade a Conclusive finding to an advisory flag.
contract ContainmentTest is TestBase {
    function _cell(uint8 s, uint8 c) internal pure returns (ContainmentAction) {
        return Containment.ladder(s, c);
    }

    function _eq(ContainmentAction a, ContainmentAction b, string memory why) internal pure {
        assertEq(uint256(a), uint256(b), why);
    }

    // --- all twelve cells ---------------------------------------------------

    function test_conclusiveBand() public pure {
        _eq(_cell(95, 90), ContainmentAction.Freeze, "81+/80+ must Freeze");
        _eq(_cell(95, 60), ContainmentAction.SuspendRelease, "81+/50-79 must SuspendRelease");
        _eq(_cell(95, 20), ContainmentAction.Flag, "81+/<50 must Flag only");
    }

    function test_strongBand() public pure {
        _eq(_cell(70, 90), ContainmentAction.SuspendRelease, "61-80/80+ must SuspendRelease");
        _eq(_cell(70, 60), ContainmentAction.ExtendSchedule, "61-80/50-79 must ExtendSchedule");
        _eq(_cell(70, 20), ContainmentAction.Flag, "61-80/<50 must Flag only");
    }

    function test_elevatedBand() public pure {
        _eq(_cell(50, 90), ContainmentAction.ExtendSchedule, "41-60/80+ must ExtendSchedule");
        _eq(_cell(50, 60), ContainmentAction.Flag, "41-60/50-79 must Flag");
        _eq(_cell(50, 20), ContainmentAction.None, "41-60/<50 must do nothing");
    }

    function test_weakBand() public pure {
        _eq(_cell(30, 90), ContainmentAction.Flag, "0-40/80+ must Flag");
        _eq(_cell(30, 60), ContainmentAction.None, "0-40/50-79 must do nothing");
        _eq(_cell(30, 20), ContainmentAction.None, "0-40/<50 must do nothing");
    }

    // --- boundaries ---------------------------------------------------------

    function test_scoreBoundaries() public pure {
        _eq(_cell(40, 90), ContainmentAction.Flag, "40 is still the weak band");
        _eq(_cell(41, 90), ContainmentAction.ExtendSchedule, "41 opens the elevated band");
        _eq(_cell(60, 90), ContainmentAction.ExtendSchedule, "60 is still elevated");
        _eq(_cell(61, 90), ContainmentAction.SuspendRelease, "61 opens the strong band");
        _eq(_cell(80, 90), ContainmentAction.SuspendRelease, "80 is still strong");
        _eq(_cell(81, 90), ContainmentAction.Freeze, "81 opens the conclusive band");
    }

    function test_confidenceBoundaries() public pure {
        _eq(_cell(95, 49), ContainmentAction.Flag, "49 is below the middle tier");
        _eq(_cell(95, 50), ContainmentAction.SuspendRelease, "50 opens the middle tier");
        _eq(_cell(95, 79), ContainmentAction.SuspendRelease, "79 is still middle");
        _eq(_cell(95, 80), ContainmentAction.Freeze, "80 opens the top tier");
    }

    function test_extremes() public pure {
        _eq(_cell(0, 0), ContainmentAction.None, "zero everything");
        _eq(_cell(0, 100), ContainmentAction.Flag, "certain about nothing is still a flag");
        _eq(_cell(100, 0), ContainmentAction.Flag, "maximal score at no confidence cannot act");
        _eq(_cell(100, 100), ContainmentAction.Freeze, "maximal both");
    }

    // --- properties ---------------------------------------------------------

    /// Refund is never reachable from detection alone, at any input.
    function testFuzz_refundUnreachable(uint8 score, uint8 confidence) public pure {
        assertTrue(_cell(score, confidence) != ContainmentAction.Refund, "ladder reached Refund");
    }

    /// Raising confidence can never weaken the response.
    function testFuzz_monotonicInConfidence(uint8 score, uint8 a, uint8 b) public pure {
        if (a > b) (a, b) = (b, a);
        assertLe(uint256(_cell(score, a)), uint256(_cell(score, b)), "confidence is not monotonic");
    }

    /// Raising the score can never weaken the response.
    function testFuzz_monotonicInScore(uint8 confidence, uint8 a, uint8 b) public pure {
        if (a > b) (a, b) = (b, a);
        assertLe(uint256(_cell(a, confidence)), uint256(_cell(b, confidence)), "score is not monotonic");
    }
}
