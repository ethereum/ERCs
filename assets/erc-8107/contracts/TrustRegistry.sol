// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {
    ITrustRegistry,
    TrustLevel,
    TrustAttestation,
    ValidationParams,
    TrustPath,
    SelfTrustProhibited,
    NonceTooLow,
    AttestationExpired,
    InvalidSignature,
    NotAuthorized,
    ENSNameNotFound,
    GateNotFound,
    InvalidAttestationLevel,
    InvalidMaxPathLength,
    InvalidMinEdgeTrust,
    TooManyRequiredAnchors,
    BatchTrustorMismatch,
    BatchNonceNotIncreasing,
    EmptyScopeList
} from "./ITrustRegistry.sol";

/// @notice Minimal ENS registry interface (ERC-137)
interface IENS {
    function owner(bytes32 node) external view returns (address);
    function resolver(bytes32 node) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/// @notice Minimal ENS NameWrapper interface
/// @dev NameWrapper is an ERC-1155; the token holder is the real name controller
interface INameWrapper {
    function ownerOf(uint256 id) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/// @notice Minimal ERC-137 forward address resolver interface
interface IAddrResolver {
    function addr(bytes32 node) external view returns (address payable);
}

/// @title ENS Trust Registry
/// @notice Reference implementation of ERC-8107
/// @dev Implements the REQUIRED `ITrustRegistry` surface only. The OPTIONAL
///      `ITrustRegistryExtended` functions (on-chain graph search, adjacency
///      enumeration) are deliberately omitted: ERC-8107 pushes path search to
///      off-chain indexers and keeps on-chain cost at O(path length).
/// @author Kwame Bryan (@KBryan)
contract TrustRegistry is ITrustRegistry, EIP712 {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 public constant TRUST_ATTESTATION_TYPEHASH = keccak256(
        "TrustAttestation(bytes32 trustorNode,bytes32 trusteeNode,uint8 level,bytes32 scope,uint64 expiry,uint64 nonce)"
    );

    /// @dev Upper bound on `ValidationParams.maxPathLength`
    uint8 internal constant MAX_PATH_LENGTH = 10;

    /// @dev Upper bound on `ValidationParams.requiredAnchors.length`
    uint256 internal constant MAX_REQUIRED_ANCHORS = 10;

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice ENS registry
    IENS private immutable _ens;

    /// @notice ENS NameWrapper, or address(0) on networks with no deployment
    address private immutable _nameWrapper;

    struct TrustRecord {
        TrustLevel level;
        uint64 expiry;
        uint64 setAt;
    }

    struct IdentityGate {
        bytes32 gatekeeperNode;
        ValidationParams params;
        bool enabled;
    }

    /// @dev trustorNode => trusteeNode => scope => TrustRecord
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => TrustRecord))) private _trust;

    /// @dev trustorNode => monotonic nonce
    mapping(bytes32 => uint64) private _nonces;

    /// @dev coordinator => coordinationType => IdentityGate
    /// @dev Keying by caller address means no two coordinators can collide on a
    ///      coordination type, so well-known constants cannot be squatted.
    mapping(address => mapping(bytes32 => IdentityGate)) private _gates;

    /// @param ensRegistry The ENS registry for this network
    /// @param nameWrapper_ The ENS NameWrapper, or address(0) where none is deployed.
    ///        MUST be pinned at deployment: a hostile contract here could claim
    ///        control of every wrapped name.
    constructor(address ensRegistry, address nameWrapper_) EIP712("TrustRegistry", "1") {
        _ens = IENS(ensRegistry);
        _nameWrapper = nameWrapper_;
    }

    /// @inheritdoc IERC165
    /// @dev Reports ITrustRegistry only. ITrustRegistryExtended is deliberately not
    ///      implemented, so it is deliberately not advertised.
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ITrustRegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice The ENS registry this instance validates against
    function ens() external view returns (address) {
        return address(_ens);
    }

    /// @notice The NameWrapper this instance unwraps against
    function nameWrapper() external view returns (address) {
        return _nameWrapper;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRUST MANAGEMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ITrustRegistry
    function setTrust(TrustAttestation calldata attestation, bytes calldata signature) external override {
        _setTrust(attestation, signature);
    }

    /// @inheritdoc ITrustRegistry
    function setTrustBatch(TrustAttestation[] calldata attestations, bytes[] calldata signatures) external override {
        uint256 n = attestations.length;
        if (n != signatures.length) revert BatchTrustorMismatch();
        if (n == 0) return;

        bytes32 trustor = attestations[0].trustorNode;
        for (uint256 i = 0; i < n; i++) {
            if (attestations[i].trustorNode != trustor) revert BatchTrustorMismatch();
            if (i > 0 && attestations[i].nonce <= attestations[i - 1].nonce) revert BatchNonceNotIncreasing();
            _setTrust(attestations[i], signatures[i]);
        }
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Revocation is caller-authorised (ENS owner or approved operator), not
    ///      signature-authorised. Approvals may submit revocations but can never
    ///      forge an attestation signature.
    function revokeTrust(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope, bytes32 reasonCode)
        external
        override
    {
        if (!_canSubmitRevocation(trustorNode, msg.sender)) revert NotAuthorized(trustorNode, msg.sender);

        _revokeOne(trustorNode, trusteeNode, scope, reasonCode);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Scopes are supplied by the caller. Enumerating a trustor's scopes on-chain
    ///      would require adjacency storage this standard deliberately avoids; callers
    ///      derive the list from TrustSet logs.
    function revokeTrustBatch(
        bytes32 trustorNode,
        bytes32 trusteeNode,
        bytes32[] calldata scopes,
        bytes32 reasonCode
    ) external override {
        if (!_canSubmitRevocation(trustorNode, msg.sender)) revert NotAuthorized(trustorNode, msg.sender);
        if (scopes.length == 0) revert EmptyScopeList();

        for (uint256 i = 0; i < scopes.length; i++) {
            _revokeOne(trustorNode, trusteeNode, scopes[i], reasonCode);
        }
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Raising the floor invalidates the trustor's outstanding attestations for
    ///      EVERY trustee and scope, not only a quarantined one. Deliberate: revocation
    ///      cannot otherwise be ordered against a signature that carries no timestamp.
    ///
    ///      Controller-only. Unlike revocation, whose effect is bounded to one trustee,
    ///      this is unbounded, and `isApprovedForAll` is a coarse approval granted for
    ///      name management rather than for voiding an agent's attestation pipeline.
    function invalidateNonces(bytes32 trustorNode, uint64 newNonce) external override {
        if (!_isController(trustorNode, msg.sender)) revert NotAuthorized(trustorNode, msg.sender);

        uint64 current = _nonces[trustorNode];
        if (newNonce <= current) revert NonceTooLow(newNonce, current + 1);

        _nonces[trustorNode] = newNonce;
        emit NoncesInvalidated(trustorNode, newNonce);
    }

    /// @dev Prior trust is NOT required. Distrusting an agent that was never trusted is
    ///      meaningful: it blocks paths that would otherwise route through this edge.
    function _revokeOne(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope, bytes32 reasonCode) internal {
        TrustRecord storage record = _trust[trustorNode][trusteeNode][scope];

        record.level = TrustLevel.None;
        // Implementation choice: explicit distrust does not expire. The record is
        // retained (not deleted) so the distrust remains observable.
        record.expiry = 0;
        record.setAt = uint64(block.timestamp);

        emit TrustRevoked(trustorNode, trusteeNode, scope, reasonCode);
    }

    /// @inheritdoc ITrustRegistry
    function getTrust(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope)
        external
        view
        override
        returns (TrustLevel level, uint64 expiry)
    {
        TrustRecord storage record = _trust[trustorNode][trusteeNode][scope];
        return (record.level, record.expiry);
    }

    /// @inheritdoc ITrustRegistry
    function getNonce(bytes32 trustorNode) external view override returns (uint64) {
        return _nonces[trustorNode];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PATH VERIFICATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ITrustRegistry
    function verifyPath(TrustPath calldata path, ValidationParams calldata params)
        external
        view
        override
        returns (bool valid)
    {
        _requireValidParams(params);
        return _verifyPath(path, params);
    }

    /// @dev Core path verification. Cost is O(path length x requiredAnchors).
    function _verifyPath(TrustPath calldata path, ValidationParams memory params) internal view returns (bool) {
        // Path must have at least 2 nodes (validator and target)
        if (path.nodes.length < 2) return false;

        // Path length constraint (edges = nodes - 1)
        if (path.nodes.length - 1 > params.maxPathLength) return false;

        // Nodes MUST be distinct. maxPathLength caps this at 11 nodes, so the quadratic
        // scan is at most 55 comparisons.
        for (uint256 i = 0; i < path.nodes.length; i++) {
            for (uint256 j = i + 1; j < path.nodes.length; j++) {
                if (path.nodes[i] == path.nodes[j]) return false;
            }
        }

        // Anchors are trivially satisfied when none are required
        bool foundAnchor = params.requiredAnchors.length == 0;

        for (uint256 i = 0; i < path.nodes.length - 1; i++) {
            (TrustLevel level, uint64 expiry) = _effectiveTrust(path.nodes[i], path.nodes[i + 1], params.scope);

            // Edge must meet the minimum trust level
            if (level < params.minEdgeTrust) return false;

            // None explicitly voids the path
            if (level == TrustLevel.None) return false;

            if (params.enforceExpiry && expiry != 0 && expiry <= block.timestamp) return false;

            // Anchor check: intermediaries only, never the validator or the target
            if (!foundAnchor && i > 0) {
                for (uint256 j = 0; j < params.requiredAnchors.length; j++) {
                    if (path.nodes[i] == params.requiredAnchors[j]) {
                        foundAnchor = true;
                        break;
                    }
                }
            }
        }

        // Anchors are part of the verdict, not a separate advisory signal
        return foundAnchor;
    }

    /// @dev Scoped trust first, falling back to universal scope when absent
    function _effectiveTrust(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope)
        internal
        view
        returns (TrustLevel level, uint64 expiry)
    {
        TrustRecord storage record = _trust[trustorNode][trusteeNode][scope];
        if (record.level == TrustLevel.Unknown && scope != bytes32(0)) {
            record = _trust[trustorNode][trusteeNode][bytes32(0)];
        }
        return (record.level, record.expiry);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-8001 INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ITrustRegistry
    /// @dev Stored under `(msg.sender, coordinationType)`. The caller owns its own
    ///      namespace, so no authorisation check is needed and no two coordinators can
    ///      collide on a coordination type. Naming `gatekeeperNode` deliberately does
    ///      NOT require controlling it: a gate only reads that agent's public
    ///      attestations.
    function setIdentityGate(bytes32 coordinationType, bytes32 gatekeeperNode, ValidationParams calldata params)
        external
        override
    {
        _requireValidParams(params);

        IdentityGate storage gate = _gates[msg.sender][coordinationType];
        gate.gatekeeperNode = gatekeeperNode;
        gate.params = params;
        gate.enabled = true;

        emit IdentityGateSet(
            msg.sender,
            coordinationType,
            gatekeeperNode,
            params.maxPathLength,
            params.minEdgeTrust,
            params.scope,
            params.enforceExpiry,
            params.requiredAnchors
        );
    }

    /// @inheritdoc ITrustRegistry
    function removeIdentityGate(bytes32 coordinationType) external override {
        if (!_gates[msg.sender][coordinationType].enabled) revert GateNotFound(coordinationType);

        delete _gates[msg.sender][coordinationType];
        emit IdentityGateRemoved(msg.sender, coordinationType);
    }

    /// @inheritdoc ITrustRegistry
    function getIdentityGate(address coordinator, bytes32 coordinationType)
        external
        view
        override
        returns (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled)
    {
        IdentityGate storage gate = _gates[coordinator][coordinationType];
        return (gate.gatekeeperNode, gate.params, gate.enabled);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Forward resolution per ERC-137. Returns address(0) when the node has no
    ///      resolver, no addr record, or an off-chain (CCIP-Read) resolver.
    function resolveAgent(bytes32 node) public view override returns (address) {
        address resolver = _ens.resolver(node);
        if (resolver == address(0)) return address(0);

        try IAddrResolver(resolver).addr(node) returns (address payable agent) {
            return agent;
        } catch {
            return address(0);
        }
    }

    /// @inheritdoc ITrustRegistry
    /// @dev An unconfigured gate is OPEN. Integrators that require an explicit gate
    ///      MUST check `getIdentityGate(...).enabled` themselves.
    function validateParticipantWithPath(
        address coordinator,
        bytes32 coordinationType,
        bytes32 participantNode,
        TrustPath calldata path
    ) external view override returns (bool isValid) {
        IdentityGate storage gate = _gates[coordinator][coordinationType];
        if (!gate.enabled) return true;

        if (!_pathStartsAtGatekeeper(path, gate.gatekeeperNode)) return false;

        // The path MUST terminate at the participant being gated. Without this the
        // result would say nothing about `participantNode`.
        if (path.nodes[path.nodes.length - 1] != participantNode) return false;

        return _verifyPath(path, gate.params);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev The ERC-8001 hook. ERC-8001 lists participants by address, so the terminal
    ///      node is bound to `participant` through its ERC-137 forward address record.
    function validateParticipantAddress(
        address coordinator,
        bytes32 coordinationType,
        address participant,
        TrustPath calldata path
    ) external view override returns (bool isValid) {
        IdentityGate storage gate = _gates[coordinator][coordinationType];
        if (!gate.enabled) return true;

        // Guards against an unresolvable node matching a zero participant address
        if (participant == address(0)) return false;

        if (!_pathStartsAtGatekeeper(path, gate.gatekeeperNode)) return false;

        if (resolveAgent(path.nodes[path.nodes.length - 1]) != participant) return false;

        return _verifyPath(path, gate.params);
    }

    function _pathStartsAtGatekeeper(TrustPath calldata path, bytes32 gatekeeperNode)
        internal
        pure
        returns (bool)
    {
        return path.nodes.length >= 2 && path.nodes[0] == gatekeeperNode;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EIP-712
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice EIP-712 digest for an attestation
    function hashAttestation(TrustAttestation calldata attestation) public view returns (bytes32) {
        return _hashTypedDataV4(_structHash(attestation));
    }

    function _structHash(TrustAttestation calldata att) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                TRUST_ATTESTATION_TYPEHASH,
                att.trustorNode,
                att.trusteeNode,
                uint8(att.level),
                att.scope,
                att.expiry,
                att.nonce
            )
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    function _setTrust(TrustAttestation calldata attestation, bytes calldata signature) internal {
        if (attestation.trustorNode == attestation.trusteeNode) revert SelfTrustProhibited();

        // Attestations grant trust; distrust is expressed by revokeTrust. This keeps
        // exactly one path, one event, and one authorisation rule per level.
        if (attestation.level == TrustLevel.Unknown || attestation.level == TrustLevel.None) {
            revert InvalidAttestationLevel(attestation.level);
        }

        uint64 currentNonce = _nonces[attestation.trustorNode];
        if (attestation.nonce <= currentNonce) revert NonceTooLow(attestation.nonce, currentNonce + 1);

        if (attestation.expiry != 0 && attestation.expiry <= block.timestamp) {
            revert AttestationExpired(attestation.expiry, uint64(block.timestamp));
        }

        address controller = _controllerOf(attestation.trustorNode);
        if (controller == address(0)) revert ENSNameNotFound(attestation.trustorNode);

        if (!_verifySignature(controller, hashAttestation(attestation), signature)) revert InvalidSignature();

        _nonces[attestation.trustorNode] = attestation.nonce;

        TrustRecord storage record = _trust[attestation.trustorNode][attestation.trusteeNode][attestation.scope];
        record.level = attestation.level;
        record.expiry = attestation.expiry;
        record.setAt = uint64(block.timestamp);

        emit TrustSet(
            attestation.trustorNode,
            attestation.trusteeNode,
            attestation.level,
            attestation.scope,
            attestation.expiry
        );
    }

    /// @dev Resolve the real controller of a name, unwrapping NameWrapper names.
    ///      `ens.owner` returns the NameWrapper contract for wrapped names, and
    ///      NameWrapper does not implement EIP-1271, so using it directly would leave
    ///      every wrapped name unable to attest. An expired wrapped name yields
    ///      address(0) and therefore has no authority.
    function _controllerOf(bytes32 node) internal view returns (address) {
        address registryOwner = _ens.owner(node);
        if (registryOwner == address(0)) return address(0);

        if (_nameWrapper != address(0) && registryOwner == _nameWrapper) {
            try INameWrapper(_nameWrapper).ownerOf(uint256(node)) returns (address wrapped) {
                return wrapped;
            } catch {
                return address(0);
            }
        }

        return registryOwner;
    }

    /// @dev Signing authority is the name controller only. Approvals are NOT accepted
    ///      here; they would break the binding between attestation and controller.
    function _verifySignature(address controller, bytes32 digest, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        if (controller.code.length == 0) {
            (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
            return err == ECDSA.RecoverError.NoError && recovered == controller;
        }

        try IERC1271(controller).isValidSignature(digest, signature) returns (bytes4 magic) {
            return magic == IERC1271.isValidSignature.selector;
        } catch {
            return false;
        }
    }

    /// @dev Controller or approved operator - authority for bounded revocation
    function _canSubmitRevocation(bytes32 node, address caller) internal view returns (bool) {
        return _isAuthorized(node, caller);
    }

    /// @dev Controller only - authority for trustor-wide operations
    function _isController(bytes32 node, address caller) internal view returns (bool) {
        address controller = _controllerOf(node);
        return controller != address(0) && caller == controller;
    }

    function _isAuthorized(bytes32 node, address actor) internal view returns (bool) {
        address controller = _controllerOf(node);
        if (controller == address(0)) return false;
        if (actor == controller) return true;

        // Approvals live on whichever contract actually holds the name
        if (_nameWrapper != address(0) && _ens.owner(node) == _nameWrapper) {
            return INameWrapper(_nameWrapper).isApprovedForAll(controller, actor);
        }

        return _ens.isApprovedForAll(controller, actor);
    }

    function _requireValidParams(ValidationParams memory params) internal pure {
        if (params.maxPathLength == 0 || params.maxPathLength > MAX_PATH_LENGTH) {
            revert InvalidMaxPathLength(params.maxPathLength);
        }
        if (params.minEdgeTrust == TrustLevel.Unknown || params.minEdgeTrust == TrustLevel.None) {
            revert InvalidMinEdgeTrust(params.minEdgeTrust);
        }
        if (params.requiredAnchors.length > MAX_REQUIRED_ANCHORS) {
            revert TooManyRequiredAnchors(params.requiredAnchors.length);
        }
    }
}
