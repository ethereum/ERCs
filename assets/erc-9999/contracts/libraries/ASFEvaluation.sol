// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes as T} from "../ASFTypes.sol";
import {ASFErrors} from "../ASFErrors.sol";
import {IASFSpecificationRegistry} from "../interfaces/IASFSpecificationRegistry.sol";

interface IERC165Probe {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title  ASFEvaluation — the registry-level check of the Safety Binding registry
/// @notice Holds the evaluation of one binding against one clause (Section 10.1 of the ERC), the combinators
///         (Section 10.3), the requirement validation (Section 10.4) and the response-set rule over a derivation
///         chain. The registry links this library externally and delegates `check` and `checkBinding` to it
///         with its own storage, so that the registry's deployed code stays below the per-transaction gas cap of
///         networks that meter code deposit heavily; the registry's ABI and behaviour are unchanged by the split.
///         The library reads the registry's storage through `T.Store` and never writes.
library ASFEvaluation {
    // ---------------------------------------------------------------------------- validation

    function validateClause(T.Clause memory clause) internal pure {
        if (clause.specRegistry == address(0) || clause.specId == bytes32(0)) revert ASFErrors.InvalidRequirement();
        for (uint256 i = 0; i < clause.interveners.length; i++) {
            T.Intervener memory iv = clause.interveners[i];
            if (iv.account == address(0) || iv.rights == 0 || iv.rights > T.RIGHT_ALL) revert ASFErrors.InvalidRequirement();
        }
    }

    function validateRequirement(T.RequirementSet memory requirement) internal pure {
        uint256 n = requirement.clauses.length;
        if (n == 0) revert ASFErrors.InvalidRequirement();
        if (requirement.combinator == T.Combinator.KOf) {
            if (requirement.k == 0 || requirement.k > n) revert ASFErrors.InvalidRequirement();
        } else if (requirement.k != 0) {
            revert ASFErrors.InvalidRequirement();
        }
        for (uint256 i = 0; i < n; i++) validateClause(requirement.clauses[i]);
    }

    /// @dev Calldata variant used by the registry's `requirementId`, which hashes the calldata struct directly.
    function validateRequirementCalldata(T.RequirementSet calldata requirement) internal pure {
        uint256 n = requirement.clauses.length;
        if (n == 0) revert ASFErrors.InvalidRequirement();
        if (requirement.combinator == T.Combinator.KOf) {
            if (requirement.k == 0 || requirement.k > n) revert ASFErrors.InvalidRequirement();
        } else if (requirement.k != 0) {
            revert ASFErrors.InvalidRequirement();
        }
        for (uint256 i = 0; i < n; i++) {
            T.Clause calldata c = requirement.clauses[i];
            if (c.specRegistry == address(0) || c.specId == bytes32(0)) revert ASFErrors.InvalidRequirement();
            for (uint256 j = 0; j < c.interveners.length; j++) {
                T.Intervener calldata iv = c.interveners[j];
                if (iv.account == address(0) || iv.rights == 0 || iv.rights > T.RIGHT_ALL) revert ASFErrors.InvalidRequirement();
            }
        }
    }

    /// @dev True when `specRegistry` has code and reports the Specification Registry interface.
    function supportsSpecRegistry(address specRegistry) internal view returns (bool) {
        if (specRegistry.code.length == 0) return false;
        try IERC165Probe(specRegistry).supportsInterface(type(IASFSpecificationRegistry).interfaceId) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    // -------------------------------------------------------------------- external entry points

    /// @notice `checkBinding(bindingId, clause)`; `args` is the ABI-encoded argument tuple (the registry forwards
    ///         its calldata without the selector).
    function checkBinding(T.Store storage s, bytes calldata args)
        external view returns (T.Verdict verdict, T.Reason reason, uint8 restrictions)
    {
        (bytes32 bindingId, T.Clause memory clause) = abi.decode(args, (bytes32, T.Clause));
        validateClause(clause);
        return evaluate(s, bindingId, clause);
    }

    /// @notice `check(requirement, bindingIds)`; `args` as above.
    function check(T.Store storage s, bytes calldata args)
        external view returns (T.Verdict verdict, T.Reason[] memory reasons, uint8[] memory restrictions)
    {
        (T.RequirementSet memory requirement, bytes32[] memory bindingIds) = abi.decode(args, (T.RequirementSet, bytes32[]));
        validateRequirement(requirement);
        uint256 n = requirement.clauses.length;
        if (bindingIds.length != n) revert ASFErrors.LengthMismatch();
        reasons = new T.Reason[](n);
        restrictions = new uint8[](n);
        uint256 satisfied;
        uint256 unknown;
        for (uint256 i = 0; i < n; i++) {
            (T.Verdict v, T.Reason r, uint8 x) = evaluate(s, bindingIds[i], requirement.clauses[i]);
            reasons[i] = r;
            restrictions[i] = x;
            if (v == T.Verdict.Satisfied) satisfied++;
            else if (v == T.Verdict.Unknown) unknown++;
        }
        if (requirement.combinator == T.Combinator.All) {
            if (satisfied == n) verdict = T.Verdict.Satisfied;
            else if (satisfied + unknown == n) verdict = T.Verdict.Unknown;
            else verdict = T.Verdict.NotSatisfied;
        } else {
            uint256 k = requirement.combinator == T.Combinator.Any ? 1 : requirement.k;
            if (satisfied >= k) verdict = T.Verdict.Satisfied;
            else if (satisfied + unknown >= k) verdict = T.Verdict.Unknown;
            else verdict = T.Verdict.NotSatisfied;
        }
    }

    // ------------------------------------------------------------------------------ evaluation

    function inWindow(T.Binding storage b) internal view returns (bool notYet, bool expired) {
        uint64 from = b.validFrom > b.createdAt ? b.validFrom : b.createdAt;
        notYet = block.timestamp < from;
        expired = b.validUntil != 0 && block.timestamp >= b.validUntil;
    }

    /// @dev The response set in force for a binding: the union of the sets of every suspended record among the
    ///      binding and its ancestors, or empty when any record in that chain is terminated or outside its window
    ///      (a chain that is not in force keeps no path open). `broken` is true when some ancestor is not Active
    ///      or outside its window.
    function chainSets(T.Store storage s, T.Binding storage b) internal view returns (uint8 union, bool broken) {
        bool dead;
        if (b.state == T.BindingState.Suspended) union = b.restrictions;
        if (b.state == T.BindingState.Terminated) dead = true;
        (bool notYet, bool expired) = inWindow(b);
        if (notYet || expired) dead = true;
        bytes32 pid = b.parentBindingId;
        while (pid != bytes32(0)) {
            T.Binding storage p = s.bindings[pid];
            if (p.state == T.BindingState.Suspended) {
                union |= p.restrictions;
                broken = true;
            } else if (p.state != T.BindingState.Active) {
                dead = true;
                broken = true;
            }
            (bool pNotYet, bool pExpired) = inWindow(p);
            if (pNotYet || pExpired) {
                dead = true;
                broken = true;
            }
            pid = p.parentBindingId;
        }
        if (dead) union = 0;
    }

    /// @dev True when every intervener of the binding that holds RIGHT_RESUME is named by the clause.
    function resumeClosed(T.Store storage s, bytes32 bindingId, T.Clause memory clause) internal view returns (bool) {
        T.Intervener[] storage list = s.interveners[bindingId];
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i].rights & T.RIGHT_RESUME == 0) continue;
            bool named;
            for (uint256 j = 0; j < clause.interveners.length; j++) {
                if (clause.interveners[j].account == list[i].account) { named = true; break; }
            }
            if (!named) return false;
        }
        return true;
    }

    /// @dev Section 10.1: the first failing reason in evaluation order, with the response set in force.
    function evaluate(T.Store storage s, bytes32 bindingId, T.Clause memory clause)
        internal view returns (T.Verdict, T.Reason, uint8)
    {
        if (bindingId == bytes32(0)) return (T.Verdict.NotSatisfied, T.Reason.NoBinding, 0);
        T.Binding storage b = s.bindings[bindingId];
        if (b.state == T.BindingState.None) return (T.Verdict.NotSatisfied, T.Reason.NoBinding, 0);
        if (b.state == T.BindingState.Terminated) return (T.Verdict.NotSatisfied, T.Reason.Terminated, 0);
        if (b.state == T.BindingState.Suspended) {
            (uint8 own,) = chainSets(s, b);
            return (T.Verdict.NotSatisfied, T.Reason.Suspended, own);
        }
        (bool notYet, bool expired) = inWindow(b);
        if (notYet) return (T.Verdict.NotSatisfied, T.Reason.NotYetValid, 0);
        if (expired) return (T.Verdict.NotSatisfied, T.Reason.Expired, 0);
        if (clause.specRegistry != b.specRegistry || clause.specId != b.specId) {
            return (T.Verdict.NotSatisfied, T.Reason.SpecMismatch, 0);
        }
        if (clause.versions.length != 0) {
            bool found;
            for (uint256 i = 0; i < clause.versions.length; i++) {
                if (clause.versions[i] == b.version) { found = true; break; }
            }
            if (!found) return (T.Verdict.NotSatisfied, T.Reason.VersionMismatch, 0);
        }
        if (clause.adopter != address(0) && clause.adopter != b.adopter) {
            return (T.Verdict.NotSatisfied, T.Reason.AdopterMismatch, 0);
        }
        if (clause.subjectKey != bytes32(0) && clause.subjectKey != b.subjectKey) {
            return (T.Verdict.NotSatisfied, T.Reason.SubjectMismatch, 0);
        }
        if (clause.scopeKey != bytes32(0) && clause.scopeKey != b.scopeKey) {
            return (T.Verdict.NotSatisfied, T.Reason.ScopeMismatch, 0);
        }
        if (clause.enforcement & b.enforcement != clause.enforcement) {
            return (T.Verdict.NotSatisfied, T.Reason.EnforcementMismatch, 0);
        }
        // required interveners: every named account must hold at least the required rights on this binding, and
        // when a clause names interveners it also closes the resume right: no account the clause does not name may
        // hold RIGHT_RESUME, otherwise the adopter could lift any intervener's suspension through an account of its own
        if (clause.interveners.length != 0) {
            for (uint256 i = 0; i < clause.interveners.length; i++) {
                T.Intervener memory req = clause.interveners[i];
                if (s.rights[bindingId][req.account] & req.rights != req.rights) {
                    return (T.Verdict.NotSatisfied, T.Reason.IntervenerMismatch, 0);
                }
            }
            if (!resumeClosed(s, bindingId, clause)) return (T.Verdict.NotSatisfied, T.Reason.IntervenerMismatch, 0);
        }
        // ancestors: every binding this one is derived from must itself be satisfied now
        (uint8 sets, bool broken) = chainSets(s, b);
        if (broken) return (T.Verdict.NotSatisfied, T.Reason.ParentNotSatisfied, sets);
        // the pinned specification registry must still be queryable; a dependency failure is Unknown, never a pass
        if (!supportsSpecRegistry(b.specRegistry)) {
            return (T.Verdict.Unknown, T.Reason.SpecRegistryUnavailable, 0);
        }
        return (T.Verdict.Satisfied, T.Reason.None, 0);
    }
}
