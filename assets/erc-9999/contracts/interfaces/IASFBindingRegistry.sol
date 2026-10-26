// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes} from "../ASFTypes.sol";

/// @title  IASFBindingRegistry — registry of Safety Bindings (scoped, attributable adoption relations)
/// @notice A Safety Binding states that the adopter (always `msg.sender`) adopts one pinned version of a
///         Safety Specification for a subject within a scope. The registry records who adopted what, where,
///         under which external authority basis and enforcement locations, and how the adoption changed
///         over time. It never decides whether the adopter was entitled to adopt, whether an action is
///         permitted, or whether the arrangement is actually enforced: those judgments belong to the
///         permission sources, policy mechanisms and enforcement points that bindings reference.
interface IASFBindingRegistry /* is IERC165 */ {
    event BindingCreated(
        bytes32 indexed bindingId,
        address indexed adopter,
        bytes32 indexed subjectKey,
        bytes32 scopeKey,
        address specRegistry,
        bytes32 specId,
        uint32 version,
        bytes32 contentHash,
        bytes32 parentBindingId
    );
    event BindingStateChanged(
        bytes32 indexed bindingId,
        ASFTypes.BindingState previous,
        ASFTypes.BindingState current,
        uint8 restrictions,
        bytes32 responseRef,
        address actor,
        bytes32 reasonRef
    );
    event BindingParamsLocatorUpdated(bytes32 indexed bindingId, string locator);
    /// @notice A standing stop recorded through a Terminated binding was lifted (the record stays Terminated).
    event StopLifted(bytes32 indexed bindingId, address indexed intervener, address actor, bytes32 reasonRef);

    /// @notice Creates an Active binding adopted by `msg.sender`. Reverts when the id already exists
    ///         (in any state), when the pinned specification version does not exist or its content hash
    ///         differs, when the validity window is malformed, or when a parent binding is given that is
    ///         not Active, pins another specification version, has a narrower validity window, or would
    ///         exceed the maximum depth.
    function adopt(ASFTypes.BindingInput calldata input) external returns (bytes32 bindingId);

    /// @notice Active -> Suspended under a non-empty set of response requirements, with the response document
    ///         reference (scope, parameters, in-flight handling, duration, who may resume) and the reason
    ///         reference (the evidence or decision behind the transition). Adopter or intervener with RIGHT_SUSPEND;
    ///         the caller is recorded as `suspendedBy`. A suspension by an intervener also records a standing stop
    ///         against the adopter for the binding's subject and specification, keyed by the intervener.
    function suspend(bytes32 bindingId, uint8 restrictions, bytes32 responseRef, bytes32 reasonRef) external;

    /// @notice Suspended -> Active. Adopter or intervener with RIGHT_RESUME, except that a suspension recorded by
    ///         an intervener can only be lifted by an intervener holding RIGHT_RESUME, never by the adopter.
    ///         Lifts the standing stop recorded through the binding. On a Terminated binding whose stop still
    ///         stands, lifts that stop only (the record stays Terminated) under the same rights.
    function resume(bytes32 bindingId, bytes32 reasonRef) external;

    /// @notice Active or Suspended -> Terminated (terminal). Adopter or intervener with RIGHT_TERMINATE. The
    ///         suspension fields of the record are kept, so that a terminated record shows the stop it carried,
    ///         and a standing stop recorded through the binding stands until lifted.
    function terminate(bytes32 bindingId, bytes32 reasonRef) external;

    /// @notice Replaces the parameters locator; the parameters hash is untouched. Adopter only.
    function setParamsLocator(bytes32 bindingId, string calldata locator) external;

    function computeBindingId(address adopter, ASFTypes.BindingInput calldata input) external view returns (bytes32);
    function bindingOf(bytes32 bindingId) external view returns (ASFTypes.Binding memory);
    function intervenersOf(bytes32 bindingId) external view returns (ASFTypes.Intervener[] memory);
    function rightsOf(bytes32 bindingId, address account) external view returns (uint8);
    /// @notice The standing stop of `intervener` against `adopter` for the subject and the specification, or a
    ///         zero record when none stands.
    function stopOf(address adopter, bytes32 subjectKey, address specRegistry, bytes32 specId, address intervener)
        external view returns (ASFTypes.Stop memory);

    /// @notice Index by (subjectKey, adopter) and by (scopeKey, adopter). The adopter is part of every
    ///         index key so that a third party's adoption is never presented as the subject's own.
    function countBySubject(bytes32 subjectKey, address adopter) external view returns (uint256);
    function bindingsBySubject(bytes32 subjectKey, address adopter, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory);
    function countByScope(bytes32 scopeKey, address adopter) external view returns (uint256);
    function bindingsByScope(bytes32 scopeKey, address adopter, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory);

    /// @notice Registry-level check of one binding against one clause at the current block time.
    ///         Pure registry logic: existence, state, validity window, pinned specification, adopter,
    ///         subject, scope, declared enforcement locations, required interveners (presence with rights, and
    ///         no unnamed holder of RIGHT_RESUME when the clause names interveners), standing stops by the
    ///         accounts the clause names, and the ancestor chain. No policy is evaluated. `restrictions` is the
    ///         set of response requirements in force for the binding: the union of the sets of every suspended
    ///         record among the binding and its ancestors, or empty when a record in that chain is terminated or
    ///         outside its validity window; under `StoppedByIntervener` it is the set of the standing stop.
    function checkBinding(bytes32 bindingId, ASFTypes.Clause calldata clause)
        external view returns (ASFTypes.Verdict verdict, ASFTypes.Reason reason, uint8 restrictions);

    /// @notice Evaluates a requirement set. `bindingIds[i]` is the candidate for `clauses[i]`
    ///         (bytes32(0) = none supplied). `Unknown` never counts as satisfied. `restrictions[i]` is the
    ///         response set in force for clause i, as defined for `checkBinding`.
    function check(ASFTypes.RequirementSet calldata requirement, bytes32[] calldata bindingIds)
        external view returns (ASFTypes.Verdict verdict, ASFTypes.Reason[] memory reasons, uint8[] memory restrictions);

    /// @notice keccak256(abi.encode(requirement)); reverts for malformed requirement sets.
    function requirementId(ASFTypes.RequirementSet calldata requirement) external pure returns (bytes32);
}
