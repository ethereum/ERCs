// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./PrivacyToken.sol";

/**
 * @title PrivacyTokenFactory
 * @notice Factory for deploying new ERC-8086 compliant privacy tokens
 * @dev Uses minimal proxy pattern (EIP-1167) for gas-efficient deployments.
 *      Anyone can create a new privacy token by paying the creation fee.
 */
contract PrivacyTokenFactory is Ownable {

    // ===================================
    //        IMMUTABLE STATE
    // ===================================

    /// @notice The implementation contract address used for all clones
    address public immutable privacyTokenImplementation;

    // ===================================
    //        PLATFORM CONFIGURATION
    // ===================================

    /// @notice Treasury address for platform fees
    address public platformTreasury;

    /// @notice Platform fee in basis points (e.g., 250 = 2.5%)
    uint256 public platformFeeBps;

    /// @notice Fee required to create a new token
    uint256 public creationFee;

    // ===================================
    //        SHARED VERIFIERS
    // ===================================

    IVerifier public mintVerifier;
    IVerifier public mintRolloverVerifier;
    IVerifier public activeTransferVerifier;
    IVerifier public finalizedTransferVerifier;
    IVerifier public rolloverTransferVerifier;

    // ===================================
    //        TREE CONFIGURATION
    // ===================================

    /// @notice Height of active subtree (e.g., 16 = 65536 leaves)
    uint8 public subtree_height;

    /// @notice Height of root tree (e.g., 20 = 1048576 subtrees)
    uint8 public roottree_height;

    /// @notice Precomputed empty root for new subtrees
    bytes32 public initialSubtreeEmptyRoot;

    /// @notice Precomputed empty root for finalized tree
    bytes32 public initialFinalizedEmptyRoot;

    // ===================================
    //        EVENTS
    // ===================================

    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint256 maxSupply,
        uint256 mintAmount,
        uint256 mintPrice,
        uint256 subTreeHeight,
        uint256 rootTreeHeight
    );

    event VerifiersUpdated(
        address newMintVerifier,
        address newMintRolloverVerifier,
        address newActiveTransferVerifier,
        address newFinalizedTransferVerifier,
        address newRolloverTransferVerifier
    );

    event PlatformFeeUpdated(uint256 newFeeBps);
    event TreasuryUpdated(address indexed newTreasury);
    event CreationFeeUpdated(uint256 newCreationFee);

    // ===================================
    //        CONSTRUCTOR
    // ===================================

    /**
     * @notice Deploys the factory with initial configuration
     * @param _implementation Address of PrivacyToken implementation
     * @param _treasury Address to receive platform fees
     * @param _verifiers Array of 5 verifier addresses: [mint, mintRollover, active, finalized, transferRollover]
     * @param _initialSubtreeEmptyRoot Precomputed empty subtree root
     * @param _initialFinalizedEmptyRoot Precomputed empty finalized tree root
     */
    constructor(
        address _implementation,
        address _treasury,
        address[5] memory _verifiers,
        bytes32 _initialSubtreeEmptyRoot,
        bytes32 _initialFinalizedEmptyRoot
    ) Ownable(msg.sender) {
        require(_implementation != address(0), "Impl address cannot be zero");
        require(_treasury != address(0), "Treasury address cannot be zero");
        for (uint i = 0; i < _verifiers.length; i++) {
            require(_verifiers[i] != address(0), "Verifier address cannot be zero");
        }

        privacyTokenImplementation = _implementation;
        platformTreasury = _treasury;
        platformFeeBps = 250; // Default 2.5%
        creationFee = 0.005 ether;
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
    //        TOKEN CREATION
    // ===================================

    /**
     * @notice Creates a new privacy token
     * @param name Token name
     * @param symbol Token symbol
     * @param maxSupply Maximum supply (in wei, 18 decimals)
     * @param mintPrice Price per mint in native token (ETH)
     * @param mintAmount Amount minted per mint operation
     * @return tokenProxy Address of the newly created token
     */
    function createToken(
        string calldata name,
        string calldata symbol,
        uint256 maxSupply,
        uint256 mintPrice,
        uint256 mintAmount
    ) external payable returns (address tokenProxy) {
        require(msg.value == creationFee, "Incorrect creation fee");
        require(bytes(name).length > 0 && bytes(symbol).length > 0, "Name and symbol required");
        require(maxSupply > 0, "Max supply must be positive");

        tokenProxy = Clones.clone(privacyTokenImplementation);

        PrivacyToken(tokenProxy).initialize(
            name,
            symbol,
            maxSupply,
            mintPrice,
            mintAmount,
            msg.sender,
            platformTreasury,
            platformFeeBps,
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

        emit TokenCreated(
            tokenProxy,
            msg.sender,
            name,
            symbol,
            maxSupply,
            mintAmount,
            mintPrice,
            subtree_height,
            roottree_height
        );
    }

    // ===================================
    //        ADMIN FUNCTIONS
    // ===================================

    function setCreationFee(uint256 _newCreationFee) external onlyOwner {
        creationFee = _newCreationFee;
        emit CreationFeeUpdated(_newCreationFee);
    }

    function setTreeHeight(uint8 _subtree_height, uint8 _roottree_height) external onlyOwner {
        require(_subtree_height > 9, "Invalid subtree height");
        require(_roottree_height > 15, "Invalid roottree height");
        subtree_height = _subtree_height;
        roottree_height = _roottree_height;
    }

    function withdrawCreationFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "Factory: No fees to withdraw");
        (bool success, ) = platformTreasury.call{value: balance}("");
        require(success, "Factory: Fee withdrawal failed");
    }

    function setPlatformFeeBps(uint256 _newFeeBps) external onlyOwner {
        require(_newFeeBps <= 10000, "Factory: Fee cannot exceed 100%");
        platformFeeBps = _newFeeBps;
        emit PlatformFeeUpdated(_newFeeBps);
    }

    function setTreasury(address _newTreasury) external onlyOwner {
        require(_newTreasury != address(0), "Factory: Invalid treasury address");
        platformTreasury = _newTreasury;
        emit TreasuryUpdated(_newTreasury);
    }

    function setVerifiers(address[5] memory _newVerifiers) external onlyOwner {
        for (uint i = 0; i < _newVerifiers.length; i++) {
            require(_newVerifiers[i] != address(0), "New verifier address cannot be zero");
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
}
