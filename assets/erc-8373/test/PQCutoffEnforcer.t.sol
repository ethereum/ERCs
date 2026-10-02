// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PQCutoffEnforcer} from "../src/PQCutoffEnforcer.sol";
import {
    IPQAnchorRegistry,
    IPQCompanionVerifier,
    IPQKeyBindingConsumer,
    PQDecision,
    PQEvidence,
    PQReason
} from "../src/IPQKeyBindingConsumer.sol";

contract MockAnchorRegistry is IPQAnchorRegistry {
    mapping(bytes32 => uint64) private _t;
    mapping(bytes32 => address) private _by;

    function anchor(bytes32 ca, uint64 t, address by) external {
        _t[ca] = t;
        _by[ca] = by;
    }

    function anchorTimeOf(bytes32 ca) external view returns (uint64) {
        return _t[ca];
    }

    function anchoredBy(bytes32 ca) external view returns (address) {
        return _by[ca];
    }
}

contract MockCompanionVerifier is IPQCompanionVerifier {
    bool public answer = true;
    bool public shouldRevert;

    function set(bool a, bool r) external {
        answer = a;
        shouldRevert = r;
    }

    function algorithm() external pure returns (string memory) {
        return "ML-DSA-65";
    }

    function verifyCompanion(bytes32, bytes calldata, bytes calldata) external view returns (bool) {
        require(!shouldRevert, "verifier down");
        return answer;
    }
}

contract PQCutoffEnforcerTest is Test {
    uint64 constant CUTOFF = 1_800_000_000;
    address constant CLASSICAL = address(0xC1a551ca1);
    address constant IMPOSTOR = address(0xBAD);

    bytes32 constant GENESIS = keccak256("binding-genesis");
    bytes32 constant ROTATED = keccak256("binding-rotated");
    bytes32 constant REVOKE_REC = keccak256("revocation-record");
    bytes constant PK1 = hex"a1a1";
    bytes constant PK2 = hex"b2b2";
    bytes constant COMPANION = hex"5165";

    MockAnchorRegistry reg;
    MockCompanionVerifier ver;
    PQCutoffEnforcer enf;

    function setUp() public {
        reg = new MockAnchorRegistry();
        ver = new MockCompanionVerifier();
        enf = new PQCutoffEnforcer(CUTOFF, reg, ver, CLASSICAL);

        reg.anchor(GENESIS, CUTOFF - 1000, CLASSICAL);
        enf.registerBinding(GENESIS, bytes32(0), PK1);
    }

    function _dec(bytes32 a, bytes memory c) internal view returns (PQDecision d) {
        (d,,,) = enf.verifyArtifact(a, c);
    }

    function _ev(bytes32 a, bytes memory c) internal view returns (PQEvidence e) {
        (, e,,) = enf.verifyArtifact(a, c);
    }

    function _artifact(bytes32 id, uint64 t) internal returns (bytes32) {
        reg.anchor(id, t, CLASSICAL);
        return id;
    }

    // ── The cutoff boundary ──────────────────────────────────────────────────
    // ERC-8373 says an artifact is admitted classical-only if it is "proven anchored before the
    // consumer's cutoff". Before is strictly before. These three tests pin that, because an
    // off-by-one here is the difference between a migration that closes and one that does not.

    function test_one_second_before_the_cutoff_is_accepted_without_a_companion() public {
        bytes32 a = _artifact(keccak256("early"), CUTOFF - 1);
        assertEq(uint256(_dec(a, "")), uint256(PQDecision.Admit));
    }

    function test_exactly_at_the_cutoff_is_not_admitted_classical_only() public {
        bytes32 a = _artifact(keccak256("at"), CUTOFF);
        assertEq(
            uint256(_dec(a, "")), uint256(PQDecision.Refuse), "the cutoff instant is on the far side of the cutoff"
        );
    }

    function test_exactly_at_the_cutoff_is_accepted_with_a_valid_companion() public {
        bytes32 a = _artifact(keccak256("at2"), CUTOFF);
        assertEq(uint256(_dec(a, COMPANION)), uint256(PQDecision.Admit));
    }

    // ── The tri-state ────────────────────────────────────────────────────────

    /// Unverifiable must be the zero value, so an unwritten slot or a failed decode can never be
    /// mistaken for authorization.
    /// Both zero values must fail closed: nothing established, nothing admitted.
    function test_zero_values_fail_closed() public pure {
        assertEq(uint256(PQEvidence.Unverifiable), 0);
        assertEq(uint256(PQDecision.Refuse), 0);
    }

    /// An artifact nobody anchored is unknown, not refused. Refusing would let an indexing gap
    /// read as a policy decision.
    function test_unanchored_artifact_is_unverifiable_not_rejected() public view {
        assertEq(uint256(_dec(keccak256("never-anchored"), COMPANION)), uint256(PQEvidence.Unverifiable));
    }

    /// A verifier that cannot answer leaves the artifact unverifiable. A reverting dependency is
    /// not evidence that the artifact is bad.
    function test_failing_companion_verifier_is_unverifiable_not_rejected() public {
        bytes32 a = _artifact(keccak256("late"), CUTOFF + 10);
        ver.set(true, true);
        assertEq(uint256(_dec(a, COMPANION)), uint256(PQDecision.Refuse), "gate closes");
        assertEq(uint256(_ev(a, COMPANION)), uint256(PQEvidence.Unverifiable), "verifier down is not a bad signature");
    }

    /// A companion that is simply wrong is a reject, which must stay distinct from the above.
    function test_invalid_companion_is_rejected() public {
        bytes32 a = _artifact(keccak256("late2"), CUTOFF + 10);
        ver.set(false, false);
        assertEq(uint256(_dec(a, COMPANION)), uint256(PQDecision.Refuse));
    }

    /// The omission attack the ERC exists to close: after the cutoff, no companion is a reject.
    function test_omitted_companion_after_the_cutoff_fails_closed() public {
        bytes32 a = _artifact(keccak256("late3"), CUTOFF + 10);
        assertEq(uint256(_dec(a, "")), uint256(PQDecision.Refuse));
    }

    // ── Anchor time is read, never supplied ──────────────────────────────────

    /// The whole design rests on anchor time being unforgeable by the caller. The interface takes
    /// no timestamp, so this test states the property the signature enforces: two callers asking
    /// about the same artifact get the same verdict, and neither can move it across the cutoff.
    function test_callers_cannot_move_an_artifact_across_the_cutoff() public {
        bytes32 a = _artifact(keccak256("fixed"), CUTOFF + 5);
        vm.prank(IMPOSTOR);
        PQDecision asImpostor = _dec(a, "");
        vm.prank(CLASSICAL);
        PQDecision asOwner = _dec(a, "");
        assertEq(uint256(asImpostor), uint256(asOwner));
        assertEq(uint256(asOwner), uint256(PQDecision.Refuse));
    }

    // ── Proof of possession comes from the anchoring transaction ─────────────

    /// ERC-8373 makes the anchoring transaction the classical proof-of-possession, so a binding
    /// anchored by anyone else is not this identity's binding regardless of who registers it.
    function test_binding_anchored_by_another_address_is_refused() public {
        bytes32 b = keccak256("impostor-binding");
        reg.anchor(b, CUTOFF - 500, IMPOSTOR);
        vm.expectRevert(abi.encodeWithSelector(PQCutoffEnforcer.WrongAnchorer.selector, CLASSICAL, IMPOSTOR));
        enf.registerBinding(b, GENESIS, PK2);
    }

    /// An un-anchored binding is admitted and then never allowed to govern.
    ///
    /// This replaces an assertion that it reverts. Reverting reads as the stricter choice and is
    /// the weaker one: a binding that cannot enter the chain cannot be reported either, so the
    /// chain silently looked shorter than it was and resolution answered from whatever remained.
    /// ERC-8373 wants an unreadable anchor surfaced as unverifiable with a reason. The published
    /// cases 21, 22 and 25 are unreachable under the old behaviour, which is how the gap was found.
    function test_unanchored_binding_is_admitted_but_never_governs() public {
        bytes32 ghost = keccak256("ghost");
        vm.prank(CLASSICAL);
        enf.registerBinding(ghost, GENESIS, PK2);

        assertEq(enf.inForceBindingAt(CUTOFF - 1), GENESIS, "the anchored binding still governs");
        assertTrue(enf.inForceBindingAt(CUTOFF - 1) != ghost, "an un-anchored binding never governs");
    }

    /// And when nothing anchored is left, that is its own reason rather than an empty chain.
    function test_only_unanchored_bindings_reports_binding_anchor_unavailable() public {
        MockAnchorRegistry sub = new MockAnchorRegistry();
        PQCutoffEnforcer bare = new PQCutoffEnforcer(CUTOFF, sub, ver, CLASSICAL);
        vm.prank(CLASSICAL);
        bare.registerBinding(keccak256("ghost"), bytes32(0), PK2);

        bytes32 art = keccak256("artifact");
        sub.anchor(art, CUTOFF - 1, CLASSICAL);

        (PQDecision d, PQEvidence e, PQReason r,) = bare.verifyArtifact(art, "");
        assertEq(uint256(d), uint256(PQDecision.Refuse));
        assertEq(uint256(e), uint256(PQEvidence.Unverifiable), "an unreadable anchor is not a refutation");
        assertEq(uint256(r), uint256(PQReason.BindingAnchorUnavailable));
    }

    // ── Chain state is the identity's to change ──────────────────────────────

    /// Un-anchored registration has no substrate fact behind it, so the caller has to be the
    /// identity. Left open, `AlreadyRegistered` keys on the content-address alone, so a squatter
    /// could register an un-anchored binding first and permanently block the real one from ever
    /// entering the chain. Content-addresses here are deterministic and visible before the
    /// anchoring transaction lands, so this was reachable.
    function test_stranger_cannot_squat_an_unanchored_binding() public {
        bytes32 ghost = keccak256("squat");
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(PQCutoffEnforcer.NotClassicalAddress.selector, CLASSICAL, address(0xBAD))
        );
        enf.registerBinding(ghost, GENESIS, PK2);

        // and the owner can still register it afterwards
        vm.prank(CLASSICAL);
        enf.registerBinding(ghost, GENESIS, PK2);
    }

    /// Terminality closes the chain to further rotation. A stranger who could set it would strand
    /// the identity on a key it can no longer rotate away from, which is the situation this
    /// contract exists to let it escape.
    function test_stranger_cannot_close_the_chain() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(PQCutoffEnforcer.NotClassicalAddress.selector, CLASSICAL, address(0xBAD))
        );
        enf.markTerminal(GENESIS);
    }

    /// It cannot force an admission, but it can flip an identity's evidence from Unverifiable to
    /// Refuted before the owner has loaded anything, and that distinction is the point.
    function test_stranger_cannot_declare_the_chain_empty() public {
        MockAnchorRegistry sub = new MockAnchorRegistry();
        PQCutoffEnforcer bare = new PQCutoffEnforcer(CUTOFF, sub, ver, CLASSICAL);

        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(PQCutoffEnforcer.NotClassicalAddress.selector, CLASSICAL, address(0xBAD))
        );
        bare.declareChainEmpty();

        bytes32 art = keccak256("artifact");
        sub.anchor(art, CUTOFF - 1, CLASSICAL);
        (, PQEvidence e, PQReason r,) = bare.verifyArtifact(art, "");
        assertEq(uint256(e), uint256(PQEvidence.Unverifiable), "still nothing established");
        assertEq(uint256(r), uint256(PQReason.ChainUnavailable));
    }

    /// A chain nobody loaded is not a chain that resolves to nothing.
    function test_unloaded_chain_is_unverifiable_not_refuted() public {
        MockAnchorRegistry sub = new MockAnchorRegistry();
        PQCutoffEnforcer bare = new PQCutoffEnforcer(CUTOFF, sub, ver, CLASSICAL);

        bytes32 art = keccak256("artifact");
        sub.anchor(art, CUTOFF - 1, CLASSICAL);

        (, PQEvidence e, PQReason r,) = bare.verifyArtifact(art, "");
        assertEq(uint256(e), uint256(PQEvidence.Unverifiable), "nothing was established");
        assertEq(uint256(r), uint256(PQReason.ChainUnavailable));

        vm.prank(CLASSICAL);
        bare.declareChainEmpty();
        (, PQEvidence e2, PQReason r2,) = bare.verifyArtifact(art, "");
        assertEq(uint256(e2), uint256(PQEvidence.Refuted), "an empty chain is a determinate answer");
        assertEq(uint256(r2), uint256(PQReason.NoBindingsInChain));
    }

    // ── Rotation is forward-acting ───────────────────────────────────────────

    /// Artifacts anchored before a rotation keep resolving to the predecessor.
    function test_rotation_does_not_reach_backwards() public {
        reg.anchor(ROTATED, CUTOFF + 100, CLASSICAL);
        enf.registerBinding(ROTATED, GENESIS, PK2);

        assertEq(enf.inForceBindingAt(CUTOFF + 50), GENESIS, "before the rotation");
        assertEq(enf.inForceBindingAt(CUTOFF + 100), ROTATED, "at the rotation");
        assertEq(enf.inForceBindingAt(CUTOFF + 500), ROTATED, "after the rotation");
    }

    /// A successor cannot be inserted behind its predecessor. Without this, a late-registered but
    /// early-anchored statement could rewrite which key governed a past instant.
    function test_successor_cannot_claim_an_earlier_anchor_than_its_predecessor() public {
        bytes32 backdated = keccak256("backdated-rotation");
        reg.anchor(backdated, CUTOFF - 2000, CLASSICAL);
        vm.expectRevert(
            abi.encodeWithSelector(PQCutoffEnforcer.RotationNotForward.selector, CUTOFF - 1000, CUTOFF - 2000)
        );
        enf.registerBinding(backdated, GENESIS, PK2);
    }

    // ── Revocation ends authority at its own anchor time ─────────────────────

    function test_revocation_is_not_retroactive() public {
        reg.anchor(REVOKE_REC, CUTOFF + 200, CLASSICAL);
        enf.revokeBinding(GENESIS, REVOKE_REC);

        assertEq(enf.inForceBindingAt(CUTOFF + 199), GENESIS, "earlier artifacts remain governed");
        assertEq(enf.inForceBindingAt(CUTOFF + 200), bytes32(0), "authority ends at the anchor");
        assertEq(enf.inForceBindingAt(CUTOFF + 999), bytes32(0));
    }

    /// An artifact anchored after a revocation, with no live binding, is refused rather than
    /// admitted. Documents the fail-closed reading of a point the ERC leaves open: whether a
    /// revoked binding falls back to its predecessor. This asserts that it does not.
    function test_artifact_after_revocation_is_rejected_with_no_fallback() public {
        reg.anchor(REVOKE_REC, CUTOFF + 200, CLASSICAL);
        enf.revokeBinding(GENESIS, REVOKE_REC);
        bytes32 a = _artifact(keccak256("post-revocation"), CUTOFF + 300);
        assertEq(uint256(_dec(a, COMPANION)), uint256(PQDecision.Refuse));
    }

    // ── Detectability ────────────────────────────────────────────────────────

    /// The ERC says deployment of the consumer rule is what makes the migration operative, so a
    /// counterparty has to be able to tell that a given contract enforces it, and read the cutoff
    /// it enforces, before relying on it.
    function test_consumer_is_detectable_and_its_cutoff_is_readable() public view {
        assertTrue(enf.supportsInterface(type(IPQKeyBindingConsumer).interfaceId));
        assertTrue(enf.supportsInterface(0x01ffc9a7));
        assertFalse(enf.supportsInterface(0xffffffff));
        assertEq(enf.cutoff(), CUTOFF);
    }

    function test_settle_emits_on_refusal_too() public {
        bytes32 a = _artifact(keccak256("refused"), CUTOFF + 10);
        vm.recordLogs();
        enf.settleArtifact(a, "");
        assertEq(vm.getRecordedLogs().length, 1, "a refusal must leave a trace");
    }
}
