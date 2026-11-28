// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Defines the interface of an Ethereum registry that maps ERC-7730 binding context IDs
///         to the descriptors and attestations an attester publishes for them. Every write is made
///         by 'msg.sender', who is the attester.
interface IClearSigningRegistry {

    /// @notice One descriptor file, published for wallets that support one ERC-7730 descriptor schema MAJOR version.
    struct DescriptorRelease {
        /// The declared canonical hash of the descriptor resolved by the URLs in the record's 'mirrorListId',
        /// computed as in ERC-8176 "Descriptor Hash Computation": 'includes' resolved, RFC 8785 serialized, Keccak-256.
        /// A URL serves either the fully resolved descriptor, or one whose relative 'includes' resolve against that URL;
        /// a URL that cannot resolve them (such as a bare IPFS file CID) must serve the resolved file.
        /// The value is used only to ensure immutability of the data served off-chain and is not enforced by the registry.
        bytes32 descriptorHash;
        /// The MAJOR version of the ERC-7730 descriptor schema per the descriptor's '$schema' key.
        uint64 schemaMajor;
    }

    /// @notice Descriptor metadata an attester provides in a registration record.
    struct DescriptorDetails {
        /// One release per supported schema MAJOR version, ordered by strictly ascending 'schemaMajor'.
        /// A wallet picks the release matching the schema MAJOR version it supports.
        DescriptorRelease[] releases;
        /// The ID of an already-published MirrorList of URLs leading to the root descriptors index file.
        /// The index file is shared by all releases and is keyed by their descriptor hashes.
        bytes32 mirrorListId;
    }

    /// @notice Attestation metadata an attester provides in a registration record.
    struct AttestationDetails {
        /// The ID of an already-published MirrorList of URLs leading to the attestations index file.
        bytes32 mirrorListId;
    }

    /// @notice The data provided by the attester containing descriptors and attestations for a given set of contexts.
    struct RegistrationRecord {
        DescriptorDetails  descriptorDetails;
        AttestationDetails attestationDetails;
    }

    /// @notice An attester's active record at a context, with its MirrorLists resolved to URLs.
    struct ResolvedRecord {
        /// The attester that wrote this record.
        address attester;
        /// The context ID the record was resolved for.
        bytes32 contextKeyId;
        /// The descriptor releases of the record, ordered by ascending 'schemaMajor'.
        DescriptorRelease[] releases;
        /// The URLs of the descriptor root index file.
        string[] descriptorUrls;
        /// The URLs of the attestations root index file.
        string[] attestationUrls;
    }

    /// @notice An attestation format an attester declares to use, with its optional revocation controller.
    struct AttestationFormatSettings {
        /// The declared attestation format identifier, calculated as 'keccak256("erc7730.attestation.<format>")'.
        bytes32 attestationFormatId;
        /// An optional contract implementing 'IRevocationController' that wallets MAY ask whether an attestation
        /// of this format was revoked, or address(0) for none, meaning attestations of this format are unrevocable.
        /// For the EAS off-chain format this is the canonical EAS contract,
        /// which wallets SHOULD query directly regardless of what is declared here.
        address revocationController;
    }

    /// @notice Self-declared settings of an attester, replaced as a whole by 'updateAttesterSettings'.
    struct AttesterSettings {
        /// The profile document URI. Display-only metadata that MUST NOT be used as trust input.
        string profileURI;
        /// The attestation formats the attester commits to use consistently across all of its records.
        /// A functional hint: the registry does not check records against it.
        AttestationFormatSettings[] attestationFormats;
    }

    /// @notice Emitted the first time a MirrorList is stored on-chain, carrying its full URI contents.
    event MirrorListPublished(bytes32 indexed mirrorListId, string[] uris);

    /// @notice Emitted when an attester writes the record for a context, replacing any previous one.
    event RecordWritten(address indexed attester, bytes32 indexed contextKeyId, RegistrationRecord record);

    /// @notice Emitted right after 'RecordWritten', once per descriptor release of the written record,
    ///         so a descriptor hash can be searched for by its topic.
    event DescriptorReleased(
        address indexed attester,
        bytes32 indexed contextKeyId,
        bytes32 indexed descriptorHash,
        uint64          schemaMajor
    );

    /// @notice Emitted when an attester deletes the record for a context.
    event RecordDeleted(address indexed attester, bytes32 indexed contextKeyId);

    /// @notice Emitted when an attester replaces its settings.
    event AttesterSettingsUpdated(address indexed attester, AttesterSettings settings);

    /// @notice Thrown when no registration records are passed.
    error EmptyRecords();

    /// @notice Thrown when 'contextKeyIds' and 'registrationRecords' differ in length.
    error ArrayLengthMismatch();

    /// @notice Thrown when a record or a deletion lists no context IDs.
    error EmptyContextKeyIds();

    /// @notice Thrown when a release declares a zero descriptor hash.
    error ZeroDescriptorHash();

    /// @notice Thrown when a record declares no descriptor releases.
    error EmptyReleases();

    /// @notice Thrown when the releases' schema MAJOR versions are not strictly ascending from a value above zero.
    error SchemaMajorsNotAscending();

    /// @notice Thrown when an empty URI list is passed to 'publishMirrorLists'.
    error EmptyMirrorList();

    /// @notice Thrown when a MirrorList id was never published via 'publishMirrorLists'.
    error UnknownMirrorList(bytes32 mirrorListId);

    /// @notice The version of this registry deployment.
    function version() external view returns (string memory);

    /// @notice Write the caller's registration records, each for one or more contexts.
    ///         Each attester has at most one record per context. Writing a record replaces the previous one
    ///         at that context as a whole, including every descriptor release it held.
    ///         Both MirrorLists referenced by a record must already be published.
    /// @param contextKeyIds        One array of context IDs per record: 'registrationRecords[i]'
    ///                             is written for every ID in 'contextKeyIds[i]'.
    /// @param registrationRecords  The records to write. Must be the same length as 'contextKeyIds'.
    function writeRecords(
        bytes32[][] calldata contextKeyIds,
        RegistrationRecord[] calldata registrationRecords
    ) external;

    /// @notice Delete the caller's record at every listed context.
    ///         A context without a record does not revert, and still emits 'RecordDeleted'.
    /// @param contextKeyIds  The context IDs whose records are deleted. Must not be empty.
    function deleteRecords(bytes32[] calldata contextKeyIds) external;

    /// @notice Resolve the records of the given attesters at the given contexts.
    ///         Returns one entry per '(attester, contextKeyId)' pair that currently has a record, ordered by
    ///         attester and then by context. Both parameters are lookup keys: an empty array yields no results.
    ///         The registry applies no filters.
    /// @param attesters      Attester addresses trusted by the wallet.
    /// @param contextKeyIds  Candidate context IDs to look up.
    /// @return resolved  The records found.
    function resolveRecords(address[] calldata attesters, bytes32[] calldata contextKeyIds)
        external view returns (ResolvedRecord[] memory resolved);

    /// @notice Publish a batch of MirrorLists on-chain, each keyed by the keccak256 hash of its ABI-encoded URIs.
    ///         MirrorLists are immutable and are stored permanently.
    /// @param uriLists  The URI lists to publish. No list may be empty.
    function publishMirrorLists(string[][] calldata uriLists) external;

    /// @notice Return the URI list for a given MirrorList ID, or an empty array if it was never published.
    /// @param mirrorListId  The MirrorList content hash.
    /// @return uris  The full URI list.
    function getMirrorListById(bytes32 mirrorListId) external view returns (string[] memory uris);

    /// @notice Replace the caller's settings: its profile URI and its declared attestation formats.
    ///         The registry checks nothing here and never calls a revocation controller.
    /// @param settings  The new settings. Replaces all previous settings, empty fields clear them.
    function updateAttesterSettings(AttesterSettings calldata settings) external;

    /// @notice The attester's current settings, or empty settings if it never set any.
    /// @param attester  The queried attester address.
    /// @return settings  The attester's settings.
    function getAttesterSettings(address attester) external view returns (AttesterSettings memory settings);
}

/// @title  IRevocationController — optional third-party revocation root for attestations
/// @notice An attester MAY declare, per attestation format, a contract wallets can ask whether a given
///         attestation was revoked. The registry never calls a controller and does not interpret
///         'data': its meaning is defined by the attestation format.
///         The signature deliberately matches 'getRevokeOffchain' of the Ethereum Attestation Service,
///         so the canonical EAS contract itself is a valid controller for the EAS off-chain format.
interface IRevocationController {
    /// @notice The timestamp at which 'revoker' revoked the identified attestation, or 0 if it did not.
    /// @param revoker  The account whose revocation counts: the attester that issued the attestation.
    /// @param data     The format-specific identifier of the attestation. For the EAS off-chain format,
    ///                 the attestation UID.
    /// @return timestamp  The revocation timestamp, or 0 if not revoked.
    function getRevokeOffchain(address revoker, bytes32 data) external view returns (uint64 timestamp);
}
