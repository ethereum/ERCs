// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAIFPEventAnchor (optional profile `aifp:profile/event-anchor/v1`)
/// @notice Anchors information event references: who, in which channel, under which rule version and on
///         the strength of which role binding, performed which action on which object, related to which
///         earlier objects. Anchoring is a declaration by the actor; it does not transport content and
///         does not prove delivery.
interface IAIFPEventAnchor {
    struct Relation {
        uint8 kind;
        bytes32 objectRef;
    }

    /// @dev `at` is the clock value when the record was written. `bindingId` is a role binding that satisfied
    ///      the role check then (the earliest-created one of the subject, for the whole channel): the
    ///      evidence that the action was authorized at that position in the chain, which re-evaluating the
    ///      role at `at` later does not show when the binding was revoked or suspended later within the same
    ///      timepoint. It is a witness that the role was held, not a statement about the capacity in which
    ///      the subject acted.
    struct EventRecord {
        bytes32 channelId;
        bytes32 subject;
        uint8 action;
        bytes32 objectRef;
        bytes32 ruleVersion;
        uint48 at;
        bytes32 bindingId;
    }

    event EventAnchored(
        bytes32 indexed channelId,
        bytes32 indexed subject,
        bytes32 indexed objectRef,
        uint8 action,
        bytes32 ruleVersion,
        uint48 at,
        uint256 recordIndex,
        bytes32 bindingId
    );
    event RelationAnchored(bytes32 indexed objectRef, uint8 kind, bytes32 indexed relatedRef);

    error AIFP_NotAnchoredBySubject(bytes32 objectRef, bytes32 subject);
    error AIFP_ObjectAlreadyAnchored(bytes32 objectRef);
    /// @dev `outcome` is what the role check answered: NOT_SATISFIED, or UNDETERMINABLE for a subject whose
    ///      binding is pending re-admission.
    error AIFP_RoleNotHeld(bytes32 channelId, bytes32 subject, uint16 role, uint8 outcome);

    function anchor(bytes32 channelId, uint8 action, bytes32 objectRef, Relation[] calldata relations) external returns (uint256 recordIndex);
    function record(uint256 recordIndex) external view returns (EventRecord memory);
    function anchoredBy(bytes32 objectRef) external view returns (bytes32 subject);
    function recordCount() external view returns (uint256);
}
