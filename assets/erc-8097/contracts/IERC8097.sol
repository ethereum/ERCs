// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

struct IRO {
    bytes32 depositId;
    string  commodity;
    string  reportingStandard;
    uint256 totalInGround;
    uint8   resourceClass;
    bytes32 anchorHash;
    uint256 anchoredAt;
}

struct IGO {
    bytes32 depositId;
    string  country;
    string  depositStyle;
    string  hostRock;
    address cpAddress;
    bytes   cpSignature;
    uint256 siteVisitDate;
    bytes32 reportHash;
    uint256 version;
}

struct ICO {
    bytes32 depositId;
    string  jurisdictionId;
    address cpAddress;
    bool    attestationValid;
    uint256 licenceExpiresAt;
    bytes32 indigenousConsentHash;
}

struct IEXO {
    bytes32 depositId;
    uint256 remainingInGround;
    uint256 lastDepletionAt;
    uint256 totalDepleted;
}

struct IEO {
    bytes32 depositId;
    bool    eiaSubmitted;
    bool    waterRightsPresent;
    bool    tailingsPlanPresent;
    bytes32 ghgReportHash;
    uint256 rehabilitationBond;
    uint256 lastUpdated;
}

/// @title IERC8097
/// @notice In-Ground Asset Token standard interface
interface IERC8097 {
    event ResourceAnchored(bytes32 indexed depositId, string commodity, uint256 totalInGround, bytes32 anchorHash);
    event DepletionRecorded(bytes32 indexed depositId, uint256 amountDepleted, uint256 remainingInGround, address indexed recorder);
    event CPAttestation(bytes32 indexed depositId, address indexed cpAddress, bytes32 reportHash, uint256 siteVisitDate, uint256 version);
    event JurisdictionUpdated(bytes32 indexed depositId, string jurisdictionId, uint256 licenceExpiresAt);
    event ESGUpdated(bytes32 indexed depositId, bytes32 ghgReportHash, bool eiaSubmitted, uint256 rehabilitationBond);

    error AlreadyAnchored(bytes32 depositId);
    error ZeroResourceQuantity();
    error DepletionExceedsRemaining(bytes32 depositId, uint256 requested, uint256 remaining);
    error InvalidCPSignature(bytes32 depositId, address cpAddress);
    error AttestationNotValid(bytes32 depositId);
    error DepositNotFound(bytes32 depositId);

    function anchorResource(IRO calldata iro) external;
    function updateGeology(IGO calldata igo) external;
    function verifyAttestation(bytes32 depositId) external returns (bool valid);
    function updateCompliance(ICO calldata ico) external;
    function recordDepletion(bytes32 depositId, uint256 amount) external;
    function updateEnvironmental(IEO calldata ieo) external;
    function getIRO(bytes32 depositId) external view returns (IRO memory);
    function getIGO(bytes32 depositId) external view returns (IGO memory);
    function getICO(bytes32 depositId) external view returns (ICO memory);
    function getIEXO(bytes32 depositId) external view returns (IEXO memory);
    function getIEO(bytes32 depositId) external view returns (IEO memory);
    function remainingInGround(bytes32 depositId) external view returns (uint256);
}
