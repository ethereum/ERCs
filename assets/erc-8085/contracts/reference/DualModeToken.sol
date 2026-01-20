// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./PrivacyToken.sol";
import "../interfaces/IDualModeToken.sol";

/**
 * @title DualModeToken
 * @notice Dual-mode token (ERC-8085) combining ERC-20 and ERC-8086 privacy features
 * @dev This contract extends PrivacyToken (ERC-8086) with public mode (ERC-20) and
 *      mode conversion capabilities, creating a unified token that operates in two modes.
 *
* Architecture:
 *   - Public Mode: Standard ERC-20 (OpenZeppelin)
 *   - Privacy Mode: ERC-8086 IZRC20 compatible
 *   - Mode Conversion: toPrivate() / toPublic()
 *Layered Design:
 *   ┌─────────────────────────────────────────┐
 *   │    DualModeToken (ERC-8085 Layer)       │
 *   │  - Public mode (ERC-20)                 │
 *   │  - Mode conversion (toPrivate/toPublic) │
 *   │                                         │
 *   ├─────────────────────────────────────────┤
 *   │    PrivacyToken (ERC-8086 Layer)        │
 *   │  - Privacy mode (IZRC20)                │
 *   │  - ZK-SNARK proofs                      │
 *   │  - Merkle trees, nullifiers             │
 *   └─────────────────────────────────────────┘
 *
 * Key Features:
 *   - Unified token with dual capabilities
 *   - totalSupply = publicSupply + privacySupply
 *   - Seamless mode conversion: toPrivate() switch token into privacy mode
 *   - Seamless mode conversion: toPublic() switch token into public mode
 *
 * Design Philosophy:
 *   "Privacy is a mode, not a separate token" - Users can switch between modes as needed
 *   while maintaining a single unified asset with consistent liquidity and market value.
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * IMPORTANT: ERC-8085 Standard vs. Reference Implementation
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * The standard ONLY requires privacy guarantees and core interface compatibility.
 * All business logic (fees, deployment) is implementation-specific.
 */
contract DualModeToken is PrivacyToken, ERC20, IDualModeToken {

    // Custom Errors
    error MaxSupplyExceeded();
    error IncorrectMintPrice(uint256 expected, uint256 sent);
    error InsufficientPublicBalance();
    error DirectPrivacyMintNotSupported();
    error ZeroAddress();

    /// @dev Burn address for toPublic conversion (provably unspendable point on curve)
    /// @notice This address ensures privacy notes cannot be spent after conversion to public
    uint256 public constant BURN_ADDRESS_X = 3782696719816812986959462081646797447108674627635188387134949121808249992769;
    uint256 public constant BURN_ADDRESS_Y = 10281180275793753078781257082583594598751421619807573114845203265637415315067;

    // ═══════════════════════════════════════════════════════════════════════
    // State Variables (ERC-8085 / Public Mode Specific)
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Token metadata (stored separately for clone pattern compatibility)
    /// @custom:standard-required ERC-20 and ERC-8086 both require name/symbol
    string private _tokenName;
    string private _tokenSymbol;

    /// @dev Public mode configuration
    /// @custom:business-logic These are reference implementation choices, NOT required by ERC-8085
    /// @notice Other implementations may use different minting mechanisms, no caps, or other models
    uint256 public MAX_SUPPLY;
    uint256 public PUBLIC_MINT_PRICE;
    uint256 public PUBLIC_MINT_AMOUNT;

    /// @dev Initialization guard
    /// @custom:implementation-detail Clone pattern security, not required by standard
    bool private _initialized;

    // ═══════════════════════════════════════════════════════════════════════
    // Constructor & Initialization
    // ═══════════════════════════════════════════════════════════════════════

    constructor() ERC20("", "") {}

    /**
     * @notice Initialize the dual-mode token (called by factory via clone pattern)
     * @dev Initializes both privacy layer (PrivacyToken) and public layer (ERC20)
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 publicMintPrice_,
        uint256 publicMintAmount_,
        address platformTreasury_,
        uint256 platformFeeBps_,
        address initiator_,
        address[5] memory verifiers_,
        uint8 subtreeHeight_,
        uint8 rootTreeHeight_,
        bytes32 initialSubtreeEmptyRoot_,
        bytes32 initialFinalizedEmptyRoot_
    ) external {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        // Initialize privacy layer (PrivacyToken)
        __PrivacyToken_init(
            platformTreasury_,
            platformFeeBps_,
            initiator_,
            verifiers_,
            subtreeHeight_,
            rootTreeHeight_,
            initialSubtreeEmptyRoot_,
            initialFinalizedEmptyRoot_
        );

        // Initialize public layer (ERC20 metadata)
        _tokenName = name_;
        _tokenSymbol = symbol_;

        // Public mode configuration
        MAX_SUPPLY = maxSupply_;
        PUBLIC_MINT_PRICE = publicMintPrice_;
        PUBLIC_MINT_AMOUNT = publicMintAmount_;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ERC-20 Metadata Overrides
    // ═══════════════════════════════════════════════════════════════════════

    function name() public view override(ERC20, IZRC20) returns (string memory) {
        return _tokenName;
    }

    function symbol() public view override(ERC20, IZRC20) returns (string memory) {
        return _tokenSymbol;
    }

    function decimals() public pure override(ERC20, IZRC20) returns (uint8) {
        return 18;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Supply Tracking (ERC-8085 Requirement)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Total supply across both modes (ERC-20 + Privacy)
     * @dev ERC-8085 requirement: totalSupply = publicSupply + privacySupply
     *      Overrides both ERC20.totalSupply() and PrivacyToken.totalSupply()
     */
    function totalSupply() public view override(ERC20, PrivacyToken, IDualModeToken) returns (uint256) {
        return ERC20.totalSupply() + PrivacyToken.totalSupply();
    }

    /**
     * @notice Total supply in privacy mode only
     * @dev Returns the privacy supply from PrivacyToken base class
     */
    function totalPrivacySupply() external view override returns (uint256) {
        return PrivacyToken.totalSupply();
    }

    /**
     * @notice Check if nullifier has been spent
     * @dev Convenience function, delegates to inherited nullifiers mapping
     */
    function isNullifierSpent(bytes32 nullifier) external view override returns (bool) {
        return nullifiers[nullifier];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Public Minting (REFERENCE IMPLEMENTATION - NOT PART OF ERC-8085)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint public tokens (standard ERC-20)
     * @dev Entry point for all tokens - ensures supply transparency
     *
     * ⚠️ IMPORTANT: This is NOT required by ERC-8085 standard!
     *
     * This is ONE possible token distribution mechanism.
     * Other ERC-8085 implementations MAY use:
     *   - Initial supply minted to deployer
     *   - Bonding curve minting
     *   - Airdrop distribution
     *   - Governance-controlled minting
     *   - Direct privacy minting (with different design trade-offs)
     *   - No public minting at all (if starting from wrapped tokens)
     *
     * ERC-8085 standard does NOT mandate:
     *   - Public minting mechanism
     *   - Minting prices or amounts
     *   - MAX_SUPPLY caps
     *   - Who can mint tokens
     *
     * This function demonstrates a simple permissionless minting model.
     */
    function mintPublic(address to, uint256 amount) external payable nonReentrant {
        if (msg.value != PUBLIC_MINT_PRICE) revert IncorrectMintPrice(PUBLIC_MINT_PRICE, msg.value);
        if (amount != PUBLIC_MINT_AMOUNT) revert IncorrectMintAmount(PUBLIC_MINT_AMOUNT, amount);
        if (totalSupply() + amount > MAX_SUPPLY) revert MaxSupplyExceeded();

        _mint(to, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IZRC20.mint - DISABLED for Dual-Mode Tokens
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Direct privacy mint is NOT supported for dual-mode tokens
     * @dev Use mintPublic() to get public tokens, then toPrivate() to convert
     *      This design ensures all tokens enter through the public mode first,
     *      maintaining supply transparency and preventing hidden inflation.
     */
    function mint(
        uint8,
        bytes calldata,
        bytes calldata
    ) external payable override {
        revert DirectPrivacyMintNotSupported();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Mode Conversion: Public → Privacy (ERC-8085 Core)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert public balance to privacy mode
     * @dev Burns ERC-20 tokens and creates privacy commitment via PrivacyToken._privacyMint
     * @param amount Amount to convert (must match proof)
     * @param proofType Type of proof (0 = regular, 1 = rollover)
     * @param proof ZK-SNARK proof of valid commitment creation
     * @param encryptedNote Encrypted note data for recipient wallet
     */
    function toPrivate(
        uint256 amount,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata encryptedNote
    ) external override nonReentrant {
        if (balanceOf(msg.sender) < amount) revert InsufficientPublicBalance();

        // 1. Burn public tokens (ERC-20 layer)
        _burn(msg.sender, amount);

        // 2. Create privacy commitment (PrivacyToken layer)
        _privacyMint(amount, proofType, proof, encryptedNote);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Mode Conversion: Privacy → Public (ERC-8085 Core)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert privacy balance to public mode
     * @dev Spends privacy notes and mints ERC-20 tokens
     * @param recipient Address to receive public tokens
     * @param proofType Type of proof (0 = active, 1 = finalized)
     * @param proof ZK-SNARK proof of note ownership and spending
     * @param encryptedNotes Encrypted notes for change outputs (if any)
     */
    function toPublic(
        address recipient,
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) external override nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();

        // 1. Spend privacy notes and get conversion amount (PrivacyToken layer)
        uint256 conversionAmount = _privacyBurn(proofType, proof, encryptedNotes);

        // 2. Mint public tokens (ERC-20 layer)
        _mint(recipient, conversionAmount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Internal: Privacy Burn (Mode Conversion Helper)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal function to burn privacy notes during mode conversion
     * @dev Calls PrivacyToken transfer functions with isModeConversion=true
     *      and decrements privacy supply
     * @return burnAmount Amount burned (converted to public)
     */
    function _privacyBurn(
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) internal returns (uint256 burnAmount) {
        if (proofType == 0) {
            burnAmount = _transferActive(proof, encryptedNotes, true);
        } else if (proofType == 1) {
            burnAmount = _transferFinalized(proof, encryptedNotes, true);
        } else {
            revert InvalidProofType(proofType);
        }
        _privacySupply -= burnAmount;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Mode Conversion Validation (Override PrivacyToken Hook)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate mode conversion parameters (overrides PrivacyToken)
     * @dev Verifies that privacy notes are sent to BURN_ADDRESS (provably unspendable)
     *      This ensures the converted value cannot be double-spent in privacy mode.
     *
     * Security Critical: Without this check, users could:
     *   1. Spend privacy notes to their own address
     *   2. Get public tokens from toPublic()
     *   3. Still have spendable privacy notes
     *   Result: Creating tokens out of thin air!
     *
     * @param conversionAmount Amount being converted (must be > 0)
     * @param recipientX X coordinate of recipient public key
     * @param recipientY Y coordinate of recipient public key
     */
    function _validateModeConversion(
        uint256 conversionAmount,
        uint256 recipientX,
        uint256 recipientY
    ) internal pure override {
        if (conversionAmount == 0) revert InvalidConversionAmount(1, 0);
        if (recipientX != BURN_ADDRESS_X || recipientY != BURN_ADDRESS_Y) {
            revert InvalidConversionAmount(0, 1);
        }
    }
}
