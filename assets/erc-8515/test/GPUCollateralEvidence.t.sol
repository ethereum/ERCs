// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IGPUCollateralEvidence} from "../contracts/IGPUCollateralEvidence.sol";
import {GPUCollateralEvidence} from "../contracts/GPUCollateralEvidence.sol";
import {ERC8515Lib} from "../contracts/ERC8515Lib.sol";

contract ERC8515LibHarness {
    function deviceKey(uint16 pciVendorId, uint8 idType, bytes memory idBytes) external pure returns (bytes32) {
        return ERC8515Lib.deviceKey(pciVendorId, idType, idBytes);
    }

    function statementRoot(bytes32[] memory sortedIds) external pure returns (bytes32) {
        return ERC8515Lib.statementRoot(sortedIds);
    }

    function domainSeparator(uint256 chainId, address registry) external pure returns (bytes32) {
        return ERC8515Lib.domainSeparator(chainId, registry);
    }

    function statementDigest(uint256 chainId, address registry, bytes32 statementId) external pure returns (bytes32) {
        return ERC8515Lib.statementDigest(chainId, registry, statementId);
    }
}

contract GPUCollateralEvidenceTest is Test {
    using stdJson for string;

    GPUCollateralEvidence internal registry;
    ERC8515LibHarness internal lib;

    address internal servicerA = address(0xA11CE);
    address internal servicerB = address(0xB0B);
    bytes32 internal collA = bytes32(uint256(0xC011));
    bytes32 internal collB = bytes32(uint256(0xC022));

    bytes32 internal dev1 = keccak256("dev1");
    bytes32 internal dev2 = keccak256("dev2");
    bytes32 internal dev3 = keccak256("dev3");

    function setUp() public {
        registry = new GPUCollateralEvidence();
        lib = new ERC8515LibHarness();
        vm.warp(1_735_800_000);
    }

    function _arr(bytes32 a) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](1);
        keys[0] = a;
    }

    function _arr(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](2);
        keys[0] = a;
        keys[1] = b;
    }

    function _arr(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory keys) {
        keys = new bytes32[](3);
        keys[0] = a;
        keys[1] = b;
        keys[2] = c;
    }

    // -------------------------------------------------------------------------
    // Pledge & release tests
    // -------------------------------------------------------------------------

    function test_pledgeAndReleaseBasic() public {
        uint64 t0 = uint64(block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit IGPUCollateralEvidence.DevicePledged(servicerA, collA, dev1);
        vm.expectEmit(true, true, true, true);
        emit IGPUCollateralEvidence.DevicePledged(servicerA, collA, dev2);

        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1, dev2));

        assertEq(registry.deviceCount(servicerA, collA), 2);
        assertTrue(registry.isPledged(servicerA, collA, dev1));
        assertTrue(registry.isPledged(servicerA, collA, dev2));
        assertFalse(registry.isPledged(servicerA, collA, dev3));
        assertEq(registry.pledgeCount(dev1), 1);

        (address s, bytes32 c, uint64 pledgedAt) = registry.pledgeAt(dev1, 0);
        assertEq(s, servicerA);
        assertEq(c, collA);
        assertEq(pledgedAt, t0);

        vm.expectEmit(true, true, true, true);
        emit IGPUCollateralEvidence.DeviceReleased(servicerA, collA, dev1);

        vm.prank(servicerA);
        registry.release(collA, _arr(dev1));

        assertEq(registry.deviceCount(servicerA, collA), 1);
        assertFalse(registry.isPledged(servicerA, collA, dev1));
        assertEq(registry.pledgeCount(dev1), 0);

        // Re-pledging after release records the new block timestamp.
        vm.warp(t0 + 500);
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1));
        (, , uint64 repledgedAt) = registry.pledgeAt(dev1, 0);
        assertEq(repledgedAt, t0 + 500);
    }

    function test_pledgeEmptyArrayNoOp() public {
        bytes32[] memory empty = new bytes32[](0);
        vm.prank(servicerA);
        registry.pledge(collA, empty);
        assertEq(registry.deviceCount(servicerA, collA), 0);

        vm.prank(servicerA);
        registry.release(collA, empty);
        assertEq(registry.deviceCount(servicerA, collA), 0);
    }

    function test_doublePledgeScenarioAndSwapPop() public {
        uint64 t1 = uint64(block.timestamp);
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1));

        uint64 t2 = t1 + 100;
        vm.warp(t2);
        vm.prank(servicerB);
        registry.pledge(collB, _arr(dev1));

        // Both active pledges exist side by side.
        assertEq(registry.pledgeCount(dev1), 2);
        assertTrue(registry.isPledged(servicerA, collA, dev1));
        assertTrue(registry.isPledged(servicerB, collB, dev1));

        (address s0, bytes32 c0, uint64 p0) = registry.pledgeAt(dev1, 0);
        (address s1, bytes32 c1, uint64 p1) = registry.pledgeAt(dev1, 1);
        assertEq(s0, servicerA);
        assertEq(c0, collA);
        assertEq(p0, t1);
        assertEq(s1, servicerB);
        assertEq(c1, collB);
        assertEq(p1, t2);

        // Servicer A releases (index 0); servicer B is swapped into index 0.
        vm.prank(servicerA);
        registry.release(collA, _arr(dev1));

        assertEq(registry.pledgeCount(dev1), 1);
        assertFalse(registry.isPledged(servicerA, collA, dev1));
        assertTrue(registry.isPledged(servicerB, collB, dev1));

        (address remS, bytes32 remC, uint64 remP) = registry.pledgeAt(dev1, 0);
        assertEq(remS, servicerB);
        assertEq(remC, collB);
        assertEq(remP, t2);

        // Releasing servicer B succeeds using the updated swapped index.
        vm.prank(servicerB);
        registry.release(collB, _arr(dev1));
        assertEq(registry.pledgeCount(dev1), 0);
        assertFalse(registry.isPledged(servicerB, collB, dev1));
    }

    function test_sameServicerDifferentCollateralsAllowed() public {
        vm.startPrank(servicerA);
        registry.pledge(collA, _arr(dev1));
        registry.pledge(collB, _arr(dev1));
        assertEq(registry.pledgeCount(dev1), 2);
        assertEq(registry.deviceCount(servicerA, collA), 1);
        assertEq(registry.deviceCount(servicerA, collB), 1);

        registry.release(collA, _arr(dev1));
        assertEq(registry.pledgeCount(dev1), 1);
        assertTrue(registry.isPledged(servicerA, collB, dev1));

        registry.release(collB, _arr(dev1));
        assertEq(registry.pledgeCount(dev1), 0);
        vm.stopPrank();
    }

    function test_revertPledgeDuplicateInInput() public {
        vm.prank(servicerA);
        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.AlreadyPledged.selector, dev1));
        registry.pledge(collA, _arr(dev1, dev1));
    }

    function test_revertPledgeAlreadyActive() public {
        vm.startPrank(servicerA);
        registry.pledge(collA, _arr(dev1));
        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.AlreadyPledged.selector, dev1));
        registry.pledge(collA, _arr(dev1));
        vm.stopPrank();
    }

    function test_revertReleaseNotPledged() public {
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1));

        // Wrong servicer
        vm.prank(servicerB);
        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.NotPledged.selector, dev1));
        registry.release(collA, _arr(dev1));

        // Wrong collateralId
        vm.prank(servicerA);
        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.NotPledged.selector, dev1));
        registry.release(collB, _arr(dev1));

        // Unpledged key
        vm.prank(servicerA);
        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.NotPledged.selector, dev2));
        registry.release(collA, _arr(dev2));
    }

    function test_revertReleaseDuplicateInInput() public {
        vm.startPrank(servicerA);
        registry.pledge(collA, _arr(dev1));
        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.NotPledged.selector, dev1));
        registry.release(collA, _arr(dev1, dev1));
        vm.stopPrank();
    }

    function test_revertPledgeAtOutOfRange() public {
        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.IndexOutOfBounds.selector, 0, 0));
        registry.pledgeAt(dev1, 0);

        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1));

        vm.expectRevert(abi.encodeWithSelector(GPUCollateralEvidence.IndexOutOfBounds.selector, 1, 1));
        registry.pledgeAt(dev1, 1);
    }

    // -------------------------------------------------------------------------
    // Report tests
    // -------------------------------------------------------------------------

    function test_latestReportDefaultZero() public view {
        (IGPUCollateralEvidence.Report memory r, uint64 reportedAt) = registry.latestReport(servicerA, collA);
        assertEq(reportedAt, 0);
        assertEq(r.periodStart, 0);
        assertEq(r.periodEnd, 0);
        assertEq(r.statementRoot, bytes32(0));
    }

    function test_reportReplaceSamePeriodAndAdvance() public {
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1, dev2));

        uint64 t1 = uint64(block.timestamp);
        IGPUCollateralEvidence.Report memory r1 = IGPUCollateralEvidence.Report({
            periodStart: 1_735_689_600,
            periodEnd: 1_735_776_000,
            devicesReported: 2,
            devicesAttested: 1,
            servedSeconds: 72_000,
            missedSeconds: 3_600,
            unknownSeconds: 97_200,
            statementRoot: keccak256("root1")
        });

        vm.expectEmit(true, true, false, true);
        emit IGPUCollateralEvidence.Reported(servicerA, collA, r1, "ipfs://v1");

        vm.prank(servicerA);
        registry.report(collA, r1, "ipfs://v1");

        (IGPUCollateralEvidence.Report memory stored, uint64 reportedAt) = registry.latestReport(servicerA, collA);
        assertEq(reportedAt, t1);
        assertEq(stored.statementRoot, r1.statementRoot);
        assertEq(stored.servedSeconds, r1.servedSeconds);

        // Replace the exact same period at a later timestamp
        uint64 t2 = t1 + 600;
        vm.warp(t2);
        IGPUCollateralEvidence.Report memory r1Replacement = IGPUCollateralEvidence.Report({
            periodStart: 1_735_689_600,
            periodEnd: 1_735_776_000,
            devicesReported: 2,
            devicesAttested: 2,
            servedSeconds: 100_000,
            missedSeconds: 0,
            unknownSeconds: 72_800,
            statementRoot: keccak256("root1-revised")
        });

        vm.expectEmit(true, true, false, true);
        emit IGPUCollateralEvidence.Reported(servicerA, collA, r1Replacement, "ipfs://v1-revised");

        vm.prank(servicerA);
        registry.report(collA, r1Replacement, "ipfs://v1-revised");

        (stored, reportedAt) = registry.latestReport(servicerA, collA);
        assertEq(reportedAt, t2);
        assertEq(stored.statementRoot, r1Replacement.statementRoot);
        assertEq(stored.devicesAttested, 2);

        // Advance to adjacent period [periodEnd, periodEnd + 1000)
        IGPUCollateralEvidence.Report memory r2 = IGPUCollateralEvidence.Report({
            periodStart: 1_735_776_000,
            periodEnd: 1_735_777_000,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 1_000,
            statementRoot: keccak256("root2")
        });
        vm.prank(servicerA);
        registry.report(collA, r2, "ipfs://v2");

        // Advance with a gap [1_735_780_000, 1_735_781_000) and zero reported devices
        IGPUCollateralEvidence.Report memory r3 = IGPUCollateralEvidence.Report({
            periodStart: 1_735_780_000,
            periodEnd: 1_735_781_000,
            devicesReported: 0,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 0,
            statementRoot: bytes32(0)
        });
        vm.prank(servicerA);
        registry.report(collA, r3, "ipfs://v3-empty");
        (stored, ) = registry.latestReport(servicerA, collA);
        assertEq(stored.periodStart, 1_735_780_000);
    }

    function test_revertReportInvalidPeriods() public {
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1));

        uint64 nowTs = uint64(block.timestamp);

        // periodStart == periodEnd
        IGPUCollateralEvidence.Report memory eqPeriod = IGPUCollateralEvidence.Report({
            periodStart: nowTs - 100,
            periodEnd: nowTs - 100,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 0,
            statementRoot: bytes32(0)
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.InvalidPeriod.selector);
        registry.report(collA, eqPeriod, "");

        // periodStart > periodEnd
        IGPUCollateralEvidence.Report memory revPeriod = IGPUCollateralEvidence.Report({
            periodStart: nowTs - 50,
            periodEnd: nowTs - 100,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 0,
            statementRoot: bytes32(0)
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.InvalidPeriod.selector);
        registry.report(collA, revPeriod, "");

        // periodEnd > block.timestamp (future period)
        IGPUCollateralEvidence.Report memory futurePeriod = IGPUCollateralEvidence.Report({
            periodStart: nowTs - 100,
            periodEnd: nowTs + 1,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 101,
            statementRoot: bytes32(0)
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.InvalidPeriod.selector);
        registry.report(collA, futurePeriod, "");
    }

    function test_revertReportOverlappingPeriods() public {
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1));

        IGPUCollateralEvidence.Report memory base = IGPUCollateralEvidence.Report({
            periodStart: 1_000,
            periodEnd: 2_000,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 1_000,
            statementRoot: keccak256("base")
        });
        vm.prank(servicerA);
        registry.report(collA, base, "");

        // Partial overlap [1500, 2500)
        IGPUCollateralEvidence.Report memory overlap = IGPUCollateralEvidence.Report({
            periodStart: 1_500,
            periodEnd: 2_500,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 1_000,
            statementRoot: keccak256("overlap")
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.OverlappingPeriod.selector);
        registry.report(collA, overlap, "");

        // Earlier disjoint [100, 500)
        IGPUCollateralEvidence.Report memory earlier = IGPUCollateralEvidence.Report({
            periodStart: 100,
            periodEnd: 500,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 400,
            statementRoot: keccak256("earlier")
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.OverlappingPeriod.selector);
        registry.report(collA, earlier, "");

        // Same start, extended end [1000, 2500)
        IGPUCollateralEvidence.Report memory sameStart = IGPUCollateralEvidence.Report({
            periodStart: 1_000,
            periodEnd: 2_500,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 1_500,
            statementRoot: keccak256("sameStart")
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.OverlappingPeriod.selector);
        registry.report(collA, sameStart, "");

        // Shifted start, same end [1500, 2000)
        IGPUCollateralEvidence.Report memory sameEnd = IGPUCollateralEvidence.Report({
            periodStart: 1_500,
            periodEnd: 2_000,
            devicesReported: 1,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 500,
            statementRoot: keccak256("sameEnd")
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.OverlappingPeriod.selector);
        registry.report(collA, sameEnd, "");
    }

    function test_revertReportInvalidDeviceCounts() public {
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1));

        // devicesAttested > devicesReported
        IGPUCollateralEvidence.Report memory badAtt = IGPUCollateralEvidence.Report({
            periodStart: 1_000,
            periodEnd: 2_000,
            devicesReported: 1,
            devicesAttested: 2,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 1_000,
            statementRoot: bytes32(0)
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.InvalidDeviceCounts.selector);
        registry.report(collA, badAtt, "");

        // devicesReported > deviceCount
        IGPUCollateralEvidence.Report memory badRep = IGPUCollateralEvidence.Report({
            periodStart: 1_000,
            periodEnd: 2_000,
            devicesReported: 2,
            devicesAttested: 0,
            servedSeconds: 0,
            missedSeconds: 0,
            unknownSeconds: 2_000,
            statementRoot: bytes32(0)
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.InvalidDeviceCounts.selector);
        registry.report(collA, badRep, "");
    }

    function test_revertReportInvalidSecondsTotal() public {
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1, dev2));

        IGPUCollateralEvidence.Report memory badSum = IGPUCollateralEvidence.Report({
            periodStart: 1_000,
            periodEnd: 2_000,
            devicesReported: 2,
            devicesAttested: 0,
            servedSeconds: 1_000,
            missedSeconds: 500,
            unknownSeconds: 499, // 1999 != 2000
            statementRoot: bytes32(0)
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.InvalidSecondsTotal.selector);
        registry.report(collA, badSum, "");
    }

    function test_reportRule3OverflowSafeLargeValues() public {
        vm.prank(servicerA);
        registry.pledge(collA, _arr(dev1, dev2, dev3));

        // 1e19 fits in uint64 (~1.8446e19 max), but 3 * 1e19 = 3e19 exceeds uint64!
        uint64 hugeDuration = 10_000_000_000_000_000_000;
        vm.warp(uint256(hugeDuration));

        IGPUCollateralEvidence.Report memory largeValid = IGPUCollateralEvidence.Report({
            periodStart: 0,
            periodEnd: hugeDuration,
            devicesReported: 3,
            devicesAttested: 3,
            servedSeconds: hugeDuration,
            missedSeconds: hugeDuration,
            unknownSeconds: hugeDuration,
            statementRoot: keccak256("large")
        });

        vm.prank(servicerA);
        registry.report(collA, largeValid, "ipfs://large");

        (IGPUCollateralEvidence.Report memory stored, uint64 reportedAt) = registry.latestReport(servicerA, collA);
        assertEq(reportedAt, hugeDuration);
        assertEq(stored.servedSeconds, hugeDuration);

        // Ensure uint64 wraparound cannot spoof rule 3:
        // rhs = 3 * 1e19, while (rhs % 2^64) = 11553255926290448384.
        uint64 wrapped = uint64(uint256(3) * uint256(hugeDuration));
        IGPUCollateralEvidence.Report memory wrappedSpoof = IGPUCollateralEvidence.Report({
            periodStart: 0,
            periodEnd: hugeDuration,
            devicesReported: 3,
            devicesAttested: 0,
            servedSeconds: wrapped,
            missedSeconds: 0,
            unknownSeconds: 0,
            statementRoot: keccak256("spoof")
        });
        vm.prank(servicerA);
        vm.expectRevert(GPUCollateralEvidence.InvalidSecondsTotal.selector);
        registry.report(collA, wrappedSpoof, "");
    }

    // -------------------------------------------------------------------------
    // ERC8515Lib unit & vectors.json cross-check tests
    // -------------------------------------------------------------------------

    function test_libStatementRootRejectsUnsortedOrDuplicate() public {
        bytes32 a = bytes32(uint256(10));
        bytes32 b = bytes32(uint256(5));

        vm.expectRevert(ERC8515Lib.UnsortedOrDuplicateStatementIds.selector);
        lib.statementRoot(_arr(a, b));

        vm.expectRevert(ERC8515Lib.UnsortedOrDuplicateStatementIds.selector);
        lib.statementRoot(_arr(a, a));
    }

    function test_vectorsJsonParityWithSolidity() public {
        string memory json = vm.readFile("./vectors.json");

        uint256 chainId = json.readUint(".context.chainId");
        address regAddr = json.readAddress(".context.registryAddress");
        bytes32 expectedDomainSep = json.readBytes32(".domainSeparator");
        bytes32 expectedEmptyRoot = json.readBytes32(".emptyRoot");

        assertEq(lib.domainSeparator(chainId, regAddr), expectedDomainSep, "domainSeparator mismatch");
        assertEq(lib.statementRoot(new bytes32[](0)), expectedEmptyRoot, "emptyRoot mismatch");
        assertEq(expectedEmptyRoot, bytes32(0), "emptyRoot should be zero");

        // Verify all 3 device keys
        bytes32[] memory deviceKeys = new bytes32[](3);
        for (uint256 i = 0; i < 3; ++i) {
            string memory prefix = string.concat(".devices[", vm.toString(i), "]");
            uint16 vendor = uint16(json.readUint(string.concat(prefix, ".pciVendorId")));
            uint8 idType = uint8(json.readUint(string.concat(prefix, ".idType")));
            bytes memory idBytes = json.readBytes(string.concat(prefix, ".idBytesHex"));
            bytes32 expectedKey = json.readBytes32(string.concat(prefix, ".deviceKey"));

            bytes32 computed = lib.deviceKey(vendor, idType, idBytes);
            assertEq(computed, expectedKey, string.concat("deviceKey mismatch at ", vm.toString(i)));
            deviceKeys[i] = computed;
        }

        // Verify all 6 EIP-712 statement digests AND ecrecover every JS signature
        for (uint256 i = 0; i < 6; ++i) {
            string memory prefix = string.concat(".statements[", vm.toString(i), "]");
            bytes32 stmtId = json.readBytes32(string.concat(prefix, ".statementId"));
            bytes32 expectedDigest = json.readBytes32(string.concat(prefix, ".digest"));
            bytes memory sig = json.readBytes(string.concat(prefix, ".signature"));
            address observer = json.readAddress(string.concat(prefix, ".observerAddress"));

            bytes32 computedDigest = lib.statementDigest(chainId, regAddr, stmtId);
            assertEq(computedDigest, expectedDigest, string.concat("digest mismatch at ", vm.toString(i)));

            assertEq(sig.length, 65, "signature length must be 65");
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := mload(add(sig, 32))
                s := mload(add(sig, 64))
                v := byte(0, mload(add(sig, 96)))
            }
            assertTrue(v == 27 || v == 28, "v must be 27 or 28");
            assertEq(ecrecover(computedDigest, v, r, s), observer, "ecrecover mismatch");
        }

        // Verify Merkle root over sorted statementIds
        bytes32[] memory sortedIds = json.readBytes32Array(".sortedStatementIds");
        bytes32 expectedRoot = json.readBytes32(".report.statementRoot");
        assertEq(lib.statementRoot(sortedIds), expectedRoot, "statementRoot mismatch");

        // Submit the vector's pledges and report to the registry to verify end-to-end on-chain acceptance
        address vecServicer = json.readAddress(".context.servicerAddress");
        bytes32 vecCollateral = json.readBytes32(".context.collateralId");

        vm.startPrank(vecServicer);
        registry.pledge(vecCollateral, deviceKeys);

        IGPUCollateralEvidence.Report memory vecReport = IGPUCollateralEvidence.Report({
            periodStart: uint64(json.readUint(".report.periodStart")),
            periodEnd: uint64(json.readUint(".report.periodEnd")),
            devicesReported: uint32(json.readUint(".report.devicesReported")),
            devicesAttested: uint32(json.readUint(".report.devicesAttested")),
            servedSeconds: uint64(json.readUint(".report.servedSeconds")),
            missedSeconds: uint64(json.readUint(".report.missedSeconds")),
            unknownSeconds: uint64(json.readUint(".report.unknownSeconds")),
            statementRoot: expectedRoot
        });
        registry.report(vecCollateral, vecReport, "ipfs://vectors-report");
        vm.stopPrank();

        (IGPUCollateralEvidence.Report memory stored, uint64 reportedAt) =
            registry.latestReport(vecServicer, vecCollateral);
        assertGt(reportedAt, 0);
        assertEq(stored.statementRoot, expectedRoot);
        assertEq(stored.devicesReported, 3);
        assertEq(stored.devicesAttested, 2);
    }
}
