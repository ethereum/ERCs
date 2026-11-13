// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDiveLogTypes} from "./IDiveLogTypes.sol";
import {IERC165} from "./IERC165.sol";

/// @title ERC-8260 Dive Log Interface
/// @notice The ERC-165 identifier for this interface is 0x4d89a8f9.
interface IDiveLog is IERC165 {
    /// @dev Emitted when a dive is logged. `diveDate` is the UTC calendar date
    ///      as YYYYMMDD (not a Unix timestamp). `contentHash` is the SHA-256 of
    ///      the exact attested UDDF bytes supplied by the owner.
    event DiveLogged(uint256 indexed diveId, uint32 indexed diveDate, bytes32 contentHash);

    /// @dev Emitted when a dive is voided or superseded. `supersededById` is 0
    ///      for a void without replacement, else the correcting dive's id.
    event DiveVoided(uint256 indexed diveId, uint256 indexed supersededById, address indexed voidedBy, string reason);

    /// @dev Emitted when a valid EIP-712 attestation is recorded. The attester
    ///      is recovered from the signature, not from `msg.sender`.
    event DiveAttested(uint256 indexed diveId, address indexed attester, bytes32 contentHash);

    /// @dev Emitted when an attester advances their nonce without attesting,
    ///      invalidating any pending signatures over the old nonce.
    event AttestationNonceCancelled(address indexed attester, uint256 newNonce);

    error NotOwner();
    error InvalidDepth();
    error InvalidTimes();
    error InvalidDate();
    error InvalidContentHash();
    error InvalidGasMix();
    error InvalidTableSchedule();
    error InvalidRepetitiveGroup();
    error InvalidBatchSize(uint256 length);
    error DiveNotFound(uint256 diveId);
    error DiveAlreadyVoided(uint256 diveId);
    error InvalidSupersede(uint256 voidedId, uint256 supersededId);
    error AlreadyAttested(uint256 diveId, address attester);
    error InvalidSignature();
    error NonceMismatch(uint256 expected, uint256 provided);
    error InvalidAttestationIndex(uint256 index);

    /// @notice The single account that may log, batch-log, or void dives.
    function owner() external view returns (address);

    /// @notice Log a single dive (including unattested self-reports).
    /// @dev Reverts `NotOwner` unless `msg.sender` is `owner()`. Validates per
    ///      the ERC's behavior requirements, assigns the next sequential id,
    ///      stores an append-only header, and emits `DiveLogged`.
    function logDive(IDiveLogTypes.DiveInput calldata input) external returns (uint256 diveId);

    /// @notice Log up to `MAX_BATCH_SIZE` dives in one transaction (historic import).
    /// @dev Owner-gated; validates each item identically to `logDive`; reverts
    ///      the entire batch if any item is invalid or if the length is 0 or
    ///      above `MAX_BATCH_SIZE` (`InvalidBatchSize`); emits one `DiveLogged` per dive.
    function batchLogDives(IDiveLogTypes.DiveInput[] calldata inputs)
        external
        returns (uint256[] memory diveIds);

    /// @notice Void or supersede a dive. The header is never mutated or deleted.
    /// @dev Owner-gated. `supersededById == 0` voids without replacement; a
    ///      non-zero target must exist, differ from `diveId`, and not already
    ///      be voided. Emits `DiveVoided`.
    function voidDive(uint256 diveId, uint256 supersededById, string calldata reason) external;

    /// @notice Submit an attestation created by the attester off-chain.
    /// @dev The attester is recovered from `signature` (EIP-712 over
    ///      `Attestation(diveId, contentHash, verifyingContract, nonce)`); any
    ///      address may submit. Reverts `InvalidContentHash` if `contentHash`
    ///      is not the stored hash, `DiveAlreadyVoided` for voided dives,
    ///      `NonceMismatch` on a stale nonce, `AlreadyAttested` on a repeat by
    ///      the same attester. Increments the attester's nonce and emits
    ///      `DiveAttested` including `contentHash`.
    function attestDive(uint256 diveId, bytes32 contentHash, uint256 nonce, bytes calldata signature) external;

    /// @notice Invalidate every pending attestation signature over the caller's current nonce.
    /// @dev Increments `msg.sender`'s nonce by 1 and emits `AttestationNonceCancelled`.
    function cancelAttestationNonce() external;

    /// @notice Read a dive header by id, including voided dives.
    function getDive(uint256 diveId) external view returns (IDiveLogTypes.DiveHeader memory);

    /// @notice Total dives ever logged (voids included).
    function getDiveCount() external view returns (uint256);

    /// @notice Whether the dive has been voided or superseded.
    function isDiveVoided(uint256 diveId) external view returns (bool);

    /// @notice The void/supersede overlay for a dive.
    function getVoidInfo(uint256 diveId) external view returns (IDiveLogTypes.VoidInfo memory);

    /// @notice Number of attestations recorded for a dive.
    function attestationCount(uint256 diveId) external view returns (uint256);

    /// @notice One attestation by index, in recording order.
    function getAttestation(uint256 diveId, uint256 index)
        external
        view
        returns (IDiveLogTypes.Attestation memory);

    /// @notice The attester's current nonce (starts at 0); signers must query it before signing.
    function attesterNonce(address attester) external view returns (uint256);
}
