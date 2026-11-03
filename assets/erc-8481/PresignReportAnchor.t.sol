// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IPresignReportAnchor} from "./IPresignReportAnchor.sol";
import {PresignReportAnchor, ArbitrumPresignReportAnchor} from "./PresignReportAnchor.sol";

contract ArbSysFixture {
    uint256 public arbBlockNumber;

    function setBlockNumber(uint256 number) external {
        arbBlockNumber = number;
    }
}

contract PresignReportAnchorTest is Test {
    PresignReportAnchor anchor;
    address constant SOURCE = address(0x8004);
    bytes32 constant SUBJECT = keccak256("prepared request");
    bytes32 constant REPORT = keccak256("canonical report");

    function setUp() public {
        vm.warp(1000);
        vm.roll(100);
        anchor = new PresignReportAnchor();
    }

    function publish(address source, bytes32 report) internal {
        vm.prank(source);
        anchor.anchor(SUBJECT, report, "ipfs://report");
    }

    function test_firstAnchorRecordsCallerAndLocalClock() public {
        vm.expectEmit(true, true, true, true, address(anchor));
        emit IPresignReportAnchor.ReportAnchored(SOURCE, SUBJECT, REPORT, "ipfs://report");
        publish(SOURCE, REPORT);
        (uint64 timestamp, uint64 number) = anchor.anchoredAt(SOURCE, REPORT);
        assertEq(timestamp, 1000);
        assertEq(number, 100);
    }

    function test_repeatPublicationDoesNotMoveFirstAnchor() public {
        publish(SOURCE, REPORT);
        vm.warp(2000);
        vm.roll(200);
        vm.expectEmit(true, true, true, true, address(anchor));
        emit IPresignReportAnchor.ReportAnchored(SOURCE, SUBJECT, REPORT, "ipfs://mirror");
        vm.prank(SOURCE);
        anchor.anchor(SUBJECT, REPORT, "ipfs://mirror");
        (uint64 timestamp, uint64 number) = anchor.anchoredAt(SOURCE, REPORT);
        assertEq(timestamp, 1000);
        assertEq(number, 100);
    }

    function test_anotherCallerCannotReserveOrOverwriteSourceRecord() public {
        publish(address(0xBAD), REPORT);
        vm.warp(2000);
        vm.roll(200);
        publish(SOURCE, REPORT);
        (uint64 attackerTime,) = anchor.anchoredAt(address(0xBAD), REPORT);
        (uint64 sourceTime, uint64 number) = anchor.anchoredAt(SOURCE, REPORT);
        assertEq(attackerTime, 1000);
        assertEq(sourceTime, 2000);
        assertEq(number, 200);
    }

    function test_distinctReportsHaveIndependentFirstAnchors() public {
        publish(SOURCE, REPORT);
        vm.warp(2000);
        bytes32 other = keccak256("another report");
        publish(SOURCE, other);
        (uint64 firstTime,) = anchor.anchoredAt(SOURCE, REPORT);
        (uint64 secondTime,) = anchor.anchoredAt(SOURCE, other);
        assertEq(firstTime, 1000);
        assertEq(secondTime, 2000);
    }

    function test_unknownPairReturnsZeros() public view {
        (uint64 timestamp, uint64 number) = anchor.anchoredAt(SOURCE, REPORT);
        assertEq(timestamp, 0);
        assertEq(number, 0);
    }

    function test_zeroHashesAreRejected() public {
        vm.expectRevert(PresignReportAnchor.ZeroHash.selector);
        anchor.anchor(bytes32(0), REPORT, "");
        vm.expectRevert(PresignReportAnchor.ZeroHash.selector);
        anchor.anchor(SUBJECT, bytes32(0), "");
    }

    function test_uriLimitCountsBytesAndAppliesToRepeatAnchors() public {
        vm.prank(SOURCE);
        anchor.anchor(SUBJECT, REPORT, string(new bytes(512)));
        vm.prank(SOURCE);
        vm.expectRevert(PresignReportAnchor.URITooLong.selector);
        anchor.anchor(SUBJECT, REPORT, string(new bytes(513)));
    }

    function test_zeroTimestampDoesNotMakeFirstAnchorMutable() public {
        vm.warp(0);
        publish(SOURCE, REPORT);
        vm.warp(1);
        publish(SOURCE, REPORT);
        (uint64 timestamp, uint64 number) = anchor.anchoredAt(SOURCE, REPORT);
        assertEq(timestamp, 0);
        assertEq(number, 100);
    }

    function test_clockOverflowRevertsInsteadOfTruncating() public {
        vm.warp(uint256(type(uint64).max) + 1);
        vm.expectRevert(PresignReportAnchor.ClockOverflow.selector);
        anchor.anchor(SUBJECT, REPORT, "");
        vm.warp(1000);
        vm.roll(uint256(type(uint64).max) + 1);
        vm.expectRevert(PresignReportAnchor.ClockOverflow.selector);
        anchor.anchor(SUBJECT, REPORT, "");
    }

    function test_arbitrumVariantUsesArbSysInsteadOfL1Number() public {
        vm.etch(address(100), address(new ArbSysFixture()).code);
        ArbSysFixture(address(100)).setBlockNumber(9000);
        ArbitrumPresignReportAnchor arbAnchor = new ArbitrumPresignReportAnchor();
        vm.prank(SOURCE);
        arbAnchor.anchor(SUBJECT, REPORT, "");
        (uint64 timestamp, uint64 number) = arbAnchor.anchoredAt(SOURCE, REPORT);
        assertEq(timestamp, 1000);
        assertEq(number, 9000);
        assertTrue(number != block.number);
    }

    function test_arbitrumVariantDoesNotFallbackWhenArbSysUnavailable() public {
        ArbitrumPresignReportAnchor arbAnchor = new ArbitrumPresignReportAnchor();
        vm.expectRevert();
        arbAnchor.anchor(SUBJECT, REPORT, "");
    }

    function testFuzz_repeatCannotChangeFirstClock(uint64 nextTime, uint64 nextBlock) public {
        publish(SOURCE, REPORT);
        vm.warp(bound(nextTime, 1000, type(uint64).max));
        vm.roll(bound(nextBlock, 100, type(uint64).max));
        publish(SOURCE, REPORT);
        (uint64 timestamp, uint64 number) = anchor.anchoredAt(SOURCE, REPORT);
        assertEq(timestamp, 1000);
        assertEq(number, 100);
    }
}
