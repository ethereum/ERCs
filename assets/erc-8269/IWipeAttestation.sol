// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  CAAP-WIPE v0.2 — attested crypto-erasure case registry for
///         ERC-8269 body leases
/// @notice Records FACTS about capsule-key custody and destruction; never
///         moves money. Economic interpretation belongs to LeaseBond under
///         the M1 failure-state spec (m1-failure-state-spec-v0.1.md), whose
///         lifecycle / evidence / resolution separation this contract's
///         enums mirror.
///
///         Design rules inherited from that spec:
///         - Key destruction is EVENT-DRIVEN: the body's lease-exit state
///           machine destroys the LDK after safe state and emits a signed
///           WipeReceipt at that moment. It never waits for a chain
///           challenge; an on-chain confirmation request is optional and
///           addressed only to surviving bodies. (No challenge-triggered
///           wipe: a disconnected body must not retain data for want of a
///           chain message, and a body that wipes then dies must remain
///           provable.)
///         - Silence is procedural, not probative: markProofUnavailable
///           records that evidence was not produced. It opens a cure
///           window; it MUST NOT slash, and it MUST NOT be read as proof
///           the key survives. (No proof-by-timeout.)
///         - Verification follows the RATS separation (RFC 9334): vendor
///           evidence is appraised by an approved verifier module; this
///           contract stores the Attestation Result binding; LeaseBond
///           applies lease policy to it.
///
///         Keying. Wipe obligations are NOT keyed by lease alone — a proof
///         for an earlier capsule or revision must never satisfy a
///         different obligation:
///           obligationId = keccak256(abi.encode(
///               leaseId,          // keccak256(utf8(lease.lease_id))
///               leaseDigest,      // keccak256(canonical lease JSON), revision-exact
///               bodyId,
///               capsuleRoot,
///               mountReceiptHash))
///
///         Uniqueness of submissions is enforced on the receipt DIGEST,
///         never on signature bytes: P-256 ECDSA signatures are malleable
///         (see EIP-7951 security notes), so signature bytes are not an
///         identity.
interface IWipeAttestation {

    // Mirrors m1-failure-state-spec §2.1 / §2.2.
    enum CaseState     { None, Bonded, Active, ExitPending, SafeStated,
                         WipeDue, EvidenceSubmitted, Disputed, Resolved }
    enum EvidenceState { None, ValidWipeReceipt, ValidDestructionEvidence,
                         ProofUnavailable, CorrectableInvalid, Contradictory,
                         FraudEvidence }

    /// RATS Attestation Result binding (spec §9). resultHash commits to the
    /// verifier's full appraisal output.
    struct Appraisal {
        uint8   verifierId;
        bytes32 verifierVersion;
        bytes32 appraisalPolicyHash;
        bytes32 referenceValueSetHash;
        bytes32 evidenceHash;
        bytes32 resultHash;
        uint64  issuedAt;
        uint64  expiresAt;
    }

    event BodyRegistered        (bytes32 indexed bodyId, bytes32 measurement, uint8 keyType);
    event MountRecorded         (bytes32 indexed obligationId, bytes32 indexed leaseId,
                                 bytes32 mountReceiptHash);
    event HeartbeatRecorded     (bytes32 indexed obligationId, bytes32 heartbeatHash,
                                 uint64 counter);
    event SafeStateReported     (bytes32 indexed obligationId, bytes32 receiptHash);
    event WipeEvidenceSubmitted (bytes32 indexed obligationId, bytes32 evidenceHash);
    event WipeEvidenceAccepted  (bytes32 indexed obligationId, bytes32 resultHash);
    event WipeProofUnavailable  (bytes32 indexed obligationId, uint64 cureDeadline);
    event ConfirmationRequested (bytes32 indexed obligationId, bytes32 nonce);
    event ContradictionRecorded (bytes32 indexed obligationId, bytes32 evidenceHash,
                                 address reporter);

    /// @notice One-time body enrollment; evidence checked by the pluggable
    ///         verifier module for `verifierId` (TPM EK/AK chain, DCAP quote,
    ///         Nitro document). Caches the body attestation key.
    function registerBody(bytes32 bodyId, uint8 verifierId, bytes calldata evidence) external;

    /// @notice Anchor a TEE-emitted MountReceipt, creating the wipe
    ///         obligation. Without a recorded mount the lease MUST NOT be
    ///         treated as Active by relying contracts; a mount invariant
    ///         discovered false later is MountInvariantBreach, adjudicated
    ///         in LeaseBond.
    function recordMount(bytes calldata mountReceipt, bytes calldata sig)
        external returns (bytes32 obligationId);

    /// @notice Optional periodic key-custody heartbeat (consequence-class
    ///         policy dependent). Narrows the unknown interval before a
    ///         casualty; never exposes the LDK.
    function recordHeartbeat(bytes32 obligationId, bytes calldata heartbeat,
                             bytes calldata sig) external;

    /// @notice Anchor the safe-state receipt that starts the wipe_due clock
    ///         (spec §4: wipe_due = safe_stated + d_wipe).
    function reportSafeState(bytes32 obligationId, bytes calldata receipt,
                             bytes calldata sig) external;

    /// @notice Submit the event-bound WipeReceipt (spec §3.3): signed by the
    ///         enrolled body key at destruction time, binding the mount
    ///         receipt, pre/post rollback-protected counters, firmware
    ///         measurement, boot counter, and safe-state receipt. Appraised
    ///         by the verifier module; on acceptance the case resolves
    ///         toward TimelyWipe/LateWipe* in LeaseBond. Signature verified
    ///         via the P-256 precompile (EIP-7951 / RIP-7212); replay
    ///         rejected on receipt digest and counter monotonicity.
    function submitWipeEvidence(bytes32 obligationId, bytes calldata wipeReceipt,
                                bytes calldata sig) external;

    /// @notice Submit destruction evidence for a casualty case (LossReport
    ///         root and verifier appraisal of physical non-recoverability).
    ///         Whether it amounts to QualifiedCasualty is LeaseBond's
    ///         policy decision, not this contract's.
    function submitDestructionEvidence(bytes32 obligationId, bytes calldata evidence)
        external;

    /// @notice OPTIONAL liveness prod addressed to surviving bodies — a
    ///         fresh nonce the body MAY answer with a supplementary signed
    ///         confirmation. MUST NOT be the only admissible proof and MUST
    ///         NOT gate acceptance of an event-bound WipeReceipt.
    function requestConfirmation(bytes32 obligationId) external returns (bytes32 nonce);

    /// @notice Records that evidence was not produced by evidence_due.
    ///         Procedural: opens the cure window, transfers nothing,
    ///         asserts nothing about key survival. Only an authenticated
    ///         operator submission history plus an expired cure window can
    ///         support a noncooperation resolution in LeaseBond.
    function markProofUnavailable(bytes32 obligationId) external;

    /// @notice Record contradiction evidence: counter rollback, accepted
    ///         post-wipe or post-loss use of the same LDK lineage or body
    ///         session, or attestation-key equivocation. Verified against
    ///         the enrolled key and stored counters; subsumes the zombie
    ///         clause (a post-claimed-death signature is one contradiction
    ///         class). Reporter identity is recorded for LeaseBond's
    ///         bounty payment.
    function reportContradiction(bytes32 obligationId, bytes calldata artifact,
                                 bytes calldata sig) external;

    function caseState(bytes32 obligationId) external view returns (CaseState);
    function evidenceState(bytes32 obligationId) external view returns (EvidenceState);
    function appraisal(bytes32 obligationId) external view returns (Appraisal memory);
    function contradictionReporter(bytes32 obligationId) external view returns (address);
}
