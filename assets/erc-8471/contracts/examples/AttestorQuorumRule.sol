// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFEvidenceRule} from "../interfaces/IADRFEvidenceRule.sol";

/// @title  AttestorQuorumRule — EVIDENCED method: an external fact accepted on k-of-n attestations
/// @notice A panel of attestors (registered with its threshold; the panel id is the method parameter) attests
///         TRUE or FALSE to a sub-question of a case. `evaluate` accepts the fact when k attestors agree; the
///         finding carries SUPPORT_SIGNED | SUPPORT_EVIDENCED: the fact was accepted on the stated attestations
///         and the trust assumption that the panel is honest, nothing more. Evidence integrity (what was
///         attested) and availability (what the attestors saw) are the panel's business, not the kernel's.
contract AttestorQuorumRule is IADRFEvidenceRule {
    struct Panel { address[] attestors; uint32 k; }

    mapping(bytes32 => Panel) private _panels;
    mapping(bytes32 => mapping(address => T.Value)) private _attestations; // keccak(caseId, sq) => attestor => value

    event PanelRegistered(bytes32 indexed panelId, uint32 k, address[] attestors);
    event Attested(bytes32 indexed caseId, uint32 indexed subQuestion, address indexed attestor, T.Value value);

    error Rule_BadPanel();
    error Rule_NotAttestor(address account);
    error Rule_BadValue();

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFEvidenceRule).interfaceId;
    }

    function registerPanel(address[] calldata attestors, uint32 k) external returns (bytes32 panelId) {
        if (attestors.length == 0 || k == 0 || k > attestors.length) revert Rule_BadPanel();
        panelId = keccak256(abi.encode(attestors, k));
        if (_panels[panelId].k != 0) return panelId;
        for (uint256 i = 0; i < attestors.length; i++) {
            if (attestors[i] == address(0)) revert Rule_BadPanel();
            _panels[panelId].attestors.push(attestors[i]);
        }
        _panels[panelId].k = k;
        emit PanelRegistered(panelId, k, attestors);
    }

    function panelOf(bytes32 panelId) external view returns (address[] memory attestors, uint32 k) {
        return (_panels[panelId].attestors, _panels[panelId].k);
    }

    /// An attestor states what it accepts as true for the sub-question. A later attestation replaces an earlier one.
    function attest(bytes32 panelId, bytes32 caseId, uint32 subQuestion, T.Value value) external {
        if (value == T.Value.UNDETERMINED) revert Rule_BadValue();
        if (!_isAttestor(panelId, msg.sender)) revert Rule_NotAttestor(msg.sender);
        _attestations[keccak256(abi.encode(caseId, subQuestion))][msg.sender] = value;
        emit Attested(caseId, subQuestion, msg.sender, value);
    }

    function evaluate(bytes32 caseId, uint32 subQuestion, bytes32, bytes32 params, bytes calldata)
        external view returns (T.Value value, bytes32 resultHash, uint8 supportKinds)
    {
        Panel storage p = _panels[params];
        if (p.k == 0) return (T.Value.UNDETERMINED, bytes32(0), 0);
        bytes32 key = keccak256(abi.encode(caseId, subQuestion));
        uint32 yes;
        uint32 no;
        for (uint256 i = 0; i < p.attestors.length; i++) {
            T.Value v = _attestations[key][p.attestors[i]];
            if (v == T.Value.TRUE) yes++;
            else if (v == T.Value.FALSE) no++;
        }
        if (yes >= p.k) value = T.Value.TRUE;
        else if (no >= p.k) value = T.Value.FALSE;
        else value = T.Value.UNDETERMINED;
        resultHash = keccak256(abi.encode(params, caseId, subQuestion, yes, no));
        supportKinds = T.SUPPORT_SIGNED | T.SUPPORT_EVIDENCED;
    }

    function _isAttestor(bytes32 panelId, address who) private view returns (bool) {
        address[] storage xs = _panels[panelId].attestors;
        for (uint256 i = 0; i < xs.length; i++) if (xs[i] == who) return true;
        return false;
    }
}
