// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IAIFPCompositeVerifier, IAIFPPredicateVerifier, IAIFPSubjectSet} from "./interfaces/IAIFPPredicateVerifier.sol";
import {AIFPPredicates} from "./libraries/AIFPPredicates.sol";
import {AIFPOutcomes} from "./libraries/AIFPOutcomes.sol";

/// @title AIFPCompositeVerifier
/// @notice Reference evaluator of predicate trees. Order of evaluation, fixed by the paradigm:
///         1. the tree is decoded and checked for well-formedness (a malformed tree reverts: it is a caller
///            error, not an outcome);
///         2. every leaf kind is checked for support; one unsupported kind makes the whole predicate
///            UNDETERMINABLE before any composition;
///         3. leaves are evaluated (OPEN, ALLOWLIST natively; EXTERNAL and semantic kinds through the
///            declared verifier, a revert or out-of-range value becoming VERIFIER_ERROR);
///         4. composites combine their children with the four-valued allOf / anyOf rules.
contract AIFPCompositeVerifier is IAIFPCompositeVerifier, IERC165 {
    using AIFPPredicates for AIFPPredicates.Node[];

    error AIFP_MalformedPredicate();
    error AIFP_DepthExceeded();

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAIFPCompositeVerifier).interfaceId;
    }

    function supportsKind(uint8 kind) public pure returns (bool) {
        return kind <= AIFPPredicates.MAX_KNOWN_KIND;
    }

    function evaluate(
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        bytes calldata predicate,
        bytes[] calldata evidence
    ) external view returns (uint8) {
        AIFPPredicates.Node[] memory nodes = AIFPPredicates.decode(predicate);
        if (!nodes.isWellFormed()) revert AIFP_MalformedPredicate();
        for (uint256 i = 0; i < nodes.length; i++) {
            if (!supportsKind(nodes[i].kind)) return AIFPOutcomes.UNDETERMINABLE;
        }
        return _eval(nodes, 0, 0, channelId, subject, role, scopeRef, evidence);
    }

    function _eval(
        AIFPPredicates.Node[] memory nodes,
        uint256 index,
        uint256 depth,
        bytes32 channelId,
        bytes32 subject,
        uint16 role,
        bytes32 scopeRef,
        bytes[] calldata evidence
    ) internal view returns (uint8) {
        if (depth > AIFPPredicates.MAX_DEPTH) revert AIFP_DepthExceeded();
        AIFPPredicates.Node memory node = nodes[index];
        if (AIFPPredicates.isComposite(node.kind)) {
            uint8[] memory outcomes = new uint8[](node.childCount);
            for (uint256 c = 0; c < node.childCount; c++) {
                outcomes[c] = _eval(nodes, node.childStart + c, depth + 1, channelId, subject, role, scopeRef, evidence);
            }
            return node.kind == AIFPPredicates.ALL_OF ? AIFPOutcomes.allOf(outcomes) : AIFPOutcomes.anyOf(outcomes);
        }
        if (node.kind == AIFPPredicates.OPEN) return AIFPOutcomes.SATISFIED;
        bytes memory ev = index < evidence.length ? bytes(evidence[index]) : bytes("");
        if (node.kind == AIFPPredicates.ALLOWLIST) {
            if (node.verifier == address(0)) return AIFPOutcomes.UNDETERMINABLE;
            if (node.verifier.code.length == 0) return AIFPOutcomes.VERIFIER_ERROR; // a declared set without code is a verifier fault
            try IAIFPSubjectSet(node.verifier).contains(subject) returns (bool ok) {
                return ok ? AIFPOutcomes.SATISFIED : AIFPOutcomes.NOT_SATISFIED;
            } catch {
                return AIFPOutcomes.VERIFIER_ERROR;
            }
        }
        // EXTERNAL and semantic kinds are delegated.
        if (node.verifier == address(0)) return AIFPOutcomes.UNDETERMINABLE;
        if (node.verifier.code.length == 0) return AIFPOutcomes.VERIFIER_ERROR; // a declared verifier without code is a verifier fault
        try IAIFPPredicateVerifier(node.verifier).verify(channelId, subject, role, scopeRef, node.kind, node.ref, node.params, ev)
        returns (uint8 outcome) {
            return AIFPOutcomes.normalize(outcome);
        } catch {
            return AIFPOutcomes.VERIFIER_ERROR;
        }
    }
}
