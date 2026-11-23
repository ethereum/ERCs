// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title IGEOFRegistry — Generative Engine Optimization Framework registry
/// @notice Minimal on-chain kernel of the GEO Framework: content-addressed declarations
///         (Object, Frame, Source, Method, Intent, Metric Definition), bounded observation
///         containers (Process) with versioned closure, attributable observation commitments
///         and attributable profile publications.
/// @dev The registry stores hashes, URIs, attribution and ordering only. It never interprets,
///      validates or scores the content of any record. Implementations MUST also implement
///      ERC-165 (`supportsInterface`) and ERC-6372 (`clock`, `CLOCK_MODE`); every stored time
///      is a value of this registry's own clock, and one deployment has exactly one clock domain.
interface IGEOFRegistry {
    // ---------------------------------------------------------------------
    // Enums
    // ---------------------------------------------------------------------

    /// @notice Kinds of content-addressed declarations.
    enum DeclarationKind {
        OBJECT, // a subject being represented (engine-independent)
        FRAME, // the seven-dimension observation boundary
        SOURCE, // a data source with class, roles, party and verifiability
        METHOD, // an immutable, versioned method descriptor
        INTENT, // a dissemination intent (optional for a process)
        METRIC // an immutable, versioned metric definition
    }

    /// @notice Kinds of observations committed to a process version.
    enum ObservationKind {
        EVENT, // one run or delivery instance
        AGGREGATE, // period counts from a source whose granularity does not reach instances
        FOLLOWUP, // a recipient action after a representation, with a link basis
        INTERVENTION // an action on the object or its carriers
    }

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    /// @notice A declaration was recorded.
    /// @param id          keccak256(abi.encode(kind, declarant, contentHash))
    /// @param kind        the declaration kind
    /// @param declarant   the submitting account; a declaration confers no control over its subject
    /// @param contentHash keccak256 of the JCS-canonical record
    /// @param supersedes  id of the previous version by the same declarant, or zero
    /// @param uri         where the record resolves
    event Declared(
        bytes32 indexed id,
        DeclarationKind indexed kind,
        address indexed declarant,
        bytes32 contentHash,
        bytes32 supersedes,
        string uri
    );

    /// @notice An OBJECT declaration was bound to a subject identifier. Several declarations
    ///         for one subjectId MAY coexist.
    event SubjectBound(bytes32 indexed id, bytes32 indexed subjectId);

    /// @notice A process was opened at version 1.
    event ProcessOpened(
        bytes32 indexed processId,
        address indexed opener,
        bytes32 indexed frameId,
        bytes32[] objectIds,
        bytes32[] intentIds,
        bytes32[] sourceIds,
        bytes32[] methodIds
    );

    /// @notice Observations were committed to an open process version.
    /// @param root  Merkle root over the canonical observation records
    /// @param count number of leaves under the root
    event ObservationsCommitted(
        bytes32 indexed processId,
        uint32 indexed version,
        address indexed observer,
        bytes32 root,
        uint64 count,
        ObservationKind kind
    );

    /// @notice The current version of a process was frozen by its opener.
    /// @param evidenceRoot      root over all commitments of this version, as the opener computed it
    /// @param observationCutoff clock value after which receptions are no longer attributed to this version
    event ProcessClosed(bytes32 indexed processId, uint32 indexed version, bytes32 evidenceRoot, uint48 observationCutoff);

    /// @notice A new open version was created for late observations.
    event AddendumOpened(bytes32 indexed processId, uint32 indexed version);

    /// @notice A profile was published against a frozen process version.
    /// @param profileId   keccak256(abi.encode(processId, version, publisher, profileHash))
    /// @param supersedes  id of the publisher's previous profile on the same process, or zero
    event ProfilePublished(
        bytes32 indexed profileId,
        bytes32 indexed processId,
        uint32 version,
        address indexed publisher,
        bytes32 profileHash,
        bytes32 supersedes,
        string uri
    );

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error GEOF_UnknownDeclaration(bytes32 id);
    error GEOF_WrongKind(bytes32 id, DeclarationKind expected);
    error GEOF_DuplicateDeclaration(bytes32 id);
    error GEOF_SupersedesMismatch(bytes32 supersedes);
    error GEOF_UnknownProcess(bytes32 processId);
    error GEOF_NotOpener(bytes32 processId, address caller);
    error GEOF_VersionFrozen(bytes32 processId, uint32 version);
    error GEOF_VersionOpen(bytes32 processId, uint32 version);
    error GEOF_UnknownVersion(bytes32 processId, uint32 version);
    error GEOF_UnknownProfile(bytes32 profileId);
    error GEOF_DuplicateProfile(bytes32 profileId);
    error GEOF_EmptyBinding();
    error GEOF_ZeroCount();
    error GEOF_ZeroHash();

    // ---------------------------------------------------------------------
    // Declarations
    // ---------------------------------------------------------------------

    /// @notice Record a FRAME, SOURCE, METHOD, INTENT or METRIC declaration.
    /// @dev Callable by any account. Reverts with GEOF_DuplicateDeclaration when the same account
    ///      re-declares an identical record. `supersedes`, when non-zero, MUST name a declaration
    ///      of the same kind by the same declarant. OBJECT declarations use `declareObject`.
    function declare(DeclarationKind kind, bytes32 contentHash, bytes32 supersedes, string calldata uri)
        external
        returns (bytes32 id);

    /// @notice Record an OBJECT declaration and bind it to a subject identifier.
    /// @param subjectId keccak256 of the canonical subject string `<scheme>:<domain>:<identifier>`
    function declareObject(bytes32 subjectId, bytes32 contentHash, bytes32 supersedes, string calldata uri)
        external
        returns (bytes32 id);

    // ---------------------------------------------------------------------
    // Processes
    // ---------------------------------------------------------------------

    /// @notice Open a process at version 1, binding a frame, objects, optional intents and the
    ///         sources and methods the opener announces.
    /// @dev Every referenced id MUST exist and have the expected kind. intentIds MAY be empty.
    function openProcess(
        bytes32 frameId,
        bytes32[] calldata objectIds,
        bytes32[] calldata intentIds,
        bytes32[] calldata sourceIds,
        bytes32[] calldata methodIds
    ) external returns (bytes32 processId);

    /// @notice Commit a batch of observations to the current open version of a process.
    /// @dev Callable by any account; attributable to msg.sender. Reverts with GEOF_VersionFrozen
    ///      when the current version is closed.
    function commitObservations(bytes32 processId, bytes32 root, uint64 count, ObservationKind kind) external;

    /// @notice Freeze the current version of a process. Opener only.
    function closeProcess(bytes32 processId, bytes32 evidenceRoot, uint48 observationCutoff) external;

    /// @notice Open the next version of a process for late observations. Opener only; reverts with
    ///         GEOF_VersionOpen while the current version is still open.
    function openAddendum(bytes32 processId) external returns (uint32 version);

    // ---------------------------------------------------------------------
    // Profiles
    // ---------------------------------------------------------------------

    /// @notice Publish a profile against a frozen process version.
    /// @dev Callable by any account. `supersedes`, when non-zero, MUST name a profile by the same
    ///      publisher on the same process. The registry designates no official profile.
    function publishProfile(bytes32 processId, uint32 version, bytes32 profileHash, bytes32 supersedes, string calldata uri)
        external
        returns (bytes32 profileId);

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
        );

    /// @notice Subject identifier bound to an OBJECT declaration (zero for other kinds).
    function subjectOf(bytes32 id) external view returns (bytes32 subjectId);

    function processOf(bytes32 processId)
        external
        view
        returns (address opener, bytes32 frameId, uint32 currentVersion, bool open);

    function processBindings(bytes32 processId)
        external
        view
        returns (
            bytes32[] memory objectIds,
            bytes32[] memory intentIds,
            bytes32[] memory sourceIds,
            bytes32[] memory methodIds
        );

    function versionOf(bytes32 processId, uint32 version)
        external
        view
        returns (bytes32 evidenceRoot, uint48 observationCutoff, uint64 commitmentCount, bool frozen);

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
        );
}
