// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IPolicyDomainRegistry} from "./IPolicyDomainRegistry.sol";

/// @notice A concrete policy-domain registry. Per-domain admin registers the domain,
/// rotates the root/program, and can revoke. Revocation bypasses the grace window.
contract PolicyDomainRegistry is IPolicyDomainRegistry {
    struct RootEntry {
        bytes32 root;
        uint64 version;
        uint64 updatedAt;
    }

    mapping(bytes32 => Domain) private _domains;
    mapping(bytes32 => RootEntry) private _current;
    mapping(bytes32 => RootEntry) private _previous; // superseded root, kept for the grace window
    mapping(bytes32 => address) public admin;

    error NotAdmin();
    error DomainExists();

    modifier onlyAdmin(bytes32 domainId) {
        if (msg.sender != admin[domainId]) revert NotAdmin();
        _;
    }

    function registerDomain(
        bytes32 domainId,
        address registrar,
        address verifier,
        bytes32 programKey,
        uint64 maxRootAge
    ) external {
        if (_domains[domainId].registrar != address(0)) revert DomainExists();
        _domains[domainId] = Domain(registrar, verifier, programKey, maxRootAge, true);
        admin[domainId] = msg.sender;
        emit DomainRegistered(domainId, registrar, verifier, programKey);
    }

    function updateRoot(bytes32 domainId, bytes32 newRoot) external onlyAdmin(domainId) {
        RootEntry storage cur = _current[domainId];
        if (cur.root != bytes32(0)) _previous[domainId] = cur;
        uint64 version = cur.version + 1;
        _current[domainId] = RootEntry(newRoot, version, uint64(block.timestamp));
        emit DomainRootUpdated(domainId, newRoot, version, uint64(block.timestamp));
    }

    function updateProgram(bytes32 domainId, bytes32 newProgramKey) external onlyAdmin(domainId) {
        bytes32 old = _domains[domainId].programKey;
        _domains[domainId].programKey = newProgramKey;
        emit DomainProgramUpdated(domainId, old, newProgramKey);
    }

    function revokeDomain(bytes32 domainId) external onlyAdmin(domainId) {
        _domains[domainId].active = false;
        emit DomainRevoked(domainId);
    }

    function domain(bytes32 domainId) external view returns (Domain memory) {
        return _domains[domainId];
    }

    function currentRoot(bytes32 domainId) external view returns (bytes32, uint64, uint64) {
        RootEntry memory c = _current[domainId];
        return (c.root, c.version, c.updatedAt);
    }

    function isRootAcceptable(bytes32 domainId, bytes32 root) external view returns (bool) {
        Domain memory d = _domains[domainId];
        if (!d.active) return false; // revocation: no grace, immediate
        if (root == bytes32(0)) return false;
        RootEntry memory c = _current[domainId];
        if (root == c.root) return true;
        RootEntry memory p = _previous[domainId];
        // A superseded root is acceptable until maxRootAge after the current root took over.
        if (p.updatedAt != 0 && root == p.root) {
            return block.timestamp < c.updatedAt + d.maxRootAge;
        }
        return false;
    }
}
