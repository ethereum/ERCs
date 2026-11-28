// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {
    Polarity,
    Mode,
    Match,
    EntryStatus,
    Basis,
    SetKind,
    SubjectRef,
    Scope,
    Criteria,
    ListConfig,
    ListInfo,
    EntryInput,
    Entry,
    Request,
    Finding
} from "./AAFTypes.sol";

/// @title Registry of scopes, criteria, lists and entries
/// @notice Records who lists what on which ground, and answers whether a subject matches a list.
/// A list recorded here has no effect on anybody until an adopter binds it.
interface IAAFRegistry {
    event ScopeDeclared(
        bytes32 indexed scopeId, address indexed anchor, bytes32 context, bytes32 documentHash, string uri, address declarer
    );
    event CriteriaRegistered(
        bytes32 indexed criteriaId,
        address indexed module,
        bytes32 documentHash,
        bytes32 moduleCodeHash,
        bytes32 moduleConfig,
        bytes32 rule,
        uint8 fanout,
        string uri
    );
    event ListCreated(
        bytes32 indexed listId,
        address indexed manager,
        Polarity polarity,
        Mode mode,
        bytes32 scopeId,
        bytes32 source,
        uint32 noticePeriod,
        string uri
    );
    /// @dev Emitted by every act that raises the revision of a list.
    event ListRevised(bytes32 indexed listId, uint64 revision, bytes32 stateHash);
    event CriteriaSet(bytes32 indexed listId, bytes32 criteriaId);
    event SourcePinSet(bytes32 indexed listId, bytes32 sourcePin);
    event ManagerOffered(bytes32 indexed listId, address indexed candidate);
    event ManagerChanged(bytes32 indexed listId, address indexed previousManager, address indexed manager);
    event ListClosed(bytes32 indexed listId);
    event EntryAdded(
        bytes32 indexed listId,
        bytes32 indexed subjectKey,
        SubjectRef subject,
        uint32 serial,
        uint64 validFrom,
        uint64 validUntil,
        Basis basis,
        bytes32 basisHash,
        bytes32 reason,
        address controller,
        bytes32 codeHash,
        string basisURI
    );
    event EntryStatusChanged(
        bytes32 indexed listId, bytes32 indexed subjectKey, uint32 serial, EntryStatus status, bytes32 reason
    );
    event SetCommitted(bytes32 indexed listId, bytes32 root, SetKind kind, uint64 size, string uri);
    event ObjectionFiled(
        bytes32 indexed listId, bytes32 indexed subjectKey, address indexed filer, bytes32 objectionHash, string uri
    );

    error NotManager();
    error UnknownList();
    error UnknownCriteria();
    error ListExists();
    error ListIsClosed();
    error WrongMode();
    error InvalidConfig();
    error InvalidWindow();
    error BasisRequired();
    error EntryExists();
    error EntryNotFound();
    error NotCandidate();
    error CodePinNotSupported();

    // ------------------------------------------------------------ identifiers

    function subjectKeyOf(SubjectRef calldata subject) external pure returns (bytes32);
    function scopeIdOf(Scope calldata scope) external view returns (bytes32);
    function criteriaIdOf(Criteria calldata criteria) external view returns (bytes32);
    function listIdOf(address creator, ListConfig calldata config) external view returns (bytes32);

    // ------------------------------------------------------------ scopes and criteria

    /// @notice Records a scope. Anyone may declare one; declaring gives no right over the anchor.
    function declareScope(Scope calldata scope, string calldata uri) external returns (bytes32 scopeId);

    /// @notice Records one version of criteria. The code hash and the configuration of the module
    /// are read at this moment and become part of the identifier.
    function registerCriteria(
        bytes32 documentHash,
        address module,
        bytes32 rule,
        uint8 fanout,
        string calldata uri
    ) external returns (bytes32 criteriaId);

    function scopeOf(bytes32 scopeId) external view returns (Scope memory);
    function criteriaOf(bytes32 criteriaId) external view returns (Criteria memory);

    // ------------------------------------------------------------ lists

    /// @notice Creates a list managed by the caller. Polarity, mode and source never change.
    function createList(ListConfig calldata config, string calldata uri) external returns (bytes32 listId);

    function setCriteria(bytes32 listId, bytes32 criteriaId) external;
    function setSourcePin(bytes32 listId, bytes32 sourcePin) external;
    function offerManager(bytes32 listId, address candidate) external;
    function acceptManager(bytes32 listId) external;
    function closeList(bytes32 listId) external;

    function listOf(bytes32 listId) external view returns (ListInfo memory);

    /// @notice The revision of a list and the hash that identifies its state. The hash covers the
    /// manager, the criteria, the committed set and, for a derived list, the state of its source.
    function stateOf(bytes32 listId) external view returns (uint64 revision, bytes32 stateHash);

    // ------------------------------------------------------------ entries (ENUMERATED)

    function addEntry(bytes32 listId, SubjectRef calldata subject, EntryInput calldata input, string calldata basisURI)
        external
        returns (bytes32 subjectKey);
    function suspendEntry(bytes32 listId, bytes32 subjectKey, bytes32 reason) external;
    function resumeEntry(bytes32 listId, bytes32 subjectKey, bytes32 reason) external;
    function revokeEntry(bytes32 listId, bytes32 subjectKey, bytes32 reason) external;

    /// @notice Records an objection to an entry. It changes nothing in the list.
    function fileObjection(bytes32 listId, bytes32 subjectKey, bytes32 objectionHash, string calldata uri) external;

    function entryOf(bytes32 listId, bytes32 subjectKey) external view returns (Entry memory);

    // ------------------------------------------------------------ committed sets (COMMITTED)

    function commitSet(bytes32 listId, bytes32 root, SetKind kind, uint64 size, string calldata uri) external;

    /// @notice Checks a SetProof for `subjectKey` against a root over `size` leaves.
    function verifySetProof(bytes32 root, SetKind kind, uint64 size, bytes32 subjectKey, bytes calldata evidence)
        external
        pure
        returns (Match result, bytes32 reason);

    // ------------------------------------------------------------ results

    /// @notice What the list says about the subject without a request and without evidence.
    function check(bytes32 listId, SubjectRef calldata subject) external view returns (Match result, bytes32 reason);

    /// @notice What the list says about the subject for a request, given evidence. Never reverts
    /// for an unknown list, a failed module or malformed evidence: those are undetermined results.
    function matchOf(bytes32 listId, SubjectRef calldata subject, Request calldata request, bytes calldata evidence)
        external
        view
        returns (Finding memory);
}
