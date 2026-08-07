// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {ScoreEvaluator} from "../src/ScoreEvaluator.sol";
import {SignalVector, Powers} from "../src/LaunchAbuseTypes.sol";

/// @dev Conformance cases 1, 2, 3 and 5 from the Test Cases section.
contract ScoreEvaluatorTest is TestBase {
    using ScoreEvaluator for SignalVector;

    uint16 internal constant NA16 = type(uint16).max;

    /// @dev A vector with no adverse conduct and full protection.
    function _clean() internal pure returns (SignalVector memory v) {
        v.deployerSupplyShare    = 0;
        v.insiderAllocationShare = 0;
        v.sniperConcentration    = 0;
        v.lpLockedShare          = 10_000;
        v.lpLockRemaining        = uint32(365 days);
        v.liquidityRemoved       = 0;
        v.deployerSellRatio      = 0;
        v.proceedsWithdrawnShare = 0;
        v.privilegedPowers       = 0;
        v.priorUpheldClaims      = 0;
    }

    /// @dev The worked hard-rug vector from Test Case 1.
    function _rug() internal pure returns (SignalVector memory v) {
        v.liquidityRemoved       = 6_000;
        v.lpLockedShare          = 0;
        v.proceedsWithdrawnShare = 9_000;
        v.lpLockRemaining        = 0;
        v.deployerSellRatio      = 7_000;
        v.privilegedPowers       = Powers.MINT | Powers.UPGRADE; // 0x0011
        v.priorUpheldClaims      = 2;
    }

    // 1. Score reproducibility: the worked vector lands in the Conclusive band.
    function test_01_scoreReproducibility() public pure {
        uint8 s = ScoreEvaluator.scoreHardRug(_rug());
        assertEq(s, 100, "expected 100");
        assertTrue(s >= 81 && s <= 100, "not in Conclusive band");
    }

    // 2. Protective polarity: full protection must lower the score, never raise it.
    function test_02_protectivePolarity() public pure {
        SignalVector memory v = _rug();
        v.lpLockedShare   = 10_000;
        v.lpLockRemaining = uint32(365 days);

        uint8 protectedScore = ScoreEvaluator.scoreHardRug(v);
        uint8 rugScore       = ScoreEvaluator.scoreHardRug(_rug());

        assertEq(protectedScore, 70, "expected 70");
        assertLt(protectedScore, rugScore, "protection did not reduce score");
    }

    // 3. Unavailable signals are excluded from numerator AND denominator,
    //    rather than being folded in as a zero contribution.
    function test_03_unavailableExcludedNotZeroed() public pure {
        SignalVector memory v = _rug();
        v.lpLockedShare     = 10_000;
        v.lpLockRemaining   = uint32(365 days);
        v.priorUpheldClaims = NA16; // withdraw the weight-5 signal

        uint8 excluded = ScoreEvaluator.scoreHardRug(v);

        // Excluding gives 65/95; zeroing would give 65/100 == 65.
        assertEq(excluded, 68, "expected 68 from a 95-weight denominator");
        assertTrue(excluded != 65, "signal was zeroed rather than excluded");
    }

    // 5. Honest failure must not read as fraud. This vector belongs to a project
    //    that simply did not work: liquidity locked, nothing sold, no retained
    //    powers. Price collapse is not an input to the score at all.
    function test_05_honestFailureScoresLow() public pure {
        SignalVector memory v = _clean();
        v.proceedsWithdrawnShare = 3_000; // took part of the raise, as agreed

        uint8 s = ScoreEvaluator.scoreHardRug(v);
        assertLe(s, 20, "honest failure escaped the None band");
        assertEq(s, 9, "expected 9");
    }

    function test_05b_fullyCleanScoresZero() public pure {
        assertEq(ScoreEvaluator.scoreHardRug(_clean()), 0, "clean vector must score 0");
    }

    // Monotonicity: worsening one adverse signal must never lower the score.
    function testFuzz_adverseMonotonic(uint16 removedA, uint16 removedB) public pure {
        removedA = uint16(bound(removedA, 0, 10_000));
        removedB = uint16(bound(removedB, 0, 10_000));
        if (removedA > removedB) (removedA, removedB) = (removedB, removedA);

        SignalVector memory a = _clean();
        SignalVector memory b = _clean();
        a.liquidityRemoved = removedA;
        b.liquidityRemoved = removedB;

        assertLe(
            ScoreEvaluator.scoreHardRug(a),
            ScoreEvaluator.scoreHardRug(b),
            "adverse signal is not monotonic"
        );
    }

    // The score is bounded regardless of input.
    function testFuzz_scoreBounded(uint16 a, uint16 b, uint32 c, uint16 d) public pure {
        SignalVector memory v = _clean();
        v.liquidityRemoved       = a;
        v.deployerSellRatio      = b;
        v.lpLockRemaining        = c;
        v.proceedsWithdrawnShare = d;
        assertLe(ScoreEvaluator.scoreHardRug(v), 100, "score exceeded 100");
    }

    function bound(uint256 x, uint256 lo, uint256 hi) internal pure returns (uint256) {
        return lo + (x % (hi - lo + 1));
    }
}
