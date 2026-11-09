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
///            declared verifier). A leaf call that reverts, runs out of its gas bound, returns anything other
///            than exactly one 32-byte word, or returns a word outside the declared range is VERIFIER_ERROR
///            for that leaf only; the rest of the tree is still evaluated and composed;
///         4. composites combine their children with the four-valued allOf / anyOf rules.
/// @dev Leaf calls are made with a low-level `staticcall` and the raw return data is checked here. A typed
///      `try ... returns (uint8)` would not do: Solidity decodes the return value in the caller, so a verifier
///      that returns no data or a word above 255 would revert the whole evaluation instead of its own leaf.
///      Each leaf call is also bounded to `LEAF_GAS_LIMIT` gas, so that one leaf cannot consume the gas of
///      the whole evaluation.
contract AIFPCompositeVerifier is IAIFPCompositeVerifier, IERC165 {
    using AIFPPredicates for AIFPPredicates.Node[];

    error AIFP_MalformedPredicate();
    error AIFP_DepthExceeded();

    /// @notice Gas forwarded to one leaf call at most (the EVM further caps it at 63/64 of the gas left).
    uint256 public constant LEAF_GAS_LIMIT = 1_000_000;

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
        if (node.verifier == address(0)) return AIFPOutcomes.UNDETERMINABLE;
        if (node.verifier.code.length == 0) return AIFPOutcomes.VERIFIER_ERROR; // a declared verifier or set without code is a verifier fault
        if (node.kind == AIFPPredicates.ALLOWLIST) {
            (bool ok, uint256 contained) = _callLeaf(node.verifier, abi.encodeCall(IAIFPSubjectSet.contains, (subject)), 1);
            if (!ok) return AIFPOutcomes.VERIFIER_ERROR;
            return contained == 1 ? AIFPOutcomes.SATISFIED : AIFPOutcomes.NOT_SATISFIED;
        }
        // EXTERNAL and semantic kinds are delegated.
        bytes memory ev = index < evidence.length ? bytes(evidence[index]) : bytes("");
        (bool success, uint256 outcome) = _callLeaf(
            node.verifier,
            abi.encodeCall(IAIFPPredicateVerifier.verify, (channelId, subject, role, scopeRef, node.kind, node.ref, node.params, ev)),
            AIFPOutcomes.VERIFIER_ERROR
        );
        if (!success) return AIFPOutcomes.VERIFIER_ERROR;
        // The cast cannot truncate: _callLeaf has already rejected any word above VERIFIER_ERROR (3).
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(outcome);
    }

    /// @dev One bounded leaf call. Returns (false, 0) on a revert, on exhaustion of the gas bound, on return
    ///      data that is not exactly one word, or on a word above `maxValue`; otherwise (true, word).
    function _callLeaf(address target, bytes memory data, uint256 maxValue) internal view returns (bool, uint256) {
        (bool success, bytes memory ret) = target.staticcall{gas: LEAF_GAS_LIMIT}(data);
        if (!success || ret.length != 32) return (false, 0);
        uint256 word = abi.decode(ret, (uint256));
        if (word > maxValue) return (false, 0);
        return (true, word);
    }
}
