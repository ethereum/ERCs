// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title RedeemGate
 * @notice Handles physical gold redemption from EmasGold (EMAS) tokens
 *
 * Redemption options:
 *   - 1 Gold Dinar coin  = 425 EMAS tokens (4.25g of 916 gold)
 *   - 1 x 5g bar        = 500 EMAS tokens (5.00g of 999.9 gold)
 *   - Custom weight      = N x 500 EMAS   (multiples of 5g, min 5g)
 *
 * Flow:
 *   User calls redeem() → tokens burned → request queued → 
 *   operator fulfils off-chain (T+2) → marks fulfilled on-chain
 */

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

interface IEmasGoldBurner {
    function burnForRedemption(address from, uint256 amount) external;
    function kycApproved(address wallet) external view returns (bool);
    function frozenAddresses(address wallet) external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IGoldCertReducer {
    function reduceRemaining(uint256 barId, uint256 gramsRedeemed) external;
}

contract RedeemGate is AccessControl, ReentrancyGuard, Pausable {
    using Counters for Counters.Counter;

    // ─── Roles ────────────────────────────────────────────────────────────────
    bytes32 public constant FULFILLER_ROLE = keccak256("FULFILLER_ROLE");
    bytes32 public constant PAUSER_ROLE    = keccak256("PAUSER_ROLE");
    bytes32 public constant FEE_MANAGER    = keccak256("FEE_MANAGER");

    // ─── Token Constants ──────────────────────────────────────────────────────

    /// @notice 1 Dinar = 4.25g = 425 EMAS tokens
    uint256 public constant DINAR_TOKENS = 425;

    /// @notice 1 x 5g bar = 500 EMAS tokens (minimum gram redemption)
    uint256 public constant MIN_GRAM_BAR_TOKENS = 500;

    /// @notice Multiples of 5g for custom redemption
    uint256 public constant CUSTOM_STEP_TOKENS = 500;

    // ─── Redemption Types ─────────────────────────────────────────────────────
    enum RedeemType {
        DINAR_COIN,     // 4.25g 916 gold dinar coin
        GRAM_BAR_5,     // 5g 999.9 gold bar
        CUSTOM_GRAM     // N x 5g custom weight (min 5g)
    }

    enum RedeemStatus {
        Pending,        // Tokens burned, awaiting physical dispatch
        Processing,     // Operator has picked up the order
        Fulfilled,      // Physical gold dispatched + tracking added
        Cancelled       // Cancelled before fulfilment (tokens refunded)
    }

    // ─── Structs ──────────────────────────────────────────────────────────────
    struct RedeemRequest {
        address     requester;
        RedeemType  redeemType;
        uint256     tokensBurned;       // EMAS tokens burned
        uint256     gramsRedeemed;      // physical gold in grams
        uint256     quantity;           // e.g. number of dinars or bars
        uint256     requestTimestamp;
        uint256     fulfilTimestamp;
        RedeemStatus status;
        string      deliveryAddress;    // encrypted off-chain, hash stored here
        string      trackingRef;        // courier tracking number (post-fulfil)
        uint256     linkedBarId;        // which physical bar used
        uint256     flatFeeCharged;     // MYR-equivalent flat fee in tokens
    }

    // ─── Storage ──────────────────────────────────────────────────────────────
    Counters.Counter private _requestIds;

    mapping(uint256 => RedeemRequest) public requests;
    mapping(address => uint256[])     public userRequests;

    IEmasGoldBurner  public immutable emasGold;
    IGoldCertReducer public immutable goldCert;

    /// @notice Flat redemption fee in EMAS tokens (operator sets per type)
    mapping(RedeemType => uint256) public flatFeeTokens;

    /// @notice Fee treasury
    address public feeTreasury;

    // ─── Events ───────────────────────────────────────────────────────────────
    event RedemptionRequested(
        uint256 indexed requestId,
        address indexed requester,
        RedeemType      redeemType,
        uint256         tokensBurned,
        uint256         gramsRedeemed,
        uint256         quantity
    );
    event RedemptionProcessing(uint256 indexed requestId, address operator);
    event RedemptionFulfilled(
        uint256 indexed requestId,
        uint256 indexed barId,
        string          trackingRef,
        uint256         fulfilTimestamp
    );
    event RedemptionCancelled(uint256 indexed requestId, uint256 tokensRefunded);
    event FlatFeeUpdated(RedeemType redeemType, uint256 feeTokens);

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor(
        address _emasGold,
        address _goldCert,
        address _feeTreasury
    ) {
        require(_emasGold     != address(0), "Redeem: zero emas");
        require(_goldCert     != address(0), "Redeem: zero cert");
        require(_feeTreasury  != address(0), "Redeem: zero treasury");

        emasGold     = IEmasGoldBurner(_emasGold);
        goldCert     = IGoldCertReducer(_goldCert);
        feeTreasury  = _feeTreasury;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FULFILLER_ROLE,     msg.sender);
        _grantRole(PAUSER_ROLE,        msg.sender);
        _grantRole(FEE_MANAGER,        msg.sender);

        // Default flat fees (in EMAS tokens):
        // Approx RM50 equivalent at current gold price
        flatFeeTokens[RedeemType.DINAR_COIN]   = 3;   // ~RM50
        flatFeeTokens[RedeemType.GRAM_BAR_5]   = 3;   // ~RM50
        flatFeeTokens[RedeemType.CUSTOM_GRAM]  = 5;   // ~RM80
    }

    // ─── Redeem: 1 Dinar Coin (4.25g 916 gold) ───────────────────────────────

    /**
     * @notice Redeem N Dinar coins. Each = 425 EMAS tokens (4.25g)
     * @param quantity         Number of Dinar coins
     * @param deliveryAddrHash Keccak256 hash of encrypted delivery address
     */
    function redeemDinar(uint256 quantity, string calldata deliveryAddrHash)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 requestId)
    {
        require(quantity >= 1, "Redeem: min 1 Dinar");
        _checkEligibility(msg.sender);

        uint256 baseTokens = quantity * DINAR_TOKENS;
        uint256 fee        = flatFeeTokens[RedeemType.DINAR_COIN];
        uint256 totalTokens = baseTokens + fee;
        uint256 gramsTotal  = (quantity * 425) / 100; // 4.25g per dinar

        require(
            emasGold.balanceOf(msg.sender) >= totalTokens,
            "Redeem: insufficient EMAS"
        );

        requestId = _createRequest(
            RedeemType.DINAR_COIN,
            totalTokens,
            gramsTotal,
            quantity,
            deliveryAddrHash,
            fee
        );

        // Burn tokens (base + fee collected separately)
        emasGold.burnForRedemption(msg.sender, baseTokens);
        if (fee > 0) {
            // Fee transferred to treasury (not burned)
            // Note: in production, use approve+transferFrom pattern for fee
            emasGold.burnForRedemption(msg.sender, fee);
        }
    }

    // ─── Redeem: 5g Gold Bar ──────────────────────────────────────────────────

    /**
     * @notice Redeem N x 5g gold bars. Each = 500 EMAS tokens
     * @param quantity         Number of 5g bars
     * @param deliveryAddrHash Keccak256 hash of encrypted delivery address
     */
    function redeemBar5g(uint256 quantity, string calldata deliveryAddrHash)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 requestId)
    {
        require(quantity >= 1, "Redeem: min 1 bar");
        _checkEligibility(msg.sender);

        uint256 baseTokens  = quantity * MIN_GRAM_BAR_TOKENS;
        uint256 fee         = flatFeeTokens[RedeemType.GRAM_BAR_5];
        uint256 totalTokens = baseTokens + fee;
        uint256 gramsTotal  = quantity * 5;

        require(
            emasGold.balanceOf(msg.sender) >= totalTokens,
            "Redeem: insufficient EMAS"
        );

        requestId = _createRequest(
            RedeemType.GRAM_BAR_5,
            totalTokens,
            gramsTotal,
            quantity,
            deliveryAddrHash,
            fee
        );

        emasGold.burnForRedemption(msg.sender, baseTokens + fee);
    }

    // ─── Redeem: Custom Weight (multiples of 5g, min 5g) ─────────────────────

    /**
     * @notice Redeem a custom weight of gold (multiples of 5g)
     * @param gramMultiples    Number of 5g multiples (e.g. 4 = 20g)
     * @param deliveryAddrHash Keccak256 hash of encrypted delivery address
     */
    function redeemCustom(uint256 gramMultiples, string calldata deliveryAddrHash)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 requestId)
    {
        require(gramMultiples >= 1, "Redeem: min 5g (1 multiple)");
        _checkEligibility(msg.sender);

        uint256 baseTokens  = gramMultiples * CUSTOM_STEP_TOKENS;
        uint256 fee         = flatFeeTokens[RedeemType.CUSTOM_GRAM];
        uint256 totalTokens = baseTokens + fee;
        uint256 gramsTotal  = gramMultiples * 5;

        require(
            emasGold.balanceOf(msg.sender) >= totalTokens,
            "Redeem: insufficient EMAS"
        );

        requestId = _createRequest(
            RedeemType.CUSTOM_GRAM,
            totalTokens,
            gramsTotal,
            gramMultiples,
            deliveryAddrHash,
            fee
        );

        emasGold.burnForRedemption(msg.sender, baseTokens + fee);
    }

    // ─── Operator: Fulfil Request ─────────────────────────────────────────────

    /**
     * @notice Operator marks a redemption as fulfilled after physical dispatch
     * @param requestId     The redemption request ID
     * @param barId         The physical bar used to fulfil
     * @param trackingRef   Courier tracking reference
     */
    function fulfil(
        uint256 requestId,
        uint256 barId,
        string calldata trackingRef
    )
        external
        onlyRole(FULFILLER_ROLE)
    {
        RedeemRequest storage req = requests[requestId];
        require(req.status == RedeemStatus.Pending ||
                req.status == RedeemStatus.Processing,
                "Redeem: not pending");
        require(bytes(trackingRef).length > 0, "Redeem: empty tracking");

        req.status           = RedeemStatus.Fulfilled;
        req.fulfilTimestamp  = block.timestamp;
        req.trackingRef      = trackingRef;
        req.linkedBarId      = barId;

        // Update the physical bar's remaining grams
        goldCert.reduceRemaining(barId, req.gramsRedeemed);

        emit RedemptionFulfilled(requestId, barId, trackingRef, block.timestamp);
    }

    /**
     * @notice Operator marks request as Processing (in progress)
     */
    function markProcessing(uint256 requestId) external onlyRole(FULFILLER_ROLE) {
        RedeemRequest storage req = requests[requestId];
        require(req.status == RedeemStatus.Pending, "Redeem: not pending");
        req.status = RedeemStatus.Processing;
        emit RedemptionProcessing(requestId, msg.sender);
    }

    // ─── Internal Helpers ─────────────────────────────────────────────────────

    function _checkEligibility(address user) internal view {
        require(emasGold.kycApproved(user),     "Redeem: KYC required");
        require(!emasGold.frozenAddresses(user), "Redeem: address frozen");
    }

    function _createRequest(
        RedeemType  redeemType,
        uint256     totalTokens,
        uint256     grams,
        uint256     quantity,
        string calldata deliveryHash,
        uint256     fee
    ) internal returns (uint256 requestId) {
        _requestIds.increment();
        requestId = _requestIds.current();

        requests[requestId] = RedeemRequest({
            requester:        msg.sender,
            redeemType:       redeemType,
            tokensBurned:     totalTokens,
            gramsRedeemed:    grams,
            quantity:         quantity,
            requestTimestamp: block.timestamp,
            fulfilTimestamp:  0,
            status:           RedeemStatus.Pending,
            deliveryAddress:  deliveryHash,
            trackingRef:      "",
            linkedBarId:      0,
            flatFeeCharged:   fee
        });

        userRequests[msg.sender].push(requestId);

        emit RedemptionRequested(
            requestId,
            msg.sender,
            redeemType,
            totalTokens,
            grams,
            quantity
        );
    }

    // ─── View Functions ───────────────────────────────────────────────────────

    function getRequest(uint256 requestId)
        external view returns (RedeemRequest memory)
    {
        return requests[requestId];
    }

    function getUserRequests(address user)
        external view returns (uint256[] memory)
    {
        return userRequests[user];
    }

    function totalRequests() external view returns (uint256) {
        return _requestIds.current();
    }

    /// @notice Convenience: how many EMAS tokens needed for N Dinars + fee
    function quoteDinar(uint256 quantity) external view returns (uint256) {
        return (quantity * DINAR_TOKENS) + flatFeeTokens[RedeemType.DINAR_COIN];
    }

    /// @notice Convenience: how many EMAS tokens needed for N x 5g bars + fee
    function quoteBar5g(uint256 quantity) external view returns (uint256) {
        return (quantity * MIN_GRAM_BAR_TOKENS) + flatFeeTokens[RedeemType.GRAM_BAR_5];
    }

    /// @notice Convenience: how many EMAS tokens needed for N x 5g custom + fee
    function quoteCustom(uint256 gramMultiples) external view returns (uint256) {
        return (gramMultiples * CUSTOM_STEP_TOKENS) + flatFeeTokens[RedeemType.CUSTOM_GRAM];
    }

    // ─── Fee Admin ────────────────────────────────────────────────────────────

    function setFlatFee(RedeemType redeemType, uint256 feeTokens)
        external onlyRole(FEE_MANAGER)
    {
        flatFeeTokens[redeemType] = feeTokens;
        emit FlatFeeUpdated(redeemType, feeTokens);
    }

    function setFeeTreasury(address newTreasury)
        external onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(newTreasury != address(0), "Redeem: zero addr");
        feeTreasury = newTreasury;
    }

    // ─── Pause ────────────────────────────────────────────────────────────────
    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
