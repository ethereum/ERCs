// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {
    IPQKeyBindingConsumer,
    IPQAnchorRegistry,
    IPQCompanionVerifier,
    PQDecision,
    PQEvidence,
    PQReason,
    PQRule
} from "./IPQKeyBindingConsumer.sol";

/// @title A reference ERC-8373 cutoff enforcer
/// @notice Implements the consumer half of the ERC-8373 verification procedure on-chain: read the
///         anchor time from the substrate, apply the cutoff, resolve the in-force binding from the
///         anchored chain, and delegate the companion check.
/// @dev    Reference implementation. Not audited, not gas-tuned, and deliberately readable rather
///         than clever, because its job is to pin the semantics of the rule.
contract PQCutoffEnforcer is IPQKeyBindingConsumer {
    struct Binding {
        bytes32 contentAddress;
        bytes32 predecessor; // bytes32(0) for the genesis binding
        bool anchored; // false when the substrate has no anchor for it
        uint64 anchorTime; // read from the substrate, never supplied
        uint64 activatedAt; // declared if given, else the binding's own anchor
        uint64 revokedAt; // 0 while live
        bool terminal;
        bool malformed; // activation precedes its own anchor, which cannot reopen the past
        bytes pqPubkey;
    }

    uint64 public immutable override cutoff;
    IPQAnchorRegistry public immutable override anchorRegistry;
    IPQCompanionVerifier public immutable companionVerifier;

    /// @notice The classical address whose transactions anchor this identity's bindings.
    address public immutable classicalAddress;

    Binding[] private _chain;
    mapping(bytes32 => uint256) private _indexPlusOne;

    /// @notice Whether a chain has been loaded at all.
    /// @dev    This is the fix for the defect the published case 12 exists to catch. Before it,
    ///         "the chain could not be fetched" and "the chain was fetched and resolves to
    ///         nothing" were the same zero-length array, so an unresolved dependency read as a
    ///         determinate refusal. They are opposite facts: one is unverifiable, the other is
    ///         refuted. False is the zero value, so a consumer that has loaded nothing says so.
    bool public chainLoaded;

    error NotAnchored(bytes32 contentAddress);
    error WrongAnchorer(address expected, address actual);
    error AlreadyRegistered(bytes32 contentAddress);
    error UnknownBinding(bytes32 contentAddress);
    error PredecessorNotInChain(bytes32 predecessor);
    error ChainIsTerminal();
    error RotationNotForward(uint64 predecessorAnchor, uint64 anchorTime);
    error NotClassicalAddress(address expected, address actual);
    error UnhandledReason(PQReason reason);

    constructor(
        uint64 cutoff_,
        IPQAnchorRegistry anchorRegistry_,
        IPQCompanionVerifier companionVerifier_,
        address classicalAddress_
    ) {
        cutoff = cutoff_;
        anchorRegistry = anchorRegistry_;
        companionVerifier = companionVerifier_;
        classicalAddress = classicalAddress_;
    }

    // ── Chain construction ───────────────────────────────────────────────────

    /// @notice Admit an anchored binding into the chain.
    /// @dev    Everything here is checked against the substrate rather than taken from the caller.
    ///         The anchoring transaction is the classical proof-of-possession, so a binding whose
    ///         anchoring transaction came from any other address is not this identity's binding,
    ///         no matter who submits it here.
    ///
    ///         The PQ side of proof-of-possession (genesis self-signature, and the predecessor's
    ///         dual-signature on rotation) is not verifiable in the EVM today. It is delegated,
    ///         like the companion check, rather than silently assumed.
    function registerBinding(bytes32 contentAddress, bytes32 predecessor, bytes calldata pqPubkey) external {
        registerBindingWithActivation(contentAddress, predecessor, pqPubkey, false, 0);
    }

    /// @notice Admit a binding into the chain, optionally with a declared activation boundary.
    ///
    /// @param activationDeclared whether the chain states an activation at all. This is a separate
    ///        flag rather than a zero sentinel because zero is a meaningful declared value: the
    ///        published case 17 declares `activated_at: 0` against an anchor of 100, and that is
    ///        precisely the retroactive activation the malformed check exists to catch. A sentinel
    ///        would make the one case that matters look like an absent field.
    /// @param declaredActivation the binding's own activation instant when `activationDeclared`.
    ///        ERC-8373 puts the `in_force` interval at `B <= t < R` with `B` the
    ///        activation anchor, and a deployment may declare an activation later than the anchor
    ///        (a binding published now, governing from a scheduled boundary). Deriving it, which
    ///        this contract used to do unconditionally, makes that state unrepresentable and makes
    ///        the retroactive case below undetectable.
    ///
    /// @dev An un-anchored binding is admitted rather than rejected, and that is deliberate. The
    ///      old code reverted `NotAnchored`, which sounds strict and is actually weaker: a state
    ///      that cannot be entered cannot be reported, so the chain silently looked shorter than
    ///      it was and resolution answered from whatever remained. ERC-8373 wants an unreadable
    ///      anchor surfaced as `unverifiable` with a reason, not made invisible. Resolution skips
    ///      un-anchored bindings and reports `BindingAnchorUnavailable` when nothing anchored is
    ///      left, so this admits the binding without ever letting it govern.
    function registerBindingWithActivation(
        bytes32 contentAddress,
        bytes32 predecessor,
        bytes calldata pqPubkey,
        bool activationDeclared,
        uint64 declaredActivation
    ) public {
        if (_indexPlusOne[contentAddress] != 0) revert AlreadyRegistered(contentAddress);

        uint64 anchorTime = anchorRegistry.anchorTimeOf(contentAddress);
        bool anchored = anchorTime != 0;

        // The anchoring transaction is the classical proof-of-possession, so a binding anchored by
        // any other address is not this identity's binding. With no anchor there is no such proof
        // to check, and the binding is admitted only so it can be reported as unverifiable.
        if (anchored) {
            address anchorer = anchorRegistry.anchoredBy(contentAddress);
            if (anchorer != classicalAddress) revert WrongAnchorer(classicalAddress, anchorer);
        } else if (msg.sender != classicalAddress) {
            // With no anchor there is no substrate fact to check, so the caller has to be the
            // identity itself. Leaving this open let anyone register an un-anchored binding for an
            // arbitrary content-address, and since `AlreadyRegistered` keys on the content-address
            // alone, a squatter could permanently block the real binding from ever entering the
            // chain. Content-addresses here are deterministic and observable before the anchoring
            // transaction lands, so that was reachable rather than theoretical.
            revert NotClassicalAddress(classicalAddress, msg.sender);
        }

        if (_chain.length != 0) {
            uint256 pi = _indexPlusOne[predecessor];
            if (pi == 0) revert PredecessorNotInChain(predecessor);
            Binding storage p = _chain[pi - 1];
            if (p.terminal) revert ChainIsTerminal();
            // Rotation is forward-acting, so a successor cannot claim an earlier anchor than the
            // binding it replaces. Without this, a late-registered but early-anchored statement
            // could be inserted behind an existing one and change history. An un-anchored
            // predecessor has no time to be forward of.
            if (anchored && p.anchored && anchorTime <= p.anchorTime) {
                revert RotationNotForward(p.anchorTime, anchorTime);
            }
        }

        // ERC-8373: activation is inclusive and the interval is half-open, so a binding governs
        // from its own anchor rather than from creation. An activation BEFORE that anchor would
        // reopen the past, which anchoring exists to prevent, so it is recorded as malformed
        // rather than clamped. Clamping would silently produce a plausible answer to a question
        // the chain is not entitled to answer.
        uint64 activatedAt = activationDeclared ? declaredActivation : anchorTime;
        bool malformed = anchored && activationDeclared && declaredActivation < anchorTime;

        _chain.push(
            Binding({
                contentAddress: contentAddress,
                predecessor: predecessor,
                anchored: anchored,
                anchorTime: anchorTime,
                activatedAt: activatedAt,
                revokedAt: 0,
                terminal: false,
                malformed: malformed,
                pqPubkey: pqPubkey
            })
        );
        _indexPlusOne[contentAddress] = _chain.length;
        chainLoaded = true;
    }

    /// @notice Record that the chain was fetched and this identity has no bindings.
    /// @dev    Distinct from never having loaded one. `bindings: []` is a determinate answer and
    ///         refuses; an unloaded chain establishes nothing and is unverifiable.
    function declareChainEmpty() external {
        // Owner-only. It cannot force an admission, but left open it let an outsider flip an
        // identity's evidence from Unverifiable to Refuted before the owner had loaded anything,
        // which is precisely the distinction this contract exists to keep honest.
        if (msg.sender != classicalAddress) revert NotClassicalAddress(classicalAddress, msg.sender);
        chainLoaded = true;
    }

    /// @notice Record an anchored revocation.
    /// @dev    Authority ends at the revocation record's own anchor time, never at a self-declared
    ///         time and never retroactively.
    function revokeBinding(bytes32 contentAddress, bytes32 revocationRecord) external {
        uint256 i = _indexPlusOne[contentAddress];
        if (i == 0) revert UnknownBinding(contentAddress);

        uint64 revokedAt = anchorRegistry.anchorTimeOf(revocationRecord);
        if (revokedAt == 0) revert NotAnchored(revocationRecord);

        address anchorer = anchorRegistry.anchoredBy(revocationRecord);
        if (anchorer != classicalAddress) revert WrongAnchorer(classicalAddress, anchorer);

        _chain[i - 1].revokedAt = revokedAt;
    }

    /// @notice Mark a binding terminal, closing the chain to further rotation.
    /// @dev Owner-only. Terminality is a standing constraint on the future binding path, and
    ///      `registerBindingWithActivation` refuses to rotate past a terminal predecessor. Left
    ///      open, any address could close the chain permanently and strand the identity on a key
    ///      it can no longer rotate away from, which is the exact situation this contract exists
    ///      to let it escape.
    function markTerminal(bytes32 contentAddress) external {
        if (msg.sender != classicalAddress) revert NotClassicalAddress(classicalAddress, msg.sender);
        uint256 i = _indexPlusOne[contentAddress];
        if (i == 0) revert UnknownBinding(contentAddress);
        _chain[i - 1].terminal = true;
    }

    // ── Resolution ───────────────────────────────────────────────────────────

    /// @inheritdoc IPQKeyBindingConsumer
    /// @dev The in-force binding at an instant is the latest one ACTIVE at or before it that has
    ///      not been revoked by then.
    ///
    ///      Two cases the reason string must not merge, which is the defect the published v0
    ///      vectors carry:
    ///
    ///      - **pre-baseline**, anchored before the first binding was registered. Innocent back
    ///        catalogue. The baseline activates at 0 and governs from creation, so this resolves
    ///        rather than falling through, and the cutoff then admits it classical-only.
    ///      - **post-revocation**, anchored after a binding's authority was deliberately ended.
    ///        A revocation is a trust-ending act and its signal is stronger than the consumer's
    ///        cutoff, so this resolves to nothing and is refused even before the cutoff.
    ///
    ///      Authority never reverts to a predecessor. That would resurrect something the owner
    ///      retired.
    function inForceBindingAt(uint64 anchorTime) public view override returns (bytes32) {
        (bytes32 binding,) = _resolve(anchorTime);
        return binding;
    }

    /// @notice Resolve the chain at an instant, returning both the binding and why.
    /// @dev    The reason is not decoration. ERC-8373 forbids collapsing `pre_baseline` and ended
    ///         authority into one answer, and they differ in outcome, not only in wording: the
    ///         first admits the back catalogue and the second refuses it even before the cutoff.
    ///         Returning bytes32(0) for both, which this contract used to do, is exactly that
    ///         collapse.
    function _resolve(uint64 anchorTime) internal view returns (bytes32 binding, PQReason reason) {
        if (!chainLoaded) return (bytes32(0), PQReason.ChainUnavailable);
        if (_chain.length == 0) return (bytes32(0), PQReason.NoBindingsInChain);

        uint256 anchoredCount;
        uint64 earliestActivation = type(uint64).max;

        for (uint256 i = 0; i < _chain.length; i++) {
            Binding storage b = _chain[i];
            if (b.malformed) return (bytes32(0), PQReason.ChainMalformed);
            // An un-anchored binding has no provable time, so it cannot govern anything. It is
            // skipped rather than treated as absent, because whether ANY anchored binding remains
            // is what separates "unreadable anchor" from "no bindings at all".
            if (!b.anchored) continue;
            anchoredCount++;
            if (b.activatedAt < earliestActivation) earliestActivation = b.activatedAt;
        }

        if (anchoredCount == 0) return (bytes32(0), PQReason.BindingAnchorUnavailable);
        if (anchorTime < earliestActivation) return (bytes32(0), PQReason.PreBaseline);

        // Latest binding active at or before the instant, walking back so a rotation wins over the
        // binding it replaces. Authority never reverts to a predecessor.
        for (uint256 i = _chain.length; i > 0; i--) {
            Binding storage b = _chain[i - 1];
            if (!b.anchored) continue;
            if (b.activatedAt > anchorTime) continue;
            // Revocation is inclusive on the revoked side: at t == R authority has already ended.
            if (b.revokedAt != 0 && b.revokedAt <= anchorTime) {
                return (bytes32(0), PQReason.NoInForceBinding);
            }
            return (b.contentAddress, PQReason.ResolvedAtAnchorTime);
        }

        return (bytes32(0), PQReason.NoInForceBinding);
    }

    function pqPubkeyOf(bytes32 contentAddress) public view returns (bytes memory) {
        uint256 i = _indexPlusOne[contentAddress];
        if (i == 0) revert UnknownBinding(contentAddress);
        return _chain[i - 1].pqPubkey;
    }

    function chainLength() external view returns (uint256) {
        return _chain.length;
    }

    // ── The rule ─────────────────────────────────────────────────────────────

    /// @inheritdoc IPQKeyBindingConsumer
    function verifyArtifact(bytes32 artifactContentAddress, bytes calldata companion)
        public
        view
        override
        returns (PQDecision, PQEvidence, PQReason, PQRule)
    {
        uint64 anchorTime = anchorRegistry.anchorTimeOf(artifactContentAddress);

        // An artifact whose anchor cannot be read is refused, but the evidence says we could not
        // tell rather than that it was bad. Merging those would let an indexing gap read as a
        // policy decision.
        if (anchorTime == 0) {
            return (
                PQDecision.Refuse,
                PQEvidence.Unverifiable,
                PQReason.ChainUnavailable,
                PQRule.PostCutoffAnchorStatusUnknown
            );
        }

        // Resolution runs BEFORE the cutoff. A revocation ends authority at its anchor time and
        // that signal outranks the consumer's cutoff, so a post-revocation artifact is refused
        // even when it falls on the classical-only side.
        (bytes32 binding, PQReason reason) = _resolve(anchorTime);

        if (binding == bytes32(0)) {
            // Only the back catalogue is admitted, and only before the cutoff. The other four
            // refuse, two of them determinately and two because nothing could be established.
            if (reason == PQReason.PreBaseline) {
                return anchorTime < cutoff
                    ? (PQDecision.Admit, PQEvidence.Verified, reason, PQRule.PreBaselineLegacyAdmit)
                    : (PQDecision.Refuse, PQEvidence.Refuted, reason, PQRule.PostCutoffNoValidCompanion);
            }
            if (reason == PQReason.NoInForceBinding) {
                return (PQDecision.Refuse, PQEvidence.Refuted, reason, PQRule.NoInForceBinding);
            }
            if (reason == PQReason.NoBindingsInChain) {
                return (PQDecision.Refuse, PQEvidence.Refuted, reason, PQRule.NoBindingsInChain);
            }
            if (reason == PQReason.ChainMalformed) {
                return (PQDecision.Refuse, PQEvidence.Unverifiable, reason, PQRule.ChainMalformed);
            }
            if (reason == PQReason.ChainUnavailable) {
                return (PQDecision.Refuse, PQEvidence.Unverifiable, reason, PQRule.ChainUnavailable);
            }
            if (reason == PQReason.BindingAnchorUnavailable) {
                return (PQDecision.Refuse, PQEvidence.Unverifiable, reason, PQRule.BindingAnchorUnavailable);
            }
            // Every reason reachable here is named above, so this is unreachable today. It reverts
            // rather than returning, because the previous version ended in an implicit else and
            // chain_unavailable fell through it to be reported as binding_anchor_unavailable. A
            // reason added later must break loudly instead of being relabelled.
            revert UnhandledReason(reason);
        }

        // "proven anchored before the consumer's cutoff". Strictly before.
        if (anchorTime < cutoff) {
            return (PQDecision.Admit, PQEvidence.Verified, reason, PQRule.AnchoredBeforeCutoff);
        }

        if (companion.length == 0) {
            return (PQDecision.Refuse, PQEvidence.Refuted, reason, PQRule.PostCutoffNoValidCompanion);
        }

        bytes memory pqPubkey = _chain[_indexPlusOne[binding] - 1].pqPubkey;

        // A verifier that cannot answer leaves the artifact unchecked. The gate still closes, but
        // the evidence records that nothing was refuted, only that nothing was established.
        try companionVerifier.verifyCompanion(artifactContentAddress, pqPubkey, companion) returns (bool ok) {
            return ok
                ? (PQDecision.Admit, PQEvidence.Verified, reason, PQRule.ValidPqCompanion)
                : (PQDecision.Refuse, PQEvidence.Refuted, reason, PQRule.PostCutoffNoValidCompanion);
        } catch {
            return (
                PQDecision.Refuse, PQEvidence.Unverifiable, reason, PQRule.PostCutoffCompanionUnchecked
            );
        }
    }

    /// @notice Verify and emit, so a refusal leaves a trace rather than vanishing.
    function settleArtifact(bytes32 artifactContentAddress, bytes calldata companion)
        external
        returns (PQDecision decision, PQEvidence evidence, PQReason reason, PQRule rule)
    {
        (decision, evidence, reason, rule) = verifyArtifact(artifactContentAddress, companion);
        uint64 anchorTime = anchorRegistry.anchorTimeOf(artifactContentAddress);
        emit ArtifactSettled(
            artifactContentAddress, inForceBindingAt(anchorTime), decision, evidence, reason, rule, anchorTime
        );
    }

    // ── ERC-165 ──────────────────────────────────────────────────────────────

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPQKeyBindingConsumer).interfaceId || interfaceId == 0x01ffc9a7;
    }
}
