// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {ScoreEvaluator} from "../src/ScoreEvaluator.sol";
import {SignalVector, Patterns, Powers} from "../src/LaunchAbuseTypes.sol";

/// @dev Every pattern in the taxonomy must be scorable. A pattern that can be
///      reported but not scored is an identifier, not a detection.
contract ProfilesTest is TestBase {
    uint16 internal constant NA = type(uint16).max;

    function _all() internal pure returns (bytes32[10] memory) {
        return [
            Patterns.HARD_RUG, Patterns.SOFT_RUG, Patterns.INSIDER_ALLOCATION,
            Patterns.SNIPER_COORDINATION, Patterns.HONEYPOT, Patterns.MINT_DILUTION,
            Patterns.RETAINED_CONTROL, Patterns.WASH_LAUNCH, Patterns.UNLOCK_EXIT,
            Patterns.SERIAL_DEPLOYER
        ];
    }

    /// A clean launch: fully protected, nothing sold, no powers, no history.
    function _clean() internal pure returns (SignalVector memory v) {
        v.lpLockedShare = 10_000;
        v.lpLockRemaining = uint32(365 days);
    }

    // --- every pattern has a profile ---------------------------------------

    function test_everyPatternHasAWeightProfile() public pure {
        bytes32[10] memory ids = _all();
        for (uint256 i = 0; i < 10; ++i) {
            ScoreEvaluator.Profile memory p = ScoreEvaluator.profileFor(ids[i]);
            uint256 sum = 0;
            for (uint256 k = 0; k < ScoreEvaluator.N; ++k) sum += p.weights[k];
            assertEq(sum, 100, "weights must sum to 100");
        }
    }

    function test_unknownPatternHasNoProfile() public {
        vm.expectRevert();
        this.profile(keccak256("erc.launch.not-a-pattern"));
    }

    function profile(bytes32 id) external pure returns (uint256) {
        return ScoreEvaluator.profileFor(id).weights[0];
    }

    /// A clean launch must score in the None band under every pattern.
    function test_cleanLaunchScoresNoneUnderEveryPattern() public pure {
        bytes32[10] memory ids = _all();
        SignalVector memory v = _clean();
        for (uint256 i = 0; i < 10; ++i) {
            assertLe(ScoreEvaluator.scoreFor(ids[i], v), 20, "clean launch flagged");
        }
    }

    // --- each pattern reaches Conclusive on its own evidence ---------------

    function test_hardRug() public pure {
        SignalVector memory v = _clean();
        v.liquidityRemoved = 6000; v.lpLockedShare = 0; v.lpLockRemaining = 0;
        v.proceedsWithdrawnShare = 9000; v.deployerSellRatio = 7000;
        v.privilegedPowers = Powers.MINT | Powers.UPGRADE; v.priorUpheldClaims = 2;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.HARD_RUG, v) >= 81, "hard rug");
    }

    /// Liquidity stays put; the deployer distributes into the bid instead.
    function test_softRug() public pure {
        SignalVector memory v = _clean();
        v.deployerSellRatio = 9000; v.deployerSupplyShare = 6000;
        v.proceedsWithdrawnShare = 9000; v.privilegedPowers = Powers.MINT;
        v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.SOFT_RUG, v) >= 81, "soft rug");
        assertEq(v.liquidityRemoved, 0, "a soft rug removes no liquidity");
    }

    function test_insiderAllocation() public pure {
        SignalVector memory v = _clean();
        v.insiderAllocationShare = 4000; v.deployerSupplyShare = 6000;
        v.sniperConcentration = 5000; v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.INSIDER_ALLOCATION, v) >= 81, "insider");
    }

    function test_sniperCoordination() public pure {
        SignalVector memory v = _clean();
        v.sniperConcentration = 7000; v.insiderAllocationShare = 3000;
        v.deployerSupplyShare = 5000; v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.SNIPER_COORDINATION, v) >= 81, "sniper");
    }

    /// The honeypot mask is the sell-blocking powers, not the expropriating ones.
    function test_honeypot() public pure {
        SignalVector memory v = _clean();
        v.privilegedPowers = Powers.PAUSE | Powers.BLACKLIST | Powers.FEE;
        v.deployerSupplyShare = 6000; v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.HONEYPOT, v) >= 81, "honeypot");

        // Mint alone is not a honeypot: it expropriates, it does not block selling.
        SignalVector memory m = _clean();
        m.privilegedPowers = Powers.MINT;
        assertLe(ScoreEvaluator.scoreFor(Patterns.HONEYPOT, m), 20, "mint is not a honeypot");
    }

    function test_mintDilution() public pure {
        SignalVector memory v = _clean();
        v.supplyInflation = 5000; v.privilegedPowers = Powers.MINT;
        v.deployerSupplyShare = 6000; v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.MINT_DILUTION, v) >= 81, "mint dilution");

        // The power without the exercise is retained control, not dilution.
        SignalVector memory cap = _clean();
        cap.privilegedPowers = Powers.MINT; cap.supplyInflation = 0;
        assertLe(ScoreEvaluator.scoreFor(Patterns.MINT_DILUTION, cap), 40, "capability alone");
    }

    function test_retainedControl() public pure {
        SignalVector memory v = _clean();
        v.privilegedPowers = Powers.UPGRADE | Powers.SEIZE;
        v.lpLockedShare = 0; v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.RETAINED_CONTROL, v) >= 81, "retained control");
    }

    function test_washLaunch() public pure {
        SignalVector memory v = _clean();
        v.washTradeRatio = 8000; v.sniperConcentration = 5000;
        v.insiderAllocationShare = 3000; v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.WASH_LAUNCH, v) >= 81, "wash launch");
    }

    function test_unlockExit() public pure {
        SignalVector memory v = _clean();
        v.lpLockRemaining = 0; v.deployerSellRatio = 8000;
        v.liquidityRemoved = 6000; v.priorUpheldClaims = 1;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.UNLOCK_EXIT, v) >= 81, "unlock exit");
    }

    function test_serialDeployer() public pure {
        SignalVector memory v = _clean();
        v.priorUpheldClaims = 3; v.deployerSupplyShare = 6000;
        v.privilegedPowers = Powers.MINT; v.insiderAllocationShare = 3000;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.SERIAL_DEPLOYER, v) >= 81, "serial deployer");

        // One prior claim must not by itself brand a repeat offender.
        SignalVector memory one = _clean();
        one.priorUpheldClaims = 1;
        assertLe(ScoreEvaluator.scoreFor(Patterns.SERIAL_DEPLOYER, one), 40, "one claim");
    }

    // --- the new signals behave like the rest ------------------------------

    /// With every weighted signal unavailable there is nothing to average, and
    /// the evaluator refuses rather than inventing a zero.
    function test_newSignalsHonorTheSentinel() public {
        SignalVector memory v = _clean();
        v.washTradeRatio = NA; v.sniperConcentration = NA;
        v.insiderAllocationShare = NA; v.priorUpheldClaims = NA;
        vm.expectRevert();
        this.scoreExternal(Patterns.WASH_LAUNCH, v);

        // One available signal is enough to score, and it carries the weight.
        v.washTradeRatio = 9000;
        assertTrue(ScoreEvaluator.scoreFor(Patterns.WASH_LAUNCH, v) == 100, "sole signal");
    }

    function scoreExternal(bytes32 id, SignalVector memory v) external pure returns (uint8) {
        return ScoreEvaluator.scoreFor(id, v);
    }

    function testFuzz_everyPatternBounded(uint16 a, uint16 b, uint16 c) public pure {
        SignalVector memory v = _clean();
        v.washTradeRatio = a; v.supplyInflation = b; v.deployerSellRatio = c;
        bytes32[10] memory ids = _all();
        for (uint256 i = 0; i < 10; ++i) {
            assertLe(ScoreEvaluator.scoreFor(ids[i], v), 100, "score exceeded 100");
        }
    }
}
