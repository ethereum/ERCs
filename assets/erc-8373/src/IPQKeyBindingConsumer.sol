// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title The on-chain half of ERC-8373 (Post-Quantum Anchored Key-Binding)
/// @notice ERC-8373 states that "deployment of the consumer rule, not publication of bindings, is
///         what makes the migration operative". These interfaces give that consumer rule a shape a
///         contract can implement and an integrator can detect.
/// @dev    ERC-8373 defines the binding statement, the anchoring rules and the verification
///         procedure. It does not define an on-chain surface for any of it. Everything here is the
///         consumer side of that specification, expressed so that whether a given deployment
///         actually enforces the cutoff is a readable on-chain fact rather than a claim.

// ── Outcome ──────────────────────────────────────────────────────────────────

/// @notice What the verifier could establish about an artifact.
/// @dev    ERC-8373's v1 conformance profile carries `evidence` and `decision` as SEPARATE fields,
///         and the distinction is load-bearing. A companion that was checked and failed is
///         `Refuted`. A companion that could not be checked at all is `Unverifiable`. Both refuse
///         admission, but they are different facts and a consumer that merges them cannot tell a
///         bad signature from a verifier that was down.
///
///         `Unverifiable` is deliberately the zero value. An unwritten slot, a failed decode and a
///         struct default all read as "we could not tell", never as evidence of correctness.
enum PQEvidence {
    Unverifiable, // 0 — a step could not be completed.
    Verified, // 1 — checked and it holds.
    Refuted // 2 — checked and it fails.
}

/// @notice Whether the artifact may be admitted.
/// @dev    A projection of the evidence plus the cutoff rule, never a rename of the evidence.
///         `Refuse` is the zero value, so anything unset or undecided fails closed.
enum PQDecision {
    Refuse, // 0 — do not admit. Read `PQEvidence` for why.
    Admit // 1 — anchored before the cutoff, or carries a valid in-force companion.
}

/// @notice Why the verdict came out the way it did.
///
/// @dev ERC-8373 requires an `unverifiable` result to carry a reason, REQUIRED rather than
///      RECOMMENDED, and requires that on-chain the reason be a closed enumeration rather than
///      free text. It also forbids collapsing `pre_baseline` and a revoked authority into one
///      reason, because they are opposite answers: an innocent back catalogue against deliberately
///      ended authority.
///
///      `ChainUnavailable` holds the zero slot on purpose, for the same reason `Refuse` and
///      `Unverifiable` hold theirs. A consumer that has not loaded a chain has established
///      nothing, and the honest default is to say so rather than to report a resolution nobody
///      performed. An empty chain is a different fact and gets its own value.
enum PQReason {
    ChainUnavailable, // 0 — the chain could not be loaded. Nothing was resolved.
    ResolvedAtAnchorTime, // 1 — a binding governs the artifact's anchor time.
    PreBaseline, // 2 — anchored before any binding governed. The back catalogue.
    NoInForceBinding, // 3 — authority ended at or before the anchor time.
    NoBindingsInChain, // 4 — the chain loaded and this identity has none.
    ChainMalformed, // 5 — a binding claims activation before its own anchor.
    BindingAnchorUnavailable // 6 — every declared binding lacks a readable anchor.
}

/// @notice Which admission rule actually decided the verdict.
///
/// @dev Distinct from `PQReason`, and both are needed. `PQReason` says how the chain resolved;
///      `PQRule` says which clause of the cutoff rule then fired. They coincide on the failure
///      paths and diverge on the successful ones: a `ResolvedAtAnchorTime` resolution still admits
///      via `AnchoredBeforeCutoff` or `ValidPqCompanion`, and refuses via
///      `PostCutoffNoValidCompanion` or `PostCutoffCompanionUnchecked`. Collapsing them would lose
///      the difference between "admitted because it predates the cutoff" and "admitted because the
///      companion verified", which is the whole point of the cutoff rule having two limbs.
///
///      `Unset` holds the zero slot so an unread or uninitialised value cannot read as an admission.
enum PQRule {
    Unset, // 0 — nothing decided. Never a valid published verdict.
    AnchoredBeforeCutoff, // 1
    ValidPqCompanion, // 2
    PreBaselineLegacyAdmit, // 3
    PostCutoffNoValidCompanion, // 4
    PostCutoffCompanionUnchecked, // 5
    PostCutoffAnchorStatusUnknown, // 6
    NoInForceBinding, // 7
    NoBindingsInChain, // 8
    ChainUnavailable, // 9
    ChainMalformed, // 10
    BindingAnchorUnavailable // 11
}

// ── Anchor substrate ─────────────────────────────────────────────────────────

/// @notice The anchor substrate, read-side.
/// @dev    ERC-8373 rests its whole guarantee on one asymmetry: "a compromised key can backdate a
///         signature; it cannot backdate an anchor." That holds only while anchor time is *read*
///         from the substrate. A consumer that accepts `anchorTime` as a call parameter hands the
///         caller the backdating power the design exists to remove, and it will still pass every
///         off-chain conformance vector, because the vectors never model a lying caller.
///
///         This is why `IPQKeyBindingConsumer` takes no timestamp from its caller.
interface IPQAnchorRegistry {
    /// @notice The substrate timestamp at which `contentAddress` was anchored.
    /// @return anchorTime unix seconds, or 0 if this content-address was never anchored.
    function anchorTimeOf(bytes32 contentAddress) external view returns (uint64 anchorTime);

    /// @notice The account whose transaction anchored `contentAddress`.
    /// @dev    ERC-8373 makes the anchoring transaction itself the classical proof-of-possession:
    ///         it "MUST be sent from the classical address being bound", and no separate classical
    ///         signature "should be trusted in its place". Exposing the anchoring sender is what
    ///         lets a verifier check that rule on-chain instead of assuming it.
    function anchoredBy(bytes32 contentAddress) external view returns (address anchorer);
}

// ── Companion verification ───────────────────────────────────────────────────

/// @notice Verification of a detached PQ companion signature.
/// @dev    Kept as a separate, swappable component on purpose. ML-DSA and SLH-DSA verification is
///         not practical in the EVM today: SLH-DSA is thousands of hash invocations and ML-DSA is
///         lattice arithmetic, neither of which has a precompile. So the honest position is that
///         **the cutoff rule is enforceable on-chain today and the companion check is not**.
///
///         Splitting them means a consumer can enforce everything it actually can, and name what
///         it delegates, rather than pretending to a completeness it does not have. A deployment
///         may point this at a ZK proof of companion validity, at an attested oracle, or at a
///         precompile if one ever lands, without touching the consumer.
interface IPQCompanionVerifier {
    /// @notice The PQ algorithm this verifier accepts, as the ERC-8373 `algorithm` field
    ///         (for example "ML-DSA-65" or "SLH-DSA-SHA2-192s").
    function algorithm() external view returns (string memory);

    /// @notice Verify a detached companion over an artifact's 32-byte content-address.
    /// @dev    MUST return false rather than revert on a malformed companion, so that a bad
    ///         signature is a reject and only an unavailable verifier is unverifiable.
    function verifyCompanion(bytes32 artifactContentAddress, bytes calldata pqPubkey, bytes calldata companion)
        external
        view
        returns (bool);
}

// ── The consumer rule ────────────────────────────────────────────────────────

/// @notice A contract that enforces the ERC-8373 cutoff.
/// @dev    ERC-165 interface id is the XOR of this interface's own function selectors.
interface IPQKeyBindingConsumer {
    /// @notice The consumer's cutoff, in unix seconds.
    /// @dev    ERC-8373: "The cutoff is consumer-side policy, not issuer-declared." Making it a
    ///         public read is what turns "this deployment enforces the migration" into something a
    ///         counterparty can check before relying on it.
    function cutoff() external view returns (uint64);

    /// @notice The anchor substrate this consumer reads anchor times from.
    function anchorRegistry() external view returns (IPQAnchorRegistry);

    /// @notice The verdict for an artifact, following the ERC-8373 verification procedure.
    /// @param artifactContentAddress the artifact's 32-byte content-address, recomputed by the
    ///        caller from raw bytes as the ERC requires
    /// @param companion a detached PQ companion over that content-address; MAY be empty for an
    ///        artifact expected to fall before the cutoff
    /// @dev   Takes no anchor time. See `IPQAnchorRegistry`.
    ///
    ///        MUST NOT revert on a well-formed-but-failing artifact. A refusal and an incomplete
    ///        check both return `Refuse`, and the caller separates them by reading `evidence`.
    /// @return decision whether to admit; `Refuse` is the zero value so anything undecided fails closed
    /// @return evidence what could actually be established, which `decision` alone cannot carry
    /// @return reason the closed-enumeration cause ERC-8373 requires an unverifiable to carry
    /// @return rule which limb of the cutoff rule decided it, from the profile's closed rule set
    function verifyArtifact(bytes32 artifactContentAddress, bytes calldata companion)
        external
        view
        returns (PQDecision decision, PQEvidence evidence, PQReason reason, PQRule rule);

    /// @notice The binding governing artifacts anchored at `anchorTime`, resolved from the chain.
    /// @dev    ERC-8373: "Resolution MUST run from the chain even at length one." Rotations are
    ///         forward-acting and revocations end authority at their own anchor time, so this is a
    ///         function of the queried instant and not of the present.
    /// @return bindingContentAddress the in-force binding, or bytes32(0) if none is in force
    function inForceBindingAt(uint64 anchorTime) external view returns (bytes32 bindingContentAddress);

    /// @notice Emitted when a consumer settles an artifact, including on refusal.
    /// @dev    Emitted for every outcome, not just acceptance. An artifact that was checked and
    ///         refused must be distinguishable from one that was never presented, which is the
    ///         same asymmetry ERC-8373 removes off-chain by insisting unverifiable is its own
    ///         state.
    event ArtifactSettled(
        bytes32 indexed artifactContentAddress,
        bytes32 indexed inForceBinding,
        PQDecision decision,
        PQEvidence evidence,
        PQReason reason,
        PQRule rule,
        uint64 anchorTime
    );
}
