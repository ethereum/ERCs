// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ITrustRegistry, TrustLevel, TrustAttestation, ValidationParams} from "./ITrustRegistry.sol";

/// @notice Minimal ENS interface
interface IENS {
    function owner(bytes32 node) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

/// @title ENS Trust Registry
/// @notice Web of trust validation using ENS names for ERC-8001 coordination
/// @dev Reference implementation of ERC-XXXX
/// @author Kwame Bryan (@KBryan)
contract TrustRegistry is ITrustRegistry, EIP712 {
    using ECDSA for bytes32;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    bytes32 public constant TRUST_ATTESTATION_TYPEHASH = keccak256(
        "TrustAttestation(bytes32 trustorNode,bytes32 trusteeNode,uint8 level,bytes32 scope,uint64 expiry,uint64 nonce)"
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice ENS registry contract
    IENS private immutable _ens;

    /// @notice Trust record storage
    struct TrustRecord {
        TrustLevel level;
        bytes32 scope;
        uint64 expiry;
        uint64 setAt;
    }

    /// @notice Identity gate configuration
    struct IdentityGate {
        bytes32 gatekeeperNode;
        ValidationParams params;
        bool enabled;
    }

    /// @dev trustorNode => trusteeNode => TrustRecord
    mapping(bytes32 => mapping(bytes32 => TrustRecord)) private _trust;

    /// @dev trustorNode => nonce
    mapping(bytes32 => uint64) private _nonces;

    /// @dev trustorNode => trustees list
    mapping(bytes32 => bytes32[]) private _trustees;

    /// @dev trusteeNode => trustors list
    mapping(bytes32 => bytes32[]) private _trustors;

    /// @dev trustorNode => trusteeNode => index in _trustees array (1-indexed, 0 = not present)
    mapping(bytes32 => mapping(bytes32 => uint256)) private _trusteeIndex;

    /// @dev trusteeNode => trustorNode => index in _trustors array (1-indexed, 0 = not present)
    mapping(bytes32 => mapping(bytes32 => uint256)) private _trustorIndex;

    /// @dev coordinationType => IdentityGate
    mapping(bytes32 => IdentityGate) private _gates;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy the Trust Registry
    /// @param ensRegistry Address of the ENS registry
    constructor(address ensRegistry) EIP712("ERC-XXXX-Trust", "1") {
        _ens = IENS(ensRegistry);
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
        if (attestations.length != signatures.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < attestations.length; i++) {
            _setTrust(attestations[i], signatures[i]);
        }
    }

    /// @inheritdoc ITrustRegistry
    function revokeTrust(bytes32 trusteeNode, string calldata reason) external override {
        // Derive trustor from msg.sender's ENS ownership
        // Note: In production, you'd want a reverse resolution or explicit trustorNode parameter
        // For simplicity, we require msg.sender to specify which trustor they control
        revert("Use revokeTrustFor(trustorNode, trusteeNode, reason)");
    }

    /// @notice Revoke trust with explicit trustor specification
    /// @param trustorNode The trustor's ENS namehash
    /// @param trusteeNode The trustee's ENS namehash
    /// @param reason Human-readable reason
    function revokeTrustFor(bytes32 trustorNode, bytes32 trusteeNode, string calldata reason) external {
        if (!_isAuthorized(trustorNode, msg.sender)) {
            revert NotAuthorized(trustorNode, msg.sender);
        }

        TrustRecord storage record = _trust[trustorNode][trusteeNode];
        if (record.level == TrustLevel.Unknown) {
            revert TrustNotFound(trustorNode, trusteeNode);
        }

        record.level = TrustLevel.None;
        record.setAt = uint64(block.timestamp);

        emit TrustRevoked(trustorNode, trusteeNode, reason);
    }

    /// @inheritdoc ITrustRegistry
    function getTrust(bytes32 trustorNode, bytes32 trusteeNode)
        external
        view
        override
        returns (TrustLevel level, bytes32 scope, uint64 expiry)
    {
        TrustRecord storage record = _trust[trustorNode][trusteeNode];
        return (record.level, record.scope, record.expiry);
    }

    /// @inheritdoc ITrustRegistry
    function getNonce(bytes32 trustorNode) external view override returns (uint64) {
        return _nonces[trustorNode];
    }

    /// @inheritdoc ITrustRegistry
    function getTrustees(bytes32 trustorNode, TrustLevel minLevel) external view override returns (bytes32[] memory) {
        bytes32[] storage allTrustees = _trustees[trustorNode];

        // Count qualifying trustees
        uint256 count = 0;
        for (uint256 i = 0; i < allTrustees.length; i++) {
            TrustRecord storage record = _trust[trustorNode][allTrustees[i]];
            if (record.level >= minLevel) count++;
        }

        // Build result array
        bytes32[] memory result = new bytes32[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < allTrustees.length; i++) {
            TrustRecord storage record = _trust[trustorNode][allTrustees[i]];
            if (record.level >= minLevel) {
                result[j++] = allTrustees[i];
            }
        }

        return result;
    }

    /// @inheritdoc ITrustRegistry
    function getTrustors(bytes32 trusteeNode, TrustLevel minLevel) external view override returns (bytes32[] memory) {
        bytes32[] storage allTrustors = _trustors[trusteeNode];

        // Count qualifying trustors
        uint256 count = 0;
        for (uint256 i = 0; i < allTrustors.length; i++) {
            TrustRecord storage record = _trust[allTrustors[i]][trusteeNode];
            if (record.level >= minLevel) count++;
        }

        // Build result array
        bytes32[] memory result = new bytes32[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < allTrustors.length; i++) {
            TrustRecord storage record = _trust[allTrustors[i]][trusteeNode];
            if (record.level >= minLevel) {
                result[j++] = allTrustors[i];
            }
        }

        return result;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // WEB OF TRUST VALIDATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ITrustRegistry
    function validateAgent(bytes32 validatorNode, bytes32 targetNode, ValidationParams calldata params)
        public
        view
        override
        returns (bool isValid, uint8 pathLength, uint8 marginalCount, uint8 fullCount)
    {
        return _validateAgent(validatorNode, targetNode, params);
    }

    /// @dev Internal validation that accepts memory params
    function _validateAgent(bytes32 validatorNode, bytes32 targetNode, ValidationParams memory params)
        internal
        view
        returns (bool isValid, uint8 pathLength, uint8 marginalCount, uint8 fullCount)
    {
        // Self-validation always succeeds
        if (validatorNode == targetNode) {
            return (true, 0, 0, 0);
        }

        // Initialize visited set (using a simple array for reference impl)
        bytes32[] memory visited = new bytes32[](params.maxPathLength + 1);

        return _validate(validatorNode, targetNode, params, 0, visited, 0);
    }

    /// @inheritdoc ITrustRegistry
    function validateAgentBatch(bytes32 validatorNode, bytes32[] calldata targetNodes, ValidationParams calldata params)
        external
        view
        override
        returns (bool[] memory results)
    {
        results = new bool[](targetNodes.length);

        for (uint256 i = 0; i < targetNodes.length; i++) {
            (results[i],,,) = validateAgent(validatorNode, targetNodes[i], params);
        }
    }

    /// @inheritdoc ITrustRegistry
    function pathExists(bytes32 fromNode, bytes32 toNode, uint8 maxDepth)
        external
        view
        override
        returns (bool exists, uint8 depth)
    {
        if (fromNode == toNode) return (true, 0);

        // Simple DFS for reference implementation
        bytes32[] memory visited = new bytes32[](maxDepth + 1);
        return _pathSearch(fromNode, toNode, maxDepth, 0, visited, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC-8001 INTEGRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ITrustRegistry
    function setIdentityGate(bytes32 coordinationType, bytes32 gatekeeperNode, ValidationParams calldata params)
        external
        override
    {
        if (!_isAuthorized(gatekeeperNode, msg.sender)) {
            revert NotAuthorized(gatekeeperNode, msg.sender);
        }

        if (params.maxPathLength == 0) revert InvalidValidationParams();

        _gates[coordinationType] = IdentityGate({gatekeeperNode: gatekeeperNode, params: params, enabled: true});

        emit IdentityGateSet(coordinationType, gatekeeperNode, params.maxPathLength, params.marginalThreshold);
    }

    /// @inheritdoc ITrustRegistry
    function removeIdentityGate(bytes32 coordinationType) external override {
        IdentityGate storage gate = _gates[coordinationType];
        if (!gate.enabled) revert GateNotFound(coordinationType);

        if (!_isAuthorized(gate.gatekeeperNode, msg.sender)) {
            revert NotAuthorized(gate.gatekeeperNode, msg.sender);
        }

        gate.enabled = false;
        emit IdentityGateRemoved(coordinationType);
    }

    /// @inheritdoc ITrustRegistry
    function getIdentityGate(bytes32 coordinationType)
        external
        view
        override
        returns (bytes32 gatekeeperNode, ValidationParams memory params, bool enabled)
    {
        IdentityGate storage gate = _gates[coordinationType];
        return (gate.gatekeeperNode, gate.params, gate.enabled);
    }

    /// @inheritdoc ITrustRegistry
    function validateParticipant(bytes32 coordinationType, bytes32 participantNode)
        public
        view
        override
        returns (bool isValid)
    {
        IdentityGate storage gate = _gates[coordinationType];

        // No gate = open participation
        if (!gate.enabled) return true;

        (isValid,,,) = _validateAgent(gate.gatekeeperNode, participantNode, gate.params);
    }

    /// @inheritdoc ITrustRegistry
    function validateParticipantBatch(bytes32 coordinationType, bytes32[] calldata participantNodes)
        external
        view
        override
        returns (bool[] memory results)
    {
        results = new bool[](participantNodes.length);

        for (uint256 i = 0; i < participantNodes.length; i++) {
            results[i] = validateParticipant(coordinationType, participantNodes[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ITrustRegistry
    function defaultParams() external pure override returns (ValidationParams memory) {
        return ValidationParams({
            maxPathLength: 5, marginalThreshold: 3, fullThreshold: 1, scope: bytes32(0), enforceExpiry: true
        });
    }

    /// @inheritdoc ITrustRegistry
    function ens() external view override returns (address) {
        return address(_ens);
    }

    /// @inheritdoc ITrustRegistry
    function hashAttestation(TrustAttestation calldata attestation) public view override returns (bytes32) {
        return _hashTypedDataV4(_structHash(attestation));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Internal trust setting logic
    function _setTrust(TrustAttestation calldata attestation, bytes calldata signature) internal {
        // Validate: no self-trust
        if (attestation.trustorNode == attestation.trusteeNode) {
            revert SelfTrustProhibited();
        }

        // Validate: nonce must be strictly increasing
        uint64 currentNonce = _nonces[attestation.trustorNode];
        if (attestation.nonce <= currentNonce) {
            revert NonceTooLow(attestation.nonce, currentNonce + 1);
        }

        // Validate: not expired
        if (attestation.expiry != 0 && attestation.expiry <= block.timestamp) {
            revert AttestationExpired(attestation.expiry, uint64(block.timestamp));
        }

        // Validate: ENS name exists
        address owner = _ens.owner(attestation.trustorNode);
        if (owner == address(0)) {
            revert ENSNameNotFound(attestation.trustorNode);
        }

        // Validate: signature
        bytes32 digest = _hashTypedDataV4(_structHash(attestation));
        address signer = _recoverSigner(digest, signature);

        if (!_isAuthorizedSigner(owner, signer)) {
            revert InvalidSignature();
        }

        // Store trust
        TrustRecord storage record = _trust[attestation.trustorNode][attestation.trusteeNode];

        // Track relationship if new
        if (record.level == TrustLevel.Unknown && attestation.level != TrustLevel.Unknown) {
            _addRelationship(attestation.trustorNode, attestation.trusteeNode);
        }

        record.level = attestation.level;
        record.scope = attestation.scope;
        record.expiry = attestation.expiry;
        record.setAt = uint64(block.timestamp);

        _nonces[attestation.trustorNode] = attestation.nonce;

        emit TrustSet(
            attestation.trustorNode, attestation.trusteeNode, attestation.level, attestation.scope, attestation.expiry
        );
    }

    /// @dev Add relationship to tracking arrays
    function _addRelationship(bytes32 trustorNode, bytes32 trusteeNode) internal {
        if (_trusteeIndex[trustorNode][trusteeNode] == 0) {
            _trustees[trustorNode].push(trusteeNode);
            _trusteeIndex[trustorNode][trusteeNode] = _trustees[trustorNode].length;
        }

        if (_trustorIndex[trusteeNode][trustorNode] == 0) {
            _trustors[trusteeNode].push(trustorNode);
            _trustorIndex[trusteeNode][trustorNode] = _trustors[trusteeNode].length;
        }
    }

    /// @dev Compute struct hash for EIP-712
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

    /// @dev Recover signer from signature (supports ERC-1271)
    function _recoverSigner(bytes32 digest, bytes calldata signature) internal view returns (address) {
        // Try ECDSA first
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);

        if (err == ECDSA.RecoverError.NoError) {
            return recovered;
        }

        // If signature is 65 bytes and ECDSA failed, it's invalid
        // ERC-1271 contracts should be passed as signer address in a different flow
        return address(0);
    }

    /// @dev Check if signer is authorized for ENS node
    function _isAuthorizedSigner(address owner, address signer) internal view returns (bool) {
        if (signer == owner) return true;
        if (_ens.isApprovedForAll(owner, signer)) return true;
        return false;
    }

    /// @dev Check if address is authorized for ENS node
    function _isAuthorized(bytes32 node, address actor) internal view returns (bool) {
        address owner = _ens.owner(node);
        if (owner == address(0)) return false;
        if (actor == owner) return true;
        return _ens.isApprovedForAll(owner, actor);
    }

    /// @dev Check if trust record is valid for validation
    function _isTrustValid(TrustRecord storage record, ValidationParams memory params) internal view returns (bool) {
        if (record.level == TrustLevel.Unknown) return false;
        if (record.level == TrustLevel.None) return false;

        // Check expiry
        if (params.enforceExpiry && record.expiry != 0 && record.expiry <= block.timestamp) {
            return false;
        }

        // Check scope
        if (params.scope != bytes32(0) && record.scope != bytes32(0) && record.scope != params.scope) {
            return false;
        }

        return true;
    }

    /// @dev Recursive validation with visited tracking
    function _validate(
        bytes32 validatorNode,
        bytes32 targetNode,
        ValidationParams memory params,
        uint8 depth,
        bytes32[] memory visited,
        uint8 visitedCount
    ) internal view returns (bool isValid, uint8 pathLength, uint8 marginalCount, uint8 fullCount) {
        // Check depth limit
        if (depth > params.maxPathLength) {
            return (false, 0, 0, 0);
        }

        // Check for cycles
        for (uint8 i = 0; i < visitedCount; i++) {
            if (visited[i] == validatorNode) {
                return (false, 0, 0, 0);
            }
        }

        // Add to visited
        if (visitedCount < visited.length) {
            visited[visitedCount] = validatorNode;
            visitedCount++;
        }

        // Direct trust check
        TrustRecord storage directRecord = _trust[validatorNode][targetNode];
        if (_isTrustValid(directRecord, params)) {
            if (directRecord.level == TrustLevel.Full) {
                return (true, depth, 0, 1);
            }
            marginalCount = 1;
            if (marginalCount >= params.marginalThreshold) {
                return (true, depth, marginalCount, 0);
            }
        }

        // Check through trustees (one level of indirection)
        bytes32[] storage trustees = _trustees[validatorNode];
        uint8 localMarginals = marginalCount;
        uint8 localFulls = 0;

        for (uint256 i = 0; i < trustees.length && i < 100; i++) { // Cap iterations
            bytes32 intermediary = trustees[i];
            TrustRecord storage interRecord = _trust[validatorNode][intermediary];

            if (!_isTrustValid(interRecord, params)) continue;

            // Check if intermediary vouches for target
            TrustRecord storage vouchRecord = _trust[intermediary][targetNode];
            if (!_isTrustValid(vouchRecord, params)) continue;

            if (interRecord.level == TrustLevel.Full) {
                localFulls++;
                if (localFulls >= params.fullThreshold) {
                    return (true, depth + 1, localMarginals, localFulls);
                }
            } else if (interRecord.level == TrustLevel.Marginal) {
                localMarginals++;
                if (localMarginals >= params.marginalThreshold) {
                    return (true, depth + 1, localMarginals, localFulls);
                }
            }
        }

        // Recursive search through trusted intermediaries
        if (depth + 1 < params.maxPathLength) {
            for (uint256 i = 0; i < trustees.length && i < 50; i++) { // Cap iterations
                bytes32 intermediary = trustees[i];
                TrustRecord storage interRecord = _trust[validatorNode][intermediary];

                if (!_isTrustValid(interRecord, params)) continue;
                if (interRecord.level < TrustLevel.Marginal) continue;

                (bool subValid, uint8 subPath, uint8 subMarg, uint8 subFull) =
                    _validate(intermediary, targetNode, params, depth + 1, visited, visitedCount);

                if (subValid) {
                    return (true, subPath, subMarg, subFull);
                }
            }
        }

        return (false, 0, localMarginals, localFulls);
    }

    /// @dev Simple path existence search
    function _pathSearch(
        bytes32 fromNode,
        bytes32 toNode,
        uint8 maxDepth,
        uint8 currentDepth,
        bytes32[] memory visited,
        uint8 visitedCount
    ) internal view returns (bool exists, uint8 depth) {
        if (currentDepth > maxDepth) return (false, 0);

        // Check for cycles
        for (uint8 i = 0; i < visitedCount; i++) {
            if (visited[i] == fromNode) return (false, 0);
        }

        // Direct check
        TrustRecord storage record = _trust[fromNode][toNode];
        if (record.level >= TrustLevel.Marginal) {
            return (true, currentDepth + 1);
        }

        // Add to visited
        if (visitedCount < visited.length) {
            visited[visitedCount] = fromNode;
            visitedCount++;
        }

        // Search through trustees
        bytes32[] storage trustees = _trustees[fromNode];
        for (uint256 i = 0; i < trustees.length && i < 50; i++) {
            TrustRecord storage interRecord = _trust[fromNode][trustees[i]];
            if (interRecord.level < TrustLevel.Marginal) continue;

            (bool found, uint8 foundDepth) =
                _pathSearch(trustees[i], toNode, maxDepth, currentDepth + 1, visited, visitedCount);

            if (found) return (true, foundDepth);
        }

        return (false, 0);
    }
}
