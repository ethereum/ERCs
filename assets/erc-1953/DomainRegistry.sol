// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title DomainRegistry — Minimal Domain Lifecycle
/// @notice Tracks which orchestrator domains are active. Separate from CAPV
///         to preserve standard independence per ERC-XXXX §6.1.
contract DomainRegistry {
    struct Domain {
        bool registered;
        bool revoked;
    }

    mapping(uint256 => Domain) public domains;

    event DomainRegistered(uint256 indexed homeDomainId);
    event DomainRevoked(uint256 indexed homeDomainId);

    /// @notice Register a new orchestrator domain.
    function registerDomain(uint256 homeDomainId) external {
        require(!domains[homeDomainId].registered, "UAC: domain already registered");
        domains[homeDomainId] = Domain(true, false);
        emit DomainRegistered(homeDomainId);
    }

    /// @notice Revoke an existing domain.
    function revokeDomain(uint256 homeDomainId) external {
        require(domains[homeDomainId].registered, "UAC: domain not registered");
        require(!domains[homeDomainId].revoked, "UAC: domain already revoked");
        domains[homeDomainId].revoked = true;
        emit DomainRevoked(homeDomainId);
    }

    /// @notice Query whether a domain is registered and not revoked.
    function isActiveDomain(uint256 homeDomainId) external view returns (bool) {
        return domains[homeDomainId].registered && !domains[homeDomainId].revoked;
    }
}
