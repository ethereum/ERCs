// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "./IDiveLogTypes.sol";
import "./IERC165.sol";

interface IDiveLog is IERC165 {
    event DiveLogged(uint256 indexed diveId, uint64 indexed diveDate);
    event DiveVoided(uint256 indexed diveId, uint256 indexed supersededById, address indexed voidedBy, string reason);
    event DiveAttested(uint256 indexed diveId, address indexed attester);
    event ProfileUpdated();

    error NotOwner();
    error InvalidDepth();
    error InvalidTimes();
    error DiveNotFound(uint256 diveId);
    error ArrayLengthMismatch();
    error DiveAlreadyVoided(uint256 diveId);
    error InvalidSupersede(uint256 voidedId, uint256 supersededId);
    error AlreadyAttested(uint256 diveId, address attester);
    error InvalidSignature();
    error NonceMismatch(uint256 expected, uint256 provided);

    function logDive(DiveInput calldata input) external returns (uint256 diveId);

    function batchLogDives(DiveInput[] calldata inputs) external returns (uint256[] memory diveIds);

    function voidDive(
        uint256 diveId,
        uint256 supersededById,
        string calldata reason
    ) external;

    function attestDive(
        uint256 diveId,
        uint256 nonce,
        bytes calldata signature
    ) external;

    function getDive(uint256 diveId) external view returns (DiveLog memory);
    function getDivesByDate(uint64 date) external view returns (uint256[] memory);
    function getMultipleDives(uint256[] calldata diveIds) external view returns (DiveLog[] memory);
    function getAllDiveIds() external view returns (uint256[] memory);
    function getDiveCount() external view returns (uint256);
    function isDiveVoided(uint256 diveId) external view returns (bool);
    function getVoidInfo(uint256 diveId) external view returns (VoidInfo memory);
    function getAttestations(uint256 diveId) external view returns (Attestation[] memory);
    function profile() external view returns (DiverProfile memory);
    function attesterNonce(address attester) external view returns (uint256);

    function updateProfile(
        string calldata name,
        uint8 age,
        uint16 height,
        uint16 weight,
        BiologicalSex sex,
        UnitSystem units
    ) external;
}
