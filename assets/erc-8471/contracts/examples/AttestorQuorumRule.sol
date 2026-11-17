// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFEvidenceRule} from "../interfaces/IADRFEvidenceRule.sol";
import {IADRFDisputeRegistry} from "../interfaces/IADRFDisputeRegistry.sol";

/// @title  AttestorQuorumRule — EVIDENCED method: an external fact accepted on k-of-n attestations
/// @notice A panel of attestors (registered with its threshold; the panel id is the method parameter) attests
///         TRUE or FALSE to a sub-question of a case of the dispute registry the rule is built for. The fact is
///         accepted when k attestors agree; the finding carries SUPPORT_SIGNED | SUPPORT_EVIDENCED: the fact was
///         accepted on the stated attestations and the trust assumption that the panel is honest, nothing more.
///         Evidence integrity (what was attested) and availability (what the attestors saw) are the panel's
///         business, not the kernel's.
///
///         The answer does not depend on who asks for it or when. A panel is a strict majority (2k > n, no
///         attestor twice), so a quorum for one value excludes a quorum for the other. Attestations are counted
///         per round of the case and accepted only while that round's evidence window is open; an attestor may
///         revise its attestation until a quorum forms, after which the round takes no further attestation. The
///         answer of a round is therefore the first quorum the panel forms inside the window, final as soon as it
///         exists, or UNDETERMINED, which the registry records only once the window has closed. A review opens a
///         new round with a fresh tally.
contract AttestorQuorumRule is IADRFEvidenceRule {
    struct Panel { address[] attestors; uint32 k; }

    IADRFDisputeRegistry public immutable registry;
    mapping(bytes32 => Panel) private _panels;
    mapping(bytes32 => mapping(address => T.Value)) private _attestations; // keccak(caseId, sq, round) => attestor => value

    event PanelRegistered(bytes32 indexed panelId, uint32 k, address[] attestors);
    event Attested(bytes32 indexed caseId, uint32 indexed subQuestion, address indexed attestor, uint32 round, T.Value value);

    error Rule_BadPanel();
    error Rule_NotAttestor(address account);
    error Rule_BadValue();
    error Rule_NotBound(bytes32 caseId, uint32 subQuestion);
    error Rule_WindowClosed(bytes32 caseId, uint64 evidenceCloseAt);
    error Rule_QuorumReached(bytes32 caseId, uint32 subQuestion, uint32 round);

    constructor(IADRFDisputeRegistry registry_) {
        registry = registry_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFEvidenceRule).interfaceId;
    }

    /// A panel must be a strict majority of distinct, non-zero attestors.
    function registerPanel(address[] calldata attestors, uint32 k) external returns (bytes32 panelId) {
        uint256 n = attestors.length;
        if (n == 0 || k == 0 || k > n || 2 * uint256(k) <= n) revert Rule_BadPanel();
        for (uint256 i = 0; i < n; i++) {
            if (attestors[i] == address(0)) revert Rule_BadPanel();
            for (uint256 j = i + 1; j < n; j++) if (attestors[j] == attestors[i]) revert Rule_BadPanel();
        }
        panelId = keccak256(abi.encode(attestors, k));
        if (_panels[panelId].k != 0) return panelId;
        for (uint256 i = 0; i < n; i++) _panels[panelId].attestors.push(attestors[i]);
        _panels[panelId].k = k;
        emit PanelRegistered(panelId, k, attestors);
    }

    function panelOf(bytes32 panelId) external view returns (address[] memory attestors, uint32 k) {
        return (_panels[panelId].attestors, _panels[panelId].k);
    }

    /// An attestor states what it accepts as true for a sub-question bound to this rule and to its panel, in the
    /// case's current round and while that round's evidence window is open. It may revise its attestation until a
    /// quorum forms; after that the round takes no further attestation.
    function attest(bytes32 panelId, bytes32 caseId, uint32 subQuestion, T.Value value) external {
        if (value == T.Value.UNDETERMINED) revert Rule_BadValue();
        if (!_isAttestor(panelId, msg.sender)) revert Rule_NotAttestor(msg.sender);
        T.SubQuestion memory q = registry.getSubQuestion(caseId, subQuestion);
        if (q.qType != T.QuestionType.EVIDENCED || q.method != address(this) || q.params != panelId) {
            revert Rule_NotBound(caseId, subQuestion);
        }
        T.CaseClock memory clock = registry.getClock(caseId);
        if (clock.admittedAt == 0 || block.timestamp > clock.evidenceCloseAt) revert Rule_WindowClosed(caseId, clock.evidenceCloseAt);
        bytes32 key = _key(caseId, subQuestion, clock.roundCount);
        Panel storage p = _panels[panelId];
        (uint32 yes, uint32 no) = _tally(p, key);
        if (yes >= p.k || no >= p.k) revert Rule_QuorumReached(caseId, subQuestion, clock.roundCount);
        _attestations[key][msg.sender] = value;
        emit Attested(caseId, subQuestion, msg.sender, clock.roundCount, value);
    }

    /// The answer for the case's current round: TRUE or FALSE once k attestors agree (final from then on),
    /// UNDETERMINED otherwise.
    function evaluate(bytes32 caseId, uint32 subQuestion, bytes32, bytes32 params, bytes calldata)
        external view returns (T.Value value, bytes32 resultHash, uint8 supportKinds)
    {
        Panel storage p = _panels[params];
        if (p.k == 0) return (T.Value.UNDETERMINED, bytes32(0), 0);
        uint32 round = registry.getClock(caseId).roundCount;
        (uint32 yes, uint32 no) = _tally(p, _key(caseId, subQuestion, round));
        if (yes >= p.k) value = T.Value.TRUE;
        else if (no >= p.k) value = T.Value.FALSE;
        else value = T.Value.UNDETERMINED;
        resultHash = keccak256(abi.encode(params, caseId, subQuestion, round, yes, no));
        supportKinds = T.SUPPORT_SIGNED | T.SUPPORT_EVIDENCED;
    }

    /// The attestations counted so far for a sub-question in a round.
    function tallyOf(bytes32 panelId, bytes32 caseId, uint32 subQuestion, uint32 round) external view returns (uint32 yes, uint32 no) {
        return _tally(_panels[panelId], _key(caseId, subQuestion, round));
    }

    function attestationOf(bytes32 caseId, uint32 subQuestion, uint32 round, address attestor) external view returns (T.Value) {
        return _attestations[_key(caseId, subQuestion, round)][attestor];
    }

    function _key(bytes32 caseId, uint32 subQuestion, uint32 round) private pure returns (bytes32) {
        return keccak256(abi.encode(caseId, subQuestion, round));
    }

    function _tally(Panel storage p, bytes32 key) private view returns (uint32 yes, uint32 no) {
        for (uint256 i = 0; i < p.attestors.length; i++) {
            T.Value v = _attestations[key][p.attestors[i]];
            if (v == T.Value.TRUE) yes++;
            else if (v == T.Value.FALSE) no++;
        }
    }

    function _isAttestor(bytes32 panelId, address who) private view returns (bool) {
        address[] storage xs = _panels[panelId].attestors;
        for (uint256 i = 0; i < xs.length; i++) if (xs[i] == who) return true;
        return false;
    }
}
