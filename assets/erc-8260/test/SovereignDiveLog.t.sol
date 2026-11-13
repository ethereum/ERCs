// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {SovereignDiveLog} from "../SovereignDiveLog.sol";
import {IDiveLog} from "../interfaces/IDiveLog.sol";
import {IDiveLogTypes} from "../interfaces/IDiveLogTypes.sol";
import {DiveLogTypedData} from "../interfaces/IDiveLogTypedData.sol";

/// @dev Minimal cheatcode interface (no forge-std dependency in this repository).
interface Vm {
    function addr(uint256 pk) external view returns (address);
    function sign(uint256 pk, bytes32 digest) external pure returns (uint8 v, bytes32 r, bytes32 s);
    function expectRevert(bytes4 selector) external;
    function expectRevert(bytes calldata revertData) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function readFile(string calldata path) external view returns (string memory);
}

contract SovereignDiveLogTest {
    // Canonical cheatcode precompile address (same as forge-std).
    Vm internal constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

    // Local mirrors of IDiveLog events (identical signatures) for expectEmit
    // (qualified emits from interfaces need Solidity >= 0.8.21; this repo pins 0.8.20).
    event DiveLogged(uint256 indexed diveId, uint32 indexed diveDate, bytes32 contentHash);
    event DiveVoided(uint256 indexed diveId, uint256 indexed supersededById, address indexed voidedBy, string reason);
    event DiveAttested(uint256 indexed diveId, address indexed attester, bytes32 contentHash);
    event AttestationNonceCancelled(address indexed attester, uint256 newNonce);

    // ------------------------------------------------ publishable constants
    // MUST equal type(IDiveLog).interfaceId and the literal published in ERCS/erc-8260.md.
    // Verified two ways: compiler probe (1300867321) and manual XOR of the 13 selectors.
    bytes4 internal constant EXPECTED_IDIVELOG_ID = 0x4d89a8f9;
    bytes4 internal constant ERC165_ID = 0x01ffc9a7;
    bytes4 internal constant INVALID_ID = 0xffffffff;

    SovereignDiveLog internal log;
    address internal owner = address(0xA11CE);
    uint256 internal attesterKey = 0xA77E571;
    address internal attester;
    uint256 internal attester2Key = 0xB0B005;
    address internal attester2;

    // secp256k1 group order (for the malleability test).
    uint256 internal constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    // 2026-05-14T13:00:00Z and its UTC calendar date.
    uint64 internal constant START = 1778763600;
    uint32 internal constant DATE = 20260514;
    // Derived instants for the default dive (leave bottom / reach surface).
    uint64 internal constant LEAVE_BOTTOM = 1778765100; // START + 1500
    uint64 internal constant REACH_SURFACE = 1778765460; // START + 1860
    // 1994-07-04T15:30:00Z (historic import).
    uint64 internal constant HISTORIC_START = 773335800;
    uint32 internal constant HISTORIC_DATE = 19940704;
    // 2026-05-15T09:00:00Z (date-mismatch test).
    uint64 internal constant NEXT_DAY_START = 1778835600;

    string internal constant FIXTURE = "./test/fixtures/minimal.uddf";

    // SHA-256 of the fixture, loaded once in setUp so input() makes no cheatcode
    // calls (vm.prank / vm.expectRevert would otherwise be consumed by readFile).
    bytes32 internal fixtureHash;

    function setUp() public {
        log = new SovereignDiveLog(owner);
        attester = vm.addr(attesterKey);
        attester2 = vm.addr(attester2Key);
        fixtureHash = sha256(bytes(vm.readFile(FIXTURE)));
    }

    // ------------------------------------------------------------- assertions

    function ok(bool c) internal pure {
        if (!c) revert("assertion failed");
    }

    function eq(uint256 a, uint256 b) internal pure {
        ok(a == b);
    }

    function eq32(bytes32 a, bytes32 b) internal pure {
        ok(a == b);
    }

    function eqStr(string memory a, string memory b) internal pure {
        ok(keccak256(bytes(a)) == keccak256(bytes(b)));
    }

    // ---------------------------------------------------------------- helpers

    function pad16(string memory s) internal pure returns (bytes16) {
        bytes memory b = bytes(s);
        require(b.length <= 16, "too long");
        bytes16 out;
        for (uint256 i; i < b.length; ++i) {
            out |= bytes16(b[i]) >> (8 * i);
        }
        return out;
    }

    function input() internal view returns (IDiveLogTypes.DiveInput memory) {
        return IDiveLogTypes.DiveInput({
            diveDate: DATE,
            startTime: START,
            maxDepth: 1820, // 182.0 FSW in tenths
            durationSeconds: 1860,
            bottomTimeSeconds: 1500,
            mode: IDiveLogTypes.DiveMode.OCRecreational,
            units: IDiveLogTypes.UnitSystem.Imperial,
            o2Bps: 2100,
            heBps: 0,
            tableSchedule: pad16("USN 60/40"),
            surfaceIntervalSeconds: 3600,
            repetitiveGroup: bytes1(0x46), // 'F'
            repetitiveGroupAfterSI: bytes1(0x43), // 'C'
            coarseGeohash: bytes4("dtnk"),
            contentHash: fixtureHash,
            profileURI: "ipfs://bafytest"
        });
    }

    function logDive() internal returns (uint256) {
        vm.prank(owner);
        return log.logDive(input());
    }

    function signAttestation(uint256 pk, uint256 diveId, bytes32 contentHash, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 digest = DiveLogTypedData.attestationDigest(diveId, contentHash, address(log), block.chainid, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    // =========================================================== ERC-165 / owner

    function test_interfaceId_matchesPublishedLiteral() public {
        ok(type(IDiveLog).interfaceId == EXPECTED_IDIVELOG_ID);
        ok(log.supportsInterface(EXPECTED_IDIVELOG_ID));
        ok(log.supportsInterface(ERC165_ID));
        ok(!log.supportsInterface(INVALID_ID));
    }

    function test_owner_isConstructorArgument() public {
        ok(log.owner() == owner);
    }

    // ================================================================= logging

    function test_logDive_assignsSequentialIdsStartingAtOne() public {
        vm.startPrank(owner);
        eq(log.logDive(input()), 1);
        eq(log.logDive(input()), 2);
        vm.stopPrank();
        eq(log.getDiveCount(), 2);
    }

    function test_logDive_storesThinHeaderAndEmitsDiveLogged() public {
        IDiveLogTypes.DiveInput memory i = input();
        vm.expectEmit(true, true, true, true);
        emit DiveLogged(1, i.diveDate, i.contentHash);
        vm.prank(owner);
        log.logDive(i);

        IDiveLogTypes.DiveHeader memory h = log.getDive(1);
        eq(h.id, 1);
        eq(h.diveDate, i.diveDate);
        eq(h.startTime, i.startTime);
        eq(h.maxDepth, i.maxDepth);
        eq(h.durationSeconds, i.durationSeconds);
        eq(h.bottomTimeSeconds, i.bottomTimeSeconds);
        ok(h.mode == i.mode);
        ok(h.units == i.units);
        eq(h.o2Bps, i.o2Bps);
        eq(h.heBps, i.heBps);
        ok(h.tableSchedule == i.tableSchedule);
        eq(h.surfaceIntervalSeconds, i.surfaceIntervalSeconds);
        ok(h.repetitiveGroup == i.repetitiveGroup);
        ok(h.repetitiveGroupAfterSI == i.repetitiveGroupAfterSI);
        ok(h.coarseGeohash == i.coarseGeohash);
        eq32(h.contentHash, i.contentHash);
        eqStr(h.profileURI, i.profileURI);
    }

    function test_logDive_storesBottomTimeAndDuration() public {
        logDive();
        IDiveLogTypes.DiveHeader memory h = log.getDive(1);
        ok(h.bottomTimeSeconds != 0);
        ok(h.durationSeconds >= h.bottomTimeSeconds);
        // Derived instants per the encodings: leave bottom and reach surface.
        eq(uint256(h.startTime) + h.bottomTimeSeconds, LEAVE_BOTTOM);
        eq(uint256(h.startTime) + h.durationSeconds, REACH_SURFACE);
    }

    function test_logDive_allowsZeroBottomTimeMeaningNotRecorded() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.bottomTimeSeconds = 0;
        vm.prank(owner);
        eq(log.logDive(i), 1);
        eq(log.getDive(1).bottomTimeSeconds, 0);
    }

    function test_logDive_revertsIfBottomTimeExceedsDuration() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.bottomTimeSeconds = i.durationSeconds + 1;
        vm.expectRevert(IDiveLog.InvalidTimes.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_storesTableScheduleRepetitiveGroupAndSurfaceInterval() public {
        logDive();
        IDiveLogTypes.DiveHeader memory h = log.getDive(1);
        ok(h.tableSchedule == pad16("USN 60/40"));
        ok(h.repetitiveGroup == bytes1("F"));
        ok(h.repetitiveGroupAfterSI == bytes1("C"));
        eq(h.surfaceIntervalSeconds, 3600);
    }

    function test_logDive_allowsZeroTableScheduleGroupAndSurfaceInterval() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.tableSchedule = bytes16(0);
        i.surfaceIntervalSeconds = 0;
        i.repetitiveGroup = 0x00;
        i.repetitiveGroupAfterSI = 0x00;
        vm.prank(owner);
        eq(log.logDive(i), 1);
        IDiveLogTypes.DiveHeader memory h = log.getDive(1);
        ok(h.tableSchedule == bytes16(0));
        ok(h.repetitiveGroup == 0x00);
        ok(h.repetitiveGroupAfterSI == 0x00);
        eq(h.surfaceIntervalSeconds, 0);
    }

    function test_logDive_storesEndOfDiveGroupWithoutAfterSI() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.repetitiveGroup = bytes1("D");
        i.repetitiveGroupAfterSI = 0x00;
        i.surfaceIntervalSeconds = 0;
        vm.prank(owner);
        log.logDive(i);
        IDiveLogTypes.DiveHeader memory h = log.getDive(1);
        ok(h.repetitiveGroup == bytes1("D"));
        ok(h.repetitiveGroupAfterSI == 0x00);
        eq(h.surfaceIntervalSeconds, 0);
    }

    function test_logDive_tableScheduleRightZeroPaddedRoundTrip() public {
        // Canonical storage: ASCII content, trailing 0x00, never trailing spaces.
        bytes16 stored = pad16("USN 60/40");
        ok(uint8(stored[9]) == 0x00 && uint8(stored[15]) == 0x00);
        ok(uint8(stored[8]) == uint8(bytes1("0"))); // last content char, not a space
        IDiveLogTypes.DiveInput memory i = input();
        i.tableSchedule = stored;
        vm.prank(owner);
        log.logDive(i);
        ok(log.getDive(1).tableSchedule == stored);
    }

    function test_logDive_revertsOnInvalidTableSchedule() public {
        // Interior NUL.
        IDiveLogTypes.DiveInput memory i = input();
        i.tableSchedule = bytes16(bytes.concat(bytes2("US"), bytes1(0x00), bytes13("N 60/40")));
        vm.expectRevert(IDiveLog.InvalidTableSchedule.selector);
        vm.prank(owner);
        log.logDive(i);

        // Non-printable byte (0x1F).
        i = input();
        i.tableSchedule = bytes16(bytes.concat(bytes4("USN "), bytes1(0x1F), bytes11("60/40")));
        vm.expectRevert(IDiveLog.InvalidTableSchedule.selector);
        vm.prank(owner);
        log.logDive(i);

        // Unknown first token.
        i = input();
        i.tableSchedule = pad16("MN90 60/40");
        vm.expectRevert(IDiveLog.InvalidTableSchedule.selector);
        vm.prank(owner);
        log.logDive(i);

        // Left-NUL padding (data after a NUL).
        i = input();
        i.tableSchedule = bytes16(bytes.concat(bytes1(0x00), bytes15("USN 60/40")));
        vm.expectRevert(IDiveLog.InvalidTableSchedule.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_revertsOnInvalidRepetitiveGroup() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.repetitiveGroup = bytes1(uint8(0x01));
        vm.expectRevert(IDiveLog.InvalidRepetitiveGroup.selector);
        vm.prank(owner);
        log.logDive(i);

        i = input();
        i.repetitiveGroup = bytes1("a");
        vm.expectRevert(IDiveLog.InvalidRepetitiveGroup.selector);
        vm.prank(owner);
        log.logDive(i);

        i = input();
        i.repetitiveGroupAfterSI = bytes1("[");
        vm.expectRevert(IDiveLog.InvalidRepetitiveGroup.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_revertsIfRepetitiveGroupWithoutTableSchedule() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.tableSchedule = bytes16(0);
        i.repetitiveGroupAfterSI = 0x00;
        i.surfaceIntervalSeconds = 0;
        vm.expectRevert(IDiveLog.InvalidRepetitiveGroup.selector);
        vm.prank(owner);
        log.logDive(i);

        i = input();
        i.tableSchedule = bytes16(0);
        i.repetitiveGroup = 0x00;
        i.surfaceIntervalSeconds = 3600;
        vm.expectRevert(IDiveLog.InvalidRepetitiveGroup.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_revertsIfAfterSIGroupWithoutSurfaceInterval() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.repetitiveGroupAfterSI = bytes1("C");
        i.surfaceIntervalSeconds = 0;
        vm.expectRevert(IDiveLog.InvalidRepetitiveGroup.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_acceptsSaturationMode() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.mode = IDiveLogTypes.DiveMode.Saturation;
        i.durationSeconds = 2_592_000; // a 30-day bell run
        i.bottomTimeSeconds = 2_400_000;
        vm.prank(owner);
        log.logDive(i);
        ok(log.getDive(1).mode == IDiveLogTypes.DiveMode.Saturation);
    }

    function test_logDive_succeedsWithoutAttestation() public {
        logDive();
        eq(log.attestationCount(1), 0);
        eq(log.getDive(1).id, 1); // still readable: valid self-reported record
    }

    function test_logDive_revertsForNonOwner() public {
        vm.expectRevert(IDiveLog.NotOwner.selector);
        log.logDive(input()); // test contract is not the owner
    }

    function test_logDive_revertsOnZeroMaxDepth() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.maxDepth = 0;
        vm.expectRevert(IDiveLog.InvalidDepth.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_revertsOnZeroDuration() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.durationSeconds = 0;
        i.bottomTimeSeconds = 0;
        vm.expectRevert(IDiveLog.InvalidTimes.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_revertsOnZeroOrInvalidDate() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.diveDate = 0;
        vm.expectRevert(IDiveLog.InvalidDate.selector);
        vm.prank(owner);
        log.logDive(i);

        i = input();
        i.diveDate = 20260230; // February 30 does not exist
        vm.expectRevert(IDiveLog.InvalidDate.selector);
        vm.prank(owner);
        log.logDive(i);

        i = input();
        i.diveDate = 20261301; // month 13
        vm.expectRevert(IDiveLog.InvalidDate.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_revertsWhenStartTimeDateMismatchesDiveDate() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.startTime = NEXT_DAY_START; // 2026-05-15
        vm.expectRevert(IDiveLog.InvalidDate.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_allowsHistoricStartTime() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.startTime = HISTORIC_START;
        i.diveDate = HISTORIC_DATE;
        vm.prank(owner);
        eq(log.logDive(i), 1);
        IDiveLogTypes.DiveHeader memory h = log.getDive(1);
        eq(h.startTime, HISTORIC_START);
        eq(h.diveDate, HISTORIC_DATE);
    }

    function test_logDive_revertsOnZeroContentHash() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.contentHash = bytes32(0);
        vm.expectRevert(IDiveLog.InvalidContentHash.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_revertsWhenGasSumExceeds10000() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.o2Bps = 6000;
        i.heBps = 4100;
        vm.expectRevert(IDiveLog.InvalidGasMix.selector);
        vm.prank(owner);
        log.logDive(i);
    }

    function test_logDive_acceptsFreediveZeroGas() public {
        IDiveLogTypes.DiveInput memory i = input();
        i.mode = IDiveLogTypes.DiveMode.Freedive;
        i.o2Bps = 0;
        i.heBps = 0;
        vm.prank(owner);
        eq(log.logDive(i), 1);
        IDiveLogTypes.DiveHeader memory h = log.getDive(1);
        eq(h.o2Bps, 0);
        eq(h.heBps, 0);
    }

    function test_contentHash_isSha256OfFixtureBytes() public {
        bytes32 expected = sha256(bytes(vm.readFile(FIXTURE)));
        ok(expected != bytes32(0));
        logDive();
        eq32(log.getDive(1).contentHash, expected);
    }

    // ================================================================== batch

    function test_batchLogDives_logsManyAndEmitsOnceEach() public {
        IDiveLogTypes.DiveInput[] memory inputs = new IDiveLogTypes.DiveInput[](3);
        for (uint256 i; i < 3; ++i) {
            inputs[i] = input();
        }
        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit DiveLogged(1, inputs[0].diveDate, inputs[0].contentHash);
        log.batchLogDives(inputs);
        vm.stopPrank();
        eq(log.getDiveCount(), 3);
        eq(log.getDive(1).id, 1);
        eq(log.getDive(2).id, 2);
        eq(log.getDive(3).id, 3);
    }

    function test_batchLogDives_revertsIfEmptyOrOverMax() public {
        IDiveLogTypes.DiveInput[] memory empty = new IDiveLogTypes.DiveInput[](0);
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.InvalidBatchSize.selector, 0));
        vm.prank(owner);
        log.batchLogDives(empty);

        IDiveLogTypes.DiveInput[] memory tooMany = new IDiveLogTypes.DiveInput[](101);
        for (uint256 i; i < 101; ++i) {
            tooMany[i] = input();
        }
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.InvalidBatchSize.selector, 101));
        vm.prank(owner);
        log.batchLogDives(tooMany);
    }

    function test_batchLogDives_revertsEntireBatchIfOneInvalid() public {
        IDiveLogTypes.DiveInput[] memory inputs = new IDiveLogTypes.DiveInput[](3);
        for (uint256 i; i < 3; ++i) {
            inputs[i] = input();
        }
        inputs[2].maxDepth = 0; // last item invalid
        vm.expectRevert(IDiveLog.InvalidDepth.selector);
        vm.prank(owner);
        log.batchLogDives(inputs);
        eq(log.getDiveCount(), 0); // no partial writes
    }

    // ================================================================== void

    function test_voidDive_revertsForNonOwner() public {
        logDive();
        vm.expectRevert(IDiveLog.NotOwner.selector);
        log.voidDive(1, 0, "typo");
    }

    function test_voidDive_marksVoidAndKeepsHeaderReadable() public {
        vm.startPrank(owner);
        log.logDive(input());
        log.logDive(input());
        vm.expectEmit(true, true, true, true);
        emit DiveVoided(1, 2, owner, "superseded");
        log.voidDive(1, 2, "superseded");
        vm.stopPrank();

        ok(log.isDiveVoided(1));
        eq(log.getDive(1).id, 1); // header still readable
        IDiveLogTypes.VoidInfo memory v = log.getVoidInfo(1);
        ok(v.isVoided);
        eq(v.supersededById, 2);
        ok(v.voidedBy == owner);
        eqStr(v.reason, "superseded");
    }

    function test_voidDive_revertsIfAlreadyVoided() public {
        logDive();
        vm.startPrank(owner);
        log.voidDive(1, 0, "typo");
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.DiveAlreadyVoided.selector, 1));
        log.voidDive(1, 0, "again");
        vm.stopPrank();
    }

    function test_voidDive_revertsIfTargetMissingOrSelf() public {
        logDive();
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.InvalidSupersede.selector, 1, 2));
        log.voidDive(1, 2, "missing target"); // 2 > diveCount
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.InvalidSupersede.selector, 1, 1));
        log.voidDive(1, 1, "self");
        vm.stopPrank();
    }

    function test_voidDive_revertsIfTargetAlreadyVoided() public {
        vm.startPrank(owner);
        log.logDive(input());
        log.logDive(input());
        log.voidDive(2, 0, "typo");
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.InvalidSupersede.selector, 1, 2));
        log.voidDive(1, 2, "chained");
        vm.stopPrank();
    }

    function test_voidDive_allowsVoidWithoutReplacement() public {
        logDive();
        vm.prank(owner);
        log.voidDive(1, 0, "wrong entry");
        IDiveLogTypes.VoidInfo memory v = log.getVoidInfo(1);
        eq(v.supersededById, 0);
        ok(v.isVoided);
    }

    // ============================================================ attestations

    function test_attestDive_recoversSignerAndBindsContentHash() public {
        logDive();
        bytes32 hash = log.getDive(1).contentHash;
        bytes memory sig = signAttestation(attesterKey, 1, hash, 0);
        vm.expectEmit(true, true, true, true);
        emit DiveAttested(1, attester, hash);
        log.attestDive(1, hash, 0, sig); // any address may submit

        eq(log.attestationCount(1), 1);
        IDiveLogTypes.Attestation memory a = log.getAttestation(1, 0);
        ok(a.attester == attester);
        eq(a.nonce, 0);
        eq(log.attesterNonce(attester), 1); // incremented
    }

    function test_attestDive_revertsIfContentHashDoesNotMatchStored() public {
        logDive();
        bytes32 wrong = sha256("not the stored hash");
        vm.expectRevert(IDiveLog.InvalidContentHash.selector);
        log.attestDive(1, wrong, 0, signAttestation(attesterKey, 1, wrong, 0));
    }

    function test_attestDive_revertsOnVoidedDive() public {
        logDive();
        vm.prank(owner);
        log.voidDive(1, 0, "voided");
        bytes32 hash = log.getDive(1).contentHash;
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.DiveAlreadyVoided.selector, 1));
        log.attestDive(1, hash, 0, signAttestation(attesterKey, 1, hash, 0));
    }

    function test_attestDive_revertsOnBadNonce() public {
        logDive();
        bytes32 hash = log.getDive(1).contentHash;
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.NonceMismatch.selector, 0, 1));
        log.attestDive(1, hash, 1, signAttestation(attesterKey, 1, hash, 1));
    }

    function test_attestDive_revertsOnMalleableS() public {
        logDive();
        bytes32 hash = log.getDive(1).contentHash;
        bytes32 digest = DiveLogTypedData.attestationDigest(1, hash, address(log), block.chainid, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attesterKey, digest);
        bytes32 sHigh = bytes32(N + 1 - uint256(s)); // s > secp256k1n/2
        vm.expectRevert(IDiveLog.InvalidSignature.selector);
        log.attestDive(1, hash, 0, abi.encodePacked(r, sHigh, v));
    }

    function test_attestDive_revertsOnReplayBySameAttester() public {
        logDive();
        bytes32 hash = log.getDive(1).contentHash;
        log.attestDive(1, hash, 0, signAttestation(attesterKey, 1, hash, 0));
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.AlreadyAttested.selector, 1, attester));
        log.attestDive(1, hash, 1, signAttestation(attesterKey, 1, hash, 1));
    }

    function test_attestDive_twoAttestersCanSignTheSameDive() public {
        logDive();
        bytes32 hash = log.getDive(1).contentHash;
        log.attestDive(1, hash, 0, signAttestation(attesterKey, 1, hash, 0));
        log.attestDive(1, hash, 0, signAttestation(attester2Key, 1, hash, 0));
        eq(log.attestationCount(1), 2);
    }

    function test_cancelAttestationNonce_invalidatesPendingSignature() public {
        logDive();
        bytes32 hash = log.getDive(1).contentHash;
        bytes memory pending = signAttestation(attesterKey, 1, hash, 0);
        vm.prank(attester);
        log.cancelAttestationNonce(); // 0 -> 1
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.NonceMismatch.selector, 1, 0));
        log.attestDive(1, hash, 0, pending);
        // New signatures must use nonce 1 and now succeed.
        log.attestDive(1, hash, 1, signAttestation(attesterKey, 1, hash, 1));
        eq(log.attestationCount(1), 1);
    }

    function test_cancelAttestationNonce_emitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit AttestationNonceCancelled(attester, 1);
        vm.prank(attester);
        log.cancelAttestationNonce();
        eq(log.attesterNonce(attester), 1);
    }

    // ================================================================== reads

    function test_getDive_revertsForUnknownId() public {
        logDive();
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.DiveNotFound.selector, 0));
        log.getDive(0);
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.DiveNotFound.selector, 2));
        log.getDive(2);
    }

    function test_getAttestation_revertsForOutOfRangeIndex() public {
        logDive();
        vm.expectRevert(abi.encodeWithSelector(IDiveLog.InvalidAttestationIndex.selector, 0));
        log.getAttestation(1, 0);
    }

    // =============================================================== typed data

    function test_domainSeparator_usesNameDiveLogAndVersion2() public {
        // Independent reconstruction of the domain separator and digest.
        bytes32 expectedDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("DiveLog"),
                keccak256("2"),
                block.chainid,
                address(log)
            )
        );
        eq32(DiveLogTypedData.domainSeparator(block.chainid, address(log)), expectedDomain);

        bytes32 contentHash = sha256("fixture stand-in");
        bytes32 expectedStruct = keccak256(
            abi.encode(
                keccak256("Attestation(uint256 diveId,bytes32 contentHash,address verifyingContract,uint256 nonce)"),
                uint256(7),
                contentHash,
                address(log),
                uint256(3)
            )
        );
        bytes32 expectedDigest =
            keccak256(abi.encodePacked("\x19\x01", expectedDomain, expectedStruct));
        eq32(
            DiveLogTypedData.attestationDigest(7, contentHash, address(log), block.chainid, 3),
            expectedDigest
        );
    }
}
