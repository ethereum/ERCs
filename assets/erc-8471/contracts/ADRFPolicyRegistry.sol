// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "./ADRFTypes.sol";
import {ADRFErrors as E} from "./ADRFErrors.sol";
import {IADRFPolicyRegistry} from "./interfaces/IADRFPolicyRegistry.sol";
import {IADRFVerifier} from "./interfaces/IADRFVerifier.sol";
import {IADRFEvidenceRule} from "./interfaces/IADRFEvidenceRule.sol";
import {IADRFJudgmentMethod} from "./interfaces/IADRFJudgmentMethod.sol";

/// @title  ADRFPolicyRegistry — Dispute Policy registry, reference kernel v0.1
/// @notice Non-upgradeable. Every parameter the dispute registry executes is part of the hashed
///         `PolicySpec`: method bindings per (obligation kind, question type), the effect vocabulary,
///         the track (windows, reviews, hard cap, enactment margin, optimistic default) and the
///         widest standing. Validation makes the same input produce the same legal state everywhere:
///         a method must exist and declare its interface, a JUDGED method must fit into the decision
///         window, the hard cap must cover every round and review window.
contract ADRFPolicyRegistry is IADRFPolicyRegistry {
    mapping(bytes32 => T.PolicySpec) private _policies;
    mapping(bytes32 => bool) private _exists;
    mapping(bytes32 => address) private _familyAuthority;
    mapping(bytes32 => bytes32) private _familyLatestId;
    mapping(bytes32 => uint32) private _familyLatestVersion;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFPolicyRegistry).interfaceId;
    }

    function policyIdOf(T.PolicySpec calldata spec) public pure returns (bytes32) {
        return keccak256(abi.encode(spec));
    }

    function registerPolicy(T.PolicySpec calldata spec) external returns (bytes32 policyId) {
        policyId = policyIdOf(spec);
        if (_exists[policyId]) revert E.ADRF_PolicyExists(policyId);
        _validate(spec);

        if (spec.family == bytes32(0)) revert E.ADRF_InvalidPolicy("zero family");
        if (spec.version == 0) revert E.ADRF_InvalidPolicy("zero version");
        if (spec.updateAuthority == address(0)) revert E.ADRF_InvalidPolicy("zero update authority");
        if (_familyAuthority[spec.family] == address(0)) {
            if (spec.previous != bytes32(0)) revert E.ADRF_BadFamilyLink("first version has previous");
        } else {
            if (msg.sender != _familyAuthority[spec.family]) revert E.ADRF_NotFamilyAuthority(spec.family);
            if (spec.previous != _familyLatestId[spec.family]) revert E.ADRF_BadFamilyLink("previous != latest");
            if (spec.version <= _familyLatestVersion[spec.family]) revert E.ADRF_BadFamilyLink("version not increasing");
        }
        _familyAuthority[spec.family] = spec.updateAuthority;
        _familyLatestId[spec.family] = policyId;
        _familyLatestVersion[spec.family] = spec.version;

        _store(policyId, spec);
        _exists[policyId] = true;
        emit PolicyRegistered(policyId, spec.family, spec.version, msg.sender);
    }

    // ------------------------------------------------------------------ validation

    function _validate(T.PolicySpec calldata spec) private view {
        if (spec.resultProfile != T.RESULT_PROFILE_V1) revert E.ADRF_InvalidPolicy("result profile");

        uint256 nm = spec.methods.length;
        if (nm == 0 || nm > T.MAX_METHODS) revert E.ADRF_InvalidPolicy("methods out of range");
        for (uint256 i = 0; i < nm; i++) {
            T.MethodBinding calldata m = spec.methods[i];
            if (m.method == address(0)) revert E.ADRF_InvalidPolicy("zero method");
            for (uint256 j = i + 1; j < nm; j++) {
                if (spec.methods[j].obligationKind == m.obligationKind && spec.methods[j].qType == m.qType) {
                    revert E.ADRF_InvalidPolicy("duplicate method binding");
                }
            }
            bytes4 want = m.qType == T.QuestionType.FORMAL
                ? type(IADRFVerifier).interfaceId
                : m.qType == T.QuestionType.EVIDENCED
                    ? type(IADRFEvidenceRule).interfaceId
                    : type(IADRFJudgmentMethod).interfaceId;
            if (!_supports(m.method, want)) revert E.ADRF_InvalidPolicy("method interface");
            if (m.qType == T.QuestionType.JUDGED) {
                uint64 need = IADRFJudgmentMethod(m.method).maxDuration(m.params);
                if (need == 0 || need > spec.track.decisionWindow) revert E.ADRF_InvalidPolicy("judgment does not fit decision window");
            }
        }

        uint256 ne = spec.effects.length;
        if (ne > T.MAX_EFFECTS) revert E.ADRF_InvalidPolicy("effects out of range");
        for (uint256 i = 0; i < ne; i++) {
            if (spec.effects[i].id == bytes32(0)) revert E.ADRF_InvalidPolicy("zero effect");
            for (uint256 j = i + 1; j < ne; j++) {
                if (spec.effects[j].id == spec.effects[i].id) revert E.ADRF_InvalidPolicy("duplicate effect");
            }
        }

        T.Track calldata t = spec.track;
        if (t.filingWindow == 0) revert E.ADRF_InvalidPolicy("zero filing window");
        if (t.decisionWindow == 0) revert E.ADRF_InvalidPolicy("zero decision window");
        if (t.evidenceWindow > t.decisionWindow) revert E.ADRF_InvalidPolicy("evidence window exceeds decision window");
        if (t.maxReviews > 0) {
            if (t.reviewWindow == 0) revert E.ADRF_InvalidPolicy("zero review window");
            if (t.reviewTypes == 0 || t.reviewTypes > 31) revert E.ADRF_InvalidPolicy("review types");
        }
        if (t.optimistic) {
            if (t.answerWindow == 0 || t.answerWindow > t.decisionWindow) revert E.ADRF_InvalidPolicy("answer window");
            if (t.silenceRule == T.SilenceRule.NONE) revert E.ADRF_InvalidPolicy("silence rule");
        } else {
            if (t.answerWindow != 0 || t.silenceRule != T.SilenceRule.NONE) revert E.ADRF_InvalidPolicy("optimistic fields");
        }
        uint256 worst = uint256(t.decisionWindow)
            + uint256(t.maxReviews) * (uint256(t.reviewWindow) + uint256(t.decisionWindow));
        if (t.maxTotalDuration < worst) revert E.ADRF_InvalidPolicy("maxTotalDuration too short");
        if (t.maxTotalDuration > type(uint64).max / 2) revert E.ADRF_InvalidPolicy("maxTotalDuration too long");
    }

    function _supports(address target, bytes4 interfaceId) private view returns (bool) {
        if (target.code.length == 0) return false;
        (bool ok, bytes memory ret) = target.staticcall{gas: 30_000}(
            abi.encodeWithSelector(0x01ffc9a7, interfaceId)
        );
        return ok && ret.length >= 32 && abi.decode(ret, (bool));
    }

    function _store(bytes32 id, T.PolicySpec calldata spec) private {
        T.PolicySpec storage p = _policies[id];
        p.family = spec.family;
        p.version = spec.version;
        p.previous = spec.previous;
        p.updateAuthority = spec.updateAuthority;
        p.objectKind = spec.objectKind;
        p.track = spec.track;
        p.standing = spec.standing;
        p.resultProfile = spec.resultProfile;
        p.economicDeclaration = spec.economicDeclaration;
        p.descriptorHash = spec.descriptorHash;
        for (uint256 i = 0; i < spec.methods.length; i++) p.methods.push(spec.methods[i]);
        for (uint256 i = 0; i < spec.effects.length; i++) p.effects.push(spec.effects[i]);
    }

    // ------------------------------------------------------------------ reads

    function policyExists(bytes32 policyId) external view returns (bool) { return _exists[policyId]; }
    function familyAuthority(bytes32 family) external view returns (address) { return _familyAuthority[family]; }
    function familyLatest(bytes32 family) external view returns (bytes32, uint32) {
        return (_familyLatestId[family], _familyLatestVersion[family]);
    }

    function policyHeader(bytes32 policyId) external view returns (
        bytes32 family, uint32 version, bytes32 previous, address updateAuthority,
        bytes32 objectKind, T.StandingMode standing, bytes32 resultProfile,
        bytes32 economicDeclaration, bytes32 descriptorHash
    ) {
        if (!_exists[policyId]) revert E.ADRF_UnknownPolicy(policyId);
        T.PolicySpec storage p = _policies[policyId];
        return (p.family, p.version, p.previous, p.updateAuthority, p.objectKind, p.standing,
            p.resultProfile, p.economicDeclaration, p.descriptorHash);
    }

    function trackOf(bytes32 policyId) external view returns (T.Track memory) {
        if (!_exists[policyId]) revert E.ADRF_UnknownPolicy(policyId);
        return _policies[policyId].track;
    }

    function methodCount(bytes32 policyId) external view returns (uint256) { return _policies[policyId].methods.length; }

    function methodOf(bytes32 policyId, uint32 index) external view returns (T.MethodBinding memory) {
        if (index >= _policies[policyId].methods.length) revert E.ADRF_InvalidPolicy("method index");
        return _policies[policyId].methods[index];
    }

    function findMethod(bytes32 policyId, uint8 obligationKind, T.QuestionType qType)
        external view returns (bool found, T.MethodBinding memory binding)
    {
        T.MethodBinding[] storage ms = _policies[policyId].methods;
        for (uint256 i = 0; i < ms.length; i++) {
            if (ms[i].qType != qType) continue;
            if (ms[i].obligationKind == 0 || ms[i].obligationKind == obligationKind) return (true, ms[i]);
        }
        return (false, binding);
    }

    function effectCount(bytes32 policyId) external view returns (uint256) { return _policies[policyId].effects.length; }

    function effectOf(bytes32 policyId, uint32 index) external view returns (T.Effect memory) {
        if (index >= _policies[policyId].effects.length) revert E.ADRF_InvalidPolicy("effect index");
        return _policies[policyId].effects[index];
    }

    function effectCategory(bytes32 policyId, bytes32 effectId) external view returns (bool declared, T.EffectCategory category) {
        T.Effect[] storage es = _policies[policyId].effects;
        for (uint256 i = 0; i < es.length; i++) {
            if (es[i].id == effectId) return (true, es[i].category);
        }
        return (false, category);
    }
}
