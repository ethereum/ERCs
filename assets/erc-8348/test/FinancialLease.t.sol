// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {MockUVAOracle} from "../src/MockUVAOracle.sol";
import {
    IFinancialLease,
    INPUT_INDEX_OBSERVATION,
    INPUT_COLLECTIONS,
    INPUT_ARREARS_RECORD,
    INPUT_INSURANCE_STATUS,
    INPUT_ASSET_CONDITION,
    INPUT_RESIDUAL_APPRAISAL,
    TERMINATION_MUTUAL_AGREEMENT,
    TERMINATION_DEFAULT
} from "../src/IFinancialLease.sol";
import {IFinancialLeaseAnchored} from "../src/IFinancialLeaseAnchored.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FinancialLeaseTest is Test {
    FinancialLease lease;
    MockERC20 token;
    MockUVAOracle oracle;

    address lessor = makeAddr("lessor");
    address lessee = makeAddr("lessee");
    address newLessee = makeAddr("newLessee");
    address defaultDeclarer = makeAddr("defaultDeclarer");

    uint64 constant DAY = 1 days;
    uint256 constant UNIT = 1e18;

    function setUp() public {
        lease = new FinancialLease();
        token = new MockERC20();
        oracle = new MockUVAOracle(1e18);

        token.mint(lessee, 1_000_000e18);
        vm.prank(lessee);
        token.approve(address(lease), type(uint256).max);
    }

    // ─── helpers ────────────────────────────────────────────

    function _schedule(uint256 n, uint256 amountEach)
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

    function _createLease(address oracle_, uint64 staleness, uint64[] memory dueDates, uint256[] memory unitAmounts)
        internal
        returns (uint256 leaseId)
    {
        leaseId = _createLeaseWithServicingConfig(
            oracle_, staleness, dueDates, unitAmounts, new bytes32[](0), new uint64[](0)
        );
    }

    /// @dev Change 3: maxStaleness per servicing input is configured AT
    ///      ORIGINATION (parallel arrays), not set by the servicer afterwards.
    function _createLeaseWithServicingConfig(
        address oracle_,
        uint64 staleness,
        uint64[] memory dueDates,
        uint256[] memory unitAmounts,
        bytes32[] memory servicingInputs,
        uint64[] memory servicingMaxStaleness
    ) internal returns (uint256 leaseId) {
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://vehicle/1",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: oracle_,
            maxStaleness: staleness,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10, // 0.10%/day
            defaultDeclarer: defaultDeclarer,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: servicingInputs,
            servicingMaxStaleness: servicingMaxStaleness
        });
        vm.prank(lessor);
        leaseId = lease.createLease(p);
    }

    function _defaultLease() internal returns (uint256 leaseId) {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        leaseId = _createLease(address(oracle), 7 days, dueDates, unitAmounts);
    }

    function _pay(uint256 leaseId, uint256 assets) internal {
        vm.prank(lessee);
        lease.pay(leaseId, assets);
    }

    // ─── T1: payment with a moving index ───────────────────

    function test_T1_paymentWithMovingIndex() public {
        uint256 id1 = _defaultLease();
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        uint256 id2 = _createLease(address(oracle), 7 days, dueDates, unitAmounts);

        // Pay the first installment of id1 with rate = 1.0
        (uint256 assets1,) = lease.nextPayment(id1);
        _pay(id1, assets1);

        // Move the oracle and pay the same nominal installment on id2
        oracle.set(2e18);
        (uint256 assets2,) = lease.nextPayment(id2);
        _pay(id2, assets2);

        assertEq(lease.outstandingUnits(id1), lease.outstandingUnits(id2), "unitsSettled must be identical");
        assertTrue(assets2 > assets1, "assets must differ with the moved rate");
        assertEq(assets2, assets1 * 2, "when the rate doubles, assets double");
    }

    // ─── T2: directional rounding ──────────────────────────

    function test_T2_directionalRounding() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 7 days, dueDates, unitAmounts);
        oracle.set(1_333_333_333_333_333_333); // rate does not divide exactly

        (uint256 assetsDue,) = lease.nextPayment(id);
        // nextPayment uses Ceil -> paying exactly that must always settle the installment
        uint256 outstandingBefore = lease.outstandingUnits(id);
        _pay(id, assetsDue);
        assertEq(lease.outstandingUnits(id), outstandingBefore - unitAmounts[0], "the full installment must be settled");

        // The contract never credits more units than those actually covered (Floor)
        // Verified indirectly: we build another lease and pay 1 wei of asset less
        (uint64[] memory dd2, uint256[] memory ua2) = _schedule(1, 100 * UNIT);
        uint256 id2 = _createLease(address(oracle), 7 days, dd2, ua2);
        uint256 underpay = assetsDue - 1;
        uint256 expectedUnitsFloor = (underpay * 1e18) / oracle.rate();
        _pay(id2, underpay);
        assertEq(lease.outstandingUnits(id2), ua2[0] - expectedUnitsFloor, "exact floor on underpayment");
        assertTrue(lease.outstandingUnits(id2) > 0, "1 wei less must not settle the installment");
    }

    // ─── T3: assignment with cash flow ─────────────────────

    function test_T3_assignmentMidStream() public {
        uint256 id = _defaultLease();
        (uint256 assets1,) = lease.nextPayment(id);
        _pay(id, assets1);

        // Transfer the NFT (lessor position) mid-contract
        vm.prank(lessor);
        lease.transferFrom(lessor, newLessee, id);
        assertEq(lease.lessor(id), newLessee);

        uint256 balBefore = token.balanceOf(newLessee);
        (uint256 assets2,) = lease.nextPayment(id);
        _pay(id, assets2);

        assertEq(token.balanceOf(newLessee), balBefore + assets2, "the new owner must receive the payment");
    }

    // ─── T4: staleness ─────────────────────────────────────

    function test_T4_staleOracleReverts() public {
        uint256 id = _defaultLease();
        oracle.set(1e18); // sets asOf = now

        vm.warp(block.timestamp + 8 days); // maxStaleness = 7 days

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.StaleOracle.selector);
        lease.pay(id, 100 * UNIT);
    }

    // ─── T5: default cycle ─────────────────────────────────

    function test_T5_defaultCycle() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate1) = lease.nextPayment(id);

        vm.warp(uint256(dueDate1) + 1 days);
        oracle.set(1e18); // refresh staleness

        // status() reports accrual as of block.timestamp without
        // needing a prior tx: it already reflects InArrears here, before
        // declareDefault.
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InArrears));

        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        // Full payment: all outstanding principal (overdue installment + the 2
        // remaining ones) PLUS all arrears reported by arrears() (overdue
        // principal + penalty accrued so far). Overpaying the overdue principal
        // is not a problem (pay() caps at what is actually owed,
        // see fix (d)): the margin comes from a real amount read from the
        // contract, not from a constant that depends on how much penalty
        // "should" have accrued under one implementation or another.
        uint256 totalUnits = lease.outstandingUnits(id);
        uint256 totalAssets = lease.convertToAssets(id, totalUnits) + lease.arrears(id);

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        _pay(id, totalAssets);

        IFinancialLease.LeaseStatus finalStatus = lease.status(id);
        assertTrue(
            finalStatus == IFinancialLease.LeaseStatus.Active || finalStatus == IFinancialLease.LeaseStatus.Completed,
            "must cure to Active or Completed"
        );
        assertEq(lease.outstandingUnits(id), 0, "no principal may remain outstanding after full payment");
    }

    // ─── T6: REGRESSION bug (a) ────────────────────────────

    function test_T6_paidFlagWhileInArrears() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);

        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);

        // Cross the due date and act on the lease before reading `paid`
        vm.prank(defaultDeclarer);
        lease.declareDefault(id); // installment 0 is now overdue and unpaid

        (,, bool paid) = lease.paymentAt(id, 0);
        assertFalse(paid, "the overdue unpaid installment must not show as paid");
    }

    // ─── T7: REGRESSION bug (b) ────────────────────────────

    function test_T7_penaltyDoesNotReducePrincipal() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);

        // Step 1: cross the due date and formalize the default. After fix
        // S3-01 the penalty accrues in closed form from the actual due
        // date of each tranche (dueDates[i]), not from the
        // moment a tx "notices" it — declareDefault no longer has
        // any effect on WHEN the penalty starts to run.
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);

        // Step 2: let additional days pass so that the stock of 100
        // overdue units keeps accruing penalty.
        vm.warp(block.timestamp + 10 days);
        oracle.set(1e18); // refresh staleness

        uint256 outstandingBefore = lease.outstandingUnits(id);
        uint256 lessorBalBefore = token.balanceOf(lessor);

        // Pay EXACTLY arrears(id): by definition it is the overdue principal
        // plus the penalty accrued so far, without reaching
        // future installments not yet due (fix d caps at what is
        // actually owed, it does not donate the rest). No number of days or
        // penalty units is assumed in advance — it comes
        // from what the contract reports.
        _pay(id, lease.arrears(id));

        uint256 outstandingAfter = lease.outstandingUnits(id);
        uint256 principalPaid = outstandingBefore - outstandingAfter;
        assertEq(principalPaid, 100 * UNIT, "outstandingUnits must decrease ONLY by the principal of the overdue installment");

        uint256 pulled = token.balanceOf(lessor) - lessorBalBefore;
        assertGt(pulled, principalPaid, "the actual payment must include penalties in addition to principal");
        assertEq(lease.arrears(id), 0, "all arrears (principal + penalties) must be settled");
    }

    // ─── extra fuzz on T2 ──────────────────────────────────

    function testFuzz_T2_floorNeverOvercredits(uint256 rate, uint256 assets) public {
        rate = bound(rate, 1e6, 1e30); // avoid rate=0 and pathological overflow
        assets = bound(assets, 0, 1_000_000e18);

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 1_000_000e18);
        oracle.set(rate);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts);

        token.mint(lessee, assets);
        vm.prank(lessee);
        token.approve(address(lease), assets);

        uint256 expectedUnitsFloor = (assets * 1e18) / rate;
        if (expectedUnitsFloor == 0) {
            vm.prank(lessee);
            vm.expectRevert(FinancialLease.NothingDue.selector);
            lease.pay(id, assets);
            return;
        }

        uint256 outstandingBefore = lease.outstandingUnits(id);
        _pay(id, assets);
        uint256 unitsSettled = outstandingBefore - lease.outstandingUnits(id);

        assertLe(unitsSettled, expectedUnitsFloor, "settledUnits must never exceed the floor of what was paid");
    }

    // ─── T9: assetAnchor (ERC-8325) ─────────────────────────

    function test_T9_assetAnchor() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://vehicle/1",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 7 days,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: defaultDeclarer,
            terminationDelay: 7 days,
            anchorChainId: 1,
            anchorRegistry: address(0xBEEF),
            anchorId: bytes32(uint256(42)),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        uint256 anchoredId = lease.createLease(p);

        (uint256 chainId, address registry, bytes32 anchorId) = lease.assetAnchor(anchoredId);
        assertEq(chainId, 1, "chainId must match");
        assertEq(registry, address(0xBEEF), "registry must match");
        assertEq(anchorId, bytes32(uint256(42)), "anchorId must match");

        uint256 unanchoredId = _defaultLease();
        (uint256 chainId2, address registry2, bytes32 anchorId2) = lease.assetAnchor(unanchoredId);
        assertEq(chainId2, 0, "unanchored: chainId must be zero");
        assertEq(registry2, address(0), "unanchored: registry must be zero");
        assertEq(anchorId2, bytes32(0), "unanchored: anchorId must be zero");

        assertTrue(
            lease.supportsInterface(type(IFinancialLeaseAnchored).interfaceId),
            "must declare ERC-165 support for IFinancialLeaseAnchored"
        );
    }

    // ─── T39: partial anchor tuple reverts (change 1) ──────

    function test_T39_partialAnchorTupleReverts() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);

        // anchorId set, registry and chainId zero: partial -> reverts
        FinancialLease.CreateLeaseParams memory p1 = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://vehicle/1",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 7 days,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: defaultDeclarer,
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(uint256(42)),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidAnchor.selector);
        lease.createLease(p1);

        // registry set, chainId and anchorId zero: also partial
        FinancialLease.CreateLeaseParams memory p2 = p1;
        p2.anchorChainId = 0;
        p2.anchorRegistry = address(0xBEEF);
        p2.anchorId = bytes32(0);
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidAnchor.selector);
        lease.createLease(p2);

        // chainId set, the rest zero: also partial
        FinancialLease.CreateLeaseParams memory p3 = p1;
        p3.anchorChainId = 1;
        p3.anchorRegistry = address(0);
        p3.anchorId = bytes32(0);
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidAnchor.selector);
        lease.createLease(p3);

        // full tuple: passes
        FinancialLease.CreateLeaseParams memory p4 = p1;
        p4.anchorChainId = 1;
        p4.anchorRegistry = address(0xBEEF);
        p4.anchorId = bytes32(uint256(42));
        vm.prank(lessor);
        uint256 idFull = lease.createLease(p4);
        (uint256 chainId, address registry, bytes32 anchorId) = lease.assetAnchor(idFull);
        assertEq(chainId, 1);
        assertEq(registry, address(0xBEEF));
        assertEq(anchorId, bytes32(uint256(42)));

        // all-zero tuple: passes (unanchored lease)
        FinancialLease.CreateLeaseParams memory p5 = p1;
        p5.anchorChainId = 0;
        p5.anchorRegistry = address(0);
        p5.anchorId = bytes32(0);
        vm.prank(lessor);
        uint256 idNone = lease.createLease(p5);
        (uint256 chainId2, address registry2, bytes32 anchorId2) = lease.assetAnchor(idNone);
        assertEq(chainId2, 0);
        assertEq(registry2, address(0));
        assertEq(anchorId2, bytes32(0));
    }

    // ─── T10: inputFreshness — derived IndexObservation ───

    function test_T10_inputFreshnessIndexObservation() public {
        uint256 id = _defaultLease(); // oracle + maxOracleStaleness = 7 days
        (, uint64 expectedAsOf) = lease.conversionRateAsOf(id);

        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_INDEX_OBSERVATION);
        assertEq(observedAt, expectedAsOf, "observedAt must match conversionRateAsOf");
        assertEq(
            reportedAt,
            expectedAsOf,
            "reportedAt also derives from conversionRateAsOf: the oracle does not distinguish the two moments"
        );
        assertEq(maxStaleness, 7 days, "maxStaleness must match maxOracleStaleness");

        // Lease with fixed denomination (no oracle)
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 fixedId = _createLease(address(0), 0, dueDates, unitAmounts);
        (uint64 observedAtFixed, uint64 reportedAtFixed, uint64 maxStalenessFixed) =
            lease.inputFreshness(fixedId, INPUT_INDEX_OBSERVATION);
        assertEq(observedAtFixed, uint64(block.timestamp), "fixed denomination: observedAt must be the current time");
        assertEq(reportedAtFixed, uint64(block.timestamp), "fixed denomination: reportedAt as well");
        assertEq(maxStalenessFixed, 0, "fixed denomination: no staleness limit");
    }

    // ─── T11: updateServicing + inputFreshness (history) ──

    function test_T11_updateServicingAndFreshness() public {
        vm.warp(block.timestamp + 100 days); // room to "observe in the past" below

        // Change 3: maxStaleness is configured AT ORIGINATION, not set by the servicer.
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = INPUT_COLLECTIONS;
        uint64[] memory maxStalenesses = new uint64[](1);
        maxStalenesses[0] = 3 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses); // default servicer = lessor (msg.sender in createLease)

        uint64 observedAtReported = uint64(block.timestamp) - 5 days; // observed 5 days ago
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, observedAtReported);
        uint64 callTime = uint64(block.timestamp);

        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAt, observedAtReported, "observedAt must be the one declared by the servicer");
        assertEq(reportedAt, callTime, "reportedAt must be the timestamp of the updateServicing tx");
        assertEq(maxStaleness, 3 days, "maxStaleness must be the one configured at origination, not by the servicer");

        vm.warp(block.timestamp + 10 days);
        (uint64 observedAtLater, uint64 reportedAtLater,) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAtLater, observedAtReported, "observedAt is historical: it does not change as time passes");
        assertEq(reportedAtLater, callTime, "reportedAt is historical: it does not change as time passes");
    }

    // ─── T12: servicer access control ──────────────────────

    function test_T12_updateServicingAccessControl() public {
        uint256 id = _defaultLease();
        address rando = makeAddr("rando");

        vm.prank(rando);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));

        vm.prank(lessor);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        (, uint64 reportedAt,) = lease.inputFreshness(id, INPUT_ARREARS_RECORD);
        assertEq(reportedAt, uint64(block.timestamp), "the servicer can attest");
    }

    // ─── T13: IndexObservation cannot be attested manually ─

    function test_T13_indexObservationNotAttestable() public {
        uint256 id = _defaultLease();
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.DerivedInput.selector);
        lease.updateServicing(id, INPUT_INDEX_OBSERVATION, uint64(block.timestamp));
    }

    // ─── T40: observedAt vs reportedAt diverge (change 2) ──

    function test_T40_observedAtAndReportedAtDiverge() public {
        vm.warp(block.timestamp + 100 days);
        uint256 id = _defaultLease();

        uint64 observedAt14DaysAgo = uint64(block.timestamp) - 14 days;
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, observedAt14DaysAgo);

        (uint64 observedAt, uint64 reportedAt,) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAt, observedAt14DaysAgo, "observedAt must be the one declared by the servicer (14 days ago)");
        assertEq(reportedAt, uint64(block.timestamp), "reportedAt must be the timestamp of the tx");
        assertTrue(observedAt != reportedAt, "observedAt and reportedAt must be able to differ");
        assertEq(reportedAt - observedAt, 14 days, "the divergence must be exactly 14 days");
    }

    // ─── T41: a future observation reverts (change 2) ──────

    function test_T41_futureObservationReverts() public {
        uint256 id = _defaultLease();
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.FutureObservation.selector);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp) + 1);

        // observedAt == block.timestamp (exact limit): not in the future, passes
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));
    }

    // ─── T42: the servicer cannot change maxStaleness (change 3) ──

    function test_T42_maxStalenessNotSettableByServicer() public {
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = INPUT_ARREARS_RECORD;
        uint64[] memory maxStalenesses = new uint64[](1);
        maxStalenesses[0] = 5 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses);

        // updateServicing no longer accepts a maxStaleness parameter: only
        // (leaseId, input, observedAt). Attesting several times does not change the
        // tolerance, which remains the one configured at origination.
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        (,, uint64 maxStaleness1) = lease.inputFreshness(id, INPUT_ARREARS_RECORD);
        assertEq(maxStaleness1, 5 days, "maxStaleness must be the one configured at origination");

        vm.warp(block.timestamp + 1 days);
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        (,, uint64 maxStaleness2) = lease.inputFreshness(id, INPUT_ARREARS_RECORD);
        assertEq(maxStaleness2, 5 days, "maxStaleness must not change between servicer attestations");

        // an input WITHOUT a configured tolerance returns 0 (default = no limit)
        (,, uint64 maxStalenessUnconfigured) = lease.inputFreshness(id, INPUT_INSURANCE_STATUS);
        assertEq(maxStalenessUnconfigured, 0, "with no config at origination, maxStaleness defaults to 0");
    }

    // ─── T43: custom input — extensibility without touching the interface (change 4) ──

    function test_T43_customInputExtensibility() public {
        uint256 id = _defaultLease();
        bytes32 customInput = keccak256("test.input.custom");

        (uint64 observedAtBefore, uint64 reportedAtBefore, uint64 maxStalenessBefore) =
            lease.inputFreshness(id, customInput);
        assertEq(observedAtBefore, 0, "before attesting: observedAt is zero");
        assertEq(reportedAtBefore, 0, "before attesting: reportedAt is zero");
        assertEq(maxStalenessBefore, 0, "before attesting: maxStaleness is zero");

        vm.prank(lessor);
        lease.updateServicing(id, customInput, uint64(block.timestamp));

        (uint64 observedAt, uint64 reportedAt,) = lease.inputFreshness(id, customInput);
        assertEq(observedAt, uint64(block.timestamp), "a custom input (outside the base set) must work the same way");
        assertEq(reportedAt, uint64(block.timestamp));
    }

    // ─── T44: a never-attested input returns zeros, without reverting ──

    function test_T44_neverReportedInputReturnsZeros() public view {
        uint256 id = 1; // no lease has been created yet in this test
        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_ASSET_CONDITION);
        assertEq(observedAt, 0);
        assertEq(reportedAt, 0);
        assertEq(maxStaleness, 0);
    }

    // ─── T45: residualAppraisal works like any base input ──

    function test_T45_residualAppraisalInput() public {
        bytes32[] memory inputs = new bytes32[](1);
        inputs[0] = INPUT_RESIDUAL_APPRAISAL;
        uint64[] memory maxStalenesses = new uint64[](1);
        maxStalenesses[0] = 30 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses);

        vm.prank(lessor);
        lease.updateServicing(id, INPUT_RESIDUAL_APPRAISAL, uint64(block.timestamp));

        (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness) = lease.inputFreshness(id, INPUT_RESIDUAL_APPRAISAL);
        assertEq(observedAt, uint64(block.timestamp));
        assertEq(reportedAt, uint64(block.timestamp));
        assertEq(maxStaleness, 30 days, "INPUT_RESIDUAL_APPRAISAL must work like any base input");
    }

    // ─── T14: servicing is parallel reporting, it does not alter pay() ─

    function test_T14_servicingIsolatedFromPayFlow() public {
        bytes32[] memory inputs = new bytes32[](4);
        inputs[0] = INPUT_COLLECTIONS;
        inputs[1] = INPUT_ARREARS_RECORD;
        inputs[2] = INPUT_INSURANCE_STATUS;
        inputs[3] = INPUT_ASSET_CONDITION;
        uint64[] memory maxStalenesses = new uint64[](4);
        maxStalenesses[0] = 1 days;
        maxStalenesses[1] = 1 days;
        maxStalenesses[2] = 1 days;
        maxStalenesses[3] = 1 days;

        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(3, 100 * UNIT);
        uint256 id =
            _createLeaseWithServicingConfig(address(oracle), 7 days, dueDates, unitAmounts, inputs, maxStalenesses);
        (, uint64 dueDate1) = lease.nextPayment(id);

        vm.warp(uint256(dueDate1) + 1 days);
        oracle.set(1e18);

        // Attest the 4 categories before generating arrears
        vm.startPrank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));
        lease.updateServicing(id, INPUT_ARREARS_RECORD, uint64(block.timestamp));
        lease.updateServicing(id, INPUT_INSURANCE_STATUS, uint64(block.timestamp));
        lease.updateServicing(id, INPUT_ASSET_CONDITION, uint64(block.timestamp));
        vm.stopPrank();

        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        // Margin derived from arrears(id) (overdue principal + actual
        // penalty), not from a constant — see T5.
        uint256 totalUnits = lease.outstandingUnits(id);
        uint256 totalAssets = lease.convertToAssets(id, totalUnits) + lease.arrears(id);

        // Re-attest mid-cycle, even after computing what is owed
        vm.prank(lessor);
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        _pay(id, totalAssets);

        // Same results as T5 (without servicing): the reporting changed nothing
        IFinancialLease.LeaseStatus finalStatus = lease.status(id);
        assertTrue(
            finalStatus == IFinancialLease.LeaseStatus.Active || finalStatus == IFinancialLease.LeaseStatus.Completed,
            "must cure to Active or Completed, same as without servicing"
        );
        assertEq(lease.outstandingUnits(id), 0, "no principal may remain outstanding after full payment");
        assertEq(lease.arrears(id), 0, "arrears must be settled, same as without servicing");

        // Servicing is still queryable and was not touched by pay()
        (uint64 observedAtCollections,, uint64 maxStalenessCollections) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertTrue(observedAtCollections > 0, "the Collections attestation must still stand");
        assertEq(maxStalenessCollections, 1 days, "pay() must not modify the servicing config");
    }

    // ─── T35: REGRESSION finding — views must reflect accrual
    //     without needing a prior tx ────────────────────────────

    function test_T35_viewReflectsArrearsWithoutPriorTx() public {
        uint256 id = _defaultLease(); // 3 installments x100 UNIT, due at 30/60/90 days
        (, uint64 dueDate1) = lease.nextPayment(id);

        // Cross the due dates of installments 1 and 2 (days 30 and 60) without
        // sending ANY transaction to the contract in between.
        vm.warp(uint256(dueDate1) + 31 days);

        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.InArrears),
            "REGRESSION: status() must reflect arrears without needing a prior tx"
        );
        assertGt(lease.arrears(id), 0, "REGRESSION: arrears() must be > 0 without needing a prior tx");
    }

    // ─── T36: the projected view matches what is persisted exactly ──

    function test_T36_viewMatchesPersistedStateExactly() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate1) = lease.nextPayment(id);
        vm.warp(uint256(dueDate1) + 45 days);
        oracle.set(1e18); // refresh staleness for the declareDefault/pay that follow

        IFinancialLease.LeaseStatus statusBefore = lease.status(id);
        uint256 arrearsBefore = lease.arrears(id);
        (uint256 nextAssetsBefore, uint64 nextDueBefore) = lease.nextPayment(id);
        assertEq(uint8(statusBefore), uint8(IFinancialLease.LeaseStatus.InArrears), "precondition: must be in arrears");

        // Persist a real state change (declareDefault), with no further
        // time passing since the read above.
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault), "post-declare: InDefault");

        // Zero divergence: what the view projected matches exactly
        // what was persisted (re-read now with nothing left to project).
        assertEq(lease.arrears(id), arrearsBefore, "arrears() must match the persisted state exactly");
        (uint256 nextAssetsAfter, uint64 nextDueAfter) = lease.nextPayment(id);
        assertEq(nextAssetsAfter, nextAssetsBefore, "nextPayment().assets must match the persisted state exactly");
        assertEq(nextDueAfter, nextDueBefore, "nextPayment().dueDate must match the persisted state exactly");
    }

    // ─── T37: projected penalties grow monotonically and
    //     match what is actually settled on payment ────────────

    function test_T37_penaltyProjectionGrowsMonotonicallyAndMatchesPersisted() public {
        uint256 id = _defaultLease(); // penaltyBpsPerDay = 10 (0.10%/day)
        (, uint64 dueDate1) = lease.nextPayment(id);

        // Put the lease in default with a real tx. Penalties accrue in closed
        // form from each installment's own due date (see T7).
        vm.warp(uint256(dueDate1) + 5 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        uint256 arrearsT0 = lease.arrears(id);

        // Advance WITHOUT sending any tx: arrears() must grow strictly
        // with each additional day of arrears, via the pure projection.
        vm.warp(block.timestamp + 3 days);
        uint256 arrearsT3 = lease.arrears(id);
        assertGt(arrearsT3, arrearsT0, "arrears() must grow over time with no tx (day 3)");

        vm.warp(block.timestamp + 4 days);
        uint256 arrearsT7 = lease.arrears(id);
        assertGt(arrearsT7, arrearsT3, "arrears() must keep growing (day 7)");

        // The value projected right before paying must be exactly what
        // is needed to settle all arrears on payment.
        uint256 projectedBeforePay = lease.arrears(id);
        uint256 totalUnitsOwed = lease.outstandingUnits(id);
        uint256 assetsToPay = lease.convertToAssets(id, totalUnitsOwed) + projectedBeforePay + 100; // generous margin

        vm.expectEmit(true, false, false, false);
        emit IFinancialLease.DefaultCured(id);
        _pay(id, assetsToPay);

        assertEq(lease.arrears(id), 0, "the payment must settle exactly all projected arrears");
        IFinancialLease.LeaseStatus finalStatus = lease.status(id);
        assertTrue(
            finalStatus == IFinancialLease.LeaseStatus.Active || finalStatus == IFinancialLease.LeaseStatus.Completed,
            "must cure to Active or Completed"
        );
    }

    // ─── T38: terminal statuses — the passage of time does not alter them ──

    function test_T38_projectedStateFrozenInTerminalStatuses() public {
        (uint64[] memory dd, uint256[] memory ua) = _schedule(1, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 7 days, dd, ua);

        vm.warp(uint256(dd[0]));
        oracle.set(1e18);
        _pay(id, lease.convertToAssets(id, ua[0]));
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        // Completed: nothing must move with time, with no tx in between.
        uint256 arrearsCompletedBefore = lease.arrears(id);
        (uint256 nextAssetsBefore,) = lease.nextPayment(id);
        vm.warp(block.timestamp + 400 days);
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Completed),
            "Completed must not change over time"
        );
        assertEq(lease.arrears(id), arrearsCompletedBefore, "arrears() must not change in Completed");
        (uint256 nextAssetsAfter,) = lease.nextPayment(id);
        assertEq(nextAssetsAfter, nextAssetsBefore, "nextPayment() must not change in Completed");

        // PurchaseExercised: likewise.
        oracle.set(1e18); // refresh staleness (maxOracleStaleness = 7 days)
        vm.prank(lessee);
        lease.exercisePurchaseOption(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));

        vm.warp(block.timestamp + 400 days);
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.PurchaseExercised),
            "PurchaseExercised must not change over time"
        );

        // Note: Terminated is also terminal and frozen in time
        // (fix S6-01): once a lease is terminated, _effectiveNow()
        // stops at the termination instant, so nothing derived from
        // _computeState moves afterwards. That freeze is covered
        // separately by T66 (views frozen after termination)
        // and T67 (every state-changing operation reverts on a
        // Terminated lease).
    }

    // ─── T47: fix S3-01 — the historical penalty of a settled tranche
    //     neither disappears nor is double-counted ──────────────────

    function test_T47_historicalPenaltyPreservedAcrossPrincipalPayment() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(2, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts); // penaltyBpsPerDay = 10

        // Both installments overdue: installment0 60 days late, installment1 30 days late.
        vm.warp(uint256(dueDates[1]) + 30 days);
        oracle.set(1e18);

        // Total dynamic penalty before paying: installment0 (100*10*60/10000
        // = 6) + installment1 (100*10*30/10000 = 3) = 9 UNIT.
        assertEq(lease.arrears(id), 209 * UNIT, "precondition: 200 principal + 9 dynamic penalty");

        // Pay exactly: 9 (all accumulated penalty) + 100 (installment0
        // in full). This crystallizes installment0's penalty (6 UNIT, at ITS
        // own due date) and leaves installment1 with its principal
        // intact — but installment1's ALREADY accrued penalty (3 UNIT)
        // is also paid, because the penalty is a single pool
        // (crystallizedPenaltyUnits + dynamic) that is paid before
        // any principal, not an amount separable per tranche.
        _pay(id, 109 * UNIT);
        assertEq(
            lease.outstandingUnits(id), 100 * UNIT, "installment0 must be settled, installment1 principal intact"
        );
        assertEq(
            lease.arrears(id),
            100 * UNIT,
            "REGRESSION S3-01: no pending penalty immediately after paying it all"
        );

        // Advance 10 more days WITHOUT paying: installment1 goes from 30 to 40 days
        // in arrears. If installment0's crystallized penalty (6 UNIT, already
        // settled in the previous step) were lost or re-counted, this
        // number would come out wrong (an underflow revert if the
        // crystallization were lost, or a value other than 101
        // if it were counted twice). The correct value is exactly the
        // new delta of installment1 (4 - 3 = 1 UNIT) on top of the outstanding
        // principal (100).
        vm.warp(block.timestamp + 10 days);
        assertEq(
            lease.arrears(id),
            101 * UNIT,
            "REGRESSION S3-01: installment0's already-paid penalty must not reappear or affect installment1's new accrual"
        );
    }

    // ─── T48: fix S3-01 — multi-tranche crystallization uses the own date
    //     of EACH tranche, not a common date for the whole payment ──

    function test_T48_multiTrancheCrystallizationUsesOwnDueDatePerTranche() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(2, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts); // penaltyBpsPerDay = 10

        // installment0: 60 days in arrears. installment1: 30 days in arrears. Total
        // dynamic penalty: 6 + 3 = 9 UNIT. arrears() = 209 UNIT.
        vm.warp(uint256(dueDates[1]) + 30 days);
        oracle.set(1e18);
        assertEq(lease.arrears(id), 209 * UNIT, "precondition");

        // Pay 9 (penalty) + 100 (installment0 IN FULL) + 50 (installment1 PARTIAL)
        // = 159. If the code crystallized with a common date (e.g.
        // reusing installment0's 60 days also for installment1's 50,
        // or vice versa), the resulting arrears() would give a number other
        // than 50 (51.5 if it used 60 for both; underflow/revert if it used 30
        // for both — verified by hand).
        uint256 lessorBalBefore = token.balanceOf(lessor);
        _pay(id, 159 * UNIT);
        uint256 pulled = token.balanceOf(lessor) - lessorBalBefore;

        assertEq(pulled, 159 * UNIT, "exactly what was paid must be transferred (rate 1:1, no rounding)");
        assertEq(
            lease.arrears(id),
            50 * UNIT,
            "REGRESSION S3-01: multi-tranche crystallization must use each tranche's own due date"
        );
        assertEq(lease.outstandingUnits(id), 50 * UNIT, "installment0 settled + half of installment1");
    }

    // ─── T49: fix S3-01 — gas cost of arrears() with the cache ───────

    function test_T49_arrearsGasWithCacheOnLongSchedule() public {
        // 60 installments, penaltyBpsPerDay = 10. Prepay the first 48
        // (not yet due at that moment) in a single pay(), which
        // advances firstUnsettledIndex/cumBeforeFirstUnsettled to 48.
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(60, 100 * UNIT);
        uint256 id = _createLease(address(oracle), 0, dueDates, unitAmounts);

        _pay(id, 48 * 100 * UNIT);
        assertEq(lease.outstandingUnits(id), 12 * 100 * UNIT, "the last 12 installments must remain");

        // Let the remaining 12 fall due.
        vm.warp(uint256(dueDates[59]) + 1 days);
        oracle.set(1e18);

        uint256 g0 = gasleft();
        lease.arrears(id);
        uint256 gasUsed = g0 - gasleft();
        console2.log("T49 - arrears() gas with 60 installments / 12 overdue (cache active):", gasUsed);

        // An isolated prototype of the design measured
        // ~86,110 gas for the same scenario (12 overdue, cache with
        // index+sum). This number is on the real contract (it includes
        // the overhead of ERC721/the full storage layout, not just the
        // loop), so it is expected to be "of the same order", not identical.
        assertLt(gasUsed, 150_000, "arrears() with cache must not scale with the total schedule length (60)");
    }

    // ─── T50: fix S4-02 — only the outgoing lessee reassigns ─────────

    function test_T50_assignLesseeOnlyOutgoingLessee() public {
        uint256 id = _defaultLease(); // defaultDeclarer = defaultDeclarer (fixed, non-zero)

        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignLessee(id, newLessee);

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignLessee(id, newLessee);

        vm.prank(lessee);
        lease.assignLessee(id, newLessee);
        assertEq(lease.lessee(id), newLessee, "the outgoing lessee can reassign");
    }

    // ─── T51: fix S4-01 — defaultDeclarer follows the NFT by default ──

    function test_T51_defaultDeclarerFollowsNftTransferByDefault() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://vehicle/1",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 7 days,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: address(0), // no override: dynamic via ownerOf
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        uint256 id = lease.createLease(p);

        vm.warp(uint256(dueDates[0]) + 1 days);
        oracle.set(1e18);

        address rando = makeAddr("t51_rando");
        address newOwner = makeAddr("t51_newOwner");

        // Without transferring anything: the original lessor (current ownerOf) can
        // declare default; a third party cannot.
        vm.prank(rando);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        // Transfer the lessor-position NFT.
        vm.prank(lessor);
        lease.transferFrom(lessor, newOwner, id);

        // The OLD lessor no longer has the power — nobody called
        // assignDefaultDeclarer, it is the dynamic resolution that removes it.
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        // The NEW NFT owner can, automatically.
        vm.prank(newOwner);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    // ─── T52: fix S4-01 — explicit delegation gated by the current owner ──

    function test_T52_assignDefaultDeclarerGatedByCurrentOwner() public {
        uint256 id = _defaultLease(); // defaultDeclarer = defaultDeclarer (fixed, non-zero)
        address riskManager = makeAddr("riskManager");

        // Only the CURRENT ownerOf (lessor) can delegate — neither the lessee nor
        // the current declarer can reassign the role to themselves.
        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignDefaultDeclarer(id, riskManager);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignDefaultDeclarer(id, riskManager);

        vm.expectEmit(true, true, true, false);
        emit FinancialLease.DefaultDeclarerAssigned(id, defaultDeclarer, riskManager);
        vm.prank(lessor);
        lease.assignDefaultDeclarer(id, riskManager);

        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);

        // The old declarer lost the power; the delegate has it.
        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.declareDefault(id);

        vm.prank(riskManager);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));
    }

    // ─── T53: fix S4-02 — the original attack is blocked end to end ──

    function test_T53_S402AttackNoLongerPossible() public {
        // Reproduces the S4-02 scenario: the lease reaches Completed, the
        // lessor (via defaultDeclarer, left at 0 at origination) tries to
        // designate itself as lessee to exercise the purchase
        // option at zero cost.
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://vehicle/1",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 7 days,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: address(0), // left unspecified, as in the original finding
            terminationDelay: 7 days,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        uint256 id = lease.createLease(p);

        // The lessee pays the whole installment on time -> Completed.
        vm.warp(uint256(dueDates[0]));
        oracle.set(1e18);
        _pay(id, lease.convertToAssets(id, unitAmounts[0]));
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Completed));

        // Original attack step: the lessor, as defaultDeclarer
        // resolved dynamically (it is ownerOf(id)), tries to reassign
        // the lessee to itself via assignLessee. With the fix, it has no
        // path at all: assignLessee does not read defaultDeclarer.
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.assignLessee(id, lessor);

        assertEq(lease.lessee(id), lessee, "the original lessee must remain the holder of the purchase option");

        // The legitimate lessee CAN exercise it.
        oracle.set(1e18);
        vm.prank(lessee);
        lease.exercisePurchaseOption(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.PurchaseExercised));
    }

    // ─── Early termination (fix S6-01) ───────────────────────────────

    // ─── T57: mutual agreement from Active ────────────────────────

    function test_T57_mutualAgreementFromActive() public {
        uint256 id = _defaultLease(); // Active

        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        vm.prank(lessor);
        lease.acceptTermination(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T58: mutual agreement from InDefault ─────────────────────

    function test_T58_mutualAgreementFromInDefault() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InDefault));

        vm.prank(lessor);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessee);
        lease.acceptTermination(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T59: the wrong party accepts ─────────────────────────────

    function test_T59_wrongAccepterReverts() public {
        uint256 id = _defaultLease();
        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        // the proposer cannot accept its own proposal
        vm.prank(lessee);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.acceptTermination(id);

        // nor can an unrelated third party
        address rando = makeAddr("t59_rando");
        vm.prank(rando);
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.acceptTermination(id);

        // the correct counterparty (the NFT owner) can
        vm.prank(lessor);
        lease.acceptTermination(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T60: proposal overwritten — the second one counts ────────

    function test_T60_proposalOverwritten() public {
        uint256 id = _defaultLease();

        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        bytes32 customReason = keccak256("t60.custom.reason");
        vm.prank(lessee);
        lease.proposeTermination(id, customReason); // A proposes again, with another reason

        // If accepting still honoured the FIRST proposal, this would not
        // change anything observable; what proves that the SECOND counts is
        // the event emitted with the new reason.
        vm.expectEmit(true, true, false, false);
        emit IFinancialLease.TerminationRecorded(id, customReason);
        vm.prank(lessor);
        lease.acceptTermination(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T61: terminateForDefault before the timelock ─────────────

    function test_T61_terminateForDefaultBeforeTimelockReverts() public {
        uint256 id = _defaultLease(); // terminationDelay = 7 days
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);

        vm.warp(block.timestamp + 6 days); // < 7-day timelock
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.TimelockNotElapsed.selector);
        lease.terminateForDefault(id);
    }

    // ─── T62: terminateForDefault after the timelock ──────────────

    function test_T62_terminateForDefaultAfterTimelock() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);

        vm.warp(block.timestamp + 7 days); // exactly the timelock
        vm.prank(lessor);
        lease.terminateForDefault(id);

        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
    }

    // ─── T63: terminateForDefault from Active/InArrears ──────────

    function test_T63_terminateForDefaultWrongStatusReverts() public {
        uint256 id = _defaultLease(); // Active

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.terminateForDefault(id);

        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.InArrears)); // derived, without declareDefault

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.terminateForDefault(id);
    }

    // ─── T64: terminateForDefault by someone who is not the owner ──

    function test_T64_terminateForDefaultNotOwnerReverts() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 1 days);
        oracle.set(1e18);
        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        vm.warp(block.timestamp + 7 days);

        vm.prank(lessee); // not the NFT owner
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.terminateForDefault(id);

        vm.prank(defaultDeclarer); // nor this one, even though it declared the default
        vm.expectRevert(FinancialLease.NotAuthorized.selector);
        lease.terminateForDefault(id);
    }

    // ─── T65: createLease with terminationDelay == 0 ──────────────

    function test_T65_zeroTerminationDelayReverts() public {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        FinancialLease.CreateLeaseParams memory p = FinancialLease.CreateLeaseParams({
            lessee: lessee,
            jurisdiction: bytes2("AR"),
            governingLaw: "Buenos Aires",
            agreementHash: keccak256("agreement"),
            assetRef: "asset://x",
            paymentAsset: address(token),
            denomSymbol: "UVA",
            oracle: address(oracle),
            maxStaleness: 7 days,
            dueDates: dueDates,
            unitAmounts: unitAmounts,
            purchasePriceUnits: 10 * UNIT,
            penaltyBpsPerDay: 10,
            defaultDeclarer: defaultDeclarer,
            terminationDelay: 0,
            anchorChainId: 0,
            anchorRegistry: address(0),
            anchorId: bytes32(0),
            servicer: address(0),
            servicingInputs: new bytes32[](0),
            servicingMaxStaleness: new uint64[](0)
        });
        vm.prank(lessor);
        vm.expectRevert(FinancialLease.InvalidTerminationDelay.selector);
        lease.createLease(p);
    }

    // ─── T66: freeze after termination ───────────────────────────

    function test_T66_freezeAfterTermination() public {
        uint256 id = _defaultLease();
        (, uint64 dueDate0) = lease.nextPayment(id);
        vm.warp(uint256(dueDate0) + 5 days); // arrears running
        oracle.set(1e18);

        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessor);
        lease.acceptTermination(id); // Active/InArrears -> Terminated, with arrears running

        uint256 arrearsAtTermination = lease.arrears(id);
        uint256 outstandingAtTermination = lease.outstandingUnits(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));
        assertGt(arrearsAtTermination, 0, "precondition: there had to be arrears at termination");

        vm.warp(block.timestamp + 90 days);

        assertEq(lease.arrears(id), arrearsAtTermination, "FREEZE: arrears() must not change after termination");
        assertEq(
            lease.outstandingUnits(id), outstandingAtTermination, "FREEZE: outstandingUnits() must not change"
        );
        assertEq(
            uint8(lease.status(id)),
            uint8(IFinancialLease.LeaseStatus.Terminated),
            "FREEZE: status() must remain Terminated"
        );
    }

    // ─── T67: absorption — everything reverts on a Terminated lease ──

    function test_T67_allOperationsRevertOnTerminated() public {
        uint256 id = _defaultLease();
        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessor);
        lease.acceptTermination(id);
        assertEq(uint8(lease.status(id)), uint8(IFinancialLease.LeaseStatus.Terminated));

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.pay(id, 1 * UNIT);

        vm.prank(defaultDeclarer);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.declareDefault(id);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.assignLessee(id, newLessee);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.acceptTermination(id);

        vm.prank(lessor);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.terminateForDefault(id);

        vm.prank(lessee);
        vm.expectRevert(FinancialLease.WrongStatus.selector);
        lease.exercisePurchaseOption(id);
    }

    // ─── T68: updateServicing DOES work on a Terminated lease ──

    function test_T68_updateServicingWorksOnTerminated() public {
        uint256 id = _defaultLease();
        vm.prank(lessee);
        lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT);
        vm.prank(lessor);
        lease.acceptTermination(id);

        vm.prank(lessor); // default servicer = msg.sender of createLease = lessor
        lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp));

        (uint64 observedAt,,) = lease.inputFreshness(id, INPUT_COLLECTIONS);
        assertEq(observedAt, uint64(block.timestamp), "updateServicing must keep working after termination");
    }

    // ─── T69: full operation matrix (conformance test) ──

    /// @dev Builds a fresh lease and takes it exactly to the requested
    ///      status, with the fewest transactions needed.
    ///      InDefault is also left with the terminationDelay timelock
    ///      ALREADY elapsed, so terminateForDefault can be tested "after
    ///      the timelock" (T61/T62 cover the before/after edge separately).
    function _mkLeaseAtStatus(IFinancialLease.LeaseStatus target) internal returns (uint256 id) {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        id = _createLease(address(oracle), 7 days, dueDates, unitAmounts);

        if (target == IFinancialLease.LeaseStatus.Active) return id;

        if (target == IFinancialLease.LeaseStatus.Completed) {
            vm.warp(uint256(dueDates[0]));
            oracle.set(1e18);
            _pay(id, lease.convertToAssets(id, unitAmounts[0]));
            return id;
        }

        if (target == IFinancialLease.LeaseStatus.PurchaseExercised) {
            vm.warp(uint256(dueDates[0]));
            oracle.set(1e18);
            _pay(id, lease.convertToAssets(id, unitAmounts[0]));
            oracle.set(1e18);
            vm.prank(lessee);
            lease.exercisePurchaseOption(id);
            return id;
        }

        // InArrears, InDefault, Terminated: all cross the due date first.
        vm.warp(uint256(dueDates[0]) + 1 days);
        oracle.set(1e18);
        if (target == IFinancialLease.LeaseStatus.InArrears) return id;

        vm.prank(defaultDeclarer);
        lease.declareDefault(id);
        if (target == IFinancialLease.LeaseStatus.InDefault) {
            vm.warp(block.timestamp + 7 days);
            return id;
        }

        vm.warp(block.timestamp + 7 days);
        vm.prank(lessor);
        lease.terminateForDefault(id);
        return id;
    }

    /// @dev Dedicated construction for the declareDefault row: unlike
    ///      the other 6 operations, declareDefault requires
    ///      GENUINE arrears in addition to the status (`principalArrears == 0`
    ///      reverts even with status Active/InArrears) — reusing
    ///      _mkLeaseAtStatus(Active) would give a lease with no arrears and the "✓" of
    ///      the matrix for that cell would be impossible to reach. With
    ///      `persistAsInArrears = false`: arrears generated but never
    ///      noticed by a tx (l.status still persisted as Active, as
    ///      in T35). With `true`: a minimal poke (a 1-wei pay that does not
    ///      cure) forces pay() to persist InArrears explicitly before
    ///      declaring default.
    function _mkLeaseWithArrears(bool persistAsInArrears) internal returns (uint256 id) {
        (uint64[] memory dueDates, uint256[] memory unitAmounts) = _schedule(1, 100 * UNIT);
        id = _createLease(address(oracle), 7 days, dueDates, unitAmounts);
        vm.warp(uint256(dueDates[0]) + 1 days);
        oracle.set(1e18);
        if (persistAsInArrears) {
            _pay(id, 1); // minimal poke, does not cure, forces l.status = InArrears
        }
    }

    function _tryPay(uint256 id) internal returns (bool ok) {
        vm.prank(lessee);
        try lease.pay(id, 10 * UNIT) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryDeclareDefault(uint256 id) internal returns (bool ok) {
        vm.prank(defaultDeclarer);
        try lease.declareDefault(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryAssignLessee(uint256 id) internal returns (bool ok) {
        vm.prank(lessee);
        try lease.assignLessee(id, newLessee) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryProposeTermination(uint256 id) internal returns (bool ok) {
        vm.prank(lessee);
        try lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryAcceptTermination(uint256 id, bool statusAllowsPropose) internal returns (bool ok) {
        if (statusAllowsPropose) {
            vm.prank(lessee);
            try lease.proposeTermination(id, TERMINATION_MUTUAL_AGREEMENT) {} catch {}
        }
        vm.prank(lessor);
        try lease.acceptTermination(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryTerminateForDefault(uint256 id) internal returns (bool ok) {
        vm.prank(lessor);
        try lease.terminateForDefault(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryExercisePurchaseOption(uint256 id) internal returns (bool ok) {
        oracle.set(1e18); // refresh staleness in case time passed during construction
        vm.prank(lessee);
        try lease.exercisePurchaseOption(id) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function _tryUpdateServicing(uint256 id) internal returns (bool ok) {
        vm.prank(lessor); // default servicer = whoever originated (lessor)
        try lease.updateServicing(id, INPUT_COLLECTIONS, uint64(block.timestamp)) {
            ok = true;
        } catch {
            ok = false;
        }
    }

    function test_T69_fullOperationMatrix() public {
        IFinancialLease.LeaseStatus[6] memory statuses = [
            IFinancialLease.LeaseStatus.Active,
            IFinancialLease.LeaseStatus.InArrears,
            IFinancialLease.LeaseStatus.InDefault,
            IFinancialLease.LeaseStatus.Terminated,
            IFinancialLease.LeaseStatus.Completed,
            IFinancialLease.LeaseStatus.PurchaseExercised
        ];

        // The exact operation matrix of the specification. Column order =
        // order of `statuses` above.
        bool[6] memory expectPay = [true, true, true, false, false, false];
        bool[6] memory expectDeclareDefault = [true, true, false, false, false, false];
        bool[6] memory expectAssignLessee = [true, true, true, false, false, false];
        bool[6] memory expectProposeTermination = [true, true, true, false, false, false];
        bool[6] memory expectAcceptTermination = [true, true, true, false, false, false];
        bool[6] memory expectTerminateForDefault = [false, false, true, false, false, false];
        bool[6] memory expectExercisePurchaseOption = [false, false, false, false, true, false];
        bool[6] memory expectUpdateServicing = [true, true, true, true, true, true];

        // declareDefault row separately: it is the only operation that
        // requires GENUINE arrears in addition to the status (see _mkLeaseWithArrears).
        // Columns 0-1 (Active/InArrears) use the dedicated construction;
        // columns 2-5 (InDefault/terminal statuses) reuse _mkLeaseAtStatus
        // like the rest, because there the status alone is enough to
        // determine the result.
        assertEq(_tryDeclareDefault(_mkLeaseWithArrears(false)), expectDeclareDefault[0], "matrix: declareDefault Active");
        assertEq(
            _tryDeclareDefault(_mkLeaseWithArrears(true)), expectDeclareDefault[1], "matrix: declareDefault InArrears"
        );
        for (uint256 s = 2; s < statuses.length; s++) {
            assertEq(
                _tryDeclareDefault(_mkLeaseAtStatus(statuses[s])), expectDeclareDefault[s], "matrix: declareDefault"
            );
        }

        for (uint256 s = 0; s < statuses.length; s++) {
            IFinancialLease.LeaseStatus st = statuses[s];

            assertEq(_tryPay(_mkLeaseAtStatus(st)), expectPay[s], "matrix: pay");
            assertEq(_tryAssignLessee(_mkLeaseAtStatus(st)), expectAssignLessee[s], "matrix: assignLessee");
            assertEq(
                _tryProposeTermination(_mkLeaseAtStatus(st)),
                expectProposeTermination[s],
                "matrix: proposeTermination"
            );

            bool statusAllowsPropose = st == IFinancialLease.LeaseStatus.Active
                || st == IFinancialLease.LeaseStatus.InArrears || st == IFinancialLease.LeaseStatus.InDefault;
            assertEq(
                _tryAcceptTermination(_mkLeaseAtStatus(st), statusAllowsPropose),
                expectAcceptTermination[s],
                "matrix: acceptTermination"
            );

            assertEq(
                _tryTerminateForDefault(_mkLeaseAtStatus(st)),
                expectTerminateForDefault[s],
                "matrix: terminateForDefault"
            );
            assertEq(
                _tryExercisePurchaseOption(_mkLeaseAtStatus(st)),
                expectExercisePurchaseOption[s],
                "matrix: exercisePurchaseOption"
            );
            assertEq(_tryUpdateServicing(_mkLeaseAtStatus(st)), expectUpdateServicing[s], "matrix: updateServicing");
        }
    }

    // ─── T70: CRITICAL BUG (external review) — underflow in _penaltyOwed
    //          from splitting a payment within the same block.timestamp ──

    /// @dev floor(a*r) + floor(b*r) <= floor((a+b)*r): crystallizing the
    ///      penalty of a and b separately (two payments that split the same
    ///      overdue tranche) loses up to 1 unit compared with crystallizing
    ///      once. penaltyPaidUnits did not compensate for that loss, so
    ///      enough splits underflowed
    ///      crystallizedPenaltyUnits + penaltyGrossNow - penaltyPaidUnits
    ///      in _penaltyOwed (panic 0x11) — reproduced with this exact
    ///      sequence before the _applyToPrincipal fix (crystallize the
    ///      difference of grosses instead of the floor of what was applied). After the
    ///      fix, besides not reverting, splitting must not change
    ///      arrears() (MUST NOT of S3-01).
    function test_T70_regressionUnderflowFromSplitPayment() public {
        (uint64[] memory dueDatesA, uint256[] memory unitAmountsA) = _schedule(12, 1e23);
        uint256 idA = _createLease(address(oracle), 0, dueDatesA, unitAmountsA);
        (uint64[] memory dueDatesB, uint256[] memory unitAmountsB) = _schedule(12, 1e23);
        uint256 idB = _createLease(address(oracle), 0, dueDatesB, unitAmountsB);

        vm.warp(block.timestamp + 200 days);
        assertEq(lease.arrears(idA), 657_000 * UNIT, "precondition");
        assertEq(lease.arrears(idB), 657_000 * UNIT, "precondition");

        uint256 p1 = 42844390007361274575661;
        uint256 p2 = 42844390007361274575660;
        uint256 p3 = 42844390007361274575660;

        // idA: the same total, all at once.
        _pay(idA, p1 + p2 + p3);

        // idB: EXACTLY the sequence that underflowed before the fix. After the
        // fix, the third payment must no longer revert.
        _pay(idB, p1);
        _pay(idB, p2);
        _pay(idB, p3);

        assertEq(lease.arrears(idA), lease.arrears(idB), "splitting within the same timestamp must not change arrears()");
    }

    /// @dev Permanent fix: paying N units in a single tx vs. in k
    ///      splits within the SAME block.timestamp must give identical
    ///      arrears(). Fuzzes over k (number of splits) and over the
    ///      total paid.
    function testFuzz_T71_INV_fractioningSameTimestampDoesNotChangeArrears(uint8 kRaw, uint96 totalRaw) public {
        // `total` is paid twice (once per lease) in the same test;
        // the setUp balance (1_000_000e18) is not enough for that plus the
        // total of the schedule (1.2e24). Extra funding only for this test.
        token.mint(lessee, 10_000_000 * UNIT);

        uint256 k = bound(uint256(kRaw), 1, 12);
        (uint64[] memory dueDatesA, uint256[] memory unitAmountsA) = _schedule(12, 1e23);
        uint256 idA = _createLease(address(oracle), 0, dueDatesA, unitAmountsA);
        (uint64[] memory dueDatesB, uint256[] memory unitAmountsB) = _schedule(12, 1e23);
        uint256 idB = _createLease(address(oracle), 0, dueDatesB, unitAmountsB);

        vm.warp(block.timestamp + 200 days);
        oracle.set(1e18);

        uint256 owed = lease.arrears(idA);
        uint256 total = bound(uint256(totalRaw), 1, owed);

        // idA: a single payment of `total`.
        _pay(idA, total);

        // idB: the SAME `total`, split into k payments (same timestamp).
        uint256 base = total / k;
        uint256 rem = total - base * k;
        for (uint256 i = 0; i < k; i++) {
            uint256 amt = base + (i == k - 1 ? rem : 0);
            if (amt == 0) continue;
            _pay(idB, amt);
        }

        assertEq(lease.arrears(idA), lease.arrears(idB), "splitting a payment within the same timestamp must not change arrears()");
    }
}
