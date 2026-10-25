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
        ASFTypes.Restriction restriction,
        address actor,
        bytes32 reasonRef
    );
    event BindingParamsLocatorUpdated(bytes32 indexed bindingId, string locator);

    /// @notice Creates an Active binding adopted by `msg.sender`. Reverts when the id already exists
    ///         (in any state), when the pinned specification version does not exist or its content hash
    ///         differs, when the validity window is malformed, or when a parent binding is given that is
    ///         not Active, pins another specification version, has a narrower validity window, or would
    ///         exceed the maximum depth.
    function adopt(ASFTypes.BindingInput calldata input) external returns (bytes32 bindingId);

    /// @notice Active -> Suspended under a named restriction. Adopter or intervener with RIGHT_SUSPEND.
    function suspend(bytes32 bindingId, ASFTypes.Restriction restriction, bytes32 reasonRef) external;

    /// @notice Suspended -> Active. Adopter or intervener with RIGHT_RESUME.
    function resume(bytes32 bindingId, bytes32 reasonRef) external;

    /// @notice Active or Suspended -> Terminated (terminal). Adopter or intervener with RIGHT_TERMINATE.
    function terminate(bytes32 bindingId, bytes32 reasonRef) external;

    /// @notice Replaces the parameters locator; the parameters hash is untouched. Adopter only.
    function setParamsLocator(bytes32 bindingId, string calldata locator) external;

    function computeBindingId(address adopter, ASFTypes.BindingInput calldata input) external view returns (bytes32);
    function bindingOf(bytes32 bindingId) external view returns (ASFTypes.Binding memory);
    function intervenersOf(bytes32 bindingId) external view returns (ASFTypes.Intervener[] memory);
    function rightsOf(bytes32 bindingId, address account) external view returns (uint8);

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
    ///         subject, scope, declared enforcement locations and the ancestor chain. No policy is evaluated.
    function checkBinding(bytes32 bindingId, ASFTypes.Clause calldata clause)
        external view returns (ASFTypes.Verdict verdict, ASFTypes.Reason reason, ASFTypes.Restriction restriction);

    /// @notice Evaluates a requirement set. `bindingIds[i]` is the candidate for `clauses[i]`
    ///         (bytes32(0) = none supplied). `Unknown` never counts as satisfied.
    function check(ASFTypes.RequirementSet calldata requirement, bytes32[] calldata bindingIds)
        external view returns (ASFTypes.Verdict verdict, ASFTypes.Reason[] memory reasons);

    /// @notice keccak256(abi.encode(requirement)); reverts for malformed requirement sets.
    function requirementId(ASFTypes.RequirementSet calldata requirement) external pure returns (bytes32);
}
