// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {ASFTypes as T} from "../ASFTypes.sol";
import {ASFErrors} from "../ASFErrors.sol";
import {IASFBindingRegistry} from "../interfaces/IASFBindingRegistry.sol";
import {IASFSpecificationRegistry} from "../interfaces/IASFSpecificationRegistry.sol";
import {ASFEvaluation} from "./ASFEvaluation.sol";

/// @title  ASFLifecycle — the writes of the Safety Binding registry
/// @notice Holds `adopt` (Section 7, registry rules 1 to 6) and the transitions `suspend`, `resume` and `terminate`
///         (Section 8) together with the standing stops of Section 8.5. The registry links this library externally
///         and delegates the four writes to it with its own storage, for the same reason as `ASFEvaluation`: the registry's deployed code must stay below the
///         per-transaction gas cap of networks that meter code deposit heavily. `msg.sender` is the registry's
///         caller (DELEGATECALL), events are emitted by the registry, and the behaviour is the one the ERC states.
library ASFLifecycle {
    /// @dev Section 3.3: keccak256(abi.encode(chainId, bindingRegistry, adopter, subjectKey, scopeKey, specRegistry,
    ///      specId, version, salt)); `address(this)` is the registry, since the library runs through DELEGATECALL.
    function computeBindingId(address adopter, T.BindingInput calldata input) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                adopter,
                input.subjectKey,
                input.scopeKey,
                input.specRegistry,
                input.specId,
                input.version,
                input.salt
            )
        );
    }

    function adopt(T.Store storage s, T.BindingInput calldata input) external returns (bytes32 bindingId) {
        bindingId = computeBindingId(msg.sender, input);
        T.Binding storage b = s.bindings[bindingId];
        if (b.state != T.BindingState.None) revert ASFErrors.BindingExists();
        checkWindowAndPin(input);
        uint8 depth = derivedDepth(s, input);
        storeInterveners(s, bindingId, input.interveners);
        write(b, input, depth);
        s.bySubject[input.subjectKey][msg.sender].push(bindingId);
        s.byScope[input.scopeKey][msg.sender].push(bindingId);
        emit IASFBindingRegistry.BindingCreated(
            bindingId,
            msg.sender,
            input.subjectKey,
            input.scopeKey,
            input.specRegistry,
            input.specId,
            input.version,
            input.contentHash,
            input.parentBindingId
        );
        emit IASFBindingRegistry.BindingStateChanged(
            bindingId, T.BindingState.None, T.BindingState.Active, 0, bytes32(0), msg.sender, bytes32(0)
        );
    }

    /// @dev Validity window (validUntil exclusive, 0 = open-ended) and the pinned specification version: the
    ///      registry must be queryable and the content hash must match.
    function checkWindowAndPin(T.BindingInput calldata input) internal view {
        if (input.validUntil != 0) {
            if (input.validUntil <= block.timestamp) revert ASFErrors.InvalidValidity();
            if (input.validFrom != 0 && input.validUntil <= input.validFrom) revert ASFErrors.InvalidValidity();
        }
        if (!ASFEvaluation.supportsSpecRegistry(input.specRegistry)) revert ASFErrors.SpecRegistryNotSupported();
        bytes32 pinned;
        try IASFSpecificationRegistry(input.specRegistry).versionOf(input.specId, input.version) returns (
            T.SpecificationVersion memory got
        ) {
            pinned = got.contentHash;
        } catch {
            revert ASFErrors.UnknownVersion();
        }
        if (pinned == bytes32(0) || pinned != input.contentHash) revert ASFErrors.ContentHashMismatch();
    }

    /// @dev Derived binding (Section 9.1): same pinned version, window inside the parent's, bounded depth.
    function derivedDepth(T.Store storage s, T.BindingInput calldata input) internal view returns (uint8) {
        if (input.parentBindingId == bytes32(0)) return 0;
        T.Binding storage p = s.bindings[input.parentBindingId];
        if (p.state != T.BindingState.Active) revert ASFErrors.ParentNotActive();
        if (p.specRegistry != input.specRegistry || p.specId != input.specId || p.version != input.version) {
            revert ASFErrors.ParentMismatch();
        }
        if (p.validUntil != 0 && (input.validUntil == 0 || input.validUntil > p.validUntil)) {
            revert ASFErrors.ParentWindowExceeded();
        }
        if (p.depth >= T.MAX_DEPTH) revert ASFErrors.DepthExceeded();
        return p.depth + 1;
    }

    /// @dev Interveners (registry rule 5): non-zero, not the adopter, no duplicates, rights in range, at most sixteen.
    function storeInterveners(T.Store storage s, bytes32 bindingId, T.Intervener[] calldata list) internal {
        uint256 n = list.length;
        if (n > T.MAX_INTERVENERS) revert ASFErrors.TooManyInterveners();
        for (uint256 i = 0; i < n; i++) {
            T.Intervener calldata iv = list[i];
            if (iv.account == address(0)) revert ASFErrors.ZeroIntervener();
            if (iv.account == msg.sender) revert ASFErrors.DuplicateIntervener();
            if (iv.rights == 0 || iv.rights > T.RIGHT_ALL) revert ASFErrors.InvalidRights();
            if (s.rights[bindingId][iv.account] != 0) revert ASFErrors.DuplicateIntervener();
            s.rights[bindingId][iv.account] = iv.rights;
            s.interveners[bindingId].push(iv);
        }
    }

    function write(T.Binding storage b, T.BindingInput calldata input, uint8 depth) internal {
        b.adopter = msg.sender;
        b.subjectKey = input.subjectKey;
        b.scopeKey = input.scopeKey;
        b.specRegistry = input.specRegistry;
        b.specId = input.specId;
        b.version = input.version;
        b.contentHash = input.contentHash;
        b.paramsHash = input.paramsHash;
        b.paramsLocator = input.paramsLocator;
        b.authorityRef = input.authorityRef;
        b.enforcement = input.enforcement;
        b.validFrom = input.validFrom;
        b.validUntil = input.validUntil;
        b.parentBindingId = input.parentBindingId;
        b.depth = depth;
        b.createdAt = uint64(block.timestamp);
        b.stateChangedAt = uint64(block.timestamp);
        b.state = T.BindingState.Active;
    }

    /// @dev The rights of `account` on a binding: the adopter holds all three; others what the binding granted.
    function rightsOf(T.Store storage s, bytes32 bindingId, address account) internal view returns (uint8) {
        T.Binding storage b = s.bindings[bindingId];
        if (b.state == T.BindingState.None) return 0;
        if (account == b.adopter) return T.RIGHT_ALL;
        return s.rights[bindingId][account];
    }

    function suspend(T.Store storage s, bytes32 bindingId, uint8 restrictions, bytes32 responseRef, bytes32 reasonRef)
        external
    {
        T.Binding storage b = existing(s, bindingId);
        if (b.state != T.BindingState.Active) revert ASFErrors.InvalidState();
        if (restrictions == 0 || restrictions > T.RESTRICT_ALL) revert ASFErrors.InvalidRestriction();
        if (rightsOf(s, bindingId, msg.sender) & T.RIGHT_SUSPEND == 0) revert ASFErrors.NotAuthorized();
        b.state = T.BindingState.Suspended;
        b.restrictions = restrictions;
        b.responseRef = responseRef;
        b.suspendedBy = msg.sender;
        b.stateChangedAt = uint64(block.timestamp);
        // an intervener's suspension is also a standing stop against the adopter for the subject and the
        // specification: it is not escaped by holding or creating another binding (Section 8.5)
        if (msg.sender != b.adopter) {
            s.stops[stopKeyOf(b, msg.sender)] = T.Stop({
                bindingId: bindingId, restrictions: restrictions, responseRef: responseRef, since: uint64(block.timestamp)
            });
        }
        emit IASFBindingRegistry.BindingStateChanged(
            bindingId, T.BindingState.Active, T.BindingState.Suspended, restrictions, responseRef, msg.sender, reasonRef
        );
    }

    function resume(T.Store storage s, bytes32 bindingId, bytes32 reasonRef) external {
        T.Binding storage b = existing(s, bindingId);
        if (b.state == T.BindingState.Terminated) {
            // a terminated record cannot become Active again, but a standing stop recorded through it can be
            // lifted, under the same rights as a resumption
            requireResumeRight(s, bindingId, b);
            bytes32 key = stopKeyOf(b, b.suspendedBy);
            if (b.suspendedBy == b.adopter || s.stops[key].bindingId != bindingId) revert ASFErrors.InvalidState();
            delete s.stops[key];
            emit IASFBindingRegistry.StopLifted(bindingId, b.suspendedBy, msg.sender, reasonRef);
            return;
        }
        if (b.state != T.BindingState.Suspended) revert ASFErrors.InvalidState();
        requireResumeRight(s, bindingId, b);
        if (b.suspendedBy != b.adopter) {
            bytes32 key = stopKeyOf(b, b.suspendedBy);
            if (s.stops[key].bindingId == bindingId) delete s.stops[key];
        }
        b.state = T.BindingState.Active;
        b.restrictions = 0;
        b.responseRef = bytes32(0);
        b.suspendedBy = address(0);
        b.stateChangedAt = uint64(block.timestamp);
        emit IASFBindingRegistry.BindingStateChanged(
            bindingId, T.BindingState.Suspended, T.BindingState.Active, 0, bytes32(0), msg.sender, reasonRef
        );
    }

    function terminate(T.Store storage s, bytes32 bindingId, bytes32 reasonRef) external {
        T.Binding storage b = existing(s, bindingId);
        if (b.state == T.BindingState.Terminated) revert ASFErrors.InvalidState();
        if (rightsOf(s, bindingId, msg.sender) & T.RIGHT_TERMINATE == 0) revert ASFErrors.NotAuthorized();
        T.BindingState previous = b.state;
        // the suspension fields are kept: a terminated record shows the stop it carried, and a standing stop
        // recorded through it stands until lifted (Section 8.5)
        b.state = T.BindingState.Terminated;
        b.stateChangedAt = uint64(block.timestamp);
        emit IASFBindingRegistry.BindingStateChanged(
            bindingId, previous, T.BindingState.Terminated, 0, bytes32(0), msg.sender, reasonRef
        );
    }

    /// @dev Resume rights: RIGHT_RESUME on the binding, and an intervener's suspension is not the adopter's to lift.
    function requireResumeRight(T.Store storage s, bytes32 bindingId, T.Binding storage b) internal view {
        if (rightsOf(s, bindingId, msg.sender) & T.RIGHT_RESUME == 0) revert ASFErrors.NotAuthorized();
        if (b.suspendedBy != b.adopter && msg.sender == b.adopter) revert ASFErrors.NotAuthorized();
    }

    function existing(T.Store storage s, bytes32 bindingId) internal view returns (T.Binding storage b) {
        b = s.bindings[bindingId];
        if (b.state == T.BindingState.None) revert ASFErrors.UnknownBinding();
    }

    function stopKeyOf(T.Binding storage b, address intervener) internal view returns (bytes32) {
        return T.stopKey(b.adopter, b.subjectKey, b.specRegistry, b.specId, intervener);
    }
}
