// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {LaunchDirectory} from "../src/LaunchDirectory.sol";
import {LaunchEscrow} from "../src/LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "../src/LaunchAbuseRegistry.sol";
import {LaunchRemediation} from "../src/LaunchRemediation.sol";
import {LaunchDetector} from "../src/LaunchDetector.sol";
import {SaleVenue} from "../src/SaleVenue.sol";
import {ScoreEvaluator} from "../src/ScoreEvaluator.sol";
import {
    AbuseReport,
    SignalVector,
    ImpersonationSignals,
    ClaimStatus,
    Patterns,
    Schemas,
    UnsupportedVectorVersion,
    InsufficientScore,
    UnknownExtensionSchema,
    InvalidSignalVector
} from "../src/LaunchAbuseTypes.sol";

/// @dev The extension mechanism and the reference schema that exercises it.
///      A pattern that can be named but not scored is an identifier rather than
///      a detection, and impersonation is the case that proves it: every base
///      signal reads clean while the token is a copy of someone else's.
contract ExtensionTest is TestBase {
    LaunchDirectory     internal dir;
    LaunchRemediation   internal rem;
    LaunchAbuseRegistry internal reg;
    LaunchEscrow        internal esc;
    LaunchDetector      internal det;
    SaleVenue           internal ven;

    address internal adj      = address(0xAD);
    address internal feeSink  = address(0xFE);
    address internal dep      = address(0xD1);
    address internal detector = address(0xDE);
    address internal alice    = address(0xA1);
    address internal token    = address(0x70);

    bytes32 internal id;
    uint64  internal start;

    function setUp() public {
        dir = new LaunchDirectory();
        rem = new LaunchRemediation(adj, feeSink, 5000, 1 ether, 1000 ether);
        reg = new LaunchAbuseRegistry(address(rem));
        esc = new LaunchEscrow(address(rem), dir);
        rem.initialize(esc, reg);
        det = new LaunchDetector(dir);
        ven = new SaleVenue(esc);

        start = uint64(block.timestamp);
        id = ven.open{value: 5 ether}(token, dep, start, uint64(block.timestamp + 30 days), 1);

        vm.deal(alice, 100 ether);
        vm.deal(detector, 100 ether);
        vm.deal(dep, 100 ether);
        vm.prank(detector);
        reg.bondDetector{value: 1 ether}();
    }

    // --- helpers ------------------------------------------------------------

    /// @dev A launch that reads clean on every one of the twelve base signals:
    ///      no retained supply, liquidity locked, no privileged powers.
    function _cleanVector() internal pure returns (SignalVector memory) {
        return SignalVector(0, 0, 0, 10_000, uint32(365 days), 0, 0, 0, 0, 0, 0, 0);
    }

    function _impersonationReport(ImpersonationSignals memory ext)
        internal
        view
        returns (AbuseReport memory r)
    {
        r.patternId = Patterns.IMPERSONATION;
        r.launchId = id;
        r.token = token;
        r.deployer = dep;
        r.linkedAddresses = new address[](0);
        r.abuseScore = 70;
        r.confidence = 85;
        r.vectorVersion = 1;
        r.launchedAt = start;
        r.windowEnd = uint64(block.timestamp);
        r.signals = _cleanVector();
        r.extensionSchema = Schemas.IMPERSONATION;
        r.extensionSignals = abi.encode(ext);
        r.evidenceRoot = keccak256("e");
        r.evidenceURI = "ipfs://e";
    }

    // --- 19. version -------------------------------------------------------

    /// @dev A vector of an unknown version must be refused, not read as though
    ///      it were version 1. Misreading it silently is the worse failure.
    function test_19_unsupportedVectorVersionRejected() public {
        AbuseReport memory r = _impersonationReport(ImpersonationSignals(1, 9_000, 0));
        r.vectorVersion = 2;

        vm.prank(detector);
        vm.expectPartialRevert(UnsupportedVectorVersion.selector);
        reg.submitReport(r);
    }

    function test_19_versionZeroIsNotAVersion() public {
        AbuseReport memory r = _impersonationReport(ImpersonationSignals(1, 9_000, 0));
        r.vectorVersion = 0;

        vm.prank(detector);
        vm.expectPartialRevert(UnsupportedVectorVersion.selector);
        reg.submitReport(r);
    }

    /// @dev Schema and payload travel together: a schema with nothing under it
    ///      claims a reading nobody made, and a payload with no schema is bytes
    ///      nobody can decode.
    function test_19_schemaAndPayloadTravelTogether() public {
        AbuseReport memory r = _impersonationReport(ImpersonationSignals(1, 9_000, 0));
        r.extensionSignals = "";

        vm.prank(detector);
        vm.expectRevert(InvalidSignalVector.selector);
        reg.submitReport(r);

        AbuseReport memory r2 = _impersonationReport(ImpersonationSignals(1, 9_000, 0));
        r2.extensionSchema = bytes32(0);

        vm.prank(detector);
        vm.expectRevert(InvalidSignalVector.selector);
        reg.submitReport(r2);
    }

    function test_19_baseReportNeedsNoExtension() public {
        AbuseReport memory r = _impersonationReport(ImpersonationSignals(1, 9_000, 0));
        r.patternId = Patterns.HARD_RUG;
        r.extensionSchema = bytes32(0);
        r.extensionSignals = "";

        vm.prank(detector);
        bytes32 rid = reg.submitReport(r);
        assertTrue(rid != bytes32(0), "a report using no extension must still submit");
    }

    // --- 20. extension signals score on identical terms ---------------------

    /// @dev The whole point of the schema: a clean base vector still scores,
    ///      because the abuse is entirely in the identity claim.
    function test_20_impersonationScoresFromExtensionAlone() public pure {
        // Ticker of an older token, name 90% similar, no metadata reuse.
        bytes memory ext = abi.encode(ImpersonationSignals(0x0002, 9_000, 0));

        uint8 s = ScoreEvaluator.scoreFor(
            Patterns.IMPERSONATION, _cleanVector(), Schemas.IMPERSONATION, ext
        );

        // symbolCollision 40 at full, nameSimilarity 30 at full, metadataReuse
        // 20 at zero, priorUpheldClaims 10 at zero: 70 of a possible 100.
        assertEq(s, 70, "extension signals did not carry the score");
        assertTrue(s >= 41, "impersonation must reach at least the Elevated band");
    }

    /// @dev Without the extension the same launch is invisible: every base
    ///      signal is clean and only `priorUpheldClaims` carries any weight.
    function test_20_baseVectorAloneCannotSeeIt() public pure {
        uint8 s = ScoreEvaluator.scoreFor(Patterns.IMPERSONATION, _cleanVector());
        assertEq(s, 0, "a clean base vector must not score impersonation");
    }

    /// @dev An unavailable extension field is excluded from both sums, exactly
    ///      as a base signal is. Treating it as zero would let a detector
    ///      suppress a field for free and lower every score by its weight.
    function test_20_unavailableExtensionFieldIsExcluded() public pure {
        uint16 unavailable = type(uint16).max;

        uint8 asZero = ScoreEvaluator.scoreFor(
            Patterns.IMPERSONATION,
            _cleanVector(),
            Schemas.IMPERSONATION,
            abi.encode(ImpersonationSignals(0x0002, 9_000, 0))
        );
        uint8 excluded = ScoreEvaluator.scoreFor(
            Patterns.IMPERSONATION,
            _cleanVector(),
            Schemas.IMPERSONATION,
            abi.encode(ImpersonationSignals(0x0002, 9_000, unavailable))
        );

        // 70 with metadataReuse weighted at zero; 88 with it excluded entirely.
        assertEq(asZero, 70, "zero-valued field scored wrongly");
        assertEq(excluded, 88, "unavailable field was not excluded from both sums");
        assertTrue(excluded > asZero, "unavailable must not be scored as zero");
    }

    /// @dev A symbol collision is categorical: sharing the ticker of an older
    ///      token is not twice as bad as sharing that of any token.
    function test_20_symbolCollisionIsCategorical() public pure {
        uint8 any = ScoreEvaluator.scoreFor(
            Patterns.IMPERSONATION,
            _cleanVector(),
            Schemas.IMPERSONATION,
            abi.encode(ImpersonationSignals(0x0001, 0, 0))
        );
        uint8 all = ScoreEvaluator.scoreFor(
            Patterns.IMPERSONATION,
            _cleanVector(),
            Schemas.IMPERSONATION,
            abi.encode(ImpersonationSignals(0x0007, 0, 0))
        );
        assertEq(any, all, "collision class must not scale the contribution");
    }

    /// @dev A schema nobody can decode is not a detection either.
    function test_20_unknownSchemaCannotBeScored() public {
        vm.expectPartialRevert(UnknownExtensionSchema.selector);
        this.scoreUnknown();
    }

    function scoreUnknown() external pure returns (uint8) {
        return ScoreEvaluator.scoreFor(
            Patterns.IMPERSONATION,
            _cleanVector(),
            keccak256("erc.launch.schema.invented"),
            abi.encode(ImpersonationSignals(1, 1, 1))
        );
    }

    // --- 21. evidence leaves ------------------------------------------------

    /// @dev An extension field's leaf must not be presentable as a base
    ///      signal's, or a detector could prove membership of the wrong claim.
    function test_21_extensionFieldIdCannotCollide() public view {
        bytes32 ext = det.extensionFieldId(Schemas.IMPERSONATION, "nameSimilarity");
        bytes32 base = keccak256("nameSimilarity");
        assertTrue(ext != base, "extension fieldId collided with a bare field name");

        bytes32 other = det.extensionFieldId(keccak256("erc.launch.schema.other"), "nameSimilarity");
        assertTrue(ext != other, "the same field name in two schemas shares an id");

        assertTrue(
            ext == keccak256(abi.encode(Schemas.IMPERSONATION, "nameSimilarity")),
            "fieldId is not derivable by a third party"
        );
    }

    // --- 22. detector reward ------------------------------------------------

    function _executedClaim() internal returns (bytes32 claimId) {
        vm.prank(alice);
        ven.buy{value: 10 ether}();

        AbuseReport memory r = _impersonationReport(ImpersonationSignals(0x0002, 9_000, 0));
        r.abuseScore = 95;
        r.confidence = 90;

        vm.prank(detector);
        bytes32 rid = reg.submitReport(r);
        vm.prank(alice);
        claimId = rem.openClaim{value: 0.1 ether}(id, rid, "x");

        vm.prank(adj);
        rem.adjudicate(claimId, ClaimStatus.Upheld, 12 ether);
        rem.executeRemedy(claimId);
    }

    /// @dev The detector recorded against the report is paid, never the caller.
    ///      A detector that was never wrong must still be able to earn.
    function test_22_detectorIsPaidFromRestitution() public {
        bytes32 claimId = _executedClaim();

        uint256 reserved = rem.detectorReward(claimId);
        assertTrue(reserved > 0, "no detector share was reserved");

        uint256 before = detector.balance;
        vm.prank(alice); // anyone may call; only the detector is paid
        uint256 paid = rem.claimDetectorReward(claimId);

        assertEq(paid, reserved, "amount paid differs from the amount reserved");
        assertEq(detector.balance - before, reserved, "the detector was not the recipient");
        assertEq(rem.detectorReward(claimId), 0, "the reward remained pullable");
    }

    function test_22_rewardCannotBePulledTwice() public {
        bytes32 claimId = _executedClaim();
        rem.claimDetectorReward(claimId);

        vm.expectRevert();
        rem.claimDetectorReward(claimId);
    }

    /// @dev Nothing is owed until the remedy has actually executed.
    function test_22_noRewardBeforeExecution() public {
        vm.prank(alice);
        ven.buy{value: 10 ether}();

        AbuseReport memory r = _impersonationReport(ImpersonationSignals(0x0002, 9_000, 0));
        r.abuseScore = 95;
        r.confidence = 90;

        vm.prank(detector);
        bytes32 rid = reg.submitReport(r);
        vm.prank(alice);
        bytes32 claimId = rem.openClaim{value: 0.1 ether}(id, rid, "x");

        vm.expectRevert();
        rem.claimDetectorReward(claimId);
    }

    /// @dev The cited report is the one whose detector is paid, so it must
    ///      carry the claim itself. Otherwise a claimant bonds as a detector,
    ///      files a worthless report of their own, cites that instead of the
    ///      real one, and collects the detector's share of somebody else's work.
    function test_22_citedReportMustSupportTheClaim() public {
        vm.prank(alice);
        ven.buy{value: 10 ether}();

        AbuseReport memory real = _impersonationReport(ImpersonationSignals(0x0002, 9_000, 0));
        real.abuseScore = 95;
        real.confidence = 90;
        vm.prank(detector);
        reg.submitReport(real);

        // The claimant bonds as a detector and files a report worth nothing.
        vm.prank(alice);
        reg.bondDetector{value: 1 ether}();
        AbuseReport memory junk = _impersonationReport(ImpersonationSignals(0, 0, 0));
        junk.abuseScore = 0;
        junk.confidence = 0;
        vm.prank(alice);
        bytes32 junkId = reg.submitReport(junk);

        // The launch scores 95 through the real report, so without the check
        // the claim would open on a citation that contributed nothing.
        vm.prank(alice);
        vm.expectPartialRevert(InsufficientScore.selector);
        rem.openClaim{value: 0.1 ether}(id, junkId, "x");
    }

    /// @dev A reservation left inside the bond must be visible to every later
    ///      spending decision, or the next upheld claim sweeps it into the
    ///      refund pool and the first detector is owed money that has gone.
    function test_22_reservationSurvivesASecondClaim() public {
        vm.prank(alice);
        ven.buy{value: 10 ether}();

        address detector2 = address(0xD2);
        vm.deal(detector2, 100 ether);
        vm.prank(detector2);
        reg.bondDetector{value: 1 ether}();

        AbuseReport memory r1 = _impersonationReport(ImpersonationSignals(0x0002, 9_000, 0));
        r1.abuseScore = 95; r1.confidence = 90;
        vm.prank(detector);
        bytes32 rid1 = reg.submitReport(r1);

        AbuseReport memory r2 = _impersonationReport(ImpersonationSignals(0x0004, 9_500, 0));
        r2.abuseScore = 90; r2.confidence = 85;
        vm.prank(detector2);
        bytes32 rid2 = reg.submitReport(r2);

        vm.prank(alice);
        bytes32 c1 = rem.openClaim{value: 0.1 ether}(id, rid1, "x");
        vm.prank(alice);
        bytes32 c2 = rem.openClaim{value: 0.1 ether}(id, rid2, "y");

        vm.prank(adj);
        rem.adjudicate(c1, ClaimStatus.Upheld, 12 ether);
        rem.executeRemedy(c1);

        uint256 reserved1 = rem.detectorReward(c1);
        assertTrue(reserved1 > 0, "first claim reserved nothing");

        vm.prank(adj);
        rem.adjudicate(c2, ClaimStatus.Upheld, 10 ether);
        rem.executeRemedy(c2);

        uint256 reserved2 = rem.detectorReward(c2);
        assertLe(reserved1 + reserved2, esc.bondOf(id), "reservations exceed the bond behind them");

        uint256 before1 = detector.balance;
        rem.claimDetectorReward(c1);
        assertEq(detector.balance - before1, reserved1, "first detector was not paid in full");

        uint256 before2 = detector2.balance;
        rem.claimDetectorReward(c2);
        assertEq(detector2.balance - before2, reserved2, "second detector was not paid in full");

        assertEq(rem.reservedBond(id), 0, "reservation outlived both pulls");
    }

    /// @dev The detector's share is bounded by the adjudication fee, so
    ///      detection cannot quietly become the larger levy on restitution.
    function test_22_detectorFeeNeverExceedsFee() public view {
        assertLe(rem.detectorFeeBps(), rem.feeBps(), "detector fee exceeds the adjudication fee");
    }
}
