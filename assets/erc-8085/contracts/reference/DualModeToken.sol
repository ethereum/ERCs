// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IZRC20.sol";
import "../verifiers/IVerifier.sol";
import "../interfaces/IDualModeToken.sol";

/**
 * @title DualModeToken
 * @notice Dual-mode token (ERC-8085) combining ERC-20 and ERC-8086 privacy features
 * @dev This contract implements both transparent (ERC-20) and privacy (IZRC20) modes
 *      with seamless conversion between them.
 *
 * Architecture:
 *   - Public Mode: Standard ERC-20 (OpenZeppelin)
 *   - Privacy Mode: ERC-8086 IZRC20 compatible
 *   - Mode Conversion: toPrivacy() / toPublic()
 *
 * Key Features:
 *   - Unified token with dual capabilities
 *   - totalSupply = publicSupply + privacySupply
 *   - ZK-SNARK proof verification for all privacy operations
 */
contract DualModeToken is ERC20, ReentrancyGuard, IDualModeToken {

    // ═══════════════════════════════════════════════════════════════════════
    // Custom Errors
    // ═══════════════════════════════════════════════════════════════════════
    error AlreadyInitialized();
    error MaxSupplyExceeded();
    error IncorrectMintPrice(uint256 expected, uint256 sent);
    error IncorrectMintAmount(uint256 expected, uint256 actual);
    error InsufficientPublicBalance();
    error DirectPrivacyMintNotSupported();
    error ZeroAddress();
    error NoFeesToDistribute();
    error FeeTransferFailed();
    error InvalidProofType(uint8 receivedType);
    error InvalidProof();
    error CommitmentAlreadyExists(bytes32 commitment);
    error DoubleSpend(bytes32 nullifier);
    error OldActiveRootMismatch(bytes32 expected, bytes32 received);
    error OldFinalizedRootMismatch(bytes32 expected, bytes32 received);
    error IncorrectSubtreeIndex(uint256 expected, uint256 received);
    error InvalidStateForRegularMint();
    error InvalidStateForRollover();
    error SubtreeCapacityExceeded(uint256 needed, uint256 available);
    error InvalidConversionAmount(uint256 expected, uint256 proven);

    // ═══════════════════════════════════════════════════════════════════════
    // Constants
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Burn address for toPublic conversion (unspendable point on curve)
    uint256 public constant BURN_ADDRESS_X = 3782696719816812986959462081646797447108674627635188387134949121808249992769;
    uint256 public constant BURN_ADDRESS_Y = 10281180275793753078781257082583594598751421619807573114845203265637415315067;

    // ═══════════════════════════════════════════════════════════════════════
    // State Variables - Configuration
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Token metadata (stored separately for clone pattern compatibility)
    string private _tokenName;
    string private _tokenSymbol;

    uint256 public MAX_SUPPLY;
    uint256 public PUBLIC_MINT_PRICE;
    uint256 public PUBLIC_MINT_AMOUNT;
    address public platformTreasury;
    uint256 public platformFeeBps;
    address public initiator;  // Token creator, receives fees
    bool private _initialized;

    // ═══════════════════════════════════════════════════════════════════════
    // State Variables - Privacy (IZRC20 / ERC-8086)
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev ZK Verifiers
    IActiveTransferVerifier public activeTransferVerifier;
    IFinalizedTransferVerifier public finalizedTransferVerifier;
    ITransferRolloverVerifier public rolloverTransferVerifier;
    IMintVerifier public mintVerifier;
    IMintRolloverVerifier public mintRolloverVerifier;

    /// @dev Privacy state
    mapping(bytes32 => bool) public override nullifiers;
    mapping(bytes32 => bool) public commitmentHashes;
    uint256 public privacyTotalSupply;

    /// @dev Merkle tree state (packed for gas efficiency)
    struct ContractState {
        uint32 currentSubtreeIndex;
        uint32 nextLeafIndexInSubtree;
        uint8 subTreeHeight;
        uint8 rootTreeHeight;
        bool initialized;
    }
    ContractState public state;

    /// @dev Tree roots
    bytes32 public EMPTY_SUBTREE_ROOT;
    bytes32 public override activeSubtreeRoot;
    bytes32 public finalizedRoot;
    uint256 public SUBTREE_CAPACITY;

    /// @dev Transaction data structure for internal processing
    struct TransactionData {
        bytes32[2] nullifiers;
        bytes32[2] commitments;
        uint256[2] ephemeralPublicKey;
        uint256 viewTag;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Constructor & Initialization
    // ═══════════════════════════════════════════════════════════════════════

    constructor() ERC20("", "") {}

    /**
     * @notice Initialize the dual-mode token (called by factory via clone pattern)
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

        // ERC20 metadata (stored in our own storage variables)
        _tokenName = name_;
        _tokenSymbol = symbol_;

        // Configuration
        MAX_SUPPLY = maxSupply_;
        PUBLIC_MINT_PRICE = publicMintPrice_;
        PUBLIC_MINT_AMOUNT = publicMintAmount_;
        platformTreasury = platformTreasury_;
        platformFeeBps = platformFeeBps_;
        initiator = initiator_;

        // Verifiers
        mintVerifier = IMintVerifier(verifiers_[0]);
        mintRolloverVerifier = IMintRolloverVerifier(verifiers_[1]);
        activeTransferVerifier = IActiveTransferVerifier(verifiers_[2]);
        finalizedTransferVerifier = IFinalizedTransferVerifier(verifiers_[3]);
        rolloverTransferVerifier = ITransferRolloverVerifier(verifiers_[4]);

        // Privacy tree state
        state.subTreeHeight = subtreeHeight_;
        SUBTREE_CAPACITY = 1 << subtreeHeight_;
        state.rootTreeHeight = rootTreeHeight_;
        EMPTY_SUBTREE_ROOT = initialSubtreeEmptyRoot_;
        activeSubtreeRoot = initialSubtreeEmptyRoot_;
        finalizedRoot = initialFinalizedEmptyRoot_;
        state.nextLeafIndexInSubtree = 0;
        state.initialized = true;
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
     */
    function totalSupply() public view override(ERC20, IDualModeToken) returns (uint256) {
        return ERC20.totalSupply() + privacyTotalSupply;
    }

    /**
     * @notice Total supply in privacy mode only
     */
    function totalPrivacySupply() external view override returns (uint256) {
        return privacyTotalSupply;
    }

    /**
     * @notice Check if nullifier has been spent
     */
    function isNullifierSpent(bytes32 nullifier) external view override returns (bool) {
        return nullifiers[nullifier];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Public Minting (ERC-20)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Mint public tokens (standard ERC-20)
     */
    function mintPublic(address to, uint256 amount) external payable nonReentrant {
        if (msg.value != PUBLIC_MINT_PRICE) revert IncorrectMintPrice(PUBLIC_MINT_PRICE, msg.value);
        if (amount != PUBLIC_MINT_AMOUNT) revert IncorrectMintAmount(PUBLIC_MINT_AMOUNT, amount);
        if (totalSupply() + amount > MAX_SUPPLY) revert MaxSupplyExceeded();

        _mint(to, amount);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IZRC20.mint - NOT SUPPORTED for Dual-Mode Tokens
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Direct privacy mint is NOT supported for dual-mode tokens
     * @dev Use mintPublic() to get public tokens, then toPrivacy() to convert
     *      This design ensures all tokens enter through the public mode first
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
     * @dev Burns ERC-20 tokens and creates privacy commitment
     */
    function toPrivacy(
        uint256 amount,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata encryptedNote
    ) external override nonReentrant {
        if (balanceOf(msg.sender) < amount) revert InsufficientPublicBalance();

        // 1. Burn public tokens
        _burn(msg.sender, amount);

        // 2. Create privacy commitment
        bytes32 commitment = _privacyMint(amount, proofType, proof, encryptedNote);

        emit ConvertToPrivacy(msg.sender, amount, commitment, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Mode Conversion: Privacy → Public (ERC-8085 Core)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Convert privacy balance to public mode
     * @dev Spends privacy notes and mints ERC-20 tokens
     */
    function toPublic(
        address recipient,
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) external override nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();

        // 1. Spend privacy notes and get conversion amount
        uint256 conversionAmount = _privacyBurn(proofType, proof, encryptedNotes);

        // 2. Mint public tokens (no fee for mode conversion)
        _mint(recipient, conversionAmount);

        emit ConvertToPublic(msg.sender, recipient, conversionAmount, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Privacy Transfer (IZRC20 / ERC-8086)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Privacy-preserving transfer (IZRC20.transfer)
     */
    function transfer(
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) external override(IZRC20) {
        _privacyTransfer(proofType, proof, encryptedNotes);
    }
    

    // ═══════════════════════════════════════════════════════════════════════
    // Internal: Privacy Mint
    // ═══════════════════════════════════════════════════════════════════════

    function _privacyMint(
        uint256 expectedAmount,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata encryptedNote
    ) internal returns (bytes32 commitment) {
        if (proofType == 0) {
            commitment = _mintRegular(expectedAmount, proof, encryptedNote);
        } else if (proofType == 1) {
            commitment = _mintAndRollover(expectedAmount, proof, encryptedNote);
        } else {
            revert InvalidProofType(proofType);
        }
        privacyTotalSupply += expectedAmount;
    }

    function _mintRegular(
        uint256 expectedAmount,
        bytes calldata _proof,
        bytes calldata _encryptedNote
    ) private returns (bytes32) {
        if (state.nextLeafIndexInSubtree >= SUBTREE_CAPACITY) revert InvalidStateForRegularMint();

        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[4] memory pubSignals) =
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[4]));

        bytes32 newActiveRoot = bytes32(pubSignals[0]);
        bytes32 oldActiveRoot = bytes32(pubSignals[1]);
        bytes32 newCommitment = bytes32(pubSignals[2]);
        uint256 mintAmount = pubSignals[3];

        if (expectedAmount != mintAmount) revert IncorrectMintAmount(expectedAmount, mintAmount);
        if (commitmentHashes[newCommitment]) revert CommitmentAlreadyExists(newCommitment);
        if (activeSubtreeRoot != oldActiveRoot) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveRoot);
        if (!mintVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        commitmentHashes[newCommitment] = true;
        activeSubtreeRoot = newActiveRoot;

        emit CommitmentAppended(state.currentSubtreeIndex, newCommitment, state.nextLeafIndexInSubtree, block.timestamp);
        emit Minted(msg.sender, newCommitment, _encryptedNote, state.currentSubtreeIndex, state.nextLeafIndexInSubtree, block.timestamp);

        state.nextLeafIndexInSubtree++;
        return newCommitment;
    }

    function _mintAndRollover(
        uint256 expectedAmount,
        bytes calldata _proof,
        bytes calldata _encryptedNote
    ) private returns (bytes32) {
        if (state.nextLeafIndexInSubtree != SUBTREE_CAPACITY) revert InvalidStateForRollover();

        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[7] memory pubSignals) =
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[7]));

        bytes32 newActiveRoot = bytes32(pubSignals[0]);
        bytes32 newFinalizedRoot = bytes32(pubSignals[1]);
        bytes32 oldActiveRoot = bytes32(pubSignals[2]);
        bytes32 oldFinalizedRoot = bytes32(pubSignals[3]);
        bytes32 newCommitment = bytes32(pubSignals[4]);
        uint256 mintAmount = pubSignals[5];
        uint256 subtreeIndex = pubSignals[6];

        if (expectedAmount != mintAmount) revert IncorrectMintAmount(expectedAmount, mintAmount);
        if (commitmentHashes[newCommitment]) revert CommitmentAlreadyExists(newCommitment);
        if (activeSubtreeRoot != oldActiveRoot) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveRoot);
        if (finalizedRoot != oldFinalizedRoot) revert OldFinalizedRootMismatch(finalizedRoot, oldFinalizedRoot);
        if (state.currentSubtreeIndex != subtreeIndex) revert IncorrectSubtreeIndex(state.currentSubtreeIndex, subtreeIndex);
        if (!mintRolloverVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        commitmentHashes[newCommitment] = true;
        activeSubtreeRoot = newActiveRoot;
        finalizedRoot = newFinalizedRoot;
        state.currentSubtreeIndex++;
        state.nextLeafIndexInSubtree = 0;

        emit CommitmentAppended(state.currentSubtreeIndex, newCommitment, state.nextLeafIndexInSubtree, block.timestamp);
        emit Minted(msg.sender, newCommitment, _encryptedNote, state.currentSubtreeIndex, state.nextLeafIndexInSubtree, block.timestamp);

        state.nextLeafIndexInSubtree++;
        return newCommitment;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Internal: Privacy Transfer
    // ═══════════════════════════════════════════════════════════════════════

    function _privacyTransfer(
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) internal {
        if (proofType == 0) {
            _transferActive(proof, encryptedNotes, false);
        } else if (proofType == 1) {
            _transferFinalized(proof, encryptedNotes, false);
        } else if (proofType == 2) {
            _transferAndRollover(proof, encryptedNotes);
        } else {
            revert InvalidProofType(proofType);
        }
    }

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
        privacyTotalSupply -= burnAmount;
    }

    function _transferActive(
        bytes calldata _proof,
        bytes[] calldata _encryptedNotes,
        bool isModeConversion
    ) private returns (uint256 conversionAmount) {
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[13] memory pubSignals) =
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[13]));

        bytes32 newActiveRoot = bytes32(pubSignals[2]);
        uint256 numRealOutputs = pubSignals[3];
        conversionAmount = pubSignals[4];
        bytes32 oldActiveRoot = bytes32(pubSignals[5]);

        // Mode conversion validation
        if (isModeConversion) {
            if (conversionAmount == 0) revert InvalidConversionAmount(1, 0);
            uint256 recipientX = pubSignals[10];
            uint256 recipientY = pubSignals[11];
            if (recipientX != BURN_ADDRESS_X || recipientY != BURN_ADDRESS_Y) {
                revert InvalidConversionAmount(0, 1);
            }
        } else {
            if (conversionAmount != 0) revert InvalidConversionAmount(0, conversionAmount);
        }

        uint256 availableCapacity = SUBTREE_CAPACITY - state.nextLeafIndexInSubtree;
        if (numRealOutputs > availableCapacity) revert SubtreeCapacityExceeded(numRealOutputs, availableCapacity);
        if (activeSubtreeRoot != oldActiveRoot) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveRoot);
        if (!activeTransferVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        activeSubtreeRoot = newActiveRoot;

        TransactionData memory data;
        data.ephemeralPublicKey = [pubSignals[0], pubSignals[1]];
        data.nullifiers = [bytes32(pubSignals[6]), bytes32(pubSignals[7])];
        data.commitments = [bytes32(pubSignals[8]), bytes32(pubSignals[9])];
        data.viewTag = pubSignals[12];

        _processTransaction(data, _encryptedNotes);
    }

    function _transferFinalized(
        bytes calldata _proof,
        bytes[] calldata _encryptedNotes,
        bool isModeConversion
    ) private returns (uint256 conversionAmount) {
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[14] memory pubSignals) =
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[14]));

        bytes32 newActiveRoot = bytes32(pubSignals[2]);
        uint256 numRealOutputs = pubSignals[3];
        conversionAmount = pubSignals[4];
        bytes32 oldFinalizedRoot = bytes32(pubSignals[5]);
        bytes32 oldActiveRoot = bytes32(pubSignals[6]);

        if (isModeConversion) {
            if (conversionAmount == 0) revert InvalidConversionAmount(1, 0);
            uint256 recipientX = pubSignals[11];
            uint256 recipientY = pubSignals[12];
            if (recipientX != BURN_ADDRESS_X || recipientY != BURN_ADDRESS_Y) {
                revert InvalidConversionAmount(0, 1);
            }
        } else {
            if (conversionAmount != 0) revert InvalidConversionAmount(0, conversionAmount);
        }

        uint256 availableCapacity = SUBTREE_CAPACITY - state.nextLeafIndexInSubtree;
        if (numRealOutputs > availableCapacity) revert SubtreeCapacityExceeded(numRealOutputs, availableCapacity);
        if (activeSubtreeRoot != oldActiveRoot) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveRoot);
        if (finalizedRoot != oldFinalizedRoot) revert OldFinalizedRootMismatch(finalizedRoot, oldFinalizedRoot);
        if (!finalizedTransferVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        activeSubtreeRoot = newActiveRoot;

        TransactionData memory data;
        data.ephemeralPublicKey = [pubSignals[0], pubSignals[1]];
        data.nullifiers = [bytes32(pubSignals[7]), bytes32(pubSignals[8])];
        data.commitments = [bytes32(pubSignals[9]), bytes32(pubSignals[10])];
        data.viewTag = pubSignals[13];

        _processTransaction(data, _encryptedNotes);
    }

    function _transferAndRollover(
        bytes calldata _proof,
        bytes[] calldata _encryptedNotes
    ) private {
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[13] memory pubSignals) =
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[13]));

        bytes32 newActive = bytes32(pubSignals[2]);
        bytes32 newFinalized = bytes32(pubSignals[3]);
        uint256 conversionAmount = pubSignals[4];
        bytes32 oldActive = bytes32(pubSignals[5]);
        bytes32 oldFinalized = bytes32(pubSignals[6]);
        uint256 subtreeIndex = pubSignals[12];

        // Rollover doesn't support mode conversion
        if (conversionAmount != 0) revert InvalidConversionAmount(0, conversionAmount);
        if (state.nextLeafIndexInSubtree != SUBTREE_CAPACITY) revert InvalidStateForRollover();
        if (activeSubtreeRoot != oldActive) revert OldActiveRootMismatch(activeSubtreeRoot, oldActive);
        if (finalizedRoot != oldFinalized) revert OldFinalizedRootMismatch(finalizedRoot, oldFinalized);
        if (state.currentSubtreeIndex != subtreeIndex) revert IncorrectSubtreeIndex(state.currentSubtreeIndex, subtreeIndex);
        if (!rolloverTransferVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        activeSubtreeRoot = newActive;
        finalizedRoot = newFinalized;
        state.currentSubtreeIndex++;
        state.nextLeafIndexInSubtree = 0;

        TransactionData memory data;
        data.ephemeralPublicKey = [pubSignals[0], pubSignals[1]];
        data.nullifiers = [bytes32(pubSignals[7]), bytes32(0)];
        data.commitments = [bytes32(pubSignals[8]), bytes32(0)];
        data.viewTag = pubSignals[11];

        _processTransaction(data, _encryptedNotes);
    }

    function _processTransaction(
        TransactionData memory _data,
        bytes[] calldata _encryptedNotes
    ) private {
        // Spend nullifiers
        for (uint32 i = 0; i < _data.nullifiers.length; i++) {
            bytes32 n = _data.nullifiers[i];
            if (n != bytes32(0)) {
                if (nullifiers[n]) revert DoubleSpend(n);
                nullifiers[n] = true;
                emit NullifierSpent(n);
            }
        }

        // Append commitments
        for (uint i = 0; i < _data.commitments.length; i++) {
            bytes32 c = _data.commitments[i];
            if (c != bytes32(0)) {
                emit CommitmentAppended(state.currentSubtreeIndex, c, state.nextLeafIndexInSubtree, block.timestamp);
                state.nextLeafIndexInSubtree++;
            }
        }

        emit Transaction(_data.commitments, _encryptedNotes, _data.ephemeralPublicKey, _data.viewTag);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Fee Distribution
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Distribute collected mint fees to platform and token creator
     * @dev Fees are split: platformFeeBps to platform, remainder to initiator
     */
    function distributeFees() external nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFeesToDistribute();

        uint256 platformAmount = (balance * platformFeeBps) / 10000;
        uint256 initiatorAmount = balance - platformAmount;

        if (platformAmount > 0) {
            (bool success1, ) = platformTreasury.call{value: platformAmount}("");
            if (!success1) revert FeeTransferFailed();
        }

        if (initiatorAmount > 0) {
            (bool success2, ) = initiator.call{value: initiatorAmount}("");
            if (!success2) revert FeeTransferFailed();
        }
    }
}
