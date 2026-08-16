// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title CapabilityCommitment — Canonical Domain-Separated Hashing
/// @notice Computes nullifier and capability commitment exactly as specified
///         in ERC-XXXX §3.3. These functions MUST be used by both the circuit
///         and any Solidity-side parity checks.
library CapabilityCommitment {
    bytes32 internal constant NULLIFIER_TAG = keccak256("ERC-XXXX/nullifier/v1");
    bytes32 internal constant CAPABILITY_TAG = keccak256("ERC-XXXX/capability/v1");

    /// @notice Compute nullifier = H(NULLIFIER_TAG, salt)
    function computeNullifier(bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(NULLIFIER_TAG, salt));
    }

    /// @notice Compute capabilityCommitment = H(CAPABILITY_TAG, salt, agentId, homeChainId,
    ///         homeDomainId, capabilityIndex, actionCommitment)
    function computeCapabilityCommitment(
        bytes32 salt,
        uint256 agentId,
        uint256 homeChainId,
        uint256 homeDomainId,
        uint256 capabilityIndex,
        bytes32 actionCommitment
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                CAPABILITY_TAG,
                salt,
                bytes32(agentId),
                bytes32(homeChainId),
                bytes32(homeDomainId),
                bytes32(capabilityIndex),
                actionCommitment
            )
        );
    }
}
