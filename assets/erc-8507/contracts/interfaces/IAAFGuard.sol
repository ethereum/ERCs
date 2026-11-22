// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {
    Outcome,
    Disposition,
    SubjectRef,
    BindingConfig,
    BindingInfo,
    Assessment,
    Admission
} from "./AAFTypes.sol";

/// @title Bindings and assessments
/// @notice Holds what adopters declared and applies it to requests. A binding governs only the
/// consumer that adopted it.
interface IAAFGuard {
    event AdopterSet(address indexed consumer, address indexed adopter);
    event BindingAdopted(
        bytes32 indexed bindingId, address indexed consumer, bytes32 indexed scopeId, bytes32 configHash, address adoptedBy, string uri
    );
    event BindingAmended(bytes32 indexed bindingId, uint64 version, bytes32 configHash, address amendedBy, string uri);
    event BindingRetired(bytes32 indexed bindingId, address retiredBy);
    event Assessed(
        bytes32 indexed bindingId,
        bytes32 indexed subjectKey,
        bytes32 indexed action,
        bytes32 context,
        address presenter,
        Outcome outcome,
        Disposition disposition,
        bytes32 reason,
        uint64 bindingVersion,
        bytes32 stateDigest,
        uint64 validUntil
    );
    event AdmissionRecorded(
        bytes32 indexed bindingId, bytes32 indexed subjectKey, bytes32 indexed action, bytes32 context, Outcome outcome
    );
    event AdmissionWithdrawn(
        bytes32 indexed bindingId, bytes32 indexed subjectKey, bytes32 indexed action, bytes32 context
    );

    error NotAuthorized();
    error UnknownBinding();
    error BindingExists();
    error BindingIsRetired();
    error InvalidBinding();

    // ------------------------------------------------------------ adoption

    /// @notice Names the account that may adopt, amend and retire bindings for the caller.
    function setAdopter(address adopter) external;
    function adopterOf(address consumer) external view returns (address);

    /// @notice Adopts a binding for `config.scope.anchor`. The caller is that consumer or its adopter.
    function adopt(BindingConfig calldata config, bytes32 salt, string calldata uri) external returns (bytes32 bindingId);

    /// @notice Replaces the configuration of a binding and raises its version. The scope stays.
    function amend(bytes32 bindingId, BindingConfig calldata config, string calldata uri) external;
    function retire(bytes32 bindingId) external;

    function bindingIdOf(address consumer, bytes32 scopeId, bytes32 salt) external view returns (bytes32);
    function bindingOf(bytes32 bindingId) external view returns (BindingInfo memory info, BindingConfig memory config);

    // ------------------------------------------------------------ assessment

    /// @notice Applies a binding to a request. `evidence[i]` belongs to list i, counting the ALLOW
    /// lists first; a shorter array leaves the remaining lists without evidence.
    function assess(
        bytes32 bindingId,
        SubjectRef calldata subject,
        address presenter,
        bytes32 action,
        bytes32 context,
        bytes[] calldata evidence
    ) external view returns (Assessment memory);

    /// @notice The same assessment, made for the consumer of the binding, which is the caller.
    /// Emits Assessed. Where the action is declared with reuse ADMISSION, a decision to proceed is
    /// recorded and honoured at later uses.
    function enforce(
        bytes32 bindingId,
        SubjectRef calldata subject,
        address presenter,
        bytes32 action,
        bytes32 context,
        bytes[] calldata evidence
    ) external returns (Disposition disposition, Outcome outcome, bytes32 reason);

    /// @notice The digest an assessment made now would carry.
    function stateDigestOf(bytes32 bindingId) external view returns (bytes32);

    /// @notice Whether an earlier assessment still rests on the current binding version and list
    /// states and has not passed its validity. Always false for a `validUntil` of zero.
    function isCurrent(bytes32 bindingId, bytes32 stateDigest, uint64 validUntil) external view returns (bool);

    function admissionOf(bytes32 bindingId, bytes32 context, bytes32 subjectKey, bytes32 action)
        external
        view
        returns (Admission memory);
    function withdrawAdmission(bytes32 bindingId, bytes32 context, bytes32 subjectKey, bytes32 action) external;
}
