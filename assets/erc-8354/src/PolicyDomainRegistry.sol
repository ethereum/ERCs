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

    /// @dev A root that is no longer current, with the moment it stopped being current.
    /// The grace window is measured from this timestamp, not from the current root's, so
    /// each superseded generation ages out on its own schedule.
    struct SupersededRoot {
        bytes32 root;
        uint64 supersededAt;
    }

    /// @dev How many superseded generations are retained per domain. The spec's grace rule
    /// is generation-agnostic — "current, or superseded less than maxRootAge ago" — so a
    /// single previous slot is wrong: rotating A->B->C inside the window drops A while it
    /// is still acceptable. History is a fixed-size ring rather than an unbounded array
    /// because the admin controls how often `updateRoot` is called, and an unbounded array
    /// would let it grow storage, and the `isRootAcceptable` scan, without limit. Eight
    /// covers realistic rotation rates: roots rotate administratively, and maxRootAge is
    /// measured in seconds-to-hours. If a domain does rotate more than eight times inside
    /// its own window, the oldest generations age out early — they are rejected sooner than
    /// maxRootAge, never later, so the overflow fails closed.
    uint256 private constant MAX_ROOT_HISTORY = 8;

    mapping(bytes32 => Domain) private _domains;
    mapping(bytes32 => RootEntry) private _current;
    mapping(bytes32 => SupersededRoot[MAX_ROOT_HISTORY]) private _history;
    mapping(bytes32 => uint256) private _rotations; // total supersessions; ring index is this modulo the size
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
        _domains[domainId] = Domain(registrar, address(0), verifier, programKey, maxRootAge, true);
        admin[domainId] = msg.sender;
        emit DomainRegistered(domainId, registrar, verifier, programKey);
    }

    /// @notice Declare (or clear) the ERC-8004 Identity Registry this domain's agent ids live in.
    /// A domain on a chain that hosts no Identity Registry leaves this at address(0), and the
    /// Guard's agent-existence check does not apply to it.
    function setIdentityRegistry(bytes32 domainId, address identityRegistry) external onlyAdmin(domainId) {
        address old = _domains[domainId].identityRegistry;
        _domains[domainId].identityRegistry = identityRegistry;
        emit DomainIdentityRegistryUpdated(domainId, old, identityRegistry);
    }

    function updateRoot(bytes32 domainId, bytes32 newRoot) external onlyAdmin(domainId) {
        RootEntry storage cur = _current[domainId];
        if (cur.root != bytes32(0)) {
            uint256 n = _rotations[domainId];
            _history[domainId][n % MAX_ROOT_HISTORY] = SupersededRoot(cur.root, uint64(block.timestamp));
            _rotations[domainId] = n + 1;
        }
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
        if (root == _current[domainId].root) return true;

        // A superseded root is acceptable until maxRootAge after it stopped being current.
        // The same root can be rotated back in and out, so take the latest supersession
        // recorded for it rather than the first match found.
        uint256 n = _rotations[domainId];
        uint256 len = n < MAX_ROOT_HISTORY ? n : MAX_ROOT_HISTORY;
        uint64 supersededAt = 0;
        for (uint256 i = 0; i < len; ++i) {
            SupersededRoot memory h = _history[domainId][i];
            if (h.root == root && h.supersededAt > supersededAt) supersededAt = h.supersededAt;
        }
        if (supersededAt == 0) return false;
        return block.timestamp < supersededAt + d.maxRootAge;
    }
}
