// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IGEOFRegistry} from "./interfaces/IGEOFRegistry.sol";

/// @title GEOFRegistry — reference implementation of the Generative Engine Optimization Framework registry
/// @notice Records content-addressed declarations, bounded observation processes with versioned
///         closure, attributable observation commitments and attributable profile publications.
///         Stores hashes, URIs, attribution and ordering only; interprets nothing.
/// @dev Non-upgradeable, ownerless. Clock: ERC-6372 timestamp mode. One deployment = one clock domain.
contract GEOFRegistry is IGEOFRegistry {
    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    struct Declaration {
        DeclarationKind kind;
        address declarant;
        bytes32 contentHash;
        bytes32 supersedes;
        uint48 declaredAt;
        bool exists;
        string uri;
    }

    struct Version {
        bytes32 evidenceRoot;
        uint48 observationCutoff;
        uint64 commitmentCount;
        bool frozen;
    }

    struct Process {
        address opener;
        bytes32 frameId;
        uint32 currentVersion;
        bool exists;
        bytes32[] objectIds;
        bytes32[] intentIds;
        bytes32[] sourceIds;
        bytes32[] methodIds;
        mapping(uint32 => Version) versions;
    }

    struct Profile {
        bytes32 processId;
        uint32 version;
        address publisher;
        bytes32 profileHash;
        bytes32 supersedes;
        uint48 publishedAt;
        bool exists;
        string uri;
    }

    mapping(bytes32 => Declaration) private _declarations;
    mapping(bytes32 => bytes32) private _subjectOf;
    mapping(bytes32 => Process) private _processes;
    mapping(bytes32 => Profile) private _profiles;
    mapping(address => uint256) private _processNonces;

    // ---------------------------------------------------------------------
    // ERC-165 / ERC-6372
    // ---------------------------------------------------------------------

    /// @dev ERC-165: 0x01ffc9a7; ERC-6372: 0xda287a1d; IGEOFRegistry: type(IGEOFRegistry).interfaceId
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == 0xda287a1d || interfaceId == type(IGEOFRegistry).interfaceId;
    }

    function clock() public view returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }

    // ---------------------------------------------------------------------
    // Declarations
    // ---------------------------------------------------------------------

    function declare(DeclarationKind kind, bytes32 contentHash, bytes32 supersedes, string calldata uri)
        external
        returns (bytes32 id)
    {
        if (kind == DeclarationKind.OBJECT) revert GEOF_WrongKind(bytes32(0), kind);
        id = _declare(kind, contentHash, supersedes, uri);
    }

    function declareObject(bytes32 subjectId, bytes32 contentHash, bytes32 supersedes, string calldata uri)
        external
        returns (bytes32 id)
    {
        if (subjectId == bytes32(0)) revert GEOF_ZeroHash();
        id = _declare(DeclarationKind.OBJECT, contentHash, supersedes, uri);
        _subjectOf[id] = subjectId;
        emit SubjectBound(id, subjectId);
    }

    function _declare(DeclarationKind kind, bytes32 contentHash, bytes32 supersedes, string calldata uri)
        internal
        returns (bytes32 id)
    {
        if (contentHash == bytes32(0)) revert GEOF_ZeroHash();
        id = keccak256(abi.encode(kind, msg.sender, contentHash));
        if (_declarations[id].exists) revert GEOF_DuplicateDeclaration(id);
        if (supersedes != bytes32(0)) {
            Declaration storage prev = _declarations[supersedes];
            if (!prev.exists) revert GEOF_UnknownDeclaration(supersedes);
            if (prev.kind != kind || prev.declarant != msg.sender) revert GEOF_SupersedesMismatch(supersedes);
        }
        _declarations[id] = Declaration({
            kind: kind,
            declarant: msg.sender,
            contentHash: contentHash,
            supersedes: supersedes,
            declaredAt: clock(),
            exists: true,
            uri: uri
        });
        emit Declared(id, kind, msg.sender, contentHash, supersedes, uri);
    }

    // ---------------------------------------------------------------------
    // Processes
    // ---------------------------------------------------------------------

    function openProcess(
        bytes32 frameId,
        bytes32[] calldata objectIds,
        bytes32[] calldata intentIds,
        bytes32[] calldata sourceIds,
        bytes32[] calldata methodIds
    ) external returns (bytes32 processId) {
        _requireKind(frameId, DeclarationKind.FRAME);
        if (objectIds.length == 0) revert GEOF_EmptyBinding();
        _requireKinds(objectIds, DeclarationKind.OBJECT);
        _requireKinds(intentIds, DeclarationKind.INTENT);
        _requireKinds(sourceIds, DeclarationKind.SOURCE);
        _requireKinds(methodIds, DeclarationKind.METHOD);

        uint256 nonce = _processNonces[msg.sender]++;
        // deterministic per (opener, frame, per-opener nonce): predictable off-chain, independent of block time
        processId = keccak256(abi.encode(msg.sender, frameId, nonce));
        Process storage p = _processes[processId];
        if (p.exists) revert GEOF_DuplicateDeclaration(processId);
        p.opener = msg.sender;
        p.frameId = frameId;
        p.currentVersion = 1;
        p.exists = true;
        p.objectIds = objectIds;
        p.intentIds = intentIds;
        p.sourceIds = sourceIds;
        p.methodIds = methodIds;

        emit ProcessOpened(processId, msg.sender, frameId, objectIds, intentIds, sourceIds, methodIds);
    }

    function commitObservations(bytes32 processId, bytes32 root, uint64 count, ObservationKind kind) external {
        Process storage p = _requireProcess(processId);
        if (root == bytes32(0)) revert GEOF_ZeroHash();
        if (count == 0) revert GEOF_ZeroCount();
        uint32 v = p.currentVersion;
        Version storage ver = p.versions[v];
        if (ver.frozen) revert GEOF_VersionFrozen(processId, v);
        ver.commitmentCount += 1;
        emit ObservationsCommitted(processId, v, msg.sender, root, count, kind);
    }

    function closeProcess(bytes32 processId, bytes32 evidenceRoot, uint48 observationCutoff) external {
        Process storage p = _requireProcess(processId);
        if (p.opener != msg.sender) revert GEOF_NotOpener(processId, msg.sender);
        uint32 v = p.currentVersion;
        Version storage ver = p.versions[v];
        if (ver.frozen) revert GEOF_VersionFrozen(processId, v);
        ver.evidenceRoot = evidenceRoot;
        ver.observationCutoff = observationCutoff;
        ver.frozen = true;
        emit ProcessClosed(processId, v, evidenceRoot, observationCutoff);
    }

    function openAddendum(bytes32 processId) external returns (uint32 version) {
        Process storage p = _requireProcess(processId);
        if (p.opener != msg.sender) revert GEOF_NotOpener(processId, msg.sender);
        uint32 v = p.currentVersion;
        if (!p.versions[v].frozen) revert GEOF_VersionOpen(processId, v);
        version = v + 1;
        p.currentVersion = version;
        emit AddendumOpened(processId, version);
    }

    // ---------------------------------------------------------------------
    // Profiles
    // ---------------------------------------------------------------------

    function publishProfile(bytes32 processId, uint32 version, bytes32 profileHash, bytes32 supersedes, string calldata uri)
        external
        returns (bytes32 profileId)
    {
        Process storage p = _requireProcess(processId);
        if (profileHash == bytes32(0)) revert GEOF_ZeroHash();
        if (version == 0 || version > p.currentVersion) revert GEOF_UnknownVersion(processId, version);
        if (!p.versions[version].frozen) revert GEOF_VersionOpen(processId, version);
        if (supersedes != bytes32(0)) {
            Profile storage prev = _profiles[supersedes];
            if (!prev.exists) revert GEOF_UnknownProfile(supersedes);
            if (prev.publisher != msg.sender || prev.processId != processId) revert GEOF_SupersedesMismatch(supersedes);
        }
        profileId = keccak256(abi.encode(processId, version, msg.sender, profileHash));
        if (_profiles[profileId].exists) revert GEOF_DuplicateProfile(profileId);
        _profiles[profileId] = Profile({
            processId: processId,
            version: version,
            publisher: msg.sender,
            profileHash: profileHash,
            supersedes: supersedes,
            publishedAt: clock(),
            exists: true,
            uri: uri
        });
        emit ProfilePublished(profileId, processId, version, msg.sender, profileHash, supersedes, uri);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function declarationOf(bytes32 id)
        external
        view
        returns (
            DeclarationKind kind,
            address declarant,
            bytes32 contentHash,
            bytes32 supersedes,
            uint48 declaredAt,
            string memory uri
        )
    {
        Declaration storage d = _declarations[id];
        if (!d.exists) revert GEOF_UnknownDeclaration(id);
        return (d.kind, d.declarant, d.contentHash, d.supersedes, d.declaredAt, d.uri);
    }

    function subjectOf(bytes32 id) external view returns (bytes32 subjectId) {
        if (!_declarations[id].exists) revert GEOF_UnknownDeclaration(id);
        return _subjectOf[id];
    }

    function processOf(bytes32 processId)
        external
        view
        returns (address opener, bytes32 frameId, uint32 currentVersion, bool open)
    {
        Process storage p = _requireProcess(processId);
        return (p.opener, p.frameId, p.currentVersion, !p.versions[p.currentVersion].frozen);
    }

    function processBindings(bytes32 processId)
        external
        view
        returns (
            bytes32[] memory objectIds,
            bytes32[] memory intentIds,
            bytes32[] memory sourceIds,
            bytes32[] memory methodIds
        )
    {
        Process storage p = _requireProcess(processId);
        return (p.objectIds, p.intentIds, p.sourceIds, p.methodIds);
    }

    function versionOf(bytes32 processId, uint32 version)
        external
        view
        returns (bytes32 evidenceRoot, uint48 observationCutoff, uint64 commitmentCount, bool frozen)
    {
        Process storage p = _requireProcess(processId);
        if (version == 0 || version > p.currentVersion) revert GEOF_UnknownVersion(processId, version);
        Version storage ver = p.versions[version];
        return (ver.evidenceRoot, ver.observationCutoff, ver.commitmentCount, ver.frozen);
    }

    function profileOf(bytes32 profileId)
        external
        view
        returns (
            bytes32 processId,
            uint32 version,
            address publisher,
            bytes32 profileHash,
            bytes32 supersedes,
            uint48 publishedAt,
            string memory uri
        )
    {
        Profile storage pr = _profiles[profileId];
        if (!pr.exists) revert GEOF_UnknownProfile(profileId);
        return (pr.processId, pr.version, pr.publisher, pr.profileHash, pr.supersedes, pr.publishedAt, pr.uri);
    }

    // ---------------------------------------------------------------------
    // Internal checks
    // ---------------------------------------------------------------------

    function _requireProcess(bytes32 processId) internal view returns (Process storage p) {
        p = _processes[processId];
        if (!p.exists) revert GEOF_UnknownProcess(processId);
    }

    function _requireKind(bytes32 id, DeclarationKind expected) internal view {
        Declaration storage d = _declarations[id];
        if (!d.exists) revert GEOF_UnknownDeclaration(id);
        if (d.kind != expected) revert GEOF_WrongKind(id, expected);
    }

    function _requireKinds(bytes32[] calldata ids, DeclarationKind expected) internal view {
        for (uint256 i = 0; i < ids.length; i++) {
            _requireKind(ids[i], expected);
        }
    }
}
