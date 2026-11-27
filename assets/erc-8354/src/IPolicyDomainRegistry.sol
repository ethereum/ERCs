// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @notice RECOMMENDED companion: manages policy domains + their roots.
interface IPolicyDomainRegistry {
    struct Domain {
        address registrar;        // ERC-7812 Registrar that owns this domain's statements
        address identityRegistry; // ERC-8004 Identity Registry; address(0) declares none
        address verifier;         // proof verifier for this domain's program
        bytes32 programKey;       // verification key / program commitment
        uint64  maxRootAge;       // seconds a superseded root stays acceptable
        bool    active;
    }

    event DomainRegistered(bytes32 indexed domainId, address registrar, address verifier, bytes32 programKey);
    event DomainRootUpdated(bytes32 indexed domainId, bytes32 newRoot, uint64 version, uint64 updatedAt);
    event DomainProgramUpdated(bytes32 indexed domainId, bytes32 oldProgramKey, bytes32 newProgramKey);
    event DomainIdentityRegistryUpdated(bytes32 indexed domainId, address oldRegistry, address newRegistry);
    event DomainRevoked(bytes32 indexed domainId);

    function domain(bytes32 domainId) external view returns (Domain memory);
    function currentRoot(bytes32 domainId) external view returns (bytes32 root, uint64 version, uint64 updatedAt);

    /// @notice Current root, or a root superseded < maxRootAge ago. A revoked domain returns false for all.
    function isRootAcceptable(bytes32 domainId, bytes32 root) external view returns (bool);
}
