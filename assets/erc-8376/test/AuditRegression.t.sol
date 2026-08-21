// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {SignalProbe} from "../src/SignalProbe.sol";
import {Powers} from "../src/LaunchAbuseTypes.sol";
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

    /// @dev A token cannot decide which of its own bytecode gets examined.
    ///      Declaring a region as metadata used to remove it from the scan, so
    ///      a dispatch table placed there read as absent. Nothing is trimmed
    ///      now: the selector is found wherever the token put it.
    function test_selectorHiddenInDeclaredMetadataIsFound() public {
        bytes memory code = new bytes(80);
        for (uint256 i = 0; i < 40; ++i) code[i] = 0x60; // PUSH1 filler
        code[40] = 0xa1;                                  // CBOR map header
        code[41] = 0x5b;                                  // JUMPDEST
        code[42] = 0x63;                                  // PUSH4
        code[43] = 0x40; code[44] = 0xc1; code[45] = 0x0f; code[46] = 0x19; // mint
        uint256 mlen = 80 - 2 - 40;
        code[78] = bytes1(uint8(mlen >> 8));
        code[79] = bytes1(uint8(mlen));

        vm.etch(address(0xC0DE), code);

        (uint16 mask, bool exact) = SignalProbe.powersOf(address(0xC0DE));
        assertTrue(mask & Powers.MINT != 0, "a selector declared as metadata went unread");
        assertTrue(exact, "an ordinary contract was reported unexaminable");
    }

    /// @dev The constant is what identifies the power. How it reaches the stack
    ///      is the author's choice: PUSH5 with a leading zero pushes the same
    ///      value, and a dispatcher can keep its constants as data and CODECOPY
    ///      them in. Keying on PUSH4 missed both.
    function test_selectorIsFoundWhateverCarriesIt() public {
        bytes memory push5 = new bytes(12);
        push5[0] = 0x64;                                   // PUSH5
        push5[1] = 0x00;
        push5[2] = 0x40; push5[3] = 0xc1; push5[4] = 0x0f; push5[5] = 0x19; // mint
        vm.etch(address(0xC0E1), push5);
        assertTrue(
            SignalProbe.hasSelector(address(0xC0E1), bytes4(keccak256("mint(address,uint256)"))),
            "a selector pushed as PUSH5 went unread"
        );

        bytes memory asData = new bytes(12);
        asData[6] = 0x84; asData[7] = 0x56; asData[8] = 0xcb; asData[9] = 0x59; // pause
        vm.etch(address(0xC0E2), asData);
        assertTrue(
            SignalProbe.hasSelector(address(0xC0E2), bytes4(keccak256("pause()"))),
            "a selector held as data went unread"
        );
    }

    /// @dev CALLCODE runs foreign code against this contract's own storage. For
    ///      everything this signal is for, that is delegation, and reading it as
    ///      an ordinary contract certifies an upgradeable token as powerless.
    function test_callcodeCountsAsDelegation() public {
        bytes memory code = new bytes(8);
        code[0] = 0x60; code[1] = 0x00; // PUSH1 0
        code[2] = 0xf2;                 // CALLCODE
        code[3] = 0x00;                 // STOP

        vm.etch(address(0xC0DF), code);

        (, bool isProxy, bool resolved) = SignalProbe.implementationOf(address(0xC0DF));
        assertTrue(isProxy, "callcode was not read as delegation");
        assertTrue(!resolved, "an unresolvable delegate reported as resolved");
        assertEq(SignalProbe.privilegedPowers(address(0xC0DF)), type(uint16).max, "not the sentinel");
    }

}
