// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

// ════════════════════════════════════════════════════════════════════════════
//  EIP-7844 — Physical Commodity-Backed Token (PCBT) Interfaces
//  https://eips.ethereum.org/EIPS/eip-7844 (draft)
// ════════════════════════════════════════════════════════════════════════════

interface ICommodityCertificate {
    enum LotStatus { Active, PartiallyRedeemed, FullyRedeemed, Suspended }

    struct CommodityLot {
        bytes32  lotId;
        string   serialNumber;
        string   custodian;
        string   assayRef;
        uint256  weightMicro;
        uint256  purityBps;
        uint256  depositedAt;
        string   ipfsCid;
        LotStatus status;
        uint256  remainingMicro;
    }

    event LotDeposited(uint256 indexed tokenId, bytes32 indexed lotId, string serialNumber, uint256 weightMicro, uint256 purityBps, string ipfsCid);
    event LotStatusUpdated(uint256 indexed tokenId, LotStatus newStatus);
    event RemainingUpdated(uint256 indexed tokenId, uint256 remainingMicro);
    event AuditDocUpdated(uint256 indexed tokenId, string newIpfsCid);

    function depositLot(address to, string calldata serial, string calldata custodian, string calldata assayRef, uint256 weightMicro, uint256 purityBps, string calldata ipfsCid) external returns (uint256 tokenId);
    function getLot(uint256 tokenId) external view returns (CommodityLot memory);
    function isLotActive(uint256 tokenId) external view returns (bool);
    function reduceRemaining(uint256 tokenId, uint256 microUnits) external;
    function linkFractionVault(uint256 tokenId, address vault) external;
    function updateAuditDoc(uint256 tokenId, string calldata newIpfsCid) external;
    function totalLots() external view returns (uint256);
}

interface IFractionVault {
    event LotFractionalized(uint256 indexed tokenId, uint256 tokensIssued, uint256 microPerToken, address mintedTo);

    function fractionalize(uint256 tokenId, address mintTo) external returns (uint256 issued);
    function microToTokens(uint256 microUnits) external view returns (uint256);
    function tokensToMicro(uint256 tokens) external view returns (uint256);
    function microPerToken() external view returns (uint256);
    function remainingCapacity(uint256 tokenId) external view returns (uint256);
    function proofOfReserve() external view returns (address);
}

interface ICommodityToken {
    event MintedFromLot(address indexed to, uint256 indexed lotId, uint256 amount);
    event BurnedFromLot(address indexed from, uint256 indexed lotId, uint256 amount);
    event FeeParamsUpdated(uint256 newBasisPoints, uint256 newMaxFee);

    function commodityType() external view returns (string memory);
    function weightUnit() external view returns (string memory);
    function microPerToken() external view returns (uint256);
    function toMicro(uint256 baseUnits) external view returns (uint256);
    function fromMicro(uint256 microUnits) external view returns (uint256);
    function commodityBalance(address account) external view returns (uint256);
    function lotTokensMinted(uint256 lotId) external view returns (uint256);
    function lotTokensBurned(uint256 lotId) external view returns (uint256);
    function lotNetMicro(uint256 lotId) external view returns (uint256);
    function mintFromLot(address to, uint256 lotId, uint256 tokenAmount) external;
    function burnForRedemption(address from, uint256 lotId, uint256 tokenAmount) external;
    function calcFee(uint256 amount) external view returns (uint256);
    function feeBasisPoints() external view returns (uint256);
    function maxFeeAbsolute() external view returns (uint256);
}

interface IRedemptionGate {
    enum RedemptionStatus { Pending, Processing, Dispatched, Delivered, Cancelled }

    struct RedemptionRequest {
        address  requester;
        uint256  tokensBurned;
        uint256  microRedeemed;
        bytes32  deliveryHash;
        uint256  requestedAt;
        uint256  fulfilledAt;
        RedemptionStatus status;
        uint256  linkedLotId;
        string   trackingRef;
        uint256  flatFee;
    }

    event RedemptionRequested(uint256 indexed requestId, address indexed requester, uint256 tokensBurned, uint256 microRedeemed);
    event RedemptionFulfilled(uint256 indexed requestId, uint256 indexed lotId, string trackingRef);
    event RedemptionCancelled(uint256 indexed requestId);

    function requestRedemption(uint256 tokenAmount, bytes32 deliveryHash) external returns (uint256 requestId);
    function fulfil(uint256 requestId, uint256 lotId, string calldata trackingRef) external;
    function quoteRedemption(uint256 microUnits) external view returns (uint256 tokensRequired, uint256 flatFeeTokens);
    function minimumRedemption() external view returns (uint256);
    function getRequest(uint256 requestId) external view returns (RedemptionRequest memory);
    function getUserRequests(address user) external view returns (uint256[] memory);
}

interface IProofOfReserve {
    event ReserveVerified(uint256 indexed lotId, uint256 microUnits, bool passed);
    event ReserveAlert(uint256 indexed lotId, string reason);

    function verify(uint256 lotId, uint256 microUnits) external view returns (bool valid);
    function getReserve(uint256 lotId) external view returns (uint256 microUnits, uint256 verifiedAt);
    function totalVerifiedReserve() external view returns (uint256);
    function oracle() external view returns (address);
}

interface IComplianceGate {
    enum ComplianceTier { None, Basic, Full, Institutional }

    event ComplianceApproved(address indexed account, ComplianceTier tier);
    event ComplianceRevoked(address indexed account);
    event TransferBlocked(address indexed from, address indexed to, string reason);

    function isApproved(address account) external view returns (bool);
    function getTier(address account) external view returns (ComplianceTier);
    function checkTransfer(address from, address to, uint256 amount) external view returns (bool allowed, string memory reason);
    function approve(address account, ComplianceTier tier, bytes32 kycRefHash) external;
    function revoke(address account) external;
    function remainingDailyLimit(address account) external view returns (uint256);
}

interface ICommodityTokenMetadata {
    function commodityName() external view returns (string memory);
    function commodityCode() external view returns (string memory);
    function certifyingBody() external view returns (string memory);
    function transparencyURL() external view returns (string memory);
    function commodityPriceUSD() external view returns (uint256);
}

// ════════════════════════════════════════════════════════════════════════════
//  ERC-7845 — Gold Token Standard (GTS) Interfaces
//  https://eips.ethereum.org/EIPS/eip-7845 (draft)
// ════════════════════════════════════════════════════════════════════════════

interface IGoldToken is ICommodityToken {
    event GoldPriceUpdated(uint256 pricePerOz, uint256 pricePerGram, uint256 updatedAt);
    event ShariahStatusUpdated(bool compliant, string advisory);
    event DinarRedemptionRequested(uint256 indexed requestId, address indexed requester, uint256 dinarCount, uint256 tokensBurned);

    // Unit system
    function MICRO_PER_TROY_OZ() external pure returns (uint256);
    function MICRO_PER_GRAM()    external pure returns (uint256);
    function MICRO_PER_TOLA()    external pure returns (uint256);
    function MICRO_PER_DINAR()   external pure returns (uint256);
    function TOKENS_PER_GRAM()   external pure returns (uint256);

    // Conversions
    function toMicrograms(uint256 baseUnits)       external view returns (uint256);
    function fromMicrograms(uint256 micrograms)    external view returns (uint256);
    function toMilligrams(uint256 baseUnits)       external view returns (uint256);
    function toGramsScaled(uint256 baseUnits)      external view returns (uint256);
    function toTroyOuncesScaled(uint256 baseUnits) external view returns (uint256);
    function toTolasScaled(uint256 baseUnits)      external view returns (uint256);
    function toDinarsScaled(uint256 baseUnits)     external view returns (uint256);

    // Purity
    function purityBps() external view returns (uint256);
    function pureGoldMicro(uint256 alloyMicro, uint256 purityBps_) external pure returns (uint256);

    // LBMA
    function isLBMACompliant(uint256 lotId) external view returns (bool);
    function lbmaAccredited()               external view returns (bool);
    function custodianName()                external view returns (string memory);

    // Oracle
    function goldPriceUSD()           external view returns (uint256 pricePerOz, uint256 updatedAt);
    function goldPricePerGramUSD()    external view returns (uint256);
    function tokenValueUSD(uint256 tokenAmount) external view returns (uint256);
    function priceOracle()            external view returns (address);

    // Shariah
    function shariahCompliant()   external view returns (bool);
    function shariahAdvisory()    external view returns (string memory);
    function isFullyAllocated()   external view returns (bool);

    // Dinar
    function dinarToTokens(uint256 dinarCount)     external view returns (uint256);
    function tokensToDinars(uint256 tokenAmount)   external view returns (uint256);
    function dinarRedemptionMinimum()              external view returns (uint256);
}

interface IGoldRedemptionGate is IRedemptionGate {
    enum GoldDenomination {
        GRAM_1, GRAM_5, GRAM_10, GRAM_20, GRAM_50, GRAM_100,
        TROY_OZ_1, DINAR_1, DINAR_5, CUSTOM_GRAM
    }

    event GoldRedemptionRequested(
        uint256 indexed requestId,
        address indexed requester,
        GoldDenomination denomination,
        uint256 quantity,
        uint256 totalMicrograms,
        uint256 tokensBurned
    );

    function requestGoldRedemption(GoldDenomination denomination, uint256 quantity, bytes32 deliveryHash) external returns (uint256 requestId);
    function quoteGoldRedemption(GoldDenomination denomination, uint256 quantity) external view returns (uint256 tokensRequired, uint256 flatFeeTokens, uint256 totalMicrograms);
    function denominationMicro(GoldDenomination denomination)   external pure returns (uint256);
    function denominationPurity(GoldDenomination denomination)  external pure returns (uint256);
}

interface IGoldCertificate is ICommodityCertificate {
    struct GoldBarDetails {
        uint256 weightTroyOzScaled;
        uint256 weightGramsScaled;
        uint256 purityBps;
        string  refineryBrand;
        string  yearMelted;
        bool    lbmaGoodDelivery;
        bool    shariahCertified;
        string  shariahCertRef;
    }

    event GoldBarCertified(uint256 indexed tokenId, string refineryBrand, bool lbmaGoodDelivery, bool shariahCertified);

    function getGoldBarDetails(uint256 tokenId)     external view returns (GoldBarDetails memory);
    function barWeightGramsScaled(uint256 tokenId)  external view returns (uint256);
    function barWeightTroyOzScaled(uint256 tokenId) external view returns (uint256);
    function totalActiveGoldGrams()                 external view returns (uint256);
    function isLBMACompliant(uint256 tokenId)       external view returns (bool);
    function isShariahCertified(uint256 tokenId)    external view returns (bool);
}

// ─── GoldUnits Library ────────────────────────────────────────────────────────
library GoldUnits {
    uint256 internal constant MICRO_PER_TROY_OZ = 31_103_477;
    uint256 internal constant MICRO_PER_GRAM    = 1_000_000;
    uint256 internal constant MICRO_PER_TOLA    = 11_663_800;
    uint256 internal constant MICRO_PER_DINAR   = 4_250_000;

    function microToGramsScaled(uint256 micro) internal pure returns (uint256) { return micro; }
    function microToTroyOzScaled(uint256 micro) internal pure returns (uint256) { return (micro * 1e8) / MICRO_PER_TROY_OZ; }
    function microToDinarsScaled(uint256 micro) internal pure returns (uint256) { return (micro * 1e4) / MICRO_PER_DINAR; }
    function microToTolasScaled(uint256 micro) internal pure returns (uint256)  { return (micro * 1e8) / MICRO_PER_TOLA;   }
    function gramsToMicro(uint256 grams) internal pure returns (uint256)        { return grams * MICRO_PER_GRAM;            }
    function troyOzToMicro(uint256 ozScaled) internal pure returns (uint256)    { return (ozScaled * MICRO_PER_TROY_OZ) / 1e8; }
    function dinarsToMicro(uint256 dinars) internal pure returns (uint256)      { return dinars * MICRO_PER_DINAR;          }
    function pureGoldMicro(uint256 alloyMicro, uint256 purityBps) internal pure returns (uint256) { return (alloyMicro * purityBps) / 10_000; }

    /// @notice Validate LBMA Good Delivery bar requirements
    function isLBMAGoodDelivery(uint256 weightTroyOzScaled, uint256 purityBps) internal pure returns (bool) {
        return weightTroyOzScaled >= 35_000_000_000  // min 350 oz
            && weightTroyOzScaled <= 43_000_000_000  // max 430 oz
            && purityBps >= 9950;                     // min 99.5%
    }
}
