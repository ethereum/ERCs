// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IWipeAttestation.sol";
import {ClaimKind, ResolutionCode} from "./CaapM1Types.sol";

/// @title  LeaseBond v0.2 — physical liability and delegated collateral for
///         ERC-8269 body leases
/// @notice The economic vault. Escrows tranched collateral against a lease,
///         adjudicates claims on committed evidence, and settles per the M1
///         failure-state spec (m1-failure-state-spec-v0.1.md §7). The EVM's
///         job is escrow, commitments, and executing resolutions; off-chain
///         verifiers and the resolver module interpret evidence. The
///         contract never infers physical truth from silence.
///
///         Claim KIND (what is alleged to have happened) is separated from
///         RESOLUTION (who bears the loss, and whether a protocol violation
///         occurred): "the body was destroyed" is an incident, not a fault.
///
///         Resolution authority: ERC-8004's Validation Registry is a rail
///         for recording validation requests/responses — it does not define
///         resolver incentives, quorum, appeals, or stake. Each bond
///         therefore names an IResolutionModule implementing those rules;
///         its parameters (quorum, appeal window, stake, conflict rules)
///         are part of the lease's signed terms.
interface ILeaseBond {

    enum BondState { None, Posted, Exiting, Locked, Released }

    // Funds separated by purpose (spec §6): a no-fault casualty must not be
    // treated like deliberate retention.
    struct BondTranches {
        uint128 performanceBond;  // sealed mount, safe state, wipe, cooperation duties
        uint128 evidenceReserve;  // predetermined no-fault payout when proof is unavailable
        uint128 casualtyReserve;  // covered destruction / unrecoverable loss
        uint128 challengeBond;    // posted by claimants; deters frivolous claims
    }

    struct BondTerms {
        bytes32 obligationId;   // joins IWipeAttestation (lease+revision+body+capsule+mount)
        bytes32 leaseId;
        bytes32 leaseDigest;
        bytes32 bodyId;
        bytes32 capsuleRoot;
        address token;
        address poster;         // subject-side smart account (scoped allowance)
        address lessor;
        address resolver;       // IResolutionModule for non-automatic outcomes
        uint64  claimDeadline;  // end of the post-exit claim window
        uint64  holdbackWindow; // contradiction (zombie) window on released funds
        uint16  holdbackBps;    // slice of performanceBond retained through that window
        BondTranches tranches;
    }

    struct Resolution {
        ResolutionCode code;
        bytes32 evidenceRoot;        // accepted evidence set
        bytes32 appraisalPolicyHash; // policy version the resolver applied
        bytes32 payoutRoot;          // commitment to the full payout vector
    }

    event BondPosted     (uint256 indexed bondId, bytes32 indexed obligationId, BondTerms terms);
    event ClaimOpened    (uint256 indexed claimId, uint256 indexed bondId,
                          ClaimKind kind, bytes32 evidenceRoot);
    event ClaimResponded (uint256 indexed claimId, bytes32 disclosureRoot);
    event ClaimResolved  (uint256 indexed claimId, ResolutionCode code,
                          bytes32 evidenceRoot, bytes32 payoutRoot);
    event AwardExecuted  (uint256 indexed claimId, address to, uint256 amount);
    event BondReleased   (uint256 indexed bondId, uint256 paid, uint256 heldBack);
    event HoldbackSlashed(uint256 indexed bondId, address reporter, uint256 bounty);
    event HoldbackReturned(uint256 indexed bondId, uint256 amount);

    /// @notice Post tranched collateral against a wipe obligation. Callable
    ///         by the subject's account under a scoped session allowance
    ///         (ERC-4337 / EIP-7702 + module policy); the lease's x_bond
    ///         field reciprocally names this bond so the body can verify
    ///         collateral before arming. Reverts unless the obligation has
    ///         a recorded mount (no mount, no Active lease).
    function post(BondTerms calldata terms) external returns (uint256 bondId);

    /// @notice Open a claim. msg.value (or token transfer per implementation)
    ///         funds the claimant's challenge bond, slashed on
    ///         ChallengerAbuse. `evidenceRoot` commits the claimant's
    ///         evidence BEFORE the respondent discloses (commit-then-reveal).
    ///         For Casualty the root commits a LossReport
    ///         (spec §5.1): terminal receipts, witness roots, RF-health
    ///         root, salvage/non-recovery documentation. Self-witnessed
    ///         C2/C3 casualty claims are rejected by resolver policy.
    function claim(uint256 bondId, ClaimKind kind, uint256 amount,
                   uint64 hlc0, uint64 hlc1, bytes32 evidenceRoot)
        external payable returns (uint256 claimId);

    /// @notice Respondent's disclosure commitment: chunk Merkle proofs for
    ///         the claim window against a capsule root anchored before the
    ///         claim existed.
    function respond(uint256 claimId, bytes32 disclosureRoot) external;

    /// @notice Resolver-only. Records the typed resolution and executes the
    ///         committed payout vector against the appropriate tranches.
    ///         Invariants: total awards never exceed remaining collateral;
    ///         a resolution binds evidence root and policy version (a bare
    ///         reason hash cannot say whether destruction qualified or who
    ///         was at fault); only spec-§8-listed outcomes may settle
    ///         automatically without this module.
    function resolve(uint256 claimId, Resolution calldata r) external;

    /// @notice Release remaining collateral to the poster. Requires ALL of:
    ///         claim window closed; no unresolved claims; all awards
    ///         executed; and the bond's EXACT obligation resolved as
    ///         TimelyWipe / LateWipe* (wipe proven) or QualifiedCasualty.
    ///         UnprovenLoss releases per the lease's evidence-reserve
    ///         policy, never automatically. Pays out minus the holdback,
    ///         which remains slashable for holdbackWindow.
    function release(uint256 bondId) external;

    /// @notice Slash the holdback on recorded contradiction (post-loss key
    ///         use, counter rollback — read from IWipeAttestation); pays
    ///         the contradiction reporter's bounty, executes the
    ///         DeliberateRetention / AttestationEquivocation re-resolution.
    function claimContradictionSlash(uint256 bondId) external;

    /// @notice Return the holdback after holdbackWindow passes clean.
    function releaseHoldback(uint256 bondId) external;

    function bondState(uint256 bondId) external view returns (BondState);
    function openClaims(uint256 bondId) external view returns (uint256);
    function resolutionOf(uint256 claimId) external view returns (Resolution memory);
}
