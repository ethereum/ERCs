// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {MockUVAOracle} from "../src/MockUVAOracle.sol";
import {IFinancialLease} from "../src/IFinancialLease.sol";
import {ChainlinkConversionOracle} from "../src/oracles/ChainlinkConversionOracle.sol";
import {MockAggregator} from "./mocks/MockAggregator.sol";

/// @dev Stablecoin mock with configurable decimals (to simulate a
///      6-decimal digital ARS, different from the 18-decimal mUSD
///      used in FinancialLease.t.sol).
contract MockStable is ERC20 {
    uint8 private immutable _dec;

    constructor(uint8 dec_) ERC20("Mock Stable", "mSTB") {
        _dec = dec_;
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title End-to-end scenarios for ERC-8348 (Financial Lease)
/// @dev This suite does NOT replace FinancialLease.t.sol (unit tests):
///      it is an additional layer that simulates real lease contracts
///      end to end, with invariants checked after every operation.
contract ScenariosTest is Test {
    FinancialLease lease;

    // "Current" token against which invariant I5 is checked (total
    // balance received by the lessor(s) == sum of PaymentReceived).
    // Each scenario uses a single payment asset throughout its
    // lifecycle, so a mutable pointer set at the start is enough.
    IERC20 internal _currentAssetToken;

    // ─── Schedule registry (to rebuild invariants from
    //     outside the contract without touching src/) ────────────
    mapping(uint256 => uint64[]) internal _schedDue;
    mapping(uint256 => uint256[]) internal _schedAmt;
    mapping(uint256 => uint256) internal _schedTotal;

    // ─── Payment accounting (I5), rebuilt by replaying logs ──
    mapping(uint256 => address) internal _ownerOfLease;
    mapping(address => uint256) internal _expectedFromPayments;
    mapping(address => uint256) internal _expectedFromPurchase;
    address[] internal _touchedAddresses;
    mapping(address => bool) internal _isTouched;

    bytes32 internal constant TRANSFER_TOPIC = keccak256("Transfer(address,address,uint256)");
    bytes32 internal constant PAYMENT_RECEIVED_TOPIC =
        keccak256("PaymentReceived(uint256,address,uint256,uint256,uint256,uint256)");
    bytes32 internal constant PURCHASE_TOPIC = keccak256("PurchaseOptionExercised(uint256,uint256)");

    function setUp() public {
        lease = new FinancialLease();
        vm.recordLogs();
    }

    // ════════════════════════════════════════════════════════════════
    // Origination helpers
    // ════════════════════════════════════════════════════════════════

    function _monthlySchedule(uint256 n, uint256 amountEach)
        internal
        view
        returns (uint64[] memory dueDates, uint256[] memory unitAmounts)
    {
        dueDates = new uint64[](n);
        unitAmounts = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            dueDates[i] = uint64(block.timestamp) + uint64((i + 1) * 30 days);
            unitAmounts[i] = amountEach;
        }
    }

    function _registerSchedule(uint256 leaseId, uint64[] memory due, uint256[] memory amt) internal {
        uint256 total;
        for (uint256 i = 0; i < due.length; i++) {
            _schedDue[leaseId].push(due[i]);
            _schedAmt[leaseId].push(amt[i]);
            total += amt[i];
        }
        _schedTotal[leaseId] = total;
    }

    function _createLease(
        address lessorAddr,
        address lesseeAddr,
        address tokenAddr,
        address oracleAddr,
        uint64 staleness,
        uint64[] memory dueDates,
        uint256[] memory unitAmounts,
        uint256 purchasePriceUnits,
        uint16 penaltyBps,
        address declarer
    ) internal returns (uint256 leaseId) {
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lesseeAddr,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://machine/1",
            paymentAsset: tokenAddr,
            denomSymbol: "UVA",
            oracle: oracleAddr,
            maxStaleness: staleness,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: purchasePriceUnits,
            penaltyBpsPerDay: penaltyBps,
            defaultDeclarer: declarer,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessorAddr);
        leaseId = lease.createLease(p);
        _registerSchedule(leaseId, dueDates, unitAmounts);
        _assertInvariants(leaseId);
    }

    // ════════════════════════════════════════════════════════════════
    // External reconstruction of arrearsPrincipalUnits
    // ════════════════════════════════════════════════════════════════

    /// @dev The contract never exposes arrearsPrincipalUnits or
    ///      arrearsPenaltyUnits separately (only arrears(), which
    ///      combines them in assets). But since pay() ALWAYS imputes in the
    ///      order penalties -> overdue principal -> future installments,
    ///      overdue principal can never "skip" installments: therefore
    ///      arrearsPrincipalUnits == totalOverdueNominal - settledUnits
    ///      (never negative), where totalOverdueNominal is the sum of
    ///      unitAmounts whose dueDate has passed. Both sides can be
    ///      rebuilt from the public interface.
    function _reconstructArrearsPrincipal(uint256 leaseId) internal view returns (uint256 principal) {
        uint256 outstanding = lease.outstandingUnits(leaseId);
        uint256 settled = _schedTotal[leaseId] - outstanding;

        uint64[] storage due = _schedDue[leaseId];
        uint256[] storage amt = _schedAmt[leaseId];
        uint256 totalOverdue;
        for (uint256 i = 0; i < due.length; i++) {
            if (due[i] < block.timestamp) totalOverdue += amt[i];
        }
        principal = totalOverdue > settled ? totalOverdue - settled : 0;
    }

    // ════════════════════════════════════════════════════════════════
    // Global invariants — call after EVERY operation
    // ════════════════════════════════════════════════════════════════

    function _assertInvariants(uint256 leaseId) internal {
        uint256 total = _schedTotal[leaseId];
        uint256 outstanding = lease.outstandingUnits(leaseId);

        // I1: settledUnits <= scheduleTotalUnits. outstandingUnits() is
        // computed as total - settled: if settled > total, the subtraction
        // would have reverted on underflow. We also check the range.
        assertLe(outstanding, total, "I1: outstandingUnits exceeds scheduleTotalUnits");

        // I2: outstandingUnits == scheduleTotalUnits - settledUnits is
        // true by construction in the contract (it is its literal
        // formula); it cannot be falsified from outside. What we DO check,
        // as a stronger regression check, is that the
        // newOutstandingUnits field emitted in each PaymentReceived matches
        // the live state read immediately afterwards (inside
        // _assertPaymentAccounting).

        // I6: the rebuilt overdue principal must never exceed what
        // remains to be paid on the schedule.
        uint256 principalRecon = _reconstructArrearsPrincipal(leaseId);
        assertLe(principalRecon, outstanding, "I6: overdue principal exceeds outstandingUnits");

        IFinancialLease.LeaseStatus st = lease.status(leaseId);
        uint256 arrearsAssets = lease.arrears(leaseId);

        // I3: Completed => outstanding == 0 && arrears == 0.
        // (arrears() == 0 in assets is exactly equivalent to "0 units"
        // because convertToAssets(0) = 0 and any positive number of
        // units rounds up to a positive amount of assets.)
        if (st == IFinancialLease.LeaseStatus.Completed) {
            assertEq(outstanding, 0, "I3: Completed with outstandingUnits != 0");
            assertEq(arrearsAssets, 0, "I3: Completed with arrears != 0");
        }

        // I4: Active => no overdue principal and no penalties.
        if (st == IFinancialLease.LeaseStatus.Active) {
            assertEq(arrearsAssets, 0, "I4: Active with pending arrears");
        }

        _assertPaymentAccounting();
    }

    function _trackAddress(address a) internal {
        if (!_isTouched[a]) {
            _isTouched[a] = true;
            _touchedAddresses.push(a);
        }
    }

    /// @dev I5: replay of logs since the last drain. Rebuilds,
    ///      for every address that ever owned the NFT of
    ///      any lease, how much it should have received via
    ///      PaymentReceived + PurchaseOptionExercised, and compares it
    ///      with its actual balance of the current payment asset.
    function _assertPaymentAccounting() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory logEntry = logs[i];
            if (logEntry.emitter != address(lease)) continue;
            if (logEntry.topics.length == 0) continue;
            bytes32 topic0 = logEntry.topics[0];

            if (topic0 == TRANSFER_TOPIC && logEntry.topics.length == 4) {
                uint256 tokenId = uint256(logEntry.topics[3]);
                address to = address(uint160(uint256(logEntry.topics[2])));
                _ownerOfLease[tokenId] = to;
                _trackAddress(to);
            } else if (topic0 == PAYMENT_RECEIVED_TOPIC && logEntry.topics.length == 3) {
                uint256 lid = uint256(logEntry.topics[1]);
                (uint256 assets,,, uint256 newOutstanding) =
                    abi.decode(logEntry.data, (uint256, uint256, uint256, uint256));
                address ownerAtPayment = _ownerOfLease[lid];
                _expectedFromPayments[ownerAtPayment] += assets;
                _trackAddress(ownerAtPayment);
                assertEq(
                    lease.outstandingUnits(lid),
                    newOutstanding,
                    "REGRESSION: PaymentReceived.newOutstandingUnits does not match live outstandingUnits()"
                );
            } else if (topic0 == PURCHASE_TOPIC && logEntry.topics.length == 2) {
                uint256 lid = uint256(logEntry.topics[1]);
                uint256 price = abi.decode(logEntry.data, (uint256));
                address ownerAtPurchase = _ownerOfLease[lid];
                _expectedFromPurchase[ownerAtPurchase] += price;
                _trackAddress(ownerAtPurchase);
            }
        }

        for (uint256 i = 0; i < _touchedAddresses.length; i++) {
            address a = _touchedAddresses[i];
            assertEq(
                _currentAssetToken.balanceOf(a),
                _expectedFromPayments[a] + _expectedFromPurchase[a],
                "I5: lessor balance does not match the sum of PaymentReceived + purchase"
            );
        }
    }

    // ════════════════════════════════════════════════════════════════
    // SCENARIO 1 — Argentine UVA lease, full clean cycle
    // ════════════════════════════════════════════════════════════════

    function test_Scenario1_UVAFullCycle() public {
        address lessorAddr = makeAddr("s1_lessor");
        address lesseeAddr = makeAddr("s1_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 10_000_000_000e6);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle uvaOracle = new MockUVAOracle(1500e6);

        uint256 n = 36;
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(n, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(uvaOracle),
            10 days,
            dueDates,
            unitAmounts,
            1000e18,
            0,
            address(0)
        );

        uint256 totalAssetsPaid;
        uint256 totalNominalConverted;
        uint256 rate = 1500e6;

        for (uint256 i = 0; i < n; i++) {
            vm.warp(uint256(dueDates[i]));
            rate = (rate * 104) / 100; // ~4% compounded monthly
            uvaOracle.set(rate);

            totalNominalConverted += lease.convertToAssets(id, unitAmounts[i]);

            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorAddr);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            totalAssetsPaid += stable.balanceOf(lessorAddr) - balBefore;
        }

        console2.log("Escenario 1 - rate final (x1e6 ARS/UVA):", rate / 1e6);
        console2.log("Scenario 1 - total assets paid by the lessee:", totalAssetsPaid);
        console2.log("Scenario 1 - nominal sum converted at the time of each payment:", totalNominalConverted);

        uint256 finalOutstanding = lease.outstandingUnits(id);
        console2.log("Escenario 1 - outstandingUnits final (esperado 0):", finalOutstanding);
        assertEq(finalOutstanding, 0, "SCENARIO 1 CRITICAL: dust remains after paying the 36 exact installments");
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Completed),
            "must be Completed after the 36th installment"
        );

        (uint256 price, bool exercisable) = lease.purchaseOption(id);
        assertTrue(exercisable, "the purchase option must be exercisable after Completed");

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.PurchaseOptionExercised(id, price);
        vm.prank(lesseeAddr);
        lease.exercisePurchaseOption(id);
        _assertInvariants(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));
    }

    // ════════════════════════════════════════════════════════════════
    // SCENARIO 2 — arrears, penalties, cure and completion
    // ════════════════════════════════════════════════════════════════

    function test_Scenario2_ArrearsPenaltyCureCompletion() public {
        address lessorAddr = makeAddr("s2_lessor");
        address lesseeAddr = makeAddr("s2_lessee");
        address declarer = makeAddr("s2_declarer");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        // Rate fixed at 1e18: convertToAssets/convertToUnits become
        // exact identities (no rounding), which makes it possible to isolate the
        // EXACT penalty component below.
        MockUVAOracle oracle_ = new MockUVAOracle(1e18);

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(12, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            30 days,
            dueDates,
            unitAmounts,
            5000e18,
            10,
            declarer
        );

        // Installments 1-3 on time
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
        }

        // Skip installments 4 and 5: advance well past their due date
        vm.warp(uint256(dueDates[4]) + 5 days); // ~65 days unpaid since installment 3
        oracle_.set(1e18);

        // status()/arrears() report accrual as of block.timestamp: they already
        // reflect the arrears right here, WITHOUT sending any transaction
        // (before the stale-views fix a minimal "poke" payment was
        // needed to force persistence; it no longer is).
        assertEq(
            uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InArrears), "must show InArrears with no prior tx"
        );
        assertGt(lease.arrears(id), 0, "arrears() must be > 0 with no prior tx");

        (,, bool paid3) = lease.paymentAt(id, 3);
        (,, bool paid4) = lease.paymentAt(id, 4);
        assertFalse(paid3, "REGRESSION: overdue unpaid installment 4 must not show as paid");
        assertFalse(paid4, "REGRESSION: overdue unpaid installment 5 must not show as paid");

        // declareDefault is the first real tx since installment 3: it emits
        // ArrearsAccrued (no pay() has flagged these arrears yet) and
        // moves the lease to InDefault.
        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.ArrearsAccrued(id, 0);
        vm.expectEmit(true, true, false, false);
        emit IFinancialLease.DefaultDeclared(id, declarer);
        vm.prank(declarer);
        lease.declareDefault(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        // Let more days pass so penalties keep accruing on the overdue stock
        vm.warp(block.timestamp + 20 days);
        oracle_.set(1e18);

        // EXACT penalty component (rate=1e18 => no rounding)
        uint256 principalUnits = _reconstructArrearsPrincipal(id);
        uint256 totalArrearsUnits = lease.arrears(id); // == exact units because rate == 1e18
        uint256 penaltyUnits = totalArrearsUnits - principalUnits;
        assertGt(penaltyUnits, 0, "penalties must have accrued");

        uint256 outstandingBeforePenaltyPay = lease.outstandingUnits(id);
        oracle_.set(1e18);
        vm.prank(lesseeAddr);
        lease.pay(id, penaltyUnits);
        _assertInvariants(id);

        // REGRESSION: paying ONLY penalties must not reduce outstandingUnits
        assertEq(
            lease.outstandingUnits(id),
            outstandingBeforePenaltyPay,
            "REGRESSION: penalties must not touch principal/outstanding"
        );
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.InDefault),
            "still in default: overdue principal is still unpaid"
        );

        // Pay the rest of the arrears (overdue principal) -> cure
        oracle_.set(1e18);
        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        vm.prank(lesseeAddr);
        lease.pay(id, principalUnits);
        _assertInvariants(id);

        assertEq(
            uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Active), "must cure to Active (installments remain)"
        );
        assertEq(lease.arrears(id), 0, "all arrears must be settled");

        // Complete the remaining installments (6 to 12) on time
        for (uint256 i = 5; i < 12; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
        }

        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Completed),
            "must reach Completed despite the arrears history"
        );
        (, bool exercisable) = lease.purchaseOption(id);
        assertTrue(exercisable, "the purchase option must remain exercisable");
    }

    // ════════════════════════════════════════════════════════════════
    // SCENARIO 3 — securitization (assignment of the lessor mid-life)
    // ════════════════════════════════════════════════════════════════

    function test_Scenario3_SecuritizationTransferMidLife() public {
        address lessorOriginal = makeAddr("s3_lessorOriginal");
        address buyerFund = makeAddr("s3_buyerFund");
        address tomador = makeAddr("s3_tomador");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(tomador, 1_000_000e18);
        vm.prank(tomador);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1e18);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(24, 1000e18);
        uint256 id = _createLease(
            lessorOriginal,
            tomador,
            address(stable),
            address(oracle_),
            60 days,
            dueDates,
            unitAmounts,
            5000e18,
            10,
            address(0)
        );

        for (uint256 i = 0; i < 8; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorOriginal);
            vm.prank(tomador);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            assertEq(
                stable.balanceOf(lessorOriginal) - balBefore,
                assetsDue,
                "installments 1-8: funds must go to lessorOriginal"
            );
        }
        assertEq(stable.balanceOf(buyerFund), 0, "buyerFund must not have funds yet");

        uint256 outstandingBeforeTransfer = lease.outstandingUnits(id);
        IFinancialLease.LeaseStatus statusBeforeTransfer = lease.status(id);
        (uint256 nextAssetsBefore, uint64 nextDueBefore) = lease.nextPayment(id);

        vm.prank(lessorOriginal);
        lease.transferFrom(lessorOriginal, buyerFund, id);
        _assertInvariants(id);

        assertEq(lease.lessor(id), buyerFund, "the NFT must pass to buyerFund");
        assertEq(
            lease.outstandingUnits(id), outstandingBeforeTransfer, "ASSERT: the assignment must not alter outstanding"
        );
        assertEq(uint8(lease.status(id)), uint8(statusBeforeTransfer), "ASSERT: the assignment must not alter the status");
        (uint256 nextAssetsAfter, uint64 nextDueAfter) = lease.nextPayment(id);
        assertEq(nextAssetsAfter, nextAssetsBefore, "ASSERT: the assignment must not alter the next installment");
        assertEq(nextDueAfter, nextDueBefore, "ASSERT: the assignment must not alter the due date");

        for (uint256 i = 8; i < 24; i++) {
            vm.warp(uint256(dueDates[i]));
            oracle_.set(1e18);
            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBeforeNew = stable.balanceOf(buyerFund);
            uint256 balBeforeOld = stable.balanceOf(lessorOriginal);
            vm.prank(tomador);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            assertEq(
                stable.balanceOf(buyerFund) - balBeforeNew,
                assetsDue,
                "installments 9-24: funds must go to buyerFund"
            );
            assertEq(stable.balanceOf(lessorOriginal), balBeforeOld, "lessorOriginal must not receive anything else");
        }

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    function test_Scenario3_TransferDuringDefault() public {
        address lessorA = makeAddr("s3b_lessorA");
        address lessorB = makeAddr("s3b_lessorB");
        address tomador = makeAddr("s3b_tomador");
        address declarer = makeAddr("s3b_declarer");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(tomador, 1_000_000e18);
        vm.prank(tomador);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1e18);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(6, 1000e18);
        uint256 id = _createLease(
            lessorA, tomador, address(stable), address(oracle_), 60 days, dueDates, unitAmounts, 2000e18, 10, declarer
        );

        // Skip installment 1 and let it accrue arrears
        vm.warp(uint256(dueDates[0]) + 20 days);
        oracle_.set(1e18);

        vm.prank(declarer);
        lease.declareDefault(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        // Transfer the NFT while the lease is InDefault
        vm.prank(lessorA);
        lease.transferFrom(lessorA, lessorB, id);
        _assertInvariants(id);
        assertEq(lease.lessor(id), lessorB);

        uint256 curePrincipal = _reconstructArrearsPrincipal(id);
        uint256 curePenalty = lease.arrears(id) - curePrincipal; // rate=1e18: exact
        uint256 balBeforeB = stable.balanceOf(lessorB);
        uint256 balBeforeA = stable.balanceOf(lessorA);

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        vm.prank(tomador);
        lease.pay(id, curePrincipal + curePenalty);
        _assertInvariants(id);

        assertEq(
            stable.balanceOf(lessorB) - balBeforeB,
            curePrincipal + curePenalty,
            "the cure payment must go to the new owner"
        );
        assertEq(stable.balanceOf(lessorA), balBeforeA, "the previous owner must not receive anything");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Active));
    }

    // ════════════════════════════════════════════════════════════════
    // SCENARIO 4 — index deflation
    // ════════════════════════════════════════════════════════════════

    function test_Scenario4_DeflationHealthyCycle() public {
        address lessorAddr = makeAddr("s4_lessor");
        address lesseeAddr = makeAddr("s4_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(2000e6);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(12, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            40 days,
            dueDates,
            unitAmounts,
            3000e18,
            10,
            address(0)
        );

        uint256 totalAssetsPaid;
        uint256 projectedAtOriginalRate;
        uint256 rate = 2000e6;

        for (uint256 i = 0; i < 12; i++) {
            vm.warp(uint256(dueDates[i]));
            if (i == 3) {
                rate = (rate * 80) / 100; // the index falls 20% between installments 3 and 4
            }
            oracle_.set(rate);

            projectedAtOriginalRate += (unitAmounts[i] * 2000e6) / 1e18;

            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorAddr);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            totalAssetsPaid += stable.balanceOf(lessorAddr) - balBefore;
        }

        console2.log("Scenario 4 - total assets paid (with deflation):", totalAssetsPaid);
        console2.log("Scenario 4 - naive projection at the original rate:", projectedAtOriginalRate);
        assertLt(
            totalAssetsPaid,
            projectedAtOriginalRate,
            "with deflation, the amount actually paid must be lower than the projection"
        );

        assertEq(lease.outstandingUnits(id), 0, "must reach 0 outstanding units despite deflation");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    function test_Scenario4_DangerousDeflationWithAccruedArrears() public {
        address lessorAddr = makeAddr("s4b_lessor");
        address lesseeAddr = makeAddr("s4b_lessee");
        address declarer = makeAddr("s4b_declarer");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(2000e6);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(6, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            60 days,
            dueDates,
            unitAmounts,
            2000e18,
            10,
            declarer
        );

        // Generate arrears: skip installment 1
        vm.warp(uint256(dueDates[0]) + 10 days);
        oracle_.set(2000e6);
        vm.prank(lesseeAddr);
        lease.pay(id, 1); // minimal payment: flags the arrears, emits ArrearsAccrued
        _assertInvariants(id);

        // Let penalties keep accumulating
        vm.warp(block.timestamp + 15 days);
        oracle_.set(2000e6);
        vm.prank(declarer);
        lease.declareDefault(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        vm.warp(block.timestamp + 15 days);
        oracle_.set(2000e6);
        vm.prank(lesseeAddr);
        lease.pay(id, 1); // another minimal payment: more penalties on the overdue stock
        _assertInvariants(id);

        // Now, with penalties already accrued, the index falls sharply
        uint256 crashedRate = (2000e6 * 50) / 100; // -50%
        oracle_.set(crashedRate);
        _assertInvariants(id); // the oracle move alone must not corrupt state

        // Pay everything at once (overdue principal + penalties + rest of the
        // schedule). pay() caps at what is actually owed, so
        // overpaying is safe and there must be no underflow anywhere.
        uint256 hugeAmount = stable.balanceOf(lesseeAddr); // the whole available balance
        vm.prank(lesseeAddr);
        lease.pay(id, hugeAmount);
        _assertInvariants(id);

        assertEq(lease.outstandingUnits(id), 0, "no underflow or corrupt state after severe deflation");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    // ════════════════════════════════════════════════════════════════
    // SCENARIO 5 — due-date edges and partial payments
    // ════════════════════════════════════════════════════════════════

    function test_Scenario5_PaymentTimingAndPartialEdges() public {
        address lessorAddr = makeAddr("s5_lessor");
        address lesseeAddr = makeAddr("s5_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 1_000_000e18);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1e18);
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(4, 500e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            30 days,
            dueDates,
            unitAmounts,
            1000e18,
            10,
            address(0)
        );

        // (a) Pay EXACTLY at dueDate: an installment is overdue only
        // strictly after its dueDate, so paying exactly on time does NOT
        // count as arrears. Observed behaviour, documented here.
        vm.warp(uint256(dueDates[0]));
        oracle_.set(1e18);
        (uint256 assetsDue0,) = lease.nextPayment(id);
        vm.prank(lesseeAddr);
        lease.pay(id, assetsDue0);
        _assertInvariants(id);
        console2.log("Scenario 5(a) - status after paying EXACTLY at dueDate:", uint8(lease.status(id)));
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Active),
            "OBSERVED: paying exactly at dueDate counts as current (no arrears), because overdue is strictly after dueDate"
        );
        assertEq(lease.arrears(id), 0);

        // (b) 1 second after the due date: arrears ARE recorded
        // (ArrearsAccrued event), even though they are cured in the same tx by paying
        // the exact amount owed.
        vm.warp(uint256(dueDates[1]) + 1);
        oracle_.set(1e18);
        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.ArrearsAccrued(id, 0);
        (uint256 assetsDue1,) = lease.nextPayment(id);
        vm.prank(lesseeAddr);
        lease.pay(id, assetsDue1);
        _assertInvariants(id);
        assertEq(lease.arrears(id), 0, "cured in the same tx by paying the exact amount");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Active));

        // (c) Partial payment of installment 3
        vm.warp(uint256(dueDates[2]));
        oracle_.set(1e18);
        (uint256 assetsDue2,) = lease.nextPayment(id);
        uint256 half = assetsDue2 / 2;
        vm.prank(lesseeAddr);
        lease.pay(id, half);
        _assertInvariants(id);
        (,, bool paid2Partial) = lease.paymentAt(id, 2);
        assertFalse(paid2Partial, "a partial payment must not mark the installment as paid");
        (uint256 remainingAssets,) = lease.nextPayment(id);
        assertGt(remainingAssets, 0, "nextPayment must reflect the remaining balance");
        assertLt(remainingAssets, assetsDue2, "the remaining balance must be lower than the original");

        vm.prank(lesseeAddr);
        lease.pay(id, remainingAssets);
        _assertInvariants(id);
        (,, bool paid2Full) = lease.paymentAt(id, 2);
        assertTrue(paid2Full, "after completing the balance, the installment must be paid");

        // (d) Overpayment on the last installment: only what is needed is transferred
        uint256 outstandingBefore = lease.outstandingBalance(id);
        uint256 overpay = outstandingBefore * 10;
        uint256 lessorBalBefore = stable.balanceOf(lessorAddr);
        vm.prank(lesseeAddr);
        lease.pay(id, overpay);
        _assertInvariants(id);
        uint256 pulled = stable.balanceOf(lessorAddr) - lessorBalBefore;
        assertEq(pulled, outstandingBefore, "no more than what is strictly owed may be transferred");
        assertEq(lease.outstandingUnits(id), 0, "must not over-credit");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        console2.log("Scenario 5(d) - assets sent in the overpayment:", overpay);
        console2.log("Escenario 5(d) - assets realmente transferidos:", pulled);
    }

    // ════════════════════════════════════════════════════════════════
    // SCENARIO 6 — long schedule, rounding stress (THE MOST IMPORTANT)
    // ════════════════════════════════════════════════════════════════

    function test_Scenario6_LongScheduleRoundingStress() public {
        address lessorAddr = makeAddr("s6_lessor");
        address lesseeAddr = makeAddr("s6_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 100_000_000_000e6);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockUVAOracle oracle_ = new MockUVAOracle(1500e6);

        uint256 n = 60;
        uint256 amountEach = 833333333333333333; // not round
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(n, amountEach);

        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(oracle_),
            10 days,
            dueDates,
            unitAmounts,
            amountEach,
            0,
            address(0)
        );

        uint256 totalAssetsPaid;
        uint256 totalNominalConverted;
        uint256 rate = 1500e6;

        for (uint256 i = 0; i < n; i++) {
            vm.warp(uint256(dueDates[i]));
            rate = (rate * 1037) / 1000; // not round, ~3.7%/month
            oracle_.set(rate);

            totalNominalConverted += lease.convertToAssets(id, amountEach);

            (uint256 assetsDue,) = lease.nextPayment(id);
            uint256 balBefore = stable.balanceOf(lessorAddr);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
            totalAssetsPaid += stable.balanceOf(lessorAddr) - balBefore;
        }

        uint256 finalOutstanding = lease.outstandingUnits(id);
        console2.log("Escenario 6 - outstandingUnits final (esperado 0):", finalOutstanding);
        console2.log("Scenario 6 - total assets paid by the lessee:", totalAssetsPaid);
        console2.log("Scenario 6 - nominal sum converted at the time of each payment:", totalNominalConverted);

        if (finalOutstanding != 0) {
            console2.log(
                "SCENARIO 6 FINDING: dust remains after 60 exact payments, residual units:", finalOutstanding
            );
        }
        assertEq(finalOutstanding, 0, "SCENARIO 6 CRITICAL: residual dust after 60 installments with non-round amounts/rate");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));
    }

    // ════════════════════════════════════════════════════════════════
    // SCENARIO 7 — real oracle adapter (Chainlink)
    // ════════════════════════════════════════════════════════════════

    function test_Scenario7_ChainlinkOracleFullCycle() public {
        address lessorAddr = makeAddr("s7_lessor");
        address lesseeAddr = makeAddr("s7_lessee");

        MockStable stable = new MockStable(6);
        _currentAssetToken = IERC20(address(stable));
        stable.mint(lesseeAddr, 10_000_000_000e6);
        vm.prank(lesseeAddr);
        stable.approve(address(lease), type(uint256).max);

        MockAggregator feed = new MockAggregator(8);
        int256 answer = 1500e8;
        feed.setAnswer(answer);
        feed.setUpdatedAt(block.timestamp);
        ChainlinkConversionOracle clOracle = new ChainlinkConversionOracle(address(feed), 6);

        uint256 n = 36;
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _monthlySchedule(n, 1000e18);
        uint256 id = _createLease(
            lessorAddr,
            lesseeAddr,
            address(stable),
            address(clOracle),
            10 days,
            dueDates,
            unitAmounts,
            1000e18,
            0,
            address(0)
        );

        for (uint256 i = 0; i < n; i++) {
            vm.warp(uint256(dueDates[i]));
            answer = (answer * 104) / 100;
            feed.setAnswer(answer);
            feed.setUpdatedAt(block.timestamp);

            (uint256 assetsDue,) = lease.nextPayment(id);
            vm.prank(lesseeAddr);
            lease.pay(id, assetsDue);
            _assertInvariants(id);
        }

        uint256 finalOutstanding = lease.outstandingUnits(id);
        console2.log("Escenario 7 - outstandingUnits final (esperado 0):", finalOutstanding);
        assertEq(finalOutstanding, 0, "SCENARIO 7: residual dust with ChainlinkConversionOracle after 36 payments");
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        (, bool exercisable) = lease.purchaseOption(id);
        assertTrue(exercisable);
        vm.prank(lesseeAddr);
        lease.exercisePurchaseOption(id);
        _assertInvariants(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));
    }
}
