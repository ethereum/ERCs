// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IFHEIFRegistry} from "./interfaces/IFHEIFRegistry.sol";
import {
    Profile,
    KeyContext,
    KeyEpoch,
    EpochInit,
    EpochStatus,
    CarryOver,
    Policy,
    PolicyInit,
    Scope,
    ScopeStatus,
    ViewDefinition
} from "./interfaces/FHEIFTypes.sol";

/// @title Reference registry of the FHE Interaction Framework
/// @notice Holds profiles, key contexts with their epochs, activity scopes with their policy
/// versions, and disclosure views. It has no owner, no upgrade path and no privileged account:
/// each key context and each scope is controlled by the account that created it.
contract FHEIFRegistry is IFHEIFRegistry {
    mapping(bytes32 => Profile) private _profiles;
    mapping(bytes32 => KeyContext) private _keyContexts;
    mapping(bytes32 => mapping(uint32 => KeyEpoch)) private _epochs;
    mapping(bytes32 => mapping(uint32 => mapping(address => bool))) private _holders;
    mapping(bytes32 => Scope) private _scopes;
    mapping(bytes32 => mapping(uint64 => Policy)) private _policies;
    mapping(bytes32 => mapping(bytes32 => bool)) private _admitted;
    mapping(bytes32 => ViewDefinition) private _views;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFHEIFRegistry).interfaceId || interfaceId == 0x01ffc9a7;
    }

    // Profiles

    function registerProfile(bytes32 descriptorHash, bytes32 evaluationClass, string calldata uri)
        external
        returns (bytes32 profileId)
    {
        if (descriptorHash == bytes32(0) || evaluationClass == bytes32(0)) revert ZeroValue();
        profileId = keccak256(abi.encode(descriptorHash, evaluationClass));
        if (_profiles[profileId].registeredAt != 0) revert AlreadyExists(profileId);
        _profiles[profileId] = Profile(descriptorHash, evaluationClass, msg.sender, uint64(block.timestamp));
        emit ProfileRegistered(profileId, descriptorHash, evaluationClass, msg.sender, uri);
    }

    function profileOf(bytes32 profileId) external view returns (Profile memory profile) {
        profile = _profiles[profileId];
        if (profile.registeredAt == 0) revert UnknownProfile(profileId);
    }

    // Key contexts

    function createKeyContext(
        bytes32 salt,
        bytes32 profileId,
        bytes32 descriptorHash,
        string calldata uri,
        EpochInit calldata firstEpoch
    ) external returns (bytes32 keyContextId) {
        if (_profiles[profileId].registeredAt == 0) revert UnknownProfile(profileId);
        if (descriptorHash == bytes32(0)) revert ZeroValue();
        keyContextId = keccak256(abi.encode(block.chainid, address(this), msg.sender, salt, "key-context"));
        if (_keyContexts[keyContextId].controller != address(0)) revert AlreadyExists(keyContextId);
        _keyContexts[keyContextId] = KeyContext(profileId, msg.sender, descriptorHash, 0);
        emit KeyContextCreated(keyContextId, profileId, msg.sender, descriptorHash, uri);
        _openEpoch(keyContextId, firstEpoch, CarryOver.NONE);
    }

    function openEpoch(bytes32 keyContextId, EpochInit calldata init, CarryOver carryOver) external returns (uint32 epoch) {
        KeyContext storage context = _controlledKeyContext(keyContextId);
        if (carryOver == CarryOver.NONE) revert InvalidCarryOver();
        uint32 previous = context.currentEpoch;
        KeyEpoch storage before = _epochs[keyContextId][previous];
        if (before.status == EpochStatus.ACTIVE) {
            before.status = carryOver == CarryOver.RESET ? EpochStatus.REVOKED : EpochStatus.RETIRED;
            emit EpochStatusChanged(keyContextId, previous, before.status);
        } else if (before.status == EpochStatus.RETIRED && carryOver == CarryOver.RESET) {
            before.status = EpochStatus.REVOKED;
            emit EpochStatusChanged(keyContextId, previous, EpochStatus.REVOKED);
        }
        epoch = _openEpoch(keyContextId, init, carryOver);
    }

    function revokeEpoch(bytes32 keyContextId, uint32 epoch) external {
        _controlledKeyContext(keyContextId);
        KeyEpoch storage record = _epochs[keyContextId][epoch];
        if (record.status == EpochStatus.NONE) revert UnknownEpoch(keyContextId, epoch);
        if (record.status == EpochStatus.REVOKED) revert InvalidEpochStatus(record.status);
        record.status = EpochStatus.REVOKED;
        emit EpochStatusChanged(keyContextId, epoch, EpochStatus.REVOKED);
    }

    function transferKeyContextControl(bytes32 keyContextId, address next) external {
        KeyContext storage context = _controlledKeyContext(keyContextId);
        if (next == address(0)) revert ZeroValue();
        emit KeyContextControlTransferred(keyContextId, context.controller, next);
        context.controller = next;
    }

    function keyContextOf(bytes32 keyContextId) external view returns (KeyContext memory context) {
        context = _keyContexts[keyContextId];
        if (context.controller == address(0)) revert UnknownKeyContext(keyContextId);
    }

    function epochOf(bytes32 keyContextId, uint32 epoch) external view returns (KeyEpoch memory record) {
        record = _epochs[keyContextId][epoch];
        if (record.status == EpochStatus.NONE) revert UnknownEpoch(keyContextId, epoch);
    }

    function isHolder(bytes32 keyContextId, uint32 epoch, address account) external view returns (bool) {
        return _holders[keyContextId][epoch][account];
    }

    // Scopes and policy versions

    function createScope(
        bytes32 salt,
        bytes32 descriptorHash,
        string calldata uri,
        bytes32 recordMode,
        PolicyInit calldata firstPolicy
    ) external returns (bytes32 scopeId) {
        if (descriptorHash == bytes32(0) || recordMode == bytes32(0)) revert ZeroValue();
        scopeId = keccak256(abi.encode(block.chainid, address(this), msg.sender, salt, "scope"));
        if (_scopes[scopeId].controller != address(0)) revert AlreadyExists(scopeId);
        _scopes[scopeId] = Scope(msg.sender, descriptorHash, recordMode, 0, ScopeStatus.ACTIVE);
        emit ScopeCreated(scopeId, msg.sender, descriptorHash, recordMode, uri);
        _activatePolicy(scopeId, firstPolicy);
    }

    function updatePolicy(bytes32 scopeId, PolicyInit calldata next) external returns (uint64 version) {
        Scope storage scope = _controlledScope(scopeId);
        if (scope.status == ScopeStatus.CLOSED) revert InvalidScopeStatus(scope.status);
        version = _activatePolicy(scopeId, next);
    }

    function pauseScope(bytes32 scopeId) external {
        Scope storage scope = _controlledScope(scopeId);
        if (scope.status != ScopeStatus.ACTIVE) revert InvalidScopeStatus(scope.status);
        scope.status = ScopeStatus.PAUSED;
        emit ScopeStatusChanged(scopeId, ScopeStatus.PAUSED);
    }

    function resumeScope(bytes32 scopeId) external {
        Scope storage scope = _controlledScope(scopeId);
        if (scope.status != ScopeStatus.PAUSED) revert InvalidScopeStatus(scope.status);
        scope.status = ScopeStatus.ACTIVE;
        emit ScopeStatusChanged(scopeId, ScopeStatus.ACTIVE);
    }

    function closeScope(bytes32 scopeId) external {
        Scope storage scope = _controlledScope(scopeId);
        if (scope.status == ScopeStatus.CLOSED) revert InvalidScopeStatus(scope.status);
        scope.status = ScopeStatus.CLOSED;
        emit ScopeStatusChanged(scopeId, ScopeStatus.CLOSED);
    }

    function transferScopeControl(bytes32 scopeId, address next) external {
        Scope storage scope = _controlledScope(scopeId);
        if (next == address(0)) revert ZeroValue();
        emit ScopeControlTransferred(scopeId, scope.controller, next);
        scope.controller = next;
    }

    function admitKeyContext(bytes32 scopeId, bytes32 keyContextId) external {
        _controlledScope(scopeId);
        if (_keyContexts[keyContextId].controller == address(0)) revert UnknownKeyContext(keyContextId);
        _admitted[scopeId][keyContextId] = true;
        emit KeyContextAdmitted(scopeId, keyContextId);
    }

    function dismissKeyContext(bytes32 scopeId, bytes32 keyContextId) external {
        _controlledScope(scopeId);
        _admitted[scopeId][keyContextId] = false;
        emit KeyContextDismissed(scopeId, keyContextId);
    }

    function scopeOf(bytes32 scopeId) external view returns (Scope memory scope) {
        scope = _scopes[scopeId];
        if (scope.controller == address(0)) revert UnknownScope(scopeId);
    }

    function policyOf(bytes32 scopeId, uint64 version) external view returns (Policy memory policy) {
        policy = _policies[scopeId][version];
        if (policy.authorizer == address(0)) revert UnknownScope(scopeId);
    }

    function isKeyContextAdmitted(bytes32 scopeId, bytes32 keyContextId) external view returns (bool) {
        return _admitted[scopeId][keyContextId];
    }

    // Disclosure views

    function defineView(
        bytes32 scopeId,
        bytes32 programHash,
        bytes32 outputHash,
        bytes32 keyContextId,
        bytes32[] calldata inputClasses
    ) external returns (bytes32 viewId) {
        Scope storage scope = _controlledScope(scopeId);
        if (scope.status == ScopeStatus.CLOSED) revert InvalidScopeStatus(scope.status);
        if (programHash == bytes32(0) || outputHash == bytes32(0)) revert ZeroValue();
        if (!_admitted[scopeId][keyContextId]) revert KeyContextNotAdmitted(scopeId, keyContextId);
        viewId = keccak256(
            abi.encode(scopeId, programHash, outputHash, keyContextId, keccak256(abi.encodePacked(inputClasses)))
        );
        if (_views[viewId].scopeId != bytes32(0)) revert AlreadyExists(viewId);
        ViewDefinition storage definition = _views[viewId];
        definition.scopeId = scopeId;
        definition.programHash = programHash;
        definition.outputHash = outputHash;
        definition.keyContextId = keyContextId;
        definition.policyVersion = scope.policyVersion;
        definition.inputClasses = inputClasses;
        emit ViewDefined(viewId, scopeId, programHash, outputHash, keyContextId, inputClasses, scope.policyVersion);
    }

    function retireView(bytes32 viewId) external {
        ViewDefinition storage definition = _views[viewId];
        if (definition.scopeId == bytes32(0)) revert UnknownView(viewId);
        _controlledScope(definition.scopeId);
        definition.retired = true;
        emit ViewRetired(viewId);
    }

    function viewOf(bytes32 viewId) external view returns (ViewDefinition memory definition) {
        definition = _views[viewId];
        if (definition.scopeId == bytes32(0)) revert UnknownView(viewId);
    }

    // Internal

    function _controlledKeyContext(bytes32 keyContextId) private view returns (KeyContext storage context) {
        context = _keyContexts[keyContextId];
        if (context.controller == address(0)) revert UnknownKeyContext(keyContextId);
        if (context.controller != msg.sender) revert NotController(msg.sender);
    }

    function _controlledScope(bytes32 scopeId) private view returns (Scope storage scope) {
        scope = _scopes[scopeId];
        if (scope.controller == address(0)) revert UnknownScope(scopeId);
        if (scope.controller != msg.sender) revert NotController(msg.sender);
    }

    function _openEpoch(bytes32 keyContextId, EpochInit calldata init, CarryOver carryOver) private returns (uint32 epoch) {
        uint256 count = init.holders.length;
        if (init.materialHash == bytes32(0)) revert ZeroValue();
        if (count == 0 || count > type(uint16).max || init.releaseQuorum == 0 || init.releaseQuorum > count) {
            revert InvalidHolders();
        }
        epoch = ++_keyContexts[keyContextId].currentEpoch;
        mapping(address => bool) storage holders = _holders[keyContextId][epoch];
        for (uint256 i = 0; i < count; ++i) {
            address holder = init.holders[i];
            if (holder == address(0) || holders[holder]) revert InvalidHolders();
            holders[holder] = true;
        }
        _epochs[keyContextId][epoch] = KeyEpoch(
            init.materialHash,
            init.accessHash,
            init.releaseQuorum,
            uint16(count),
            EpochStatus.ACTIVE,
            carryOver,
            uint64(block.timestamp)
        );
        emit EpochOpened(
            keyContextId, epoch, init.materialHash, init.accessHash, init.releaseQuorum, init.holders, carryOver
        );
    }

    function _activatePolicy(bytes32 scopeId, PolicyInit calldata init) private returns (uint64 version) {
        if (init.policyHash == bytes32(0) || init.authorizer == address(0)) revert ZeroValue();
        version = ++_scopes[scopeId].policyVersion;
        _policies[scopeId][version] =
            Policy(init.policyHash, init.authorizer, init.successorRight, uint64(block.timestamp));
        emit PolicyActivated(scopeId, version, init.policyHash, init.authorizer, init.successorRight);
    }
}
