// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BarFractionizer
 * @notice Takes a GoldCertificate NFT (bar) and mints EmasGold ERC-20 tokens
 *         at a ratio of 1 EMAS = 0.01 gram of gold (100 tokens per gram)
 * @dev Interacts with GoldCertificate.sol and EmasGold.sol
 */

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IGoldCertificate {
    struct GoldBar {
        string  serialNumber;
        string  refinery;
        uint256 weightGrams;
        uint256 purityBps;
        string  assayNumber;
        string  ipfsDocHash;
        uint8   status;
        uint256 depositTimestamp;
        uint256 remainingGrams;
    }
    function getBar(uint256 barId) external view returns (GoldBar memory);
    function ownerOf(uint256 tokenId) external view returns (address);
    function isBarActive(uint256 barId) external view returns (bool);
    function markFractionized(uint256 barId, address fractionContract) external;
    function barFractionized(uint256 barId) external view returns (bool);
}

interface IEmasGold {
    function mintFromBar(address to, uint256 barId, uint256 tokenAmount) external;
    function totalBarTokens(uint256 barId) external view returns (uint256);
}

interface IProofOfReserve {
    function verify(uint256 barId, uint256 gramsToMint) external view returns (bool);
}

contract BarFractionizer is AccessControl, ReentrancyGuard, Pausable {

    // ─── Constants ────────────────────────────────────────────────────────────
    /// @notice 100 EMAS tokens per gram → 1 EMAS = 0.01g
    uint256 public constant TOKENS_PER_GRAM = 100;

    // ─── Roles ────────────────────────────────────────────────────────────────
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE   = keccak256("PAUSER_ROLE");

    // ─── Addresses ────────────────────────────────────────────────────────────
    IGoldCertificate public immutable goldCert;
    IEmasGold        public immutable emasGold;
    IProofOfReserve  public           proofOfReserve; // updatable oracle

    // ─── State ────────────────────────────────────────────────────────────────
    // barId => tokens already minted from this bar
    mapping(uint256 => uint256) public mintedTokensPerBar;

    // barId => total tokens capacity (set once on fractionization)
    mapping(uint256 => uint256) public totalCapacityPerBar;

    // ─── Events ───────────────────────────────────────────────────────────────
    event BarFractionized(
        uint256 indexed barId,
        uint256 weightGrams,
        uint256 totalTokensMinted,
        address mintedTo
    );
    event TopUpMinted(
        uint256 indexed barId,
        uint256 additionalTokens,
        address mintedTo
    );
    event ProofOfReserveUpdated(address indexed newPoR);

    // ─── Constructor ──────────────────────────────────────────────────────────
    constructor(
        address _goldCert,
        address _emasGold,
        address _proofOfReserve
    ) {
        require(_goldCert != address(0),        "Frac: zero cert addr");
        require(_emasGold != address(0),        "Frac: zero emas addr");
        require(_proofOfReserve != address(0),  "Frac: zero por addr");

        goldCert       = IGoldCertificate(_goldCert);
        emasGold       = IEmasGold(_emasGold);
        proofOfReserve = IProofOfReserve(_proofOfReserve);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE,      msg.sender);
        _grantRole(PAUSER_ROLE,        msg.sender);
    }

    // ─── Core: Fractionize a Bar ──────────────────────────────────────────────

    /**
     * @notice Operator fractionizes a full bar: mints 100 EMAS per gram to treasury
     * @dev Bar must be active, not already fractionized, and PoR must pass
     * @param barId     The GoldCertificate token ID to fractionize
     * @param mintTo    Address to receive the freshly minted EMAS tokens (treasury)
     */
    function fractionizeBar(uint256 barId, address mintTo)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        require(mintTo != address(0),                    "Frac: zero mint addr");
        require(goldCert.isBarActive(barId),             "Frac: bar not active");
        require(!goldCert.barFractionized(barId),        "Frac: already done");

        IGoldCertificate.GoldBar memory bar = goldCert.getBar(barId);
        require(bar.weightGrams > 0,                     "Frac: zero weight bar");

        // Proof of Reserve check — oracle confirms gold is in vault
        require(
            proofOfReserve.verify(barId, bar.weightGrams),
            "Frac: PoR check failed"
        );

        uint256 tokensToMint = bar.weightGrams * TOKENS_PER_GRAM;

        // Update state before external calls
        mintedTokensPerBar[barId]   = tokensToMint;
        totalCapacityPerBar[barId]  = tokensToMint;

        // Mark bar as fractionized in certificate contract
        goldCert.markFractionized(barId, address(emasGold));

        // Mint EMAS tokens to treasury
        emasGold.mintFromBar(mintTo, barId, tokensToMint);

        emit BarFractionized(barId, bar.weightGrams, tokensToMint, mintTo);
    }

    // ─── View: Token Math ─────────────────────────────────────────────────────

    /**
     * @notice Returns how many EMAS tokens a given weight of gold equals
     * @param grams Weight in grams (can be fractional as uint256 * 100)
     */
    function gramsToTokens(uint256 grams) public pure returns (uint256) {
        return grams * TOKENS_PER_GRAM;
    }

    /**
     * @notice Returns how many grams a given EMAS token count represents
     * @param tokens Number of EMAS tokens (1 token = 0.01g)
     */
    function tokensToGrams(uint256 tokens) public pure returns (uint256) {
        return tokens / TOKENS_PER_GRAM;
    }

    /**
     * @notice Returns remaining mintable tokens for a bar
     */
    function remainingCapacity(uint256 barId) external view returns (uint256) {
        return totalCapacityPerBar[barId] - mintedTokensPerBar[barId];
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    function updateProofOfReserve(address newPoR) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newPoR != address(0), "Frac: zero addr");
        proofOfReserve = IProofOfReserve(newPoR);
        emit ProofOfReserveUpdated(newPoR);
    }

    function pause()   external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }
}
