// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title IAIFPParadigmRegistry
/// @notice Registry of flow paradigm descriptors. A paradigm is identified by the keccak256 of its
///         canonical descriptor (JCS, RFC 8785) and never changes; a change is a new version in the
///         same family. The registry records hashes, labels, role predicate commitments, family
///         control and succession; it does not interpret the descriptor.
interface IAIFPParadigmRegistry {
    struct RolePredicate {
        uint16 role; // a single role bit
        bytes32 predicateHash; // keccak256(abi.encode(AIFPPredicates.Node[]))
    }

    struct ParadigmRecord {
        bytes32 family;
        bytes32 supersedes;
        address registrant;
        uint48 registeredAt;
        string descriptorURI;
    }

    event ParadigmRegistered(
        bytes32 indexed paradigmId,
        bytes32 indexed family,
        bytes32 indexed supersedes,
        address registrant,
        string descriptorURI
    );
    /// @dev The canonical descriptor bytes, emitted once so that indexers can reconstruct the paradigm.
    event ParadigmDescriptor(bytes32 indexed paradigmId, bytes canonicalDescriptor);
    event FamilyControllerChanged(bytes32 indexed family, address indexed previousController, address indexed newController);

    error AIFP_ParadigmExists(bytes32 paradigmId);
    error AIFP_UnknownParadigm(bytes32 paradigmId);
    error AIFP_NotFamilyController(bytes32 family, address caller);
    error AIFP_SupersedesOutsideFamily(bytes32 supersedes, bytes32 family);
    error AIFP_InvalidRole(uint16 role);
    error AIFP_EmptyDescriptor();

    /// @notice Registers a paradigm version. The first registration in a family makes the caller its
    ///         controller; later versions in the family require the controller.
    function registerParadigm(
        bytes calldata canonicalDescriptor,
        bytes32 family,
        bytes32 supersedes,
        bytes32[] calldata labels,
        RolePredicate[] calldata rolePredicates,
        string calldata descriptorURI
    ) external returns (bytes32 paradigmId);

    function transferFamily(bytes32 family, address newController) external;

    function paradigm(bytes32 paradigmId) external view returns (ParadigmRecord memory);
    function exists(bytes32 paradigmId) external view returns (bool);
    /// @notice True when the label was registered with the paradigm. Registration is a declaration;
    ///         conformance to the label's identification condition is checked by the canonical validator.
    function hasLabel(bytes32 paradigmId, bytes32 label) external view returns (bool);
    function labelsOf(bytes32 paradigmId) external view returns (bytes32[] memory);
    /// @notice Predicate commitment for acquiring `role` through the admission path; 0 when the role
    ///         cannot be acquired by predicate under this paradigm.
    function rolePredicateHash(bytes32 paradigmId, uint16 role) external view returns (bytes32);
    function familyController(bytes32 family) external view returns (address);
}
