// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PQCutoffEnforcer} from "../src/PQCutoffEnforcer.sol";
import {IPQAnchorRegistry, IPQCompanionVerifier, PQDecision, PQEvidence, PQReason, PQRule} from "../src/IPQKeyBindingConsumer.sol";
import {VectorChain, VectorBinding, ChainShape} from "./VectorChain.sol";

/// @notice A substrate replaying the anchor times the vectors record, and nothing else.
contract VectorAnchorSubstrate is IPQAnchorRegistry {
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

/// @notice Companion validity as the vectors supply it. The v1 file distinguishes a companion that
///         was CHECKED and failed from one that could not be checked at all, so this models both.
///         `down` reverts, which is how a verifier that cannot answer presents on-chain.
contract VectorCompanionVerifier is IPQCompanionVerifier {
    bool public valid;
    bool public underInForceKey;
    bool public down;

    function set(bool valid_, bool inForce_, bool down_) external {
        valid = valid_;
        underInForceKey = inForce_;
        down = down_;
    }

    function algorithm() external pure returns (string memory) {
        return "SLH-DSA-SHA2-192s";
    }

    function verifyCompanion(bytes32, bytes calldata, bytes calldata) external view returns (bool) {
        require(!down, "verifier unavailable");
        return valid && underInForceKey;
    }
}

/// @notice Drives the reference enforcer with the published ERC-8373 conformance vectors.
///
/// @dev Rewritten 1 Sep 2026. The previous runner registered the file's genesis binding for EVERY
///      case regardless of what the case declared, and read only `bindings[0].revoked_at`. Under
///      that runner the suite reported 9 green against a 9-case file. The published file now
///      carries 26 cases and declares a per-case chain on 17 of them, including one that is
///      explicitly unavailable. The old runner could not present any of those, so cases it
///      "passed" were never actually asked. Case 12 is the clearest: it declares `bindings: null`,
///      the runner registered genesis anyway, and the enforcer admitted an artifact the case says
///      is unverifiable.
///
///      This runner builds each case's own chain and fails loudly, naming the missing capability,
///      when the enforcer cannot be driven into the declared state at all. A state the reference
///      implementation cannot represent is a finding, not a case to skip.
contract CutoffVectorsTest is Test {
    using VectorChain for string;

    string constant V1 = "pq-key-binding-v1.cutoff-vectors.json";
    string constant V0 = "pq-key-binding-v0.cutoff-vectors.json";

    address constant CLASSICAL = 0xFf9a176577Fb42b6bc9c19fd05a241e8fCd0ca14;

    string json;
    uint64 consumerCutoff;
    uint256 caseCount;

    function setUp() public {
        json = vm.readFile(V1);
        consumerCutoff = uint64(vm.parseJsonUint(json, ".consumer_cutoff"));
        while (vm.keyExistsJson(json, string.concat(_case(caseCount), ".artifact.anchor_time"))) {
            caseCount++;
        }
    }

    function _case(uint256 i) internal pure returns (string memory) {
        return string.concat(".cases[", vm.toString(i), "]");
    }

    // ── Driving one case ─────────────────────────────────────────────────────

    /// @dev Returns the enforcer with the case's declared chain built, plus `unrepresentable` set
    ///      to the capability the enforcer lacks when the state cannot be reached at all.
    function _build(uint256 i) internal returns (PQCutoffEnforcer enf, VectorCompanionVerifier ver) {
        VectorAnchorSubstrate sub = new VectorAnchorSubstrate();
        ver = new VectorCompanionVerifier();
        enf = new PQCutoffEnforcer(consumerCutoff, sub, ver, CLASSICAL);

        // Chain state mutators are owner-only, so build every case as the identity itself.
        vm.startPrank(CLASSICAL);
        _buildChain(enf, sub, i);
        vm.stopPrank();
    }

    function _buildChain(PQCutoffEnforcer enf, VectorAnchorSubstrate sub, uint256 i) internal {
        ChainShape shape = VectorChain.shapeOf(json, i);

        // `bindings: null`. Load nothing at all, which is now a state the enforcer can hold.
        if (shape == ChainShape.Unavailable) return;

        // `bindings: []`. Fetched, and this identity has none. A different fact from the above.
        if (shape == ChainShape.Empty) {
            enf.declareChainEmpty();
            return;
        }

        if (shape == ChainShape.Default) {
            bytes32 ca = keccak256(bytes(vm.parseJsonString(json, ".bindings[0].name")));
            sub.anchor(ca, uint64(vm.parseJsonUint(json, ".bindings[0].binding_anchor_time")), CLASSICAL);
            enf.registerBinding(ca, bytes32(0), bytes(vm.parseJsonString(json, ".bindings[0].pq_pubkey")));
            return;
        }

        uint256 n = VectorChain.countOf(json, i);
        bytes32 prev = bytes32(0);
        for (uint256 k = 0; k < n; k++) {
            VectorBinding memory b =
                VectorChain.readAt(json, string.concat(VectorChain.path(i), "[", vm.toString(k), "]"));

            bytes32 ca = keccak256(bytes(b.name));
            // An un-anchored binding is anchored nowhere, so the substrate is simply not told
            // about it and the enforcer reads back a zero anchor time.
            if (b.anchored) sub.anchor(ca, b.anchorTime, CLASSICAL);

            enf.registerBindingWithActivation(ca, prev, b.pqPubkey, b.hasActivatedAt, b.activatedAt);
            prev = ca;

            if (b.hasRevokedAt) {
                bytes32 rec = keccak256(abi.encodePacked(b.name, "-revocation"));
                sub.anchor(rec, b.revokedAt, CLASSICAL);
                enf.revokeBinding(ca, rec);
            }
        }
    }

    function _runCase(uint256 i)
        internal
        returns (PQDecision decision, PQEvidence evidence, PQReason reason, PQRule rule)
    {
        (PQCutoffEnforcer enf, VectorCompanionVerifier ver) = _build(i);

        VectorAnchorSubstrate sub = VectorAnchorSubstrate(address(enf.anchorRegistry()));
        uint64 anchorTime = uint64(vm.parseJsonUint(json, string.concat(_case(i), ".artifact.anchor_time")));
        bytes32 artifact = keccak256(abi.encode("artifact", i));
        sub.anchor(artifact, anchorTime, CLASSICAL);

        bytes memory companion = _configureCompanion(i, ver);
        (decision, evidence, reason, rule) = enf.verifyArtifact(artifact, companion);
    }

    /// Reads the companion block for a case and configures the verifier to match it.
    function _configureCompanion(uint256 i, VectorCompanionVerifier ver) internal returns (bytes memory companion) {
        if (!vm.keyExistsJson(json, string.concat(_case(i), ".artifact.pq_companion.present"))) {
            return companion;
        }
        companion = hex"5165";

        // A vector with no `valid` key is the UNCHECKED case: the companion is present but nothing
        // was established about it. On-chain that is a verifier which cannot answer.
        bool isUnchecked = !vm.keyExistsJson(json, string.concat(_case(i), ".artifact.pq_companion.valid"));
        bool isValid =
            isUnchecked ? false : vm.parseJsonBool(json, string.concat(_case(i), ".artifact.pq_companion.valid"));

        bool inForce = true;
        if (vm.keyExistsJson(json, string.concat(_case(i), ".artifact.pq_companion.pq_pubkey"))) {
            inForce = _startsWith(
                vm.parseJsonString(json, string.concat(_case(i), ".artifact.pq_companion.pq_pubkey")), "638c"
            );
        }
        ver.set(isValid, inForce, isUnchecked);
    }

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory p = bytes(prefix);
        if (b.length < p.length) return false;
        for (uint256 i = 0; i < p.length; i++) {
            if (b[i] != p[i]) return false;
        }
        return true;
    }

    function _asDecision(string memory d) internal pure returns (PQDecision) {
        bytes32 h = keccak256(bytes(d));
        return (h == keccak256("ADMIT") || h == keccak256("ACCEPT")) ? PQDecision.Admit : PQDecision.Refuse;
    }

    function _asEvidence(string memory e) internal pure returns (PQEvidence) {
        bytes32 h = keccak256(bytes(e));
        if (h == keccak256("refuted")) return PQEvidence.Refuted;
        if (h == keccak256("unverifiable")) return PQEvidence.Unverifiable;
        return PQEvidence.Verified;
    }

    function _asRule(string memory r) internal pure returns (PQRule) {
        bytes32 h = keccak256(bytes(r));
        if (h == keccak256("anchored_before_cutoff")) return PQRule.AnchoredBeforeCutoff;
        if (h == keccak256("valid_pq_companion")) return PQRule.ValidPqCompanion;
        if (h == keccak256("pre_baseline_legacy_admit")) return PQRule.PreBaselineLegacyAdmit;
        if (h == keccak256("post_cutoff_no_valid_companion")) return PQRule.PostCutoffNoValidCompanion;
        if (h == keccak256("post_cutoff_companion_unchecked")) return PQRule.PostCutoffCompanionUnchecked;
        if (h == keccak256("post_cutoff_anchor_status_unknown")) return PQRule.PostCutoffAnchorStatusUnknown;
        if (h == keccak256("no_in_force_binding")) return PQRule.NoInForceBinding;
        if (h == keccak256("no_bindings_in_chain")) return PQRule.NoBindingsInChain;
        if (h == keccak256("chain_unavailable")) return PQRule.ChainUnavailable;
        if (h == keccak256("chain_malformed")) return PQRule.ChainMalformed;
        if (h == keccak256("binding_anchor_unavailable")) return PQRule.BindingAnchorUnavailable;
        revert(string.concat("vector declares a rule this enum has no value for: ", r));
    }

    function _asReason(string memory r) internal pure returns (PQReason) {
        bytes32 h = keccak256(bytes(r));
        if (h == keccak256("resolved_at_anchor_time")) return PQReason.ResolvedAtAnchorTime;
        if (h == keccak256("pre_baseline")) return PQReason.PreBaseline;
        if (h == keccak256("no_in_force_binding")) return PQReason.NoInForceBinding;
        if (h == keccak256("no_bindings_in_chain")) return PQReason.NoBindingsInChain;
        if (h == keccak256("chain_malformed")) return PQReason.ChainMalformed;
        if (h == keccak256("binding_anchor_unavailable")) return PQReason.BindingAnchorUnavailable;
        if (h == keccak256("chain_unavailable")) return PQReason.ChainUnavailable;
        revert(string.concat("vector declares a reason this enum has no value for: ", r));
    }

    function _firstCaseWithReason(string memory want) internal view returns (uint256, bool) {
        for (uint256 i = 0; i < caseCount; i++) {
            if (keccak256(bytes(_expected(i, "resolution_reason"))) == keccak256(bytes(want))) return (i, true);
        }
        return (0, false);
    }

    function _expected(uint256 i, string memory field) internal view returns (string memory) {
        return vm.parseJsonString(json, string.concat(_case(i), ".expected.", field));
    }

    // ── The suite ────────────────────────────────────────────────────────────

    /// Assert we are reading the file we think we are, before drawing any conclusion from it.
    function test_v1_vector_file_is_the_published_one() public view {
        assertEq(consumerCutoff, 1790000000);
        assertEq(uint64(vm.parseJsonUint(json, ".bindings[0].binding_anchor_time")), 1785423299);
        assertEq(caseCount, 26, "the published v1 set has 26 cases; a different count means a stale copy");
    }

    /// The reason is the field ERC-8373 makes REQUIRED for an unverifiable and requires to be a
    /// closed enumeration on-chain. It is also what stops `pre_baseline` and ended authority being
    /// reported as the same answer, which the ERC forbids by name.
    function test_enforcer_reproduces_every_v1_reason() public {
        for (uint256 i = 0; i < caseCount; i++) {
            (,, PQReason got,) = _runCase(i);
            assertEq(
                uint256(got),
                uint256(_asReason(_expected(i, "resolution_reason"))),
                string.concat("case ", vm.toString(i), " reason")
            );
        }
    }

    /// The rule is the profile's own closed set, eleven values, and it is not a rename of the
    /// reason. A `resolved_at_anchor_time` resolution still admits under `anchored_before_cutoff`
    /// or `valid_pq_companion` and refuses under `post_cutoff_no_valid_companion`, so surfacing
    /// only the reason loses which limb of the cutoff rule actually fired.
    function test_enforcer_reproduces_every_v1_rule() public {
        for (uint256 i = 0; i < caseCount; i++) {
            (,,, PQRule got) = _runCase(i);
            assertEq(
                uint256(got),
                uint256(_asRule(_expected(i, "rule"))),
                string.concat("case ", vm.toString(i), " rule")
            );
        }
    }

    /// The two the ERC singles out. Opposite answers, and a consumer that merged them would admit
    /// artifacts whose authority was deliberately ended.
    function test_pre_baseline_and_ended_authority_are_not_the_same_answer() public {
        (uint256 pre, bool foundPre) = _firstCaseWithReason("pre_baseline");
        (uint256 ended, bool foundEnded) = _firstCaseWithReason("no_in_force_binding");
        assertTrue(foundPre && foundEnded, "the file must declare both");

        (PQDecision dPre,, PQReason rPre,) = _runCase(pre);
        (PQDecision dEnd,, PQReason rEnd,) = _runCase(ended);

        assertTrue(rPre != rEnd, "one reason for both would be the collapse the ERC forbids");
        assertEq(uint256(dPre), uint256(PQDecision.Admit), "the back catalogue is admitted");
        assertEq(uint256(dEnd), uint256(PQDecision.Refuse), "ended authority is refused");
    }

    /// Every published case reproduces on the admission decision.
    function test_enforcer_reproduces_every_v1_decision() public {
        for (uint256 i = 0; i < caseCount; i++) {
            (PQDecision got,,,) = _runCase(i);
            assertEq(
                uint256(got),
                uint256(_asDecision(_expected(i, "decision"))),
                string.concat("case ", vm.toString(i), " decision")
            );
        }
    }

    /// And on the evidence, which is the field v1 added and which a single verdict cannot carry.
    function test_enforcer_reproduces_every_v1_evidence() public {
        uint256 checked;
        for (uint256 i = 0; i < caseCount; i++) {
            (, PQEvidence got,,) = _runCase(i);
            assertEq(
                uint256(got),
                uint256(_asEvidence(_expected(i, "evidence"))),
                string.concat("case ", vm.toString(i), " evidence")
            );
            checked++;
        }
        assertGt(checked, 0, "no case was actually checked");
    }

    /// The pair that motivated splitting the enum. Both refuse, and they are not the same fact.
    /// Selected by what the case declares rather than by index, because indices move when the
    /// published file grows and a hardcoded one silently checks the wrong case.
    function test_refuted_and_unverifiable_both_refuse_but_stay_distinct() public {
        (uint256 refutedCase, bool foundR) = _firstCaseWithEvidence("refuted");
        (uint256 unvCase, bool foundU) = _firstCaseWithEvidence("unverifiable");
        assertTrue(foundR && foundU, "the file must declare both evidence states");

        (PQDecision dRef, PQEvidence eRef,,) = _runCase(refutedCase);
        (PQDecision dUnc, PQEvidence eUnc,,) = _runCase(unvCase);

        assertEq(uint256(dRef), uint256(PQDecision.Refuse));
        assertEq(uint256(dUnc), uint256(PQDecision.Refuse));
        assertEq(uint256(eRef), uint256(PQEvidence.Refuted), "checked and failed");
        assertEq(uint256(eUnc), uint256(PQEvidence.Unverifiable), "never checked");
        assertTrue(eRef != eUnc, "a single verdict field would merge these");
    }

    function _firstCaseWithEvidence(string memory want) internal view returns (uint256, bool) {
        for (uint256 i = 0; i < caseCount; i++) {
            if (keccak256(bytes(_expected(i, "evidence"))) == keccak256(bytes(want))) return (i, true);
        }
        return (0, false);
    }

    /// v0 and v1 must agree that a pre-baseline artifact is admitted classical-only.
    ///
    /// @dev This replaces a test that asserted they DISAGREED. The v0 set used to reject the
    ///      pre-baseline case as `no_in_force_binding`, collapsing the innocent back catalogue into
    ///      ended authority, which is the inconsistency that started this thread. The published v0
    ///      asset now admits it as `anchored_before_cutoff`, so the gap is closed and the useful
    ///      assertion is the one that stops it reopening. Both files are read directly rather than
    ///      restated, and the case is found by its declared reason rather than by index, because a
    ///      hardcoded index is what made the previous version of this test wrong the moment the
    ///      published file grew.
    function test_v0_and_v1_agree_on_the_back_catalogue() public view {
        string memory v0 = vm.readFile(V0);

        bool foundV0;
        for (uint256 i = 0; i < 64 && !foundV0; i++) {
            string memory p = string.concat(".cases[", vm.toString(i), "].name");
            if (!vm.keyExistsJson(v0, p)) break;
            if (
                keccak256(bytes(vm.parseJsonString(v0, p)))
                    == keccak256("artifact anchored before any binding existed")
            ) {
                assertEq(
                    vm.parseJsonString(v0, string.concat(".cases[", vm.toString(i), "].expected.decision")),
                    "ADMIT",
                    "v0 must admit the back catalogue"
                );
                foundV0 = true;
            }
        }
        assertTrue(foundV0, "v0 must still declare the pre-baseline case");

        (uint256 v1Case, bool foundV1) = _firstCaseWithReason("pre_baseline");
        assertTrue(foundV1, "v1 must declare a pre_baseline case");
        assertEq(_expected(v1Case, "decision"), "ADMIT", "v1 must admit it too");
    }
}
