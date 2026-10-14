// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
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
    BatchLengthMismatch,
    EmptyBatch,
    BatchTrustorMismatch,
    BatchNonceNotIncreasing,
    EmptyScopeList,
    NonceJumpTooLarge,
    NonceChanged
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

    /// @dev Upper bound on how far one attestation or `invalidateNonces` call may
    ///      raise the nonce floor
    uint64 internal constant MAX_NONCE_JUMP = 2 ** 32;

    /// @dev Gas forwarded to a node's resolver in `resolveAgent`
    uint256 internal constant RESOLVE_GAS = 50_000;

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The ENS registry this instance validates against
    IENS public immutable ens;

    /// @notice The NameWrapper this instance unwraps against, or address(0) on
    ///         networks with no deployment
    address public immutable nameWrapper;

    /// @dev One storage slot. Endorsement (level, expiry, setAt) and denial are
    ///      independent: every write names its fields, so no operation on one
    ///      overwrites the other.
    struct TrustRecord {
        TrustLevel level;
        uint64 expiry;
        uint64 setAt;
        bool denied;
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
        ens = IENS(ensRegistry);
        nameWrapper = nameWrapper_;
    }

    /// @inheritdoc IERC165
    /// @dev Reports ITrustRegistry only. ITrustRegistryExtended is deliberately not
    ///      implemented, so it is deliberately not advertised.
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ITrustRegistry).interfaceId || interfaceId == type(IERC165).interfaceId;
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
        if (n != signatures.length) revert BatchLengthMismatch();
        if (n == 0) revert EmptyBatch();

        // Batch-level checks run over the whole batch, in the specified order, before
        // any item is applied
        bytes32 trustor = attestations[0].trustorNode;
        for (uint256 i = 1; i < n; i++) {
            if (attestations[i].trustorNode != trustor) revert BatchTrustorMismatch();
        }
        for (uint256 i = 1; i < n; i++) {
            if (attestations[i].nonce <= attestations[i - 1].nonce) revert BatchNonceNotIncreasing();
        }

        for (uint256 i = 0; i < n; i++) {
            _setTrust(attestations[i], signatures[i]);
        }
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Revocation is caller-authorised (name controller or approved operator), not
    ///      signature-authorised. Approvals may submit revocations but can never
    ///      forge an attestation signature.
    function revokeTrust(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope, bytes32 reasonCode)
        external
        override
    {
        if (!canSubmitRevocation(trustorNode, msg.sender)) revert NotAuthorized(trustorNode, msg.sender);

        _revokeOne(trustorNode, trusteeNode, scope, reasonCode);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Scopes are supplied by the caller. Enumerating a trustor's scopes on-chain
    ///      would require adjacency storage this standard deliberately avoids; callers
    ///      derive the list from TrustSet logs.
    function revokeTrustBatch(bytes32 trustorNode, bytes32 trusteeNode, bytes32[] calldata scopes, bytes32 reasonCode)
        external
        override
    {
        if (!canSubmitRevocation(trustorNode, msg.sender)) revert NotAuthorized(trustorNode, msg.sender);
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
        if (newNonce <= current) revert NonceTooLow(newNonce, _next(current));

        uint64 max = _maxNonce(current);
        if (newNonce > max) revert NonceJumpTooLarge(newNonce, max);

        _nonces[trustorNode] = newNonce;
        emit NoncesInvalidated(trustorNode, newNonce);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Controller-only. A denial overrides endorsements by other agents within
    ///      the trustor's own decisions, so it carries the same authority as signing
    ///      an attestation rather than the bounded authority of a withdrawal.
    function setDenial(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope, bytes32 reasonCode) external override {
        if (!_isController(trustorNode, msg.sender)) revert NotAuthorized(trustorNode, msg.sender);
        if (trustorNode == trusteeNode) revert SelfTrustProhibited();

        _writeDenial(trustorNode, trusteeNode, scope, true, reasonCode);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Every attestation that lands raises the trustor's nonce, so an unchanged
    ///      nonce means the stored endorsements, in every scope, are those the caller
    ///      reviewed. Withdrawals do not raise it, but can only reduce trust.
    function clearDenial(
        bytes32 trustorNode,
        bytes32 trusteeNode,
        bytes32 scope,
        uint64 expectedNonce,
        bytes32 reasonCode
    ) external override {
        if (!_isController(trustorNode, msg.sender)) {
            revert NotAuthorized(trustorNode, msg.sender);
        }
        if (trustorNode == trusteeNode) revert SelfTrustProhibited();

        uint64 current = _nonces[trustorNode];
        if (current != expectedNonce) revert NonceChanged(expectedNonce, current);

        _writeDenial(trustorNode, trusteeNode, scope, false, reasonCode);
    }

    /// @dev Emits only on a change, so the latest DenialSet reconstructs the flag
    function _writeDenial(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope, bool denied, bytes32 reasonCode)
        internal
    {
        TrustRecord storage record = _trust[trustorNode][trusteeNode][scope];
        if (record.denied == denied) return;

        record.denied = denied;
        emit DenialSet(trustorNode, trusteeNode, scope, denied, reasonCode);
    }

    /// @inheritdoc ITrustRegistry
    function getDenial(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope) external view override returns (bool) {
        return _trust[trustorNode][trusteeNode][scope].denied;
    }

    /// @dev Prior trust is NOT required. Withdrawing in a scope that was never granted
    ///      is meaningful: it blocks the universal fallback for that scope.
    function _revokeOne(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope, bytes32 reasonCode) internal {
        TrustRecord storage record = _trust[trustorNode][trusteeNode][scope];

        record.level = TrustLevel.None;
        // A withdrawal does not expire: getTrust returns (None, 0). The record is
        // retained (not deleted) so the withdrawal remains observable.
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
        return _getTrust(trustorNode, trusteeNode, scope);
    }

    function _getTrust(bytes32 trustorNode, bytes32 trusteeNode, bytes32 scope)
        internal
        view
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
        return _verifyPath(path, params, true);
    }

    /// @dev Core path verification. Cost is O(path length x requiredAnchors).
    ///      Besides the per-edge checks, the validator must not effectively deny any
    ///      later node: its denial overrides any indirect endorsement within its own
    ///      trust decision.
    ///      `validateParams` is false only for parameters read from a stored gate,
    ///      which `setIdentityGate` validated when it stored them.
    function _verifyPath(TrustPath memory path, ValidationParams memory params, bool validateParams)
        internal
        view
        returns (bool)
    {
        // Parameters are validated BEFORE they are used. Skipping this would let
        // minEdgeTrust == Unknown make every edge comparison vacuously pass.
        if (validateParams) requireValidParams(params);

        // Path must have at least 2 nodes (validator and target)
        if (path.nodes.length < 2) return false;

        // Path length constraint (edges = nodes - 1)
        if (path.nodes.length - 1 > params.maxPathLength) return false;

        // Nodes MUST be distinct; a repeated node inflates length without adding trust.
        // maxPathLength caps this at 11 nodes, so the quadratic scan is bounded.
        for (uint256 i = 0; i < path.nodes.length; i++) {
            for (uint256 j = i + 1; j < path.nodes.length; j++) {
                if (path.nodes[i] == path.nodes[j]) return false;
            }
        }

        // The validator's denial overrides any indirect endorsement.
        // k = 1 is already covered by the first edge check.
        bytes32 validator = path.nodes[0];
        for (uint256 k = 2; k < path.nodes.length; ++k) {
            (,, bool validatorDenies) = _edgeTrust(validator, path.nodes[k], params.scope);
            if (validatorDenies) return false;
        }

        // Track anchor satisfaction
        bool foundAnchor = params.requiredAnchors.length == 0;

        // Verify each edge
        for (uint256 i = 0; i < path.nodes.length - 1; i++) {
            // Universal None, then a stored scoped record, then universal trust
            (TrustLevel level, uint64 expiry, bool denied) = _edgeTrust(path.nodes[i], path.nodes[i + 1], params.scope);

            // Denial voids the edge whatever its endorsement
            if (denied) return false;

            // Edge must meet minimum trust level
            if (level < params.minEdgeTrust) return false;

            // None explicitly voids (even if minEdgeTrust is somehow None)
            if (level == TrustLevel.None) return false;

            // Expiry check
            if (params.enforceExpiry && expiry != 0 && expiry <= block.timestamp) {
                return false;
            }

            // Anchor check (intermediate nodes only, not first or last)
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

    /// @dev The endorsement and the effective denial that apply to one edge when
    ///      verifying in `scope`. Each record is one slot, so denial costs no extra read.
    function _edgeTrust(bytes32 from, bytes32 to, bytes32 scope)
        internal
        view
        returns (TrustLevel level, uint64 expiry, bool denied)
    {
        TrustRecord storage u = _trust[from][to][bytes32(0)];

        // Universal denial holds in every scope, so no scoped record can lift it
        if (scope == bytes32(0) || u.denied) return (u.level, u.expiry, u.denied);

        TrustRecord storage s = _trust[from][to][scope];

        // 1. Universal None voids the endorsement in every scope
        if (u.level == TrustLevel.None) return (TrustLevel.None, u.expiry, s.denied);

        // 2. Any stored scoped record is authoritative, expired or not
        if (s.level != TrustLevel.Unknown) return (s.level, s.expiry, s.denied);

        // 3. Otherwise universal applies
        return (u.level, u.expiry, s.denied);
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
        requireValidParams(params);

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
        return _getIdentityGate(coordinator, coordinationType);
    }

    function _getIdentityGate(address coordinator, bytes32 coordinationType)
        internal
        view
        returns (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled)
    {
        IdentityGate storage gate = _gates[coordinator][coordinationType];
        return (gate.gatekeeperNode, gate.params, gate.enabled);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Forward resolution per ERC-137. Returns address(0) when the node has no
    ///      resolver, no addr record, or an off-chain (CCIP-Read) resolver.
    function resolveAgent(bytes32 node) public view override returns (address) {
        address resolver = ens.resolver(node);
        if (resolver == address(0)) return address(0);

        // Low-level, gas-capped, bounded-copy call. A participant controls its own
        // resolver, so a high-level call would let it make validation REVERT (no code,
        // short or dirty return data) or burn 63/64 of the caller's gas, either of
        // which aborts a coordinator looping over every participant of an intent.
        bytes memory data = abi.encodeWithSelector(IAddrResolver.addr.selector, node);
        bool ok;
        uint256 word;
        uint256 size;
        assembly ("memory-safe") {
            ok := staticcall(RESOLVE_GAS, resolver, add(data, 0x20), mload(data), 0, 0x20)
            size := returndatasize()
            word := mload(0)
        }
        if (!ok || size < 0x20 || word >> 160 != 0) return address(0);
        return address(uint160(word));
    }

    /// @inheritdoc ITrustRegistry
    /// @dev Reverts with GateNotFound when no gate is enabled, so a wrong coordinator
    ///      address or mistyped coordination type fails loudly instead of admitting
    ///      every participant.
    function validateParticipantWithPath(
        address coordinator,
        bytes32 coordinationType,
        bytes32 participantNode,
        TrustPath calldata path
    ) external view override returns (bool isValid) {
        (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled) =
            _getIdentityGate(coordinator, coordinationType);

        // No gate = misconfiguration, not open participation
        if (!enabled) revert GateNotFound(coordinationType);

        if (path.nodes.length < 2) return false;

        // Path MUST start at the gatekeeper...
        if (path.nodes[0] != gatekeeperNode) return false;

        // ...and MUST terminate at the participant being gated
        if (path.nodes[path.nodes.length - 1] != participantNode) return false;

        return _verifyPath(path, params, false);
    }

    /// @inheritdoc ITrustRegistry
    /// @dev The ERC-8001 hook. ERC-8001 lists participants by address, so the terminal
    ///      node is bound to `participant` through its ERC-137 forward address record.
    ///      Reverts with GateNotFound when no gate is enabled.
    function validateParticipantAddress(
        address coordinator,
        bytes32 coordinationType,
        address participant,
        TrustPath calldata path
    ) external view override returns (bool isValid) {
        (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled) =
            _getIdentityGate(coordinator, coordinationType);

        // No gate = misconfiguration, not open participation
        if (!enabled) revert GateNotFound(coordinationType);

        if (participant == address(0)) return false;
        if (path.nodes.length < 2) return false;
        if (path.nodes[0] != gatekeeperNode) return false;

        // The terminal node MUST be bound to the participant address
        if (resolveAgent(path.nodes[path.nodes.length - 1]) != participant) return false;

        return _verifyPath(path, params, false);
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

        // Attestations grant trust; withdrawal is expressed by revokeTrust. This keeps
        // exactly one path, one event, and one authorisation rule per level.
        if (attestation.level == TrustLevel.Unknown || attestation.level == TrustLevel.None) {
            revert InvalidAttestationLevel(attestation.level);
        }

        if (attestation.expiry != 0 && attestation.expiry <= block.timestamp) {
            revert AttestationExpired(attestation.expiry, uint64(block.timestamp));
        }

        if (ens.owner(attestation.trustorNode) == address(0)) revert ENSNameNotFound(attestation.trustorNode);

        uint64 currentNonce = _nonces[attestation.trustorNode];
        if (attestation.nonce <= currentNonce) revert NonceTooLow(attestation.nonce, _next(currentNonce));

        uint64 maxNonce = _maxNonce(currentNonce);
        if (attestation.nonce > maxNonce) revert NonceJumpTooLarge(attestation.nonce, maxNonce);

        // Covers a name with no controller too, such as a wrapped .eth name past its
        // grace period: controllerOf returns address(0)
        if (!verifySignature(attestation.trustorNode, hashAttestation(attestation), signature)) {
            revert InvalidSignature();
        }

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
            attestation.expiry,
            attestation.nonce
        );
    }

    /// @dev Resolve the real controller of a name, unwrapping NameWrapper names.
    ///      `ens.owner` returns the NameWrapper contract for wrapped names, and
    ///      NameWrapper does not implement EIP-1271, so using it directly would leave
    ///      every wrapped name unable to attest.
    function controllerOf(bytes32 node) internal view returns (address) {
        address owner = ens.owner(node);
        if (owner == address(0)) return address(0);

        // Wrapped name: the ERC-1155 holder is the real controller
        if (nameWrapper != address(0) && owner == nameWrapper) {
            try INameWrapper(nameWrapper).ownerOf(uint256(node)) returns (address wrapped) {
                // address(0) once a name with PARENT_CANNOT_CONTROL burned passes its
                // NameWrapper expiry; an unemancipated subname keeps its holder
                return wrapped;
            } catch {
                return address(0);
            }
        }

        return owner;
    }

    /// @dev Verify signature - signing authority is the name controller only
    function verifySignature(bytes32 node, bytes32 digest, bytes calldata signature) internal view returns (bool) {
        address controller = controllerOf(node);
        if (controller == address(0)) return false;

        // ECDSA first: covers plain EOAs and EIP-7702 delegated EOAs
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == controller) return true;

        // ERC-1271 fallback for any controller with code
        if (controller.code.length == 0) return false;
        // Low-level call with a returndata length check: a high-level call would revert
        // with empty data (not InvalidSignature) when the controller's code returns
        // nothing, e.g. an EIP-7702 delegate with an empty fallback
        return SignatureChecker.isValidERC1271SignatureNow(controller, digest, signature);
    }

    /// @dev Check if caller can submit a revokeTrust transaction
    function canSubmitRevocation(bytes32 node, address caller) internal view returns (bool) {
        address controller = controllerOf(node);
        if (controller == address(0)) return false;
        if (caller == controller) return true;

        // Approvals live on whichever contract actually holds the name
        if (nameWrapper != address(0) && ens.owner(node) == nameWrapper) {
            return INameWrapper(nameWrapper).isApprovedForAll(controller, caller);
        }

        return ens.isApprovedForAll(controller, caller);
    }

    /// @dev Highest nonce the floor may move to from `current` in one step. Bounded so
    ///      no single signature or call can exhaust the nonce space; caps at
    ///      type(uint64).max rather than wrapping.
    function _maxNonce(uint64 current) internal pure returns (uint64) {
        return current > type(uint64).max - MAX_NONCE_JUMP ? type(uint64).max : current + MAX_NONCE_JUMP;
    }

    /// @dev Saturating successor, so NonceTooLow reports cleanly at type(uint64).max
    function _next(uint64 current) internal pure returns (uint64) {
        return current == type(uint64).max ? current : current + 1;
    }

    /// @dev Controller only - authority for trustor-wide operations
    function _isController(bytes32 node, address caller) internal view returns (bool) {
        address controller = controllerOf(node);
        return controller != address(0) && caller == controller;
    }

    function requireValidParams(ValidationParams memory params) internal pure {
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
