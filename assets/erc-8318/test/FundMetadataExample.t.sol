// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {FundMetadataExample} from "../contracts/FundMetadataExample.sol";
import {
    IFundMetadata,
    IFundMetadataAUM,
    IFundMetadataLockup,
    IFundMetadataYield,
    IFundMetadataMultiClass,
    IFundMetadataProofOfReserves,
    LifecycleState,
    DistributionType,
    DistributionStatus,
    DistributionInfo
} from "../contracts/IFundMetadata.sol";

contract MockShareToken is ERC20 {
    constructor() ERC20("Mock Fund Share", "MFS") {}
}

contract FundMetadataExampleTest is Test {
    MockShareToken token;
    FundMetadataExample fund;
    address admin = address(0xA11CE);
    address stranger = address(0xBEEF);
    bytes3 constant USD = 0x555344;

    event NavUpdated(uint256 previousNav, uint256 newNav, uint8 navDecimals, uint256 effectiveAt);
    event LifecycleStateChanged(
        LifecycleState indexed previousState, LifecycleState indexed newState, uint256 timestamp
    );
    event DistributionDeclared(
        uint256 indexed id,
        DistributionType indexed distributionType,
        uint256 exDate,
        uint256 recordDate,
        uint256 paymentDate,
        uint256 amountPerShare,
        uint8 amountDecimals,
        bytes3 currency
    );
    event DistributionPaid(
        uint256 indexed id, uint256 totalAmount, uint8 amountDecimals, bytes3 currency, uint256 paidAt
    );
    event DistributionCancelled(uint256 indexed id, string reason);

    function setUp() public {
        vm.warp(1_000_000);
        token = new MockShareToken();
        fund = new FundMetadataExample(token, USD, 1 days, admin);
    }

    /* ------------------------------ helpers ------------------------------ */

    function _setNav(uint256 nav, uint256 at) internal {
        vm.prank(admin);
        fund.setNav(nav, 18, at);
    }

    function _go(LifecycleState s) internal {
        vm.prank(admin);
        fund.setLifecycleState(s);
    }

    function _declare() internal returns (uint256) {
        vm.prank(admin);
        return fund.declareDistribution(
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            block.timestamp + 3 days,
            5e16,
            18,
            USD,
            DistributionType.Dividend
        );
    }

    /* ------------------------- ERC-165 / interface IDs ------------------------- */

    function testInterfaceIdsMatchSpecTable() public pure {
        assertEq(type(IFundMetadata).interfaceId, bytes4(0x9539c458));
        assertEq(type(IFundMetadataAUM).interfaceId, bytes4(0x081529b6));
        assertEq(type(IFundMetadataLockup).interfaceId, bytes4(0xb6e90569));
        assertEq(type(IFundMetadataYield).interfaceId, bytes4(0xc744ad19));
        assertEq(type(IFundMetadataMultiClass).interfaceId, bytes4(0xe872a87f));
        assertEq(type(IFundMetadataProofOfReserves).interfaceId, bytes4(0x9655511c));
    }

    function testCoreInterfaceIdIsXorOfSelectors() public pure {
        bytes4 x = IFundMetadata.navPerShare.selector ^ IFundMetadata.navAsOf.selector
            ^ IFundMetadata.navUpdatedAt.selector ^ IFundMetadata.navStale.selector
            ^ IFundMetadata.navStalenessThreshold.selector ^ IFundMetadata.valuationCurrency.selector
            ^ IFundMetadata.lifecycleState.selector ^ IFundMetadata.lifecycleStateUpdatedAt.selector
            ^ IFundMetadata.distributionCount.selector ^ IFundMetadata.distributionById.selector
            ^ IFundMetadata.pendingDistributionIds.selector ^ IFundMetadata.lastDistributionId.selector
            ^ IFundMetadata.nextDistributionDate.selector ^ IFundMetadata.managementFeeBps.selector
            ^ IFundMetadata.performanceFeeBps.selector ^ IFundMetadata.subscriptionFeeBps.selector
            ^ IFundMetadata.redemptionFeeBps.selector ^ IFundMetadata.minInvestment.selector
            ^ IFundMetadata.subscriptionWindow.selector ^ IFundMetadata.redemptionWindow.selector
            ^ IFundMetadata.maturityDate.selector;
        assertEq(x, type(IFundMetadata).interfaceId);
    }

    function testSupportsInterface() public view {
        assertTrue(fund.supportsInterface(type(IERC165).interfaceId));
        assertTrue(fund.supportsInterface(type(IFundMetadata).interfaceId));
        assertTrue(fund.supportsInterface(type(IAccessControl).interfaceId));
        assertFalse(fund.supportsInterface(0xffffffff));
        // Optional extensions are not implemented by this contract.
        assertFalse(fund.supportsInterface(type(IFundMetadataAUM).interfaceId));
        assertFalse(fund.supportsInterface(type(IFundMetadataLockup).interfaceId));
        assertFalse(fund.supportsInterface(type(IFundMetadataYield).interfaceId));
        assertFalse(fund.supportsInterface(type(IFundMetadataMultiClass).interfaceId));
        assertFalse(fund.supportsInterface(type(IFundMetadataProofOfReserves).interfaceId));
    }

    /* ------------------------------ event topics ------------------------------ */

    function testEventTopicLayout() public {
        vm.recordLogs();
        _setNav(1e18, block.timestamp);
        _go(LifecycleState.SubscriptionOpen);
        uint256 id = _declare();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 3);

        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256("NavUpdated(uint256,uint256,uint8,uint256)"));

        assertEq(logs[1].topics.length, 3);
        assertEq(logs[1].topics[0], keccak256("LifecycleStateChanged(uint8,uint8,uint256)"));
        assertEq(uint256(logs[1].topics[1]), uint256(LifecycleState.Pending));
        assertEq(uint256(logs[1].topics[2]), uint256(LifecycleState.SubscriptionOpen));

        assertEq(logs[2].topics.length, 3);
        assertEq(
            logs[2].topics[0],
            keccak256("DistributionDeclared(uint256,uint8,uint256,uint256,uint256,uint256,uint8,bytes3)")
        );
        assertEq(uint256(logs[2].topics[1]), id);
        assertEq(uint256(logs[2].topics[2]), uint256(DistributionType.Dividend));

        vm.warp(block.timestamp + 2 days);
        vm.recordLogs();
        vm.prank(admin);
        fund.markDistributionPaid(id, 1e21);
        logs = vm.getRecordedLogs();
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("DistributionPaid(uint256,uint256,uint8,bytes3,uint256)"));

        uint256 id2 = _declare();
        vm.recordLogs();
        vm.prank(admin);
        fund.cancelDistribution(id2, "x");
        logs = vm.getRecordedLogs();
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("DistributionCancelled(uint256,string)"));
    }

    /* ----------------------------------- NAV ----------------------------------- */

    function testInitialNavState() public view {
        (uint256 nav, uint8 dec) = fund.navPerShare();
        assertEq(nav, 0);
        assertEq(dec, 0);
        assertEq(fund.navUpdatedAt(), 0);
        assertTrue(fund.navStale());
        assertEq(fund.navStalenessThreshold(), 1 days);
        assertEq(fund.valuationCurrency(), USD);
    }

    function testSetNavEmitsAndUpdates() public {
        vm.expectEmit(false, false, false, true, address(fund));
        emit NavUpdated(0, 1e18, 18, block.timestamp);
        _setNav(1e18, block.timestamp);

        (uint256 nav, uint8 dec) = fund.navPerShare();
        assertEq(nav, 1e18);
        assertEq(dec, 18);
        assertEq(fund.navUpdatedAt(), block.timestamp);
        assertFalse(fund.navStale());
    }

    function testIdenticalNavDoesNotEmit() public {
        _setNav(1e18, block.timestamp);
        vm.recordLogs();
        _setNav(1e18, block.timestamp);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function testNavCorrectionAtSameTimestampEmits() public {
        _setNav(1e18, block.timestamp);
        vm.expectEmit(false, false, false, true, address(fund));
        emit NavUpdated(1e18, 1.01e18, 18, block.timestamp);
        _setNav(1.01e18, block.timestamp);
        (uint256 nav,) = fund.navAsOf(block.timestamp);
        assertEq(nav, 1.01e18);
    }

    function testZeroNavIsValidAndDistinguishableFromUnset() public {
        _setNav(0, block.timestamp);
        (uint256 nav,) = fund.navPerShare();
        assertEq(nav, 0);
        assertEq(fund.navUpdatedAt(), block.timestamp);
        assertFalse(fund.navStale());
    }

    function testStalenessBoundary() public {
        uint256 t = block.timestamp;
        _setNav(1e18, t);
        vm.warp(t + 1 days);
        assertFalse(fund.navStale(), "age == threshold is not stale");
        vm.warp(t + 1 days + 1);
        assertTrue(fund.navStale(), "age > threshold is stale");
        (uint256 nav,) = fund.navPerShare();
        assertEq(nav, 1e18, "stale NAV still returned");
    }

    function testStalenessWithMaxThresholdDoesNotOverflow() public {
        vm.prank(admin);
        fund.setStalenessThreshold(type(uint256).max);
        _setNav(1e18, block.timestamp);
        vm.warp(type(uint64).max);
        assertFalse(fund.navStale());
    }

    function testNavAsOfPredecessorLookup() public {
        uint256 t1 = block.timestamp;
        _setNav(1e18, t1);
        vm.warp(t1 + 10);
        _setNav(2e18, t1 + 10);
        vm.warp(t1 + 20);
        _setNav(3e18, t1 + 20);

        (uint256 nav,) = fund.navAsOf(t1);
        assertEq(nav, 1e18);
        (nav,) = fund.navAsOf(t1 + 5);
        assertEq(nav, 1e18, "between updates -> earlier");
        (nav,) = fund.navAsOf(t1 + 10);
        assertEq(nav, 2e18);
        (nav,) = fund.navAsOf(t1 + 19);
        assertEq(nav, 2e18);
        (nav,) = fund.navAsOf(type(uint256).max);
        assertEq(nav, 3e18);
    }

    function testNavAsOfBeforeFirstReverts() public {
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.NoNavAtOrBefore.selector, block.timestamp));
        fund.navAsOf(block.timestamp);

        _setNav(1e18, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.NoNavAtOrBefore.selector, block.timestamp - 1));
        fund.navAsOf(block.timestamp - 1);
    }

    function testNavHistoryKeepsPerEntryDecimals() public {
        uint256 t = block.timestamp;
        vm.prank(admin);
        fund.setNav(1e6, 6, t);
        vm.warp(t + 1);
        vm.prank(admin);
        fund.setNav(1e18, 18, t + 1);
        (uint256 nav, uint8 dec) = fund.navAsOf(t);
        assertEq(nav, 1e6);
        assertEq(dec, 6);
    }

    function testNavRejectsFutureOutOfOrderAndZero() public {
        vm.startPrank(admin);
        vm.expectRevert(FundMetadataExample.FutureNav.selector);
        fund.setNav(1e18, 18, block.timestamp + 1);
        vm.expectRevert(FundMetadataExample.ZeroEffectiveAt.selector);
        fund.setNav(1e18, 18, 0);
        fund.setNav(1e18, 18, block.timestamp);
        vm.expectRevert(FundMetadataExample.NavOutOfOrder.selector);
        fund.setNav(2e18, 18, block.timestamp - 1);
        vm.stopPrank();
    }

    /* -------------------------------- lifecycle -------------------------------- */

    function testLifecycleTransitionEmits() public {
        vm.expectEmit(true, true, false, true, address(fund));
        emit LifecycleStateChanged(LifecycleState.Pending, LifecycleState.SubscriptionOpen, block.timestamp);
        _go(LifecycleState.SubscriptionOpen);
        assertEq(uint8(fund.lifecycleState()), uint8(LifecycleState.SubscriptionOpen));
        assertEq(fund.lifecycleStateUpdatedAt(), block.timestamp);
    }

    function testFullHappyPathToClosed() public {
        _go(LifecycleState.SubscriptionOpen);
        _go(LifecycleState.SubscriptionClosed);
        _go(LifecycleState.Operating);
        _go(LifecycleState.RedemptionOnly);
        _go(LifecycleState.WindingDown);
        _go(LifecycleState.Closed);
        assertEq(uint8(fund.lifecycleState()), uint8(LifecycleState.Closed));
    }

    function testIllegalTransitionReverts() public {
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                FundMetadataExample.IllegalTransition.selector, LifecycleState.Pending, LifecycleState.Closed
            )
        );
        fund.setLifecycleState(LifecycleState.Closed);
    }

    function testNoOpTransitionReverts() public {
        vm.prank(admin);
        vm.expectRevert(FundMetadataExample.NoOpTransition.selector);
        fund.setLifecycleState(LifecycleState.Pending);
    }

    function testClosedIsTerminal() public {
        _go(LifecycleState.SubscriptionOpen);
        _go(LifecycleState.Operating);
        _go(LifecycleState.WindingDown);
        _go(LifecycleState.Closed);
        for (uint8 s = 0; s < 8; s++) {
            if (s == uint8(LifecycleState.Closed)) continue;
            vm.prank(admin);
            vm.expectRevert();
            fund.setLifecycleState(LifecycleState(s));
        }
        vm.prank(admin);
        vm.expectRevert(FundMetadataExample.FundClosed.selector);
        fund.setNav(1e18, 18, block.timestamp);
    }

    function testPauseResumeToPreviousState() public {
        _go(LifecycleState.SubscriptionOpen);
        _go(LifecycleState.Operating);
        _go(LifecycleState.Paused);
        _go(LifecycleState.Operating);
        assertEq(uint8(fund.lifecycleState()), uint8(LifecycleState.Operating));
    }

    function testPauseExitToLegalSuccessorOfPrevious() public {
        _go(LifecycleState.SubscriptionOpen);
        _go(LifecycleState.Operating);
        _go(LifecycleState.Paused);
        _go(LifecycleState.WindingDown); // legal successor of Operating
        assertEq(uint8(fund.lifecycleState()), uint8(LifecycleState.WindingDown));
    }

    function testPauseExitToIllegalStateReverts() public {
        _go(LifecycleState.SubscriptionOpen);
        _go(LifecycleState.Paused);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                FundMetadataExample.IllegalTransition.selector, LifecycleState.Paused, LifecycleState.Closed
            )
        );
        fund.setLifecycleState(LifecycleState.Closed);
    }

    function testPausePauseIsNoOp() public {
        _go(LifecycleState.Paused);
        vm.prank(admin);
        vm.expectRevert(FundMetadataExample.NoOpTransition.selector);
        fund.setLifecycleState(LifecycleState.Paused);
    }

    /* ------------------------------- distributions ------------------------------ */

    function testEmptyDistributionState() public {
        assertEq(fund.distributionCount(), 0);
        assertEq(fund.pendingDistributionIds().length, 0);
        assertEq(fund.lastDistributionId(), 0);
        assertEq(fund.nextDistributionDate(), 0);
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.UnknownDistribution.selector, 0));
        fund.distributionById(0);
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.UnknownDistribution.selector, 1));
        fund.distributionById(1);
    }

    function testDeclareEmitsAndStores() public {
        uint256 t = block.timestamp;
        vm.expectEmit(true, true, false, true, address(fund));
        emit DistributionDeclared(1, DistributionType.Dividend, t + 1 days, t + 2 days, t + 3 days, 5e16, 18, USD);
        uint256 id = _declare();

        assertEq(id, 1);
        assertEq(fund.distributionCount(), 1);
        DistributionInfo memory d = fund.distributionById(1);
        assertEq(d.id, 1);
        assertEq(d.declaredAt, t);
        assertEq(d.amountPerShare, 5e16);
        assertEq(d.amountDecimals, 18);
        assertEq(d.currency, USD);
        assertEq(uint8(d.status), uint8(DistributionStatus.Declared));
        assertEq(fund.pendingDistributionIds()[0], 1);
        assertEq(fund.nextDistributionDate(), t + 3 days);
    }

    function testIdsAreSequential() public {
        assertEq(_declare(), 1);
        assertEq(_declare(), 2);
        assertEq(_declare(), 3);
        assertEq(fund.distributionCount(), 3);
    }

    function testBadDatesRevert() public {
        vm.prank(admin);
        vm.expectRevert(FundMetadataExample.BadDistributionDates.selector);
        fund.declareDistribution(10, 5, 20, 1, 18, USD, DistributionType.Coupon);
        vm.prank(admin);
        vm.expectRevert(FundMetadataExample.BadDistributionDates.selector);
        fund.declareDistribution(1, 5, 4, 1, 18, USD, DistributionType.Coupon);
    }

    function testExDateStatusIsReported() public {
        uint256 id = _declare();
        vm.warp(block.timestamp + 1 days);
        assertEq(uint8(fund.distributionById(id).status), uint8(DistributionStatus.ExDate));
    }

    function testMarkPaid() public {
        uint256 id = _declare();
        vm.warp(block.timestamp + 2 days);
        vm.expectEmit(true, false, false, true, address(fund));
        emit DistributionPaid(id, 1e21, 18, USD, block.timestamp);
        vm.prank(admin);
        fund.markDistributionPaid(id, 1e21);

        assertEq(uint8(fund.distributionById(id).status), uint8(DistributionStatus.Paid));
        assertEq(fund.lastDistributionId(), id);
        assertEq(fund.pendingDistributionIds().length, 0);
        assertEq(fund.nextDistributionDate(), 0);
    }

    function testMarkPaidBeforeRecordDateReverts() public {
        uint256 id = _declare();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.BeforeRecordDate.selector, id));
        fund.markDistributionPaid(id, 1);
    }

    function testDoublePayAndPayCancelledRevert() public {
        uint256 a = _declare();
        uint256 b = _declare();
        vm.warp(block.timestamp + 2 days);
        vm.startPrank(admin);
        fund.markDistributionPaid(a, 1);
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.DistributionNotPending.selector, a));
        fund.markDistributionPaid(a, 1);
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.DistributionNotPending.selector, a));
        fund.cancelDistribution(a, "late");
        fund.cancelDistribution(b, "error");
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.DistributionNotPending.selector, b));
        fund.markDistributionPaid(b, 1);
        vm.expectRevert(abi.encodeWithSelector(FundMetadataExample.UnknownDistribution.selector, 99));
        fund.cancelDistribution(99, "x");
        vm.stopPrank();
    }

    function testCancelEmitsAndUpdatesPending() public {
        uint256 a = _declare();
        uint256 b = _declare();
        uint256 c = _declare();
        vm.expectEmit(true, false, false, true, address(fund));
        emit DistributionCancelled(a, "board withdrew");
        vm.prank(admin);
        fund.cancelDistribution(a, "board withdrew");

        assertEq(uint8(fund.distributionById(a).status), uint8(DistributionStatus.Cancelled));
        uint256[] memory p = fund.pendingDistributionIds();
        assertEq(p.length, 2);
        assertTrue((p[0] == b && p[1] == c) || (p[0] == c && p[1] == b));
        assertEq(fund.lastDistributionId(), 0, "cancel is not payment");
    }

    function testNextDistributionDateIsEarliestPending() public {
        uint256 t = block.timestamp;
        vm.startPrank(admin);
        fund.declareDistribution(t, t, t + 30 days, 1, 18, USD, DistributionType.Coupon);
        fund.declareDistribution(t, t, t + 10 days, 1, 18, USD, DistributionType.Coupon);
        vm.stopPrank();
        assertEq(fund.nextDistributionDate(), t + 10 days);
    }

    /* -------------------------------- fund params -------------------------------- */

    function testParamsDefaultsAndSetters() public {
        assertEq(fund.managementFeeBps(), 0);
        assertEq(fund.maturityDate(), 0);
        (uint256 o, uint256 c) = fund.subscriptionWindow();
        assertEq(o, 0);
        assertEq(c, 0);

        vm.startPrank(admin);
        fund.setFees(50, 1000, 10, 20);
        fund.setMinInvestment(100_000e6, 6);
        fund.setWindows(1, 2, 3, 4);
        fund.setMaturityDate(2_000_000_000);
        vm.expectRevert(FundMetadataExample.FeeTooHigh.selector);
        fund.setFees(10_001, 0, 0, 0);
        vm.expectRevert(FundMetadataExample.BadWindow.selector);
        fund.setWindows(2, 1, 0, 0);
        vm.stopPrank();

        assertEq(fund.managementFeeBps(), 50);
        assertEq(fund.performanceFeeBps(), 1000);
        assertEq(fund.subscriptionFeeBps(), 10);
        assertEq(fund.redemptionFeeBps(), 20);
        (uint256 amt, uint8 dec) = fund.minInvestment();
        assertEq(amt, 100_000e6);
        assertEq(dec, 6);
        (o, c) = fund.redemptionWindow();
        assertEq(o, 3);
        assertEq(c, 4);
        assertEq(fund.maturityDate(), 2_000_000_000);
    }

    /* ------------------------------- access control ------------------------------ */

    function testUnauthorizedWritesRevert() public {
        vm.startPrank(stranger);
        vm.expectRevert();
        fund.setNav(1e18, 18, block.timestamp);
        vm.expectRevert();
        fund.setLifecycleState(LifecycleState.SubscriptionOpen);
        vm.expectRevert();
        fund.declareDistribution(1, 2, 3, 1, 18, USD, DistributionType.Other);
        vm.expectRevert();
        fund.markDistributionPaid(1, 1);
        vm.expectRevert();
        fund.cancelDistribution(1, "x");
        vm.expectRevert();
        fund.setFees(1, 1, 1, 1);
        vm.expectRevert();
        fund.setStalenessThreshold(1);
        vm.stopPrank();
    }

    function testConstructorRejectsZeroAddresses() public {
        vm.expectRevert(FundMetadataExample.ZeroAddress.selector);
        new FundMetadataExample(MockShareToken(address(0)), USD, 1 days, admin);
        vm.expectRevert(FundMetadataExample.ZeroAddress.selector);
        new FundMetadataExample(token, USD, 1 days, address(0));
    }
}
