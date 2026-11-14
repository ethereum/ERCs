// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IAIFPCompositeVerifier, IAIFPPredicateVerifier, IAIFPSubjectSet} from "./interfaces/IAIFPPredicateVerifier.sol";
import {AIFPPredicates} from "./libraries/AIFPPredicates.sol";
import {AIFPOutcomes} from "./libraries/AIFPOutcomes.sol";
import {AIFPCalls} from "./libraries/AIFPCalls.sol";

/// @title AIFPCompositeVerifier
/// @notice Reference evaluator of predicate trees. Order of evaluation, fixed by the paradigm:
///         1. the node array is decoded (bytes that do not decode revert);
///         2. every node kind is checked for support; one unsupported kind makes the whole predicate
///            UNDETERMINABLE before anything else is judged - a verifier cannot tell whether an array is a
///            tree when it does not know whether one of its kinds has children;
///         3. the array is checked for well-formedness - a tree of at most 64 nodes and depth 8 (a malformed
///            predicate reverts: it is a caller error, not an outcome);
///         4. the children of a composite are evaluated in index order (OPEN, ALLOWLIST natively; EXTERNAL
///            and semantic kinds through the declared verifier). A leaf call that reverts, does not complete
///            within the gas bound, returns anything other than exactly one 32-byte word, or returns a word
///            outside the declared range is VERIFIER_ERROR for that leaf only;
///         5. composites combine their children with the four-valued allOf / anyOf rules. An `anyOf` stops at
///            its first SATISFIED child and an `allOf` at its first NOT_SATISFIED child: those answers decide
///            the composite whatever the remaining children would answer, so the remaining children are not
///            evaluated and their leaves are not called.
/// @dev Three properties of a leaf call, each of which a typed `try ... returns (uint8)` would not give:
///      - the raw return data is judged here. Solidity decodes a typed return value in the caller, so a
///        verifier that returns no data or a word above 255 would revert the whole evaluation instead of its
///        own leaf;
///      - at most 32 bytes of return data are copied (`AIFPCalls.staticcallWord`), so a leaf cannot make this
///        contract pay for a large return buffer that its own gas bound does not cover;
///      - every leaf that is called is given exactly `leafGasLimit()` gas, whatever gas the caller of
///        `evaluate` supplied. When that amount cannot be forwarded in full the evaluation reverts with
///        `AIFP_InsufficientGas` and reports no outcome: an outcome must not depend on the caller's gas, and a
///        leaf that was given less than the bound has not been shown to be faulty.
///      Two things about a transaction still reach a leaf, and no composite verifier can remove them. What a
///      leaf *needs* is not constant: state access is cheaper for accounts and storage slots already touched
///      in the transaction, so a leaf whose cost is close to the bound can complete in one transaction and
///      not in another; a leaf verifier has to fit the bound from a cold start for its answer to be the same
///      everywhere. And the sender of a transaction is charged its gas limit times the gas price before
///      execution, so a leaf that reads the native balance of the sending account sees a balance that depends
///      on the gas limit.
contract AIFPCompositeVerifier is IAIFPCompositeVerifier, IERC165 {
    using AIFPPredicates for AIFPPredicates.Node[];

    error AIFP_MalformedPredicate();

    /// @dev What a leaf is asked about; constant for one evaluation.
    struct Question {
        bytes32 channelId;
        bytes32 subject;
        uint16 role;
        bytes32 scopeRef;
    }

    uint256 internal constant LEAF_GAS_LIMIT = 1_000_000;

    /// @dev Gas kept, on top of `LEAF_GAS_LIMIT * 64 / 63`, for the leaf call itself when checking that the
    ///      bound can be forwarded in full. The call costs 100 gas here, because `_eval` has already read the
    ///      target's code size; the margin would also cover a cold account (2,600) with a cold EIP-7702
    ///      delegate (2,600) and the opcodes between the check and the call.
    uint256 internal constant LEAF_CALL_MARGIN = 10_000;

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAIFPCompositeVerifier).interfaceId;
    }

    function supportsKind(uint8 kind) public pure returns (bool) {
        return kind <= AIFPPredicates.MAX_KNOWN_KIND;
    }

    /// @notice Gas given to every leaf call: exactly this amount, never less and never more.
    function leafGasLimit() public pure returns (uint256) {
        return LEAF_GAS_LIMIT;
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
        // Kinds first: an array that uses a kind this verifier does not know cannot be judged at all, not
        // even for well-formedness, since the unknown kind may be one that has children.
        for (uint256 i = 0; i < nodes.length; i++) {
            if (!supportsKind(nodes[i].kind)) return AIFPOutcomes.UNDETERMINABLE;
        }
        if (!nodes.isWellFormed()) revert AIFP_MalformedPredicate();
        Question memory q = Question({channelId: channelId, subject: subject, role: role, scopeRef: scopeRef});
        return _eval(nodes, 0, q, evidence);
    }

    /// @dev The recursion is at most `AIFPPredicates.MAX_DEPTH` deep and visits each node at most once:
    ///      `isWellFormed` has checked the depth of every node and that the array is a tree.
    function _eval(AIFPPredicates.Node[] memory nodes, uint256 index, Question memory q, bytes[] calldata evidence)
        internal
        view
        returns (uint8)
    {
        AIFPPredicates.Node memory node = nodes[index];
        if (AIFPPredicates.isComposite(node.kind)) {
            // NOT_SATISFIED decides an allOf and SATISFIED decides an anyOf (AIFPOutcomes): stop there.
            uint8 deciding = node.kind == AIFPPredicates.ALL_OF ? AIFPOutcomes.NOT_SATISFIED : AIFPOutcomes.SATISFIED;
            bool undeterminable;
            bool verifierError;
            for (uint256 c = 0; c < node.childCount; c++) {
                uint8 outcome = _eval(nodes, node.childStart + c, q, evidence);
                if (outcome == deciding) return deciding;
                if (outcome == AIFPOutcomes.UNDETERMINABLE) undeterminable = true;
                else if (outcome == AIFPOutcomes.VERIFIER_ERROR) verifierError = true;
            }
            if (undeterminable) return AIFPOutcomes.UNDETERMINABLE;
            if (verifierError) return AIFPOutcomes.VERIFIER_ERROR;
            // Every child gave the other definite answer.
            return deciding == AIFPOutcomes.SATISFIED ? AIFPOutcomes.NOT_SATISFIED : AIFPOutcomes.SATISFIED;
        }
        if (node.kind == AIFPPredicates.OPEN) return AIFPOutcomes.SATISFIED;
        if (node.verifier == address(0)) return AIFPOutcomes.UNDETERMINABLE;
        if (node.verifier.code.length == 0) return AIFPOutcomes.VERIFIER_ERROR; // a declared verifier or set without code is a verifier fault
        if (node.kind == AIFPPredicates.ALLOWLIST) {
            (bool ok, uint256 contained) = _callLeaf(node.verifier, abi.encodeCall(IAIFPSubjectSet.contains, (q.subject)), 1);
            if (!ok) return AIFPOutcomes.VERIFIER_ERROR;
            return contained == 1 ? AIFPOutcomes.SATISFIED : AIFPOutcomes.NOT_SATISFIED;
        }
        // EXTERNAL and semantic kinds are delegated.
        bytes memory ev = index < evidence.length ? bytes(evidence[index]) : bytes("");
        (bool success, uint256 answer) = _callLeaf(
            node.verifier,
            abi.encodeCall(IAIFPPredicateVerifier.verify, (q.channelId, q.subject, q.role, q.scopeRef, node.kind, node.ref, node.params, ev)),
            AIFPOutcomes.VERIFIER_ERROR
        );
        if (!success) return AIFPOutcomes.VERIFIER_ERROR;
        // The cast cannot truncate: _callLeaf has already rejected any word above VERIFIER_ERROR (3).
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint8(answer);
    }

    /// @dev One leaf call with exactly `LEAF_GAS_LIMIT` gas. Reverts with `AIFP_InsufficientGas` when that
    ///      amount cannot be forwarded in full. Returns (false, 0) when the leaf reverts, does not complete
    ///      within the bound, returns data that is not exactly one word, or returns a word above `maxValue`;
    ///      otherwise (true, word). The caller has read `target.code.length`, so the account is warm here.
    function _callLeaf(address target, bytes memory data, uint256 maxValue) internal view returns (bool, uint256) {
        if (!AIFPCalls.hasGasFor(LEAF_GAS_LIMIT, LEAF_CALL_MARGIN)) revert AIFP_InsufficientGas();
        (bool success, uint256 size, bytes32 word) = AIFPCalls.staticcallWord(target, data, LEAF_GAS_LIMIT);
        if (!success || size != 32 || uint256(word) > maxValue) return (false, 0);
        return (true, uint256(word));
    }
}
