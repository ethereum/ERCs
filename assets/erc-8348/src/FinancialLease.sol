// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "./IConversionOracle.sol";
import {IFinancialLease, INPUT_INDEX_OBSERVATION, TERMINATION_DEFAULT} from "./IFinancialLease.sol";
import {IFinancialLeaseAnchored} from "./IFinancialLeaseAnchored.sol";

/// @title FinancialLease — reference implementation of ERC-8348 (Financial Lease)
/// @dev Lessor position = NFT (tokenId == leaseId). Immutable schedule
///      in units of account; conversion to the payment asset via oracle.
contract FinancialLease is ERC721, ReentrancyGuard, IFinancialLease, IFinancialLeaseAnchored {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @dev observedAt: when the servicer says it observed the datum
    ///      off-chain. reportedAt: when it was persisted on-chain
    ///      (always block.timestamp of the updateServicing tx). The two
    ///      may diverge (see inputFreshness) — maxStaleness does NOT live
    ///      here: it is set by the lease configuration (see
    ///      Lease.maxStalenessByInput), not by the servicer.
    struct ServicingAttestation {
        uint64 observedAt;
        uint64 reportedAt;
    }

    struct Lease {
        // Parties and legal layer
        address lessee;
        bytes2 jurisdiction;
        string governingLaw;
        bytes32 agreementHash;
        string assetRef;
        // Denomination
        address paymentAsset;
        string denomSymbol;
        address oracle; // address(0) = fixed denomination
        uint64 maxOracleStaleness; // seconds; 0 = no limit
        // Schedule (immutable, in units)
        uint64[] dueDates;
        uint256[] unitAmounts;
        uint256 scheduleTotalUnits; // total sum of the schedule
        // Live state — closed-form accrual (fix S3-01). Nothing here is
        // "projected": arrears()/status()/nextPayment() are pure
        // functions of these fields + block.timestamp, with no
        // intermediate
        // persistence step.
        uint256 settledUnits; // schedule units actually paid (principal, FIFO)
        // Penalty: "accrued gross" (crystallizedPenaltyUnits + dynamic part
        // on what is currently unpaid, see _computeState) MINUS what has
        // actually been paid (penaltyPaidUnits). crystallizedPenaltyUnits
        // only grows when a payment reduces unpaidAmount(i) of an overdue
        // tranche — never through the mere passage of time or a re-read.
        uint256 crystallizedPenaltyUnits;
        uint256 penaltyPaidUnits;
        // Gas cache (NOT a source of truth): first tranche of the schedule
        // with an unpaid balance, and the cumulative sum of unitAmounts BEFORE
        // that index. Kept up to date on every pay(); if for any reason it
        // fell behind, the loops that use it are defensive (see
        // _computeState) and the result is still correct, just less
        // gas-efficient.
        uint256 firstUnsettledIndex;
        uint256 cumBeforeFirstUnsettled;
        LeaseStatus status;
        // Delinquency governance (fix S4-01): 0 = no override, the power to
        // declare default follows ownerOf(leaseId) DYNAMICALLY (see
        // _declarer()) — it survives NFT transfers and never stays
        // with a lessor that has already sold its
        // position. A lessor can delegate to a fixed address via
        // assignDefaultDeclarer, gated on being the current ownerOf.
        address defaultDeclarer;
        // Timestamp of the last successful transition to InDefault (0 = never).
        // Used as the anchor of the terminateForDefault timelock.
        uint64 defaultDeclaredAt;
        // Early termination (fix S6-01): see _terminate(),
        // proposeTermination(), acceptTermination(), terminateForDefault().
        // terminationTimestamp == 0 means "not terminated" — once
        // set, _effectiveNow() uses it to freeze every economic quantity
        // derived from _computeState at that instant forever,
        // no matter how much time passes afterwards.
        uint64 terminationTimestamp;
        uint64 terminationDelay; // set at origination; MUST be > 0
        bytes32 terminationReason;
        address terminationProposedBy;
        bytes32 terminationProposedReason;
        // Purchase option
        uint256 purchasePriceUnits;
        // Penalty: daily bps on the overdue stock
        uint16 penaltyBpsPerDay;
        // Anchor to a titled asset in an ERC-8325 registry (optional)
        uint256 anchorChainId;
        address anchorRegistry;
        bytes32 anchorId;
        // Parallel servicing: freshness attestations per input (bytes32)
        address servicer;
        mapping(bytes32 => ServicingAttestation) servicingAttestations;
        // maxStaleness declared per input, set when the lease is originated
        // (change 3): the servicer can NO longer self-assess its own
        // tolerance via updateServicing.
        mapping(bytes32 => uint64) maxStalenessByInput;
    }

    uint256 public nextLeaseId = 1;
    mapping(uint256 => Lease) internal _leases;

    error StaleOracle();
    error NotAuthorized();
    error WrongStatus();
    error NothingDue();
    error DerivedInput();
    error InvalidAnchor();
    error FutureObservation();
    error InvalidTerminationDelay();
    error TimelockNotElapsed();

    /// @dev Not part of IFinancialLease: specific to how this
    ///      implementation resolves the defaultDeclarer role (fix S4-01).
    event DefaultDeclarerAssigned(uint256 indexed leaseId, address indexed oldDeclarer, address indexed newDeclarer);

    /// @dev Not part of IFinancialLease: records who proposed a mutual
    ///      termination. The reason itself is reported through
    ///      TerminationRecorded, declared in IFinancialLease.
    event TerminationProposed(uint256 indexed leaseId, address indexed proposedBy, bytes32 reason);

    constructor() ERC721("Financial Lease Position", "LEASE") {}

    // ─── Origination ──────────────────────────────────────────

    /// @dev Grouped in a struct to avoid "stack too deep": createLease
    ///      had 14 loose parameters (several calldata/arrays), which
    ///      exceeds the stack limit even with via-ir. The fields and their
    ///      semantics are identical to the original signature.
    struct CreateLeaseParams {
        address lessee;
        bytes2 jurisdiction;
        string governingLaw;
        bytes32 agreementHash;
        string assetRef;
        address paymentAsset;
        string denomSymbol;
        address oracle;
        uint64 maxStaleness;
        uint64[] dueDates;
        uint256[] unitAmounts;
        uint256 purchasePriceUnits;
        uint16 penaltyBpsPerDay;
        address defaultDeclarer;
        // Timelock between declareDefault and terminateForDefault. MUST be > 0:
        // zero admits three reasonable readings (no timelock / use an
        // implicit default / invalid configuration) and that pattern already
        // cost one finding (S2-05, a staleness sentinel with ambiguous
        // semantics across layers) — createLease reverts explicitly instead
        // of leaving it ambiguous.
        uint64 terminationDelay;
        uint256 anchorChainId;
        address anchorRegistry;
        bytes32 anchorId;
        address servicer;
        // Staleness tolerance per servicing input (change 3): parallel
        // arrays because calldata structs do not support mappings.
        // IndexObservation ignores this config: it uses maxOracleStaleness.
        bytes32[] servicingInputs;
        uint64[] servicingMaxStaleness;
    }

    function createLease(CreateLeaseParams calldata p) external returns (uint256 leaseId) {
        require(p.dueDates.length == p.unitAmounts.length && p.dueDates.length > 0, "bad schedule");
        for (uint256 i = 1; i < p.dueDates.length; i++) {
            require(p.dueDates[i] > p.dueDates[i - 1], "unsorted schedule");
        }
        require(p.servicingInputs.length == p.servicingMaxStaleness.length, "bad servicing config");
        if (p.terminationDelay == 0) revert InvalidTerminationDelay();

        // Change 1: the anchor tuple is either all-zero (not anchored) or
        // fully set. Partial tuples are invalid.
        bool anyAnchorField = p.anchorChainId != 0 || p.anchorRegistry != address(0) || p.anchorId != bytes32(0);
        bool allAnchorFields = p.anchorChainId != 0 && p.anchorRegistry != address(0) && p.anchorId != bytes32(0);
        if (anyAnchorField && !allAnchorFields) revert InvalidAnchor();

        leaseId = nextLeaseId++;
        Lease storage l = _leases[leaseId];
        l.lessee = p.lessee;
        l.jurisdiction = p.jurisdiction;
        l.governingLaw = p.governingLaw;
        l.agreementHash = p.agreementHash;
        l.assetRef = p.assetRef;
        l.paymentAsset = p.paymentAsset;
        l.denomSymbol = p.denomSymbol;
        l.oracle = p.oracle;
        l.maxOracleStaleness = p.maxStaleness;
        l.dueDates = p.dueDates;
        l.unitAmounts = p.unitAmounts;
        l.purchasePriceUnits = p.purchasePriceUnits;
        l.penaltyBpsPerDay = p.penaltyBpsPerDay;
        // Fix S4-01: address(0) is NO longer replaced by msg.sender. Leaving it
        // at 0 means "no override" -> _declarer() resolves it
        // dynamically against ownerOf(leaseId) on every call, so it
        // follows the NFT if it is transferred. Passing an explicit address
        // fixes that declarer from origination (initial delegation).
        l.defaultDeclarer = p.defaultDeclarer;
        l.terminationDelay = p.terminationDelay;
        l.status = LeaseStatus.Active;
        l.anchorChainId = p.anchorChainId;
        l.anchorRegistry = p.anchorRegistry;
        l.anchorId = p.anchorId;
        l.servicer = p.servicer == address(0) ? msg.sender : p.servicer;

        for (uint256 i = 0; i < p.servicingInputs.length; i++) {
            l.maxStalenessByInput[p.servicingInputs[i]] = p.servicingMaxStaleness[i];
        }

        uint256 total;
        for (uint256 i = 0; i < p.unitAmounts.length; i++) {
            total += p.unitAmounts[i];
        }
        l.scheduleTotalUnits = total;
        // firstUnsettledIndex / cumBeforeFirstUnsettled stay at their
        // default (0, 0) — correct: they point to the first tranche of the
        // schedule, with nothing accumulated before it.

        _mint(msg.sender, leaseId); // lessor = NFT owner
        emit LeaseCreated(leaseId, msg.sender, p.lessee, p.jurisdiction, p.paymentAsset);
    }

    // ─── Conversion ───────────────────────────────────────────

    function conversionRateAsOf(uint256 leaseId) public view returns (uint256 rate, uint64 asOf) {
        Lease storage l = _leases[leaseId];
        if (l.oracle == address(0)) return (1e18, uint64(block.timestamp));
        (rate, asOf) = IConversionOracle(l.oracle).latestRate();
    }

    function _freshRate(uint256 leaseId) internal view returns (uint256 rate) {
        Lease storage l = _leases[leaseId];
        uint64 asOf;
        (rate, asOf) = conversionRateAsOf(leaseId);
        // S2-01: an oracle with a future asOf would underflow `block.timestamp
        // - asOf` -> Panic -> DoS of pay()/exercisePurchaseOption(). The
        // servicing layer already requires this (see FutureObservation in
        // updateServicing); the oracle layer reuses the same error,
        // regardless of whether the specific oracle in use is trusted.
        if (asOf > block.timestamp) revert FutureObservation();
        if (l.maxOracleStaleness != 0 && block.timestamp - asOf > l.maxOracleStaleness) {
            revert StaleOracle();
        }
    }

    /// @dev Charges: round UP (against the payer)
    function convertToAssets(uint256 leaseId, uint256 units) public view returns (uint256) {
        (uint256 rate,) = conversionRateAsOf(leaseId);
        return units.mulDiv(rate, 1e18, Math.Rounding.Ceil);
    }

    /// @dev Payment crediting: round DOWN (against the payer)
    function convertToUnits(uint256 leaseId, uint256 assets) public view returns (uint256) {
        (uint256 rate,) = conversionRateAsOf(leaseId);
        return assets.mulDiv(1e18, rate, Math.Rounding.Floor);
    }

    // ─── Terminality and freezing ─────────────────────────────

    /// @dev Single source of truth for "is this a terminal status?". By
    ///      exact value, not by enum order — a `uint8(status) >
    ///      uint8(X)` breaks silently if a new member is ever inserted
    ///      in the middle of the enum; this does not.
    function _isTerminal(LeaseStatus s) internal pure returns (bool) {
        return s == LeaseStatus.Completed || s == LeaseStatus.PurchaseExercised || s == LeaseStatus.Terminated;
    }

    /// @dev "Now", for the purposes of any economic calculation. Before
    ///      termination: the real block.timestamp. After termination:
    ///      frozen forever at the instant of termination — so
    ///      arrears()/status()/nextPayment() (everything that goes through
    ///      _computeState) stop moving as soon as the lease is Terminated,
    ///      no matter how much time passes afterwards.
    function _effectiveNow(Lease storage l) internal view returns (uint64) {
        return l.terminationTimestamp == 0 ? uint64(block.timestamp) : l.terminationTimestamp;
    }

    // ─── Accrual (closed-form, no intermediate state) ─────────

    /// @dev Single source of truth for delinquency, in units of account.
    ///      Walks the schedule from the cache (firstUnsettledIndex /
    ///      cumBeforeFirstUnsettled) up to the first tranche NOT yet due
    ///      (dueDates ascending => it can stop there, everything after it
    ///      is also not yet due). It is pure: no external call
    ///      can change its result except a real payment (which mutates
    ///      settledUnits/crystallizedPenaltyUnits/penaltyPaidUnits) — that is
    ///      why arrears()/status()/nextPayment()/pay() always return the
    ///      same value no matter how many times they were called before (fix
    ///      S3-01). It also returns nextIdx/cumAtNextIdx: the first tranche
    ///      with dueDate >= now (or length if none is left) and the cumulative
    ///      sum up to it — reused by nextPayment() to avoid
    ///      paying for a second pass or a separate binary search.
    function _computeState(Lease storage l)
        internal
        view
        returns (uint256 principalArrears, uint256 penaltyGrossNow, uint256 nextIdx, uint256 cumAtNextIdx)
    {
        uint256 n = l.dueDates.length;
        uint256 i = l.firstUnsettledIndex;
        uint256 cum = l.cumBeforeFirstUnsettled;
        uint256 settled = l.settledUnits;
        uint16 bps = l.penaltyBpsPerDay;
        uint64 nowEff = _effectiveNow(l); // frozen after termination

        for (; i < n; i++) {
            cum += l.unitAmounts[i];
            if (cum <= settled) continue; // settled (cache defensively behind); continue
            if (l.dueDates[i] >= nowEff) break; // first tranche not yet due: stop here
            uint256 unpaid = cum - settled;
            if (unpaid > l.unitAmounts[i]) unpaid = l.unitAmounts[i]; // defensive clamp
            principalArrears += unpaid;
            if (bps > 0) {
                uint256 daysLate = (nowEff - l.dueDates[i]) / 1 days;
                penaltyGrossNow += unpaid.mulDiv(uint256(bps) * daysLate, 10_000, Math.Rounding.Floor);
            }
        }
        nextIdx = i;
        cumAtNextIdx = cum;
    }

    /// @dev penaltyOwed = (crystallizedPenaltyUnits + dynamic-as-of-now) −
    ///      penaltyPaidUnits. Never negative by construction: each payment
    ///      may only pay up to min(remaining, penaltyOwed)
    ///      (see pay()), and the numerator is monotonically non-decreasing, so
    ///      penaltyPaidUnits can never exceed it.
    function _penaltyOwed(Lease storage l, uint256 penaltyGrossNow) internal view returns (uint256) {
        return l.crystallizedPenaltyUnits + penaltyGrossNow - l.penaltyPaidUnits;
    }

    function _statusView(Lease storage l) internal view returns (LeaseStatus) {
        if (l.status != LeaseStatus.Active) return l.status;
        (uint256 principalArrears,,,) = _computeState(l);
        return principalArrears > 0 ? LeaseStatus.InArrears : LeaseStatus.Active;
    }

    /// @dev Applies `remaining` units to principal, FIFO from the cache,
    ///      crystallizing per tranche with ITS OWN due date
    ///      (not a common date for the whole payment — see T48). Covers both
    ///      overdue principal (crystallizes) and future installments (does not
    ///      crystallize, `dueDates[i] >= block.timestamp`) in a single
    ///      pass: they are the same FIFO queue, they only differ in whether
    ///      they generate a penalty.
    function _applyToPrincipal(Lease storage l, uint256 remaining) internal {
        uint256 i = l.firstUnsettledIndex;
        uint256 cumBefore = l.cumBeforeFirstUnsettled; // sum of unitAmounts[0..i-1]
        uint256 settledSoFar = l.settledUnits;
        uint256 crystallizedNow;
        uint256 n = l.dueDates.length;
        uint16 bps = l.penaltyBpsPerDay;
        // Unreachable with a Terminated lease (pay() already reverts before
        // getting here), but _effectiveNow() anyway for
        // consistency: no economic calculation in this contract should
        // depend on block.timestamp directly, not even on a path that is
        // unreachable today.
        uint64 nowEff = _effectiveNow(l);

        while (remaining > 0 && i < n) {
            uint256 cumThroughI = cumBefore + l.unitAmounts[i];
            uint256 unpaid = cumThroughI > settledSoFar ? cumThroughI - settledSoFar : 0;
            if (unpaid == 0) {
                cumBefore = cumThroughI;
                i++;
                continue;
            }
            uint256 applied = Math.min(remaining, unpaid);

            // Crystallizes the DIFFERENCE of floored grosses (gross(unpaid)
            // before vs. after this payment), not floor(applied*r): floor
            // is subadditive (floor(a*r)+floor(b*r) <= floor((a+b)*r)), so
            // crystallizing floor(applied*r) separately loses up to 1
            // unit every time a payment splits a tranche, and that loss
            // is never recovered -> underflow in _penaltyOwed if it repeats
            // often enough (see test_T70_BUG). By telescoping, the sum of
            // these differences over any number of payments
            // on the same tranche is EXACTLY gross(initial_unpaid) -
            // gross(final_unpaid), with no residue.
            if (bps > 0 && l.dueDates[i] < nowEff) {
                uint256 daysLate = (nowEff - l.dueDates[i]) / 1 days;
                uint256 r = uint256(bps) * daysLate;
                crystallizedNow += unpaid.mulDiv(r, 10_000, Math.Rounding.Floor)
                    - (unpaid - applied).mulDiv(r, 10_000, Math.Rounding.Floor);
            }

            settledSoFar += applied;
            remaining -= applied;

            if (applied == unpaid) {
                cumBefore = cumThroughI;
                i++;
            }
        }

        l.firstUnsettledIndex = i;
        l.cumBeforeFirstUnsettled = cumBefore;
        l.settledUnits = settledSoFar;
        if (crystallizedNow > 0) l.crystallizedPenaltyUnits += crystallizedNow;
    }

    // ─── Payment ──────────────────────────────────────────────

    /// @dev Reference imputation: penalties → overdue principal → installments.
    ///      Penalties (crystallized + dynamic, net of what was paid)
    ///      can be paid independently of the principal that
    ///      generated them (see T7/Scenario2) — paying only the penalty does NOT reduce
    ///      outstandingUnits.
    function pay(uint256 leaseId, uint256 assets) external nonReentrant {
        Lease storage l = _leases[leaseId];
        if (_isTerminal(l.status)) revert WrongStatus();

        uint256 rate = _freshRate(leaseId);

        LeaseStatus statusBefore = l.status;
        (uint256 principalArrears, uint256 penaltyGrossNow,,) = _computeState(l);
        uint256 penaltyOwed = _penaltyOwed(l, penaltyGrossNow);

        if (statusBefore == LeaseStatus.Active && principalArrears > 0) {
            emit ArrearsAccrued(leaseId, principalArrears + penaltyOwed);
        }

        // Fix (d): cap at what is owed and transfer only what is needed
        uint256 remainingPrincipal = l.scheduleTotalUnits - l.settledUnits;
        uint256 owedUnits = penaltyOwed + remainingPrincipal;
        uint256 units = Math.min(assets.mulDiv(1e18, rate, Math.Rounding.Floor), owedUnits);
        if (units == 0) revert NothingDue();
        uint256 pulled = units.mulDiv(rate, 1e18, Math.Rounding.Ceil);

        // ── Effects ──
        uint256 remaining = units;

        // 1) Penalties — fix (b): they do NOT touch settledUnits or principal
        uint256 toPenalty = Math.min(remaining, penaltyOwed);
        l.penaltyPaidUnits += toPenalty;
        remaining -= toPenalty;

        // 2) Principal (overdue first, by the cache's FIFO order, then
        //    future installments) — crystallizes the penalty per tranche as it goes
        if (remaining > 0) {
            _applyToPrincipal(l, remaining);
        }

        bool stillOverdue =
            l.firstUnsettledIndex < l.dueDates.length && l.dueDates[l.firstUnsettledIndex] < _effectiveNow(l);
        bool stillOwesPenalty = l.crystallizedPenaltyUnits != l.penaltyPaidUnits;

        if (!stillOverdue && !stillOwesPenalty) {
            if (statusBefore == LeaseStatus.InDefault) emit DefaultCured(leaseId);
            l.status = l.settledUnits == l.scheduleTotalUnits ? LeaseStatus.Completed : LeaseStatus.Active;
            if (l.status == LeaseStatus.Completed) {
                emit LeaseTerminated(leaseId, LeaseStatus.Completed);
            }
        } else if (statusBefore == LeaseStatus.Active) {
            // Arrears persist and had not been flagged yet — it is
            // recorded so that a later payment does not emit
            // ArrearsAccrued again for the same arrears.
            l.status = LeaseStatus.InArrears;
        }

        // ── Interaction last — fix (e) ──
        IERC20(l.paymentAsset).safeTransferFrom(msg.sender, ownerOf(leaseId), pulled);

        emit PaymentReceived(leaseId, msg.sender, pulled, units, rate, l.scheduleTotalUnits - l.settledUnits);
    }

    // ─── Formal default ───────────────────────────────────────

    /// @dev Fix S4-01: if it was never explicitly delegated (defaultDeclarer
    ///      == 0), the power to declare default belongs to the CURRENT
    ///      ownerOf(leaseId) — it follows the NFT on every transfer and never stays
    ///      frozen with a lessor that already sold its position.
    function _declarer(Lease storage l, uint256 leaseId) internal view returns (address) {
        return l.defaultDeclarer == address(0) ? ownerOf(leaseId) : l.defaultDeclarer;
    }

    /// @dev Explicit delegation of the defaultDeclarer role, gated on
    ///      whoever is the CURRENT owner of the NFT (never whoever owned it when
    ///      the lease was originated). `newDeclarer == address(0)` clears the
    ///      delegation and returns to dynamic resolution via ownerOf.
    function assignDefaultDeclarer(uint256 leaseId, address newDeclarer) external {
        if (msg.sender != ownerOf(leaseId)) revert NotAuthorized();
        Lease storage l = _leases[leaseId];
        address old = l.defaultDeclarer;
        l.defaultDeclarer = newDeclarer;
        emit DefaultDeclarerAssigned(leaseId, old, newDeclarer);
    }

    function declareDefault(uint256 leaseId) external {
        Lease storage l = _leases[leaseId];
        if (msg.sender != _declarer(l, leaseId)) revert NotAuthorized();
        // Active: arrears never "noticed" by a previous pay(). InArrears: already
        // noticed (persisted by pay(), see the epilogue of pay()). Both are
        // valid — the only difference is whether ArrearsAccrued was already emitted.
        LeaseStatus statusBefore = l.status;
        if (statusBefore != LeaseStatus.Active && statusBefore != LeaseStatus.InArrears) revert WrongStatus();

        (uint256 principalArrears, uint256 penaltyGrossNow,,) = _computeState(l);
        if (principalArrears == 0) revert WrongStatus();

        if (statusBefore == LeaseStatus.Active) {
            emit ArrearsAccrued(leaseId, principalArrears + _penaltyOwed(l, penaltyGrossNow));
        }

        l.status = LeaseStatus.InDefault;
        l.defaultDeclaredAt = uint64(block.timestamp);
        emit DefaultDeclared(leaseId, msg.sender);
    }

    // ─── Early termination (fix S6-01) ───────────────────────

    /// @dev Freezes the lease forever: persists the instant and the
    ///      cause, and moves to Terminated. From here on, _effectiveNow()
    ///      stops advancing for this lease — no economic quantity
    ///      derived from _computeState changes again.
    function _terminate(uint256 leaseId, Lease storage l, bytes32 reason) internal {
        l.terminationTimestamp = uint64(block.timestamp);
        l.status = LeaseStatus.Terminated;
        l.terminationReason = reason;
        emit LeaseTerminated(leaseId, LeaseStatus.Terminated);
        emit TerminationRecorded(leaseId, reason);
    }

    /// @dev Step 1 of termination by mutual agreement. Callable by the
    ///      lessee or by the current ownerOf(leaseId), in any
    ///      non-terminal status (Active, InArrears or InDefault). A new
    ///      proposal ALWAYS overwrites the previous one — regardless of who
    ///      made it or whether one was already pending acceptance.
    function proposeTermination(uint256 leaseId, bytes32 reason) external {
        Lease storage l = _leases[leaseId];
        if (_isTerminal(l.status)) revert WrongStatus();
        if (msg.sender != l.lessee && msg.sender != ownerOf(leaseId)) revert NotAuthorized();

        l.terminationProposedBy = msg.sender;
        l.terminationProposedReason = reason;
        emit TerminationProposed(leaseId, msg.sender, reason);
    }

    /// @dev Step 2. Only the COUNTERPARTY of the last `proposeTermination`
    ///      can accept: if the lessee proposed, the current ownerOf accepts,
    ///      and vice versa (evaluated with the identities IN FORCE at
    ///      acceptance time, not those at proposal time — if
    ///      `lessee`/the NFT owner changed in between,
    ///      assignLessee/transferFrom remain allowed until the lease has
    ///      terminated, see the operation matrix).
    function acceptTermination(uint256 leaseId) external {
        Lease storage l = _leases[leaseId];
        if (_isTerminal(l.status)) revert WrongStatus();

        address proposer = l.terminationProposedBy;
        if (proposer == address(0)) revert NotAuthorized(); // nothing proposed yet
        address expectedAccepter = proposer == l.lessee ? ownerOf(leaseId) : l.lessee;
        if (msg.sender != expectedAccepter) revert NotAuthorized();

        bytes32 reason = l.terminationProposedReason;
        l.terminationProposedBy = address(0);
        l.terminationProposedReason = bytes32(0);

        _terminate(leaseId, l, reason);
    }

    /// @dev Termination for breach. Only the current ownerOf(leaseId)
    ///      (never the defaultDeclarer as such, although they usually
    ///      coincide unless explicitly delegated — see S4-01/S4-02:
    ///      declaring default and deciding to terminate are distinct
    ///      powers; the first can be delegated without delegating the
    ///      second). Requires status == InDefault (strictly, not
    ///      InArrears or Active) AND that the timelock has elapsed since
    ///      defaultDeclaredAt.
    function terminateForDefault(uint256 leaseId) external {
        if (msg.sender != ownerOf(leaseId)) revert NotAuthorized();
        Lease storage l = _leases[leaseId];
        if (l.status != LeaseStatus.InDefault) revert WrongStatus();
        if (block.timestamp < uint256(l.defaultDeclaredAt) + uint256(l.terminationDelay)) {
            revert TimelockNotElapsed();
        }

        _terminate(leaseId, l, TERMINATION_DEFAULT);
    }

    // ─── Purchase option ──────────────────────────────────────

    function purchaseOption(uint256 leaseId) public view returns (uint256 priceInAssets, bool exercisable) {
        Lease storage l = _leases[leaseId];
        priceInAssets = convertToAssets(leaseId, l.purchasePriceUnits);
        exercisable = _statusView(l) == LeaseStatus.Completed;
    }

    function exercisePurchaseOption(uint256 leaseId) external nonReentrant {
        Lease storage l = _leases[leaseId];
        if (msg.sender != l.lessee) revert NotAuthorized();
        (, bool ok) = purchaseOption(leaseId);
        if (!ok) revert WrongStatus();

        uint256 rate = _freshRate(leaseId);
        uint256 price = l.purchasePriceUnits.mulDiv(rate, 1e18, Math.Rounding.Ceil);

        l.status = LeaseStatus.PurchaseExercised;

        IERC20(l.paymentAsset).safeTransferFrom(msg.sender, ownerOf(leaseId), price);

        emit PurchaseOptionExercised(leaseId, price);
        emit LeaseTerminated(leaseId, LeaseStatus.PurchaseExercised);
        // Asset-bound extension: atomic settlement of the asset would go here
    }

    // ─── Lessee assignment ────────────────────────────────────

    /// @dev Fix S4-02: only the OUTGOING lessee can reassign
    ///      itself. The previous version also accepted
    ///      `defaultDeclarer` (which by default ended up being the
    ///      lessor) with no status gate and no lessee consent —
    ///      it allowed stealing the purchase option at zero cost
    ///      (finding S4-02). Reference simplification: in
    ///      production, add explicit consent (signature/two-step)
    ///      + a compliance hook (3643/7943). Reassignment initiated by
    ///      a third party (e.g. repossession after default) would require a
    ///      separate, explicitly delegated role — never the one that
    ///      declares default, nor the lessor.
    /// @dev Allowed in Active/InArrears/InDefault, blocked in
    ///      terminal statuses (fix S6-01, operation matrix): it is a
    ///      commercial policy, not an authorization question — the standard leaves
    ///      this choice to the implementation; this reference chooses to
    ///      allow it even in arrears because there is no economic
    ///      reason to prevent the lessee from assigning its position
    ///      while the lease is still alive.
    function assignLessee(uint256 leaseId, address newLessee) external {
        Lease storage l = _leases[leaseId];
        if (msg.sender != l.lessee) revert NotAuthorized();
        if (_isTerminal(l.status)) revert WrongStatus();
        address old = l.lessee;
        l.lessee = newLessee;
        emit LesseeAssigned(leaseId, old, newLessee);
    }

    // ─── Anchoring to an ERC-8325 registry ────────────────────

    function assetAnchor(uint256 leaseId) external view returns (uint256 chainId, address registry, bytes32 anchorId) {
        Lease storage l = _leases[leaseId];
        return (l.anchorChainId, l.anchorRegistry, l.anchorId);
    }

    // ─── Servicing (parallel reporting, not enforced) ─────────

    /// @dev IndexObservation is derived from conversionRateAsOf (observedAt ==
    ///      reportedAt: the oracle does not distinguish the two moments) and is never
    ///      attested manually (see DerivedInput in updateServicing).
    ///      The other categories are attestations that the servicer
    ///      updates. Reporting only: they take no part in pay() or in the
    ///      lease state. A bytes32 input never attested and not derived
    ///      returns (0,0,0) — valid information ("never reported"), not
    ///      an error case.
    function inputFreshness(uint256 leaseId, bytes32 input)
        external
        view
        returns (uint64 observedAt, uint64 reportedAt, uint64 maxStaleness)
    {
        Lease storage l = _leases[leaseId];
        if (input == INPUT_INDEX_OBSERVATION) {
            (, uint64 asOf) = conversionRateAsOf(leaseId);
            return (asOf, asOf, l.maxOracleStaleness);
        }
        ServicingAttestation storage a = l.servicingAttestations[input];
        return (a.observedAt, a.reportedAt, l.maxStalenessByInput[input]);
    }

    function updateServicing(uint256 leaseId, bytes32 input, uint64 observedAt) external {
        Lease storage l = _leases[leaseId];
        if (input == INPUT_INDEX_OBSERVATION) revert DerivedInput();
        if (msg.sender != l.servicer) revert NotAuthorized();
        if (observedAt > block.timestamp) revert FutureObservation();

        uint64 reportedAt = uint64(block.timestamp);
        l.servicingAttestations[input] = ServicingAttestation({observedAt: observedAt, reportedAt: reportedAt});
        emit ServicingUpdated(leaseId, input, observedAt, reportedAt);
    }

    // ─── Standard views ───────────────────────────────────────

    function lessor(uint256 id) external view returns (address) {
        return ownerOf(id);
    }

    function lessee(uint256 id) external view returns (address) {
        return _leases[id].lessee;
    }

    function jurisdiction(uint256 id) external view returns (bytes2) {
        return _leases[id].jurisdiction;
    }

    function governingLaw(uint256 id) external view returns (string memory) {
        return _leases[id].governingLaw;
    }

    function agreementHash(uint256 id) external view returns (bytes32) {
        return _leases[id].agreementHash;
    }

    function assetReference(uint256 id) external view returns (string memory) {
        return _leases[id].assetRef;
    }

    function paymentAsset(uint256 id) external view returns (address) {
        return _leases[id].paymentAsset;
    }

    function denomination(uint256 id) external view returns (string memory, address) {
        return (_leases[id].denomSymbol, _leases[id].oracle);
    }

    function paymentCount(uint256 id) external view returns (uint256) {
        return _leases[id].dueDates.length;
    }

    /// @dev Fix (a): `paid` is derived from the settled cumulative amount, not from the
    ///      accrual pointer. A loop is acceptable in a reference;
    ///      production would use prefix sums.
    /// @dev Does not need _computeState: `paid` depends only on
    ///      settledUnits (which pay() mutates directly) and on the immutable
    ///      schedule — neither is touched by the passage of time,
    ///      so it is already accurate at any moment between txs.
    function paymentAt(uint256 id, uint256 i) external view returns (uint256 units, uint64 dueDate, bool paid) {
        Lease storage l = _leases[id];
        units = l.unitAmounts[i];
        dueDate = l.dueDates[i];
        uint256 cum;
        for (uint256 k = 0; k <= i; k++) {
            cum += l.unitAmounts[k];
        }
        paid = l.settledUnits >= cum;
    }

    /// @dev settledUnits is only mutated by pay() — the mere passage of time
    ///      never touches it, so this view is already accurate at any
    ///      moment between txs without needing _computeState.
    function outstandingUnits(uint256 id) public view returns (uint256) {
        Lease storage l = _leases[id];
        return l.scheduleTotalUnits - l.settledUnits;
    }

    function outstandingBalance(uint256 id) external view returns (uint256) {
        return convertToAssets(id, outstandingUnits(id));
    }

    /// @dev Frequency-independent by construction (fix S3-01): a pure
    ///      function of (schedule, settledUnits, crystallizedPenaltyUnits,
    ///      penaltyPaidUnits, block.timestamp). No poke (a call without a
    ///      real payment) can alter any of those fields.
    function arrears(uint256 id) external view returns (uint256) {
        Lease storage l = _leases[id];
        (uint256 principalArrears, uint256 penaltyGrossNow,,) = _computeState(l);
        return convertToAssets(id, principalArrears + _penaltyOwed(l, penaltyGrossNow));
    }

    /// @dev Next installment in the calendar whose due date has NOT YET
    ///      passed (regardless of arrears on earlier installments — arrears
    ///      are queried via arrears()/status()). If the schedule is already
    ///      fully settled (even if prepaid before falling
    ///      due), there is no "next" to report: (0, 0).
    function nextPayment(uint256 id) external view returns (uint256 assets, uint64 dueDate) {
        Lease storage l = _leases[id];
        if (l.settledUnits >= l.scheduleTotalUnits) return (0, 0);
        (,, uint256 nextIdx, uint256 cumAtNextIdx) = _computeState(l);
        if (nextIdx >= l.dueDates.length) return (0, 0);
        uint256 unpaid = cumAtNextIdx > l.settledUnits ? cumAtNextIdx - l.settledUnits : 0;
        if (unpaid > l.unitAmounts[nextIdx]) unpaid = l.unitAmounts[nextIdx];
        return (convertToAssets(id, unpaid), l.dueDates[nextIdx]);
    }

    function status(uint256 id) external view returns (LeaseStatus) {
        return _statusView(_leases[id]);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return interfaceId == type(IFinancialLease).interfaceId
            || interfaceId == type(IFinancialLeaseAnchored).interfaceId || super.supportsInterface(interfaceId);
    }
}
