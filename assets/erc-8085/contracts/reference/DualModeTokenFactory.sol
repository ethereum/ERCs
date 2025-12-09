// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./DualModeToken.sol";
import "../verifiers/IVerifier.sol";

/**
 * @title DualModeTokenFactory
 * @dev Factory for creating dual-mode tokens with ERC20 + ZK-SNARK privacy
 *
 * Features:
 *   - Clone-based deployment for gas efficiency
 *   - Centralized verifier management
 *   - Configurable tree parameters
 *   - Creation fee collection
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * IMPORTANT: Factory Pattern is NOT Required by ERC-8085
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * ⚠️ THIS IS A REFERENCE IMPLEMENTATION CHOICE, NOT A STANDARD REQUIREMENT!
 *
 * This factory contract demonstrates ONE way to deploy ERC-8085 tokens efficiently.
 *
 * Other valid deployment approaches:
 *   - Direct contract deployment (no factory, no clones)
 *   - Different clone patterns (e.g., Beacon proxies, UUPS)
 *   - No central verifier management (each token has its own)
 *   - Different fee structures or no creation fees
 *   - Permissioned deployment (vs. permissionless)
 *
 * The factory pattern here provides:
 *   ✅ Gas optimization (clones ~10x cheaper than direct deployment)
 *   ✅ Centralized verifier upgrades (if needed)
 *   ✅ Revenue model (creation fees)
 *   ✅ Token registry (tracking deployed tokens)
 *
 * But ERC-8085 does NOT mandate:
 *   - Using factories
 *   - Using clones
 *   - Central verifier management
 *   - Creation fees
 *   - Token registries
 *
 * You can deploy ERC-8085 tokens however you want!
 */
contract DualModeTokenFactory is Ownable {

    // ===================================
    //        STATE VARIABLES
    // ===================================

    /// @notice Implementation contract for cloning
    address public immutable dualModeTokenImplementation;

    /// @notice Platform treasury address
    address public platformTreasury;

    /// @notice Platform fee in basis points (e.g., 250 = 2.5%)
    uint256 public platformFeeBps;

    /// @notice Fee to create a new token
    uint256 public creationFee;

    /// @notice Shared ZK verifier contracts
    IVerifier public mintVerifier;
    IVerifier public mintRolloverVerifier;
    IVerifier public activeTransferVerifier;
    IVerifier public finalizedTransferVerifier;
    IVerifier public rolloverTransferVerifier;

    /// @notice Tree geometry parameters
    uint8 public subtree_height;
    uint8 public roottree_height;
    bytes32 public initialSubtreeEmptyRoot;
    bytes32 public initialFinalizedEmptyRoot;

    /// @notice Track deployed tokens
    address[] public deployedTokens;
    mapping(address => bool) public isDeployedToken;

    // ===================================
    //        EVENTS
    // ===================================

    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint256 maxSupply,
        uint256 publicMintPrice,
        uint256 publicMintAmount,
        uint256 subTreeHeight,
        uint256 rootTreeHeight
    );

    event VerifiersUpdated(
        address mintVerifier,
        address mintRolloverVerifier,
        address activeTransferVerifier,
        address finalizedTransferVerifier,
        address rolloverTransferVerifier
    );

    event TreasuryUpdated(address indexed newTreasury);
    event PlatformFeeUpdated(uint256 newFeeBps);
    event CreationFeeUpdated(uint256 newCreationFee);
    event TreeParametersUpdated(uint8 subtreeHeight, uint8 rootTreeHeight);

    // ===================================
    //        CONSTRUCTOR
    // ===================================

    /**
     * @param _implementation Address of DualModeToken implementation
     * @param _treasury Platform treasury address
     * @param _verifiers Array of verifier addresses [mint, mintRollover, active, finalized, rollover]
     * @param _initialSubtreeEmptyRoot Empty subtree root hash
     * @param _initialFinalizedEmptyRoot Empty finalized root hash
     */
    constructor(
        address _implementation,
        address _treasury,
        address[5] memory _verifiers,
        bytes32 _initialSubtreeEmptyRoot,
        bytes32 _initialFinalizedEmptyRoot
    ) Ownable(msg.sender) {
        require(_implementation != address(0), "Invalid implementation");
        require(_treasury != address(0), "Invalid treasury");
        for (uint i = 0; i < _verifiers.length; i++) {
            require(_verifiers[i] != address(0), "Invalid verifier");
        }

        dualModeTokenImplementation = _implementation;
        platformTreasury = _treasury;
        platformFeeBps = 250; // Default 2.5%
        creationFee = 0 ether;
        subtree_height = 16;
        roottree_height = 20;

        mintVerifier = IVerifier(_verifiers[0]);
        mintRolloverVerifier = IVerifier(_verifiers[1]);
        activeTransferVerifier = IVerifier(_verifiers[2]);
        finalizedTransferVerifier = IVerifier(_verifiers[3]);
        rolloverTransferVerifier = IVerifier(_verifiers[4]);

        initialSubtreeEmptyRoot = _initialSubtreeEmptyRoot;
        initialFinalizedEmptyRoot = _initialFinalizedEmptyRoot;
    }

    // ===================================
    //        CORE FUNCTIONALITY
    // ===================================

    /**
     * @notice Create a new dual-mode token
     * @param name Token name
     * @param symbol Token symbol
     * @param maxSupply Maximum total supply (public + privacy)
     * @param publicMintPrice Price to mint public tokens
     * @param publicMintAmount Amount minted per public mint
     * @return token Address of the newly created token
     */
    function createToken(
        string calldata name,
        string calldata symbol,
        uint256 maxSupply,
        uint256 publicMintPrice,
        uint256 publicMintAmount
    ) external payable returns (address token) {
        require(msg.value == creationFee, "Incorrect creation fee");
        require(bytes(name).length > 0, "Name required");
        require(bytes(symbol).length > 0, "Symbol required");
        require(maxSupply > 0, "Max supply must be positive");

        // Clone the implementation
        token = Clones.clone(dualModeTokenImplementation);

        // Initialize the token
        DualModeToken(token).initialize(
            name,
            symbol,
            maxSupply,
            publicMintPrice,
            publicMintAmount,
            platformTreasury,
            platformFeeBps,
            msg.sender,  // initiator = token creator
            [
                address(mintVerifier),
                address(mintRolloverVerifier),
                address(activeTransferVerifier),
                address(finalizedTransferVerifier),
                address(rolloverTransferVerifier)
            ],
            subtree_height,
            roottree_height,
            initialSubtreeEmptyRoot,
            initialFinalizedEmptyRoot
        );

        // Track deployment
        deployedTokens.push(token);
        isDeployedToken[token] = true;

        emit TokenCreated(
            token,
            msg.sender,
            name,
            symbol,
            maxSupply,
            publicMintPrice,
            publicMintAmount,
            subtree_height,
            roottree_height
        );
    }

    // ===================================
    //        ADMIN FUNCTIONS
    // ===================================

    /**
     * @notice Update verifier contracts
     * @param _newVerifiers Array of new verifier addresses
     */
    function setVerifiers(address[5] memory _newVerifiers) external onlyOwner {
        for (uint i = 0; i < _newVerifiers.length; i++) {
            require(_newVerifiers[i] != address(0), "Invalid verifier");
        }

        mintVerifier = IVerifier(_newVerifiers[0]);
        mintRolloverVerifier = IVerifier(_newVerifiers[1]);
        activeTransferVerifier = IVerifier(_newVerifiers[2]);
        finalizedTransferVerifier = IVerifier(_newVerifiers[3]);
        rolloverTransferVerifier = IVerifier(_newVerifiers[4]);

        emit VerifiersUpdated(
            _newVerifiers[0],
            _newVerifiers[1],
            _newVerifiers[2],
            _newVerifiers[3],
            _newVerifiers[4]
        );
    }

    /**
     * @notice Update platform treasury
     * @param _newTreasury New treasury address
     */
    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Invalid treasury");
        platformTreasury = _newTreasury;
        emit TreasuryUpdated(_newTreasury);
    }

    /**
     * @notice Update platform fee
     * @param _newFeeBps New fee in basis points (max 10000 = 100%)
     */
    function setPlatformFeeBps(uint256 _newFeeBps) external onlyOwner {
        require(_newFeeBps <= 10000, "Fee cannot exceed 100%");
        platformFeeBps = _newFeeBps;
        emit PlatformFeeUpdated(_newFeeBps);
    }

    /**
     * @notice Update creation fee
     * @param _newCreationFee New creation fee
     */
    function setCreationFee(uint256 _newCreationFee) external onlyOwner {
        creationFee = _newCreationFee;
        emit CreationFeeUpdated(_newCreationFee);
    }

    /**
     * @notice Update tree height parameters
     * @param _subtree_height New subtree height
     * @param _roottree_height New root tree height
     */
    function setTreeHeight(uint8 _subtree_height, uint8 _roottree_height) external onlyOwner {
        require(_subtree_height > 9, "Invalid subtree height");
        require(_roottree_height > 15, "Invalid root tree height");
        subtree_height = _subtree_height;
        roottree_height = _roottree_height;
        emit TreeParametersUpdated(_subtree_height, _roottree_height);
    }

    /**
     * @notice Withdraw collected creation fees
     */
    function withdrawCreationFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        (bool success, ) = platformTreasury.call{value: balance}("");
        require(success, "Fee withdrawal failed");
    }

    // ===================================
    //        VIEW FUNCTIONS
    // ===================================

    /**
     * @notice Get total number of deployed tokens
     */
    function getDeployedTokenCount() external view returns (uint256) {
        return deployedTokens.length;
    }

    /**
     * @notice Get deployed token at index
     */
    function getDeployedToken(uint256 index) external view returns (address) {
        require(index < deployedTokens.length, "Index out of bounds");
        return deployedTokens[index];
    }

    /**
     * @notice Get all deployed tokens
     */
    function getAllDeployedTokens() external view returns (address[] memory) {
        return deployedTokens;
    }
}
