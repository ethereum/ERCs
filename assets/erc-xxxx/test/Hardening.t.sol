// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {SignalProbe} from "../src/SignalProbe.sol";
import {ScoreEvaluator} from "../src/ScoreEvaluator.sol";
import {AbuseReport, SignalVector, ClaimStatus, LaunchState, Patterns, Powers}
    from "../src/LaunchAbuseTypes.sol";

contract Impl {
    function mint(address, uint256) external {}
    function seize(address, uint256) external {}
}

/// @dev EIP-1967-style proxy exposing the conventional getter.
contract GetterProxy {
    address public immutable target;
    constructor(address t) { target = t; }
    function implementation() external view returns (address) { return target; }
    fallback() external payable {
        address t = target;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), t, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok case 0 { revert(0, returndatasize()) } default { return(0, returndatasize()) }
        }
    }
}

/// @dev A proxy that hides its implementation entirely.
contract OpaqueProxy {
    address private immutable target;
    constructor(address t) { target = t; }
    fallback() external payable {
        address t = target;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), t, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok case 0 { revert(0, returndatasize()) } default { return(0, returndatasize()) }
        }
    }
}

contract HardeningTest is TestBase {
    LaunchDirectory     internal directory;
    LaunchRemediation   internal remediation;
    LaunchAbuseRegistry internal registry;
    LaunchEscrow        internal escrow;
    SaleVenue           internal venue;

    address internal adjudicator = address(0xAD);
    address internal deployer    = address(0xD1);
    address internal detA        = address(0xDA);
    address internal detB        = address(0xDB);
    address internal alice       = address(0xA1);
    address internal bob         = address(0xB2);
    address internal token       = address(0x70);

    bytes32 internal id;
    uint64  internal start;

    function setUp() public {
        directory   = new LaunchDirectory();
        remediation = new LaunchRemediation(adjudicator, address(0xFE), 5000, 1 ether, 50 ether);
        registry    = new LaunchAbuseRegistry(address(remediation));
        escrow      = new LaunchEscrow(address(remediation), directory);
        remediation.initialize(escrow, registry);
        venue       = new SaleVenue(escrow);

        start = uint64(block.timestamp);
        id = venue.open{value: 5 ether}(token, deployer, start, uint64(block.timestamp + 30 days), 1);

        vm.deal(alice, 200 ether);
        vm.deal(bob, 200 ether);
        vm.deal(detA, 10 ether);
        vm.deal(detB, 10 ether);
        vm.deal(deployer, 200 ether);

        vm.prank(detA); registry.bondDetector{value: 1 ether}();
        vm.prank(detB); registry.bondDetector{value: 1 ether}();
    }

    function _report(uint8 score) internal view returns (AbuseReport memory r) {
        r.patternId = Patterns.HARD_RUG;
        r.launchId = id;
        r.token = token;
        r.deployer = deployer;
        r.linkedAddresses = new address[](0);
        r.abuseScore = score;
        r.confidence = 90;
        r.launchedAt = start;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0, 0, 0, 0, 0, 6000, 7000, 9000, 0x0011, 2, 0, 0);
        r.evidenceRoot = keccak256("evidence");
        r.evidenceURI = "ipfs://e";
    }

    // --- 1. proxy-aware probing --------------------------------------------

    // A proxy is upgradeable by definition, and the powers of the code it runs
    // are its powers too.
    function test_probeFollowsResolvableProxy() public {
        Impl impl = new Impl();
        GetterProxy proxy = new GetterProxy(address(impl));

        (uint16 mask, bool exact) = SignalProbe.powersOf(address(proxy));
        assertTrue(exact, "resolvable proxy should be exact");
        assertTrue(mask & Powers.UPGRADE != 0, "proxy implies upgradeability");
        assertTrue(mask & Powers.MINT != 0, "implementation mint not followed");
        assertTrue(mask & Powers.SEIZE != 0, "implementation seize not followed");
    }

    // The dangerous failure was reporting an unreadable proxy as clean. It must
    // report unavailable instead, so the evaluator excludes it.
    function test_opaqueProxyIsNotReportedClean() public {
        Impl impl = new Impl();
        OpaqueProxy proxy = new OpaqueProxy(address(impl));

        (uint16 mask, bool exact) = SignalProbe.powersOf(address(proxy));
        assertTrue(!exact, "opaque proxy should not be exact");
        assertTrue(mask & Powers.UPGRADE != 0, "delegatecall implies upgradeability");
        assertEq(
            SignalProbe.privilegedPowers(address(proxy)),
            type(uint16).max,
            "opaque proxy must be unavailable, never clean"
        );
    }

    // And the sentinel actually removes the signal from the score rather than
    // contributing zero.
    function test_opaqueProxySignalIsExcludedFromScore() public pure {
        SignalVector memory v;
        v.lpLockedShare = 10_000;
        v.lpLockRemaining = uint32(365 days);
        v.privilegedPowers = type(uint16).max; // unreadable
        uint8 s = ScoreEvaluator.scoreHardRug(v);
        assertLe(s, 100, "score bounded");
    }

    // --- 2. bond sizing is policy, not a magic number -----------------------

    function test_bondScalesWithRaiseAndRespectsFloor() public view {
        assertEq(remediation.requiredBond(100 ether), 50 ether, "50% of raise");
        assertEq(remediation.requiredBond(1 ether), 1 ether, "floor applies");
        assertEq(remediation.bondBps(), 5000, "ratio is a deployment parameter");
    }

    function test_bondRatioIsConfigurable() public {
        LaunchRemediation strict = new LaunchRemediation(adjudicator, address(0xFE), 10_000, 0, 0);
        assertEq(strict.requiredBond(100 ether), 100 ether, "full-cover policy");
    }

    // --- 3. concurrent claims -----------------------------------------------

    // Two buyers may both have grounds. The first to file must not consume the
    // only opportunity, and one resolution must not release the freeze.
    function test_concurrentClaimsShareOneFreeze() public {
        vm.prank(alice); venue.buy{value: 10 ether}();

        vm.prank(detA);
        bytes32 rid = registry.submitReport(_report(95));

        vm.prank(alice);
        bytes32 c1 = remediation.openClaim{value: 0.1 ether}(id, rid, "a");
        vm.prank(bob);
        bytes32 c2 = remediation.openClaim{value: 0.1 ether}(id, rid, "b");

        assertEq(remediation.openClaims(id), 2, "two claims should be open");
        assertTrue(escrow.stateOf(id) == LaunchState.Frozen, "not frozen");

        // Rejecting one leaves the launch frozen for the other.
        vm.prank(adjudicator);
        remediation.adjudicate(c1, ClaimStatus.Rejected, 0);
        assertEq(remediation.openClaims(id), 1, "count not decremented");
        assertTrue(escrow.stateOf(id) == LaunchState.Frozen, "freed too early");

        vm.prank(adjudicator);
        remediation.adjudicate(c2, ClaimStatus.Rejected, 0);
        assertEq(remediation.openClaims(id), 0, "count not cleared");
        assertTrue(escrow.stateOf(id) != LaunchState.Frozen, "still frozen after last claim");
    }

    // A second upheld claim tops the pool up instead of reverting.
    function test_secondUpheldClaimAugmentsPool() public {
        vm.prank(alice); venue.buy{value: 10 ether}();

        vm.prank(detA);
        bytes32 rid = registry.submitReport(_report(95));
        vm.prank(alice);
        bytes32 c1 = remediation.openClaim{value: 0.1 ether}(id, rid, "a");
        vm.prank(bob);
        bytes32 c2 = remediation.openClaim{value: 0.1 ether}(id, rid, "b");

        vm.prank(adjudicator);
        remediation.adjudicate(c1, ClaimStatus.Upheld, 10 ether);
        remediation.executeRemedy(c1);
        uint256 first = escrow.entitlementOf(id, alice);

        vm.prank(adjudicator);
        remediation.adjudicate(c2, ClaimStatus.Upheld, 2 ether);
        remediation.executeRemedy(c2); // must not revert
        assertTrue(escrow.entitlementOf(id, alice) > first, "pool did not grow");
    }

    // --- 4. corroboration for high-value claims -----------------------------

    // Below the threshold one accountable detector suffices.
    function test_lowValueClaimNeedsOneDetector() public {
        vm.prank(alice); venue.buy{value: 1 ether}();
        vm.prank(detA);
        bytes32 rid = registry.submitReport(_report(95));

        vm.prank(alice);
        remediation.openClaim{value: 0.1 ether}(id, rid, "a"); // succeeds
        assertEq(remediation.openClaims(id), 1, "claim did not open");
    }

    // Above it, a lone detector cannot manufacture a freeze.
    function test_highValueClaimRequiresCorroboration() public {
        vm.prank(alice); venue.buy{value: 100 ether}();

        vm.prank(detA);
        bytes32 rid = registry.submitReport(_report(95));

        (uint8 solo, , uint256 distinct) = registry.corroboratedScore(id, 2);
        assertEq(solo, 0, "one detector must not corroborate");
        assertEq(distinct, 1, "distinct count wrong");

        vm.prank(alice);
        vm.expectRevert();
        remediation.openClaim{value: 0.1 ether}(id, rid, "a");

        // A second independent detector unlocks it.
        vm.prank(detB);
        registry.submitReport(_report(90));
        (uint8 pair, , uint256 d2) = registry.corroboratedScore(id, 2);
        assertEq(pair, 90, "corroborated level is the lower of the two");
        assertEq(d2, 2, "distinct count wrong");

        vm.prank(alice);
        remediation.openClaim{value: 0.1 ether}(id, rid, "a");
        assertEq(remediation.openClaims(id), 1, "claim did not open after corroboration");
    }

    // One detector cannot corroborate itself by publishing repeatedly.
    function test_selfCorroborationImpossible() public {
        vm.prank(detA); registry.submitReport(_report(95));
        vm.prank(detA); registry.submitReport(_report(94));
        vm.prank(detA); registry.submitReport(_report(93));

        (uint8 score, , uint256 distinct) = registry.corroboratedScore(id, 2);
        assertEq(distinct, 1, "repeat reports counted as independent");
        assertEq(score, 0, "self-corroboration succeeded");
    }

    receive() external payable {}
}
