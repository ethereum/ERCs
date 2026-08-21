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
import {
    AbuseReport,
    SignalVector,
    ImpersonationSignals,
    ClaimStatus,
    Patterns,
    Schemas,
    InvalidSignalVector
} from "../src/LaunchAbuseTypes.sol";

/// @dev Regressions for the second audit pass. Each of these passed review as
///      written and failed it on the second reading.
contract AuditRegressionTest is TestBase {
    LaunchDirectory     internal dir;
    LaunchRemediation   internal rem;
    LaunchAbuseRegistry internal reg;
    LaunchEscrow        internal esc;
    SaleVenue           internal ven;

    address internal adj      = address(0xAD);
    address internal dep      = address(0xD1);
    address internal detector = address(0xDE);
    address internal alice    = address(0xA1);
    address internal token    = address(0x70);

    bytes32 internal id;
    uint64  internal start;

    function setUp() public {
        dir = new LaunchDirectory();
        rem = new LaunchRemediation(adj, address(0xFE), 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        esc = new LaunchEscrow(address(rem), dir);
        rem.initialize(esc, reg);
        ven = new SaleVenue(esc);

        start = uint64(block.timestamp);
        id = ven.open{value: 5 ether}(token, dep, start, uint64(block.timestamp + 30 days), 1);

        vm.deal(alice, 100 ether);
        vm.deal(dep, 100 ether);
        vm.deal(detector, 100 ether);
        vm.prank(detector);
        reg.bondDetector{value: 1 ether}();
    }

    function _report(uint8 score) internal view returns (AbuseReport memory r) {
        r.patternId = Patterns.HARD_RUG;
        r.launchId = id;
        r.token = token;
        r.deployer = dep;
        r.linkedAddresses = new address[](0);
        r.abuseScore = score;
        r.confidence = 90;
        r.vectorVersion = 1;
        r.launchedAt = start;
        r.windowEnd = uint64(block.timestamp);
        r.signals = SignalVector(0, 0, 0, 0, 0, 6000, 7000, 9000, 0x0011, 2, 0, 0);
        r.evidenceRoot = keccak256("e");
        r.evidenceURI = "ipfs://e";
    }

    function _claim() internal returns (bytes32 claimId) {
        vm.prank(alice);
        ven.buy{value: 10 ether}();
        vm.prank(detector);
        bytes32 rid = reg.submitReport(_report(95));
        vm.prank(alice);
        claimId = rem.openClaim{value: 0.1 ether}(id, rid, "x");
    }

    // --- settlement ---------------------------------------------------------

    /// @dev The claimant agrees to a figure, not to whatever is standing when
    ///      their transaction lands. Without the expected amount, the deployer
    ///      replaces five ether with one wei in front of the acceptance and the
    ///      claim closes anyway: terminal, unfrozen, and worth nothing.
    function test_offerCannotBeSwappedUnderTheClaimant() public {
        bytes32 cid = _claim();

        vm.prank(dep);
        rem.settle{value: 5 ether}(cid, 5 ether);

        // The deployer front-runs the acceptance with a smaller offer.
        vm.prank(dep);
        rem.settle{value: 1}(cid, 1);

        vm.prank(alice);
        vm.expectRevert();
        rem.acceptSettlement(cid, 5 ether);

        (, , ClaimStatus st, ) = rem.getClaim(cid);
        assertTrue(st != ClaimStatus.Settled, "the claim settled at the swapped figure");

        // Accepting the offer that actually stands still works.
        vm.prank(alice);
        rem.acceptSettlement(cid, 1);
        (, , ClaimStatus after_, ) = rem.getClaim(cid);
        assertTrue(after_ == ClaimStatus.Settled, "the standing offer could not be accepted");
    }

    // --- the detector pool --------------------------------------------------

    /// @dev A pool that only ever fills is value taken from claimants and given
    ///      to nobody. It must reach a detector.
    function test_detectorPoolPaysOut() public {
        // A rejected claim forfeits half the bond into the pool.
        bytes32 rejected = _claim();
        vm.prank(adj);
        rem.adjudicate(rejected, ClaimStatus.Rejected, 0);
        uint256 pooled = reg.detectorPool();
        assertTrue(pooled > 0, "the pool was never funded");

        // A later upheld claim pays its detector, topped up from the pool.
        vm.prank(detector);
        bytes32 rid = reg.submitReport(_report(96));
        vm.prank(alice);
        bytes32 upheld = rem.openClaim{value: 0.1 ether}(id, rid, "y");
        vm.prank(adj);
        rem.adjudicate(upheld, ClaimStatus.Upheld, 12 ether);
        rem.executeRemedy(upheld);

        uint256 before = detector.balance;
        uint256 paid = rem.claimDetectorReward(upheld);

        assertTrue(paid > 0, "no reward was paid");
        assertEq(detector.balance - before, paid, "the detector did not receive the reward");
        assertLt(reg.detectorPool(), pooled, "the pool did not contribute");
    }

    // --- scoring ------------------------------------------------------------

    /// @dev A schema whose every field is unavailable is a declaration, not a
    ///      reading. Scoring it drops ninety of the hundred weight and leaves
    ///      one prior claim reaching 100 on no impersonation evidence.
    function test_declaredSchemaWithNothingInItCannotScore() public {
        uint16 u = type(uint16).max;
        vm.expectPartialRevert(InvalidSignalVector.selector);
        this.scoreEmptyExtension(u);
    }

    function scoreEmptyExtension(uint16 u) external pure returns (uint8) {
        SignalVector memory v = SignalVector(0, 0, 0, 10_000, uint32(365 days), 0, 0, 0, 0, 1, 0, 0);
        return ScoreEvaluator.scoreFor(
            Patterns.IMPERSONATION,
            v,
            Schemas.IMPERSONATION,
            abi.encode(ImpersonationSignals(u, u, u))
        );
    }

    // --- the bytecode scan --------------------------------------------------

    /// @dev The trailing length is written by the token. Pointing it at a region
    ///      that carries DELEGATECALL must not trim that region out of view:
    ///      the token would then read as an ordinary contract with no
    ///      privileged powers, which is an exculpatory answer drawn from
    ///      evidence never examined.
    function test_metadataHintCannotHideDelegation() public {
        address crafted = address(0xC0DE);

        // 40 bytes of ordinary-looking front matter, then a tail that opens with
        // a CBOR map header, carries a DELEGATECALL, and declares its own length.
        bytes memory code = new bytes(80);
        for (uint256 i = 0; i < 40; ++i) code[i] = 0x60; // PUSH1 filler
        code[40] = 0xa1;                                  // CBOR map header
        code[60] = 0xf4;                                  // DELEGATECALL, hidden in the "metadata"
        uint256 mlen = 80 - 2 - 40;                       // trim would start at 40
        code[78] = bytes1(uint8(mlen >> 8));
        code[79] = bytes1(uint8(mlen));

        vm.etch(crafted, code);

        (, bool isProxy, bool resolved) = SignalProbe.implementationOf(crafted);
        assertTrue(isProxy, "delegation in the declared metadata was trimmed out of view");
        assertTrue(!resolved, "an unresolvable proxy reported as resolved");

        (, bool exact) = SignalProbe.powersOf(crafted);
        assertTrue(!exact, "a token that hid its delegation was certified exact");
    }
}
