// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC165} from "./interfaces/IERC165.sol";
import {IAIFPEventAnchor} from "./interfaces/IAIFPEventAnchor.sol";
import {IAIFPChannelRegistry} from "./interfaces/IAIFPChannelRegistry.sol";
import {IAIFPParticipationRegistry} from "./interfaces/IAIFPParticipationRegistry.sol";
import {IERC6372} from "./interfaces/IERC6372.sol";
import {AIFPEvents} from "./libraries/AIFPEvents.sol";
import {AIFPRoles} from "./libraries/AIFPRoles.sol";
import {AIFPOutcomes} from "./libraries/AIFPOutcomes.sol";
import {AIFPSubject} from "./libraries/AIFPSubject.sol";

/// @title AIFPEventAnchor
/// @notice Reference implementation of the optional event-anchor profile. The anchor checks, at the
///         registry clock, that the actor holds the role the action needs; it records the rule version in
///         force and the role binding that satisfied the check; supersede and retract are accepted only from
///         the subject that anchored the target object. A forward keeps the object reference unchanged; a
///         derivation anchors a new object that points back to its source. Anchoring proves a declaration
///         at a time, not delivery or truth.
/// @dev The role check is a decision taken when the transaction executes. The record keeps the binding it
///      relied on because that decision cannot always be recomputed afterwards: a binding revoked or
///      suspended later within the same timepoint no longer evaluates as SATISFIED at that timepoint.
contract AIFPEventAnchor is IAIFPEventAnchor, IERC165 {
    IAIFPChannelRegistry public immutable channelRegistry;
    IAIFPParticipationRegistry public immutable participationRegistry;

    /// @dev Stored form of an `EventRecord`: the same fields, ordered so that `at` and `action` share a slot.
    struct StoredRecord {
        bytes32 channelId;
        bytes32 subject;
        bytes32 objectRef;
        bytes32 ruleVersion;
        bytes32 bindingId;
        uint48 at;
        uint8 action;
    }

    StoredRecord[] private _records;
    mapping(bytes32 => bytes32) private _anchoredBy; // objectRef => subject
    mapping(bytes32 => bytes32) private _anchoredIn; // objectRef => channelId

    error AIFP_InvalidAction(uint8 action);
    error AIFP_InvalidRelation(uint8 kind);
    error AIFP_MissingRelation(uint8 action, uint8 requiredKind);

    constructor(IAIFPChannelRegistry channelRegistry_, IAIFPParticipationRegistry participationRegistry_) {
        channelRegistry = channelRegistry_;
        participationRegistry = participationRegistry_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAIFPEventAnchor).interfaceId;
    }

    function anchor(bytes32 channelId, uint8 action, bytes32 objectRef, Relation[] calldata relations)
        external
        returns (uint256 recordIndex)
    {
        if (action > AIFPEvents.MAX_ACTION) revert AIFP_InvalidAction(action);
        bytes32 subject = AIFPSubject.self(msg.sender);
        uint48 now_ = IERC6372(address(channelRegistry)).clock();
        uint16 role = _roleFor(action);
        // The role is checked for the whole channel (scope zero), at the current clock value.
        (uint8 outcome, bytes32 bindingId) = participationRegistry.evaluateWithBinding(channelId, subject, role, bytes32(0), now_);
        if (outcome != AIFPOutcomes.SATISFIED) revert AIFP_RoleNotHeld(channelId, subject, role, outcome);
        if (action == AIFPEvents.ACTION_FORWARD) {
            // The same object enters another context: it must already be anchored and keeps its reference.
            if (_anchoredBy[objectRef] == bytes32(0)) revert AIFP_NotAnchoredBySubject(objectRef, bytes32(0));
            _requireRelation(relations, AIFPEvents.REL_FORWARDS, action);
        } else {
            if (_anchoredBy[objectRef] != bytes32(0)) revert AIFP_ObjectAlreadyAnchored(objectRef);
            _anchoredBy[objectRef] = subject;
            _anchoredIn[objectRef] = channelId;
        }
        if (action == AIFPEvents.ACTION_DERIVE) _requireRelation(relations, AIFPEvents.REL_DERIVES_FROM, action);
        if (action == AIFPEvents.ACTION_SYNTHESIZE) _requireRelation(relations, AIFPEvents.REL_SYNTHESIZES, action);
        if (action == AIFPEvents.ACTION_SUPERSEDE) _requireOwnTarget(relations, AIFPEvents.REL_SUPERSEDES, subject, action);
        if (action == AIFPEvents.ACTION_RETRACT) _requireOwnTarget(relations, AIFPEvents.REL_RETRACTS, subject, action);

        bytes32 ruleVersion = channelRegistry.paradigmAt(channelId, now_);
        _records.push(
            StoredRecord({
                channelId: channelId,
                subject: subject,
                objectRef: objectRef,
                ruleVersion: ruleVersion,
                bindingId: bindingId,
                at: now_,
                action: action
            })
        );
        recordIndex = _records.length - 1;
        // Between the role check above and this log the anchor makes no call that can change state
        // (`paradigmAt` is a view, called statically), so no other contract can record anything in between:
        // the position of this log in the chain is the position at which the action was accepted.
        emit EventAnchored(channelId, subject, objectRef, action, ruleVersion, now_, recordIndex, bindingId);
        for (uint256 i = 0; i < relations.length; i++) {
            if (relations[i].kind > AIFPEvents.MAX_RELATION) revert AIFP_InvalidRelation(relations[i].kind);
            emit RelationAnchored(objectRef, relations[i].kind, relations[i].objectRef);
        }
    }

    function record(uint256 recordIndex) external view returns (EventRecord memory) {
        StoredRecord storage r = _records[recordIndex];
        return EventRecord({
            channelId: r.channelId,
            subject: r.subject,
            action: r.action,
            objectRef: r.objectRef,
            ruleVersion: r.ruleVersion,
            at: r.at,
            bindingId: r.bindingId
        });
    }

    function anchoredBy(bytes32 objectRef) external view returns (bytes32) {
        return _anchoredBy[objectRef];
    }

    function anchoredIn(bytes32 objectRef) external view returns (bytes32) {
        return _anchoredIn[objectRef];
    }

    function recordCount() external view returns (uint256) {
        return _records.length;
    }

    function _roleFor(uint8 action) internal pure returns (uint16) {
        if (action == AIFPEvents.ACTION_PUBLISH || action == AIFPEvents.ACTION_SUBMIT) return AIFPRoles.SUBMIT;
        if (action == AIFPEvents.ACTION_RESPOND) return AIFPRoles.RESPOND;
        if (action == AIFPEvents.ACTION_MODIFY) return AIFPRoles.MODIFY;
        if (action == AIFPEvents.ACTION_FORWARD || action == AIFPEvents.ACTION_DERIVE || action == AIFPEvents.ACTION_SYNTHESIZE) {
            return AIFPRoles.REDISTRIBUTE;
        }
        return AIFPRoles.SUBMIT; // supersede, retract: the author acts on its own object
    }

    function _requireRelation(Relation[] calldata relations, uint8 kind, uint8 action) internal pure {
        for (uint256 i = 0; i < relations.length; i++) {
            if (relations[i].kind == kind) return;
        }
        revert AIFP_MissingRelation(action, kind);
    }

    function _requireOwnTarget(Relation[] calldata relations, uint8 kind, bytes32 subject, uint8 action) internal view {
        bool found;
        for (uint256 i = 0; i < relations.length; i++) {
            if (relations[i].kind == kind) {
                found = true;
                if (_anchoredBy[relations[i].objectRef] != subject) revert AIFP_NotAnchoredBySubject(relations[i].objectRef, subject);
            }
        }
        if (!found) revert AIFP_MissingRelation(action, kind);
    }
}
