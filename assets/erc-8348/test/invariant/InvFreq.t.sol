// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FinancialLease} from "../../src/FinancialLease.sol";
import {INPUT_COLLECTIONS, INPUT_ARREARS_RECORD} from "../../src/IFinancialLease.sol";
import {MockERC20} from "./Handler.sol";

/// @title INV-FREQ (directed scenario test)
/// @dev Confirms the S3-01 fix. After the fix there is no internal "_accrue"
///      to expose through a harness — arrears() is a pure view, so
///      it is tested against FinancialLease directly.
///
///      MUST PASS with the current (post-fix) code. If it fails, the fix is
///      wrong — do not touch this test to make it pass.
contract InvFreqTest is Test {
    FinancialLease internal lease;
    MockERC20 internal token;
    address internal lessee_ = makeAddr("lessee");
    address internal lessor_ = makeAddr("lessor");
    address internal declarer_ = makeAddr("declarer");
    address internal otherLessee = makeAddr("otherLessee");
    address internal otherLessor = makeAddr("otherLessor");

    uint256 internal constant UNIT = 1e18;
    uint256 internal constant PRINCIPAL = 1_000_000 * UNIT;
    uint16 internal constant PENALTY_BPS_PER_DAY = 10; // 0.10%/day

    /// @dev Storage, not a local: with the optimizer enabled, a local that
    ///      holds block.timestamp before a vm.warp can be elided
    ///      and solc rematerializes TIMESTAMP at the point of use (correct
    ///      under real EVM semantics -- the timestamp does not change within a tx --
    ///      but it breaks these tests, which use vm.warp, a cheatcode, to
    ///      simulate time passing within the same test tx). An
    ///      SLOAD does not suffer from this: the optimizer must assume potential
    ///      reentrancy on any external call (Foundry cheatcodes
    ///      are external calls to the VM address) and cannot elide the
    ///      storage re-read across them.
    uint256 internal t0Slot;

    function setUp() public {
        lease = new FinancialLease();
        token = new MockERC20();
        token.mint(lessee_, 10_000_000 * UNIT);
        vm.prank(lessee_);
        token.approve(address(lease), type(uint256).max);

        token.mint(otherLessee, 10_000_000 * UNIT);
        vm.prank(otherLessee);
        token.approve(address(lease), type(uint256).max);
    }

    function _mkLease() internal returns (uint256 id) {
        uint64[] memory dueDates = new uint64[](1);
        uint256[] memory unitAmounts = new uint256[](1);
        dueDates[0] = uint64(block.timestamp) + 1;
        unitAmounts[0] = PRINCIPAL;

        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee_,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://x",
            paymentAsset: address(token),
            denomSymbol: "USD",
            oracle: address(0), // fixed 1:1 rate, units == assets
            maxStaleness: 0,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 0,
            penaltyBpsPerDay: PENALTY_BPS_PER_DAY,
            defaultDeclarer: declarer_,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: lessor_,
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor_);
        id = lease.createLease(p);
    }

    /// @dev Simple, view-only version. True by construction (a view
    ///      never mutates storage); kept as a cheap baseline but
    ///      FLAGGED as trivial: it proves nothing about real
    ///      transactions, only about re-reads. The strong test is
    ///      test_INV_FREQ_immuneToNonEconomicTransactions below.
    function test_INV_FREQ_readsAloneCannotDiverge_trivialBaseline() public {
        uint256 idA = _mkLease();
        uint256 idB = _mkLease();
        vm.warp(block.timestamp + 2);
        t0Slot = block.timestamp;

        vm.warp(t0Slot + 90 days);
        uint256 arrearsA = lease.arrears(idA);

        for (uint256 i = 0; i < 90; i++) {
            vm.warp(t0Slot + i * 1 days);
            lease.arrears(idB); // discarded — a view cannot mutate anything
        }
        vm.warp(t0Slot + 90 days);
        uint256 arrearsB = lease.arrears(idB);

        assertEq(arrearsA, arrearsB, "trivial: views never mutate storage");
    }

    /// @dev Strong INV-FREQ — immune to transactions with no economic effect.
    ///      Tests what S3-01 really asked for: two identical leases, with
    ///      the SAME payments at the SAME instants, but one of them
    ///      also receives every real transaction (not reverted, with
    ///      genuine storage writes) that can be interleaved without moving
    ///      money in the lease — declareDefault, updateServicing,
    ///      assignLessee, transfer of the lessor-position NFT, and
    ///      a payment attempt that reverts. arrears() must match
    ///      EXACTLY at the end in both.
    ///
    ///      ARGUMENT (not just empirical) for why this has to be
    ///      equal, verified by exhaustive inspection of
    ///      src/FinancialLease.sol before writing this test (every
    ///      `l.<field> = ...` in the contract, grep-confirmed one by one):
    ///
    ///      arrears() depends ONLY on the fields read by
    ///      _computeState()/_penaltyOwed(): dueDates, unitAmounts,
    ///      penaltyBpsPerDay (all three set once in
    ///      createLease, never rewritten afterwards), settledUnits,
    ///      firstUnsettledIndex, cumBeforeFirstUnsettled,
    ///      crystallizedPenaltyUnits, penaltyPaidUnits.
    ///
    ///      Of those 5 "live" fields, the ONLY writes anywhere in
    ///      the contract outside createLease are those made by
    ///      _applyToPrincipal() (settledUnits, firstUnsettledIndex,
    ///      cumBeforeFirstUnsettled, crystallizedPenaltyUnits) and
    ///      penaltyPaidUnits (mutated only inside pay()). No other
    ///      function of the contract — declareDefault, exercisePurchaseOption,
    ///      assignLessee, updateServicing, nor the inherited ERC721
    ///      transfers (which also live in OpenZeppelin storage,
    ///      fully separate from the Lease struct) — writes any of
    ///      those 5 fields. declareDefault/exercisePurchaseOption only
    ///      write `status` (which _computeState does not even read);
    ///      assignLessee only writes `lessee`; updateServicing only
    ///      writes the servicing mapping. Therefore NO
    ///      transaction without a payment can alter the result of arrears() —
    ///      it is a structural guarantee of the design (closed-form, no
    ///      aggregate bucket or intermediate persistence step), not a
    ///      coincidence of this particular scenario.
    function test_INV_FREQ_immuneToNonEconomicTransactions() public {
        uint256 idA = _mkLease();
        uint256 idB = _mkLease();

        vm.warp(block.timestamp + 2); // cross the due date in both
        t0Slot = block.timestamp;

        // Lease B: interleave every real transaction with no economic effect
        // that the contract allows, BEFORE the payment.
        vm.prank(lessor_);
        lease.updateServicing(idB, INPUT_COLLECTIONS, uint64(block.timestamp));

        vm.prank(declarer_);
        lease.declareDefault(idB); // valid: idB is already in arrears (1,000,000 overdue)

        vm.prank(lessor_);
        lease.transferFrom(lessor_, otherLessor, idB); // the position NFT changes owner

        vm.prank(lessee_);
        lease.assignLessee(idB, otherLessee); // the lessee is reassigned

        vm.prank(otherLessor); // the new servicer is NOT otherLessor -> reverts
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.updateServicing(idB, INPUT_ARREARS_RECORD, uint64(block.timestamp));

        vm.prank(otherLessee); // payment of 0 -> reverts, must leave no trace
        vm.expectRevert(FinancialLease.NothingDue.selector);
        lease.pay(idB, 0);

        // Advance 90 days interleaving MORE payment-free transactions on B
        // (lease A receives none — only the passage of time).
        for (uint256 i = 0; i < 90; i++) {
            vm.warp(t0Slot + (i + 1) * 1 days);
            if (i % 10 == 0) {
                vm.prank(lessor_);
                lease.updateServicing(idB, INPUT_COLLECTIONS, uint64(block.timestamp));
            }
        }
        assertEq(block.timestamp, t0Slot + 90 days, "precondition: same final timestamp");

        // The SAME payment, at the SAME instant, on both leases — this is
        // the only kind of transaction the design allows to alter
        // arrears(), and it is identical on A and B.
        uint256 payment = 500_000 * UNIT;
        vm.prank(lessee_);
        lease.pay(idA, payment);
        vm.prank(otherLessee); // on B the lessee was already reassigned above
        lease.pay(idB, payment);

        assertEq(
            lease.arrears(idA),
            lease.arrears(idB),
            "strong INV-FREQ: arrears() must match even though B received real transactions (declareDefault, updateServicing, assignLessee, NFT transfer, reverted payments) that A never received"
        );

        // Quantitative check: SIMPLE interest per tranche (fix
        // S3-01), 1,000,000 UNIT overdue since t0, penaltyBpsPerDay=10,
        // 90 days, minus the 500,000 UNIT payment applied at the same
        // instant on both. The penalty before the payment is identical to the
        // historical "Case A" of the bug (90,000 UNIT) on both leases.
        assertEq(
            lease.arrears(idA), (PRINCIPAL + 90_000 * UNIT) - payment, "exact simple penalty, after the payment"
        );
    }
}
