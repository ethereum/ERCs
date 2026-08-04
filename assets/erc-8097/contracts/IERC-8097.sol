// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title IERC-8097: In-Ground Asset Token
 * @notice Canonical on-chain record interface for mining and natural resource
 *         assets. Full object data is stored off-chain; this interface anchors
 *         hashes, lifecycle state, CP/QP attestations, depletion, and score-log
 *         references.
 */

enum LifecycleState {
    INDEXED,
    CLAIMED,
    VERIFIED,
    ANCHORED
}

enum ProductionStatus {
    PRE_EXPLORATION,
    EXPLORATION,
    PRE_FEASIBILITY,
    FEASIBILITY,
    DEVELOPMENT,
    PRODUCTION,
    CARE_AND_MAINTENANCE,
    CLOSED
}

enum DisclosureStatus {
    UNKNOWN,
    CONFIRMED,
    REFERENCED,
    NOT_DISCLOSED,
    NOT_APPLICABLE
}

struct IRO {
    bytes32 assetId;
    string depositName;
    string primaryCommodity;
    string reportingStandard;
    uint256 jorcEffectiveDate;
    uint256 totalResourceMt;
    uint256 totalGrade;
    string gradeUnit;
    uint256 totalContainedMetal;
    string containedMetalUnit;
    string[] classifications;
    uint256[] classTonnesMt;
    uint256[] classGrades;
    uint256[] classContained;
    bool oreReserveDeclared;
    uint256 reserveTotalMt;
    uint256 reserveGrade;
    uint256 reserveContained;
    bool explorationTargetPresent;
    uint256 cutOffGrade;
    string cutOffUnits;
    string cpNameResources;
    string cpBodyResources;
    string cpNameReserves;
    string cpBodyReserves;
    bytes32 objectHash;
    uint256 anchoredAt;
    uint8 extractionConfidence;
}

struct IGO {
    bytes32 assetId;
    string depositStyle;
    string hostRock;
    string mineralogy;
    uint256 strikeLengthKm;
    uint256 depthMaxM;
    uint256 drillingTotalMetres;
    uint256 drillingHolesCount;
    string estimationMethod;
    string blockModelSoftware;
    uint256 compositeIntervalM;
    bool qaqcBlanks;
    bool qaqcStandards;
    bool qaqcDuplicates;
    bool qaqcUmpireAssays;
    string laboratoryName;
    bool laboratoryAccreditedISO;
    string cpName;
    string cpMembershipBody;
    string cpMembershipNumber;
    uint256 cpSiteVisitDate;
    bool cpSiteVisitConfirmed;
    uint256 reportDate;
    bytes32 objectHash;
    uint256 anchoredAt;
    uint8 extractionConfidence;
}

struct ICO {
    bytes32 assetId;
    string jurisdictionCountry;
    string jurisdictionState;
    string regulatoryBodyMining;
    string regulatoryBodyEnvironment;
    string regulatoryBodyWater;
    string legalFramework;
    string tenureType;
    uint8 tenureStatus;
    string legalEntityName;
    string parentCompany;
    uint256 ownershipPct;
    string[] jvPartners;
    bool cpAttestationPresent;
    uint8 cpCount;
    string royaltyType;
    bool royaltyRateDisclosed;
    bool indigenousAgreement;
    string indigenousAgreementCounterparty;
    string indigenousFramework;
    uint8 environmentalPermitsStatus;
    bool allTenureOnGranted;
    bytes32 objectHash;
    uint256 anchoredAt;
    uint8 extractionConfidence;
}

struct IEXO {
    bytes32 assetId;
    ProductionStatus productionStatus;
    uint256 productionCommencedYear;
    uint256 annualGuidanceMin;
    uint256 annualGuidanceMax;
    string annualGuidanceUnit;
    string annualGuidanceCurrency;
    uint256 aiscMin;
    uint256 aiscMax;
    string aiscCurrency;
    string aiscUnit;
    uint256 processingPlantCapacityMtpa;
    uint256 processingRecoveryPct;
    string processingMethod;
    string mineType;
    uint256 depletionReportedMt;
    bool depletionReported;
    bytes32 objectHash;
    uint256 anchoredAt;
    uint8 extractionConfidence;
}

struct IEOEnvironmental {
    DisclosureStatus eiaStatus;
    DisclosureStatus waterRights;
    bool tailingsFacilityPresent;
    DisclosureStatus tailingsManagementPlan;
    DisclosureStatus rehabilitationPlan;
    DisclosureStatus acidRockDrainageStudy;
    bool ghgScope1;
    bool ghgScope2;
    bool ghgScope3;
    bool netZeroTarget;
    uint256 netZeroTargetYear;
    bool renewableEnergyPresent;
    DisclosureStatus tcfdAlignment;
}

struct IEOSocial {
    DisclosureStatus communityConsultation;
    DisclosureStatus indigenousConsultation;
    DisclosureStatus grievanceMechanism;
    DisclosureStatus healthSafetyKPIs;
    bool resettlementRequired;
    DisclosureStatus resettlementPlan;
    DisclosureStatus localEmploymentPlan;
}

struct IEOGovernance {
    DisclosureStatus boardESGCommittee;
    DisclosureStatus antiBriberyPolicy;
    DisclosureStatus thirdPartyESGAudit;
    bool irmaAligned;
    bool icmmMember;
    bool sustainabilityReportPresent;
    uint256 sustainabilityReportDate;
    string sustainabilityReportFramework;
}

struct IEO {
    bytes32 assetId;
    IEOEnvironmental environmental;
    IEOSocial social;
    IEOGovernance governance;
    bytes32 objectHash;
    uint256 anchoredAt;
    uint8 extractionConfidence;
}

struct SML {
    bytes32 assetId;
    uint256 currentScore;
    string scoreVersion;
    string rulebookVersion;
    bytes32 smlHash;
    uint256 anchoredAt;
}

struct CPAttestation {
    bytes32 assetId;
    bytes32 objectHash;
    string cpName;
    string cpBody;
    string cpMembershipNumber;
    uint256 attestationTimestamp;
    address signerAddress;
    bytes signature;
}

struct AssetRecord {
    bytes32 assetId;
    string mineName;
    string mineSlug;
    LifecycleState lifecycleState;
    string schemaVersion;
    string rulebookVersion;
    bytes32 iroHash;
    bytes32 igoHash;
    bytes32 icoHash;
    bytes32 iexoHash;
    bytes32 ieoHash;
    bytes32 smlHash;
    bytes32 reportPdfHash;
    string reportIpfsUri;
    uint256 anchoredAt;
    address anchoredBy;
    bool active;
}

interface IERC8097 is IERC165 {
    event AssetRegistered(bytes32 indexed assetId, string mineSlug, address registeredBy, uint256 timestamp);

    event AssetAnchored(
        bytes32 indexed assetId,
        string mineSlug,
        bytes32 iroHash,
        bytes32 igoHash,
        bytes32 icoHash,
        bytes32 iexoHash,
        bytes32 ieoHash,
        bytes32 smlHash,
        bytes32 reportPdfHash,
        uint256 anchoredAt
    );

    event AssetReAnchored(bytes32 indexed assetId, bytes32 previousIroHash, bytes32 newIroHash, uint256 reAnchoredAt);
    event LifecycleAdvanced(bytes32 indexed assetId, LifecycleState fromState, LifecycleState toState, uint256 timestamp);

    event CPAttestationRecorded(
        bytes32 indexed assetId,
        bytes32 indexed objectHash,
        string cpName,
        string cpBody,
        address signerAddress,
        uint256 attestationTimestamp
    );

    event DepletionUpdated(bytes32 indexed assetId, uint256 previousDepletionMt, uint256 newDepletionMt, uint256 timestamp);
    event SMLUpdated(bytes32 indexed assetId, bytes32 newSmlHash, uint256 currentScore, uint256 timestamp);
    event ProductionStatusAdvanced(bytes32 indexed assetId, ProductionStatus fromStatus, ProductionStatus toStatus, uint256 timestamp);

    function register(
        string calldata mineSlug,
        string calldata mineName,
        string calldata schemaVersion
    ) external returns (bytes32 assetId);

    function anchor(
        bytes32 assetId,
        bytes32 iroHash,
        bytes32 igoHash,
        bytes32 icoHash,
        bytes32 iexoHash,
        bytes32 ieoHash,
        bytes32 smlHash,
        uint256 currentScore,
        bytes32 reportPdfHash,
        string calldata reportIpfsUri,
        string calldata rulebookVersion,
        string calldata schemaVersion
    ) external;

    function advanceLifecycle(bytes32 assetId, LifecycleState newState) external;

    function recordCPAttestation(
        bytes32 assetId,
        bytes32 objectHash,
        string calldata cpName,
        string calldata cpBody,
        string calldata cpMembershipNumber,
        address expectedSigner,
        uint256 attestationTimestamp,
        bytes calldata signature
    ) external;

    function advanceProductionStatus(bytes32 assetId, ProductionStatus newStatus) external;
    function updateDepletion(bytes32 assetId, uint256 newDepletionMt) external;
    function updateSML(bytes32 assetId, bytes32 newSmlHash, uint256 currentScore) external;

    function getAsset(bytes32 assetId) external view returns (AssetRecord memory);
    function getAssetBySlug(string calldata mineSlug) external view returns (bytes32);
    function getLifecycleState(bytes32 assetId) external view returns (LifecycleState);
    function getCPAttestations(bytes32 objectHash) external view returns (CPAttestation[] memory);
    function isAnchored(bytes32 assetId) external view returns (bool);
    function getCurrentScore(bytes32 assetId) external view returns (uint256);
    function getDepletion(bytes32 assetId) external view returns (uint256);
    function getProductionStatus(bytes32 assetId) external view returns (ProductionStatus);
    function getSML(bytes32 assetId) external view returns (SML memory);
    function getDomainSeparator() external view returns (bytes32);
    function isProductionTransitionAllowed(ProductionStatus from, ProductionStatus to) external view returns (bool);
}
