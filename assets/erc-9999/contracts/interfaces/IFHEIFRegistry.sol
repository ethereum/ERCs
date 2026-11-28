// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {
    Profile,
    KeyContext,
    KeyEpoch,
    EpochInit,
    EpochStatus,
    CarryOver,
    Policy,
    PolicyInit,
    SuccessorRight,
    Scope,
    ScopeStatus,
    ViewDefinition
} from "./FHEIFTypes.sol";

/// @title FHE Interaction Framework: registry of profiles, key contexts, scopes and views
interface IFHEIFRegistry {
    event ProfileRegistered(
        bytes32 indexed profileId, bytes32 descriptorHash, bytes32 indexed evaluationClass, address indexed registrant, string uri
    );
    event KeyContextCreated(
        bytes32 indexed keyContextId, bytes32 indexed profileId, address indexed controller, bytes32 descriptorHash, string uri
    );
    event KeyContextControlTransferred(bytes32 indexed keyContextId, address indexed previous, address indexed next);
    event EpochOpened(
        bytes32 indexed keyContextId,
        uint32 indexed epoch,
        bytes32 materialHash,
        bytes32 accessHash,
        uint16 releaseQuorum,
        address[] holders,
        CarryOver carryOver
    );
    event EpochStatusChanged(bytes32 indexed keyContextId, uint32 indexed epoch, EpochStatus status);
    event ScopeCreated(
        bytes32 indexed scopeId, address indexed controller, bytes32 descriptorHash, bytes32 recordMode, string uri
    );
    event ScopeControlTransferred(bytes32 indexed scopeId, address indexed previous, address indexed next);
    event ScopeStatusChanged(bytes32 indexed scopeId, ScopeStatus status);
    event PolicyActivated(
        bytes32 indexed scopeId, uint64 indexed version, bytes32 policyHash, address indexed authorizer, SuccessorRight successorRight
    );
    event KeyContextAdmitted(bytes32 indexed scopeId, bytes32 indexed keyContextId);
    event KeyContextDismissed(bytes32 indexed scopeId, bytes32 indexed keyContextId);
    event ViewDefined(
        bytes32 indexed viewId,
        bytes32 indexed scopeId,
        bytes32 indexed programHash,
        bytes32 outputHash,
        bytes32 keyContextId,
        bytes32[] inputClasses,
        uint64 policyVersion
    );
    event ViewRetired(bytes32 indexed viewId);

    error ZeroValue();
    error AlreadyExists(bytes32 id);
    error UnknownProfile(bytes32 profileId);
    error UnknownKeyContext(bytes32 keyContextId);
    error UnknownEpoch(bytes32 keyContextId, uint32 epoch);
    error UnknownScope(bytes32 scopeId);
    error UnknownView(bytes32 viewId);
    error NotController(address caller);
    error InvalidHolders();
    error InvalidCarryOver();
    error InvalidEpochStatus(EpochStatus status);
    error InvalidScopeStatus(ScopeStatus status);
    error KeyContextNotAdmitted(bytes32 scopeId, bytes32 keyContextId);

    // Profiles

    /// @notice Registers a crypto profile. The identifier binds the descriptor to its evaluation class.
    function registerProfile(bytes32 descriptorHash, bytes32 evaluationClass, string calldata uri)
        external
        returns (bytes32 profileId);

    function profileOf(bytes32 profileId) external view returns (Profile memory);

    // Key contexts

    /// @notice Creates a key context under `profileId` and opens its first epoch. The caller controls it.
    function createKeyContext(
        bytes32 salt,
        bytes32 profileId,
        bytes32 descriptorHash,
        string calldata uri,
        EpochInit calldata firstEpoch
    ) external returns (bytes32 keyContextId);

    /// @notice Opens the next epoch. The epoch before it becomes RETIRED, or REVOKED under RESET.
    function openEpoch(bytes32 keyContextId, EpochInit calldata init, CarryOver carryOver) external returns (uint32 epoch);

    /// @notice Revokes an ACTIVE or RETIRED epoch. Nothing proceeds under a revoked epoch.
    function revokeEpoch(bytes32 keyContextId, uint32 epoch) external;

    function transferKeyContextControl(bytes32 keyContextId, address next) external;

    function keyContextOf(bytes32 keyContextId) external view returns (KeyContext memory);

    function epochOf(bytes32 keyContextId, uint32 epoch) external view returns (KeyEpoch memory);

    /// @notice Whether `account` may attest releases under `epoch`.
    function isHolder(bytes32 keyContextId, uint32 epoch, address account) external view returns (bool);

    // Scopes and policy versions

    /// @notice Creates an activity scope with its first policy version. The caller controls it.
    function createScope(
        bytes32 salt,
        bytes32 descriptorHash,
        string calldata uri,
        bytes32 recordMode,
        PolicyInit calldata firstPolicy
    ) external returns (bytes32 scopeId);

    /// @notice Activates the next policy version of a scope.
    function updatePolicy(bytes32 scopeId, PolicyInit calldata next) external returns (uint64 version);

    function pauseScope(bytes32 scopeId) external;

    function resumeScope(bytes32 scopeId) external;

    /// @notice Closes a scope. A closed scope does not reopen.
    function closeScope(bytes32 scopeId) external;

    function transferScopeControl(bytes32 scopeId, address next) external;

    function admitKeyContext(bytes32 scopeId, bytes32 keyContextId) external;

    function dismissKeyContext(bytes32 scopeId, bytes32 keyContextId) external;

    function scopeOf(bytes32 scopeId) external view returns (Scope memory);

    function policyOf(bytes32 scopeId, uint64 version) external view returns (Policy memory);

    function isKeyContextAdmitted(bytes32 scopeId, bytes32 keyContextId) external view returns (bool);

    // Disclosure views

    /// @notice Defines a disclosure view of a scope. The identifier is derived from every argument.
    function defineView(
        bytes32 scopeId,
        bytes32 programHash,
        bytes32 outputHash,
        bytes32 keyContextId,
        bytes32[] calldata inputClasses
    ) external returns (bytes32 viewId);

    /// @notice Retires a view. No release proceeds under a retired view.
    function retireView(bytes32 viewId) external;

    function viewOf(bytes32 viewId) external view returns (ViewDefinition memory);
}
