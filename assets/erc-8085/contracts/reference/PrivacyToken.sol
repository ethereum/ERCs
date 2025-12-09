// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IZRC20.sol";
import "../verifiers/IVerifier.sol";

/**
 * @title PrivacyToken
 * @notice Pure ERC-8086 privacy token implementation - the foundation layer
 * @dev This contract implements the complete IZRC20 interface with ZK-SNARK privacy features.
 *      It serves as the base layer for dual-mode tokens (ERC-8085) and can also be used
 *      standalone for pure privacy applications.
 *
 *
 * ═══════════════════════════════════════════════════════════════════════════════
 * IMPORTANT: ERC-8086 Standard vs. Reference Implementation
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 * The standard ONLY requires privacy guarantees and core interface compatibility.
 * All business logic (fees, deployment) is implementation-specific.
 */
abstract contract PrivacyToken is IZRC20, ReentrancyGuard {

    // ═══════════════════════════════════════════════════════════════════════
    // Custom Errors
    // ═══════════════════════════════════════════════════════════════════════

    error AlreadyInitialized();
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
    error ModeConversionNotSupported();
    error IncorrectMintAmount(uint256 expected, uint256 actual);
    error NoFeesToDistribute();
    error FeeTransferFailed();

    /// @dev ZK Verifiers for different proof types
    /// @custom:implementation-detail Not required by ERC-8086, specific to this ZK circuit design
    IActiveTransferVerifier public activeTransferVerifier;
    IFinalizedTransferVerifier public finalizedTransferVerifier;
    ITransferRolloverVerifier public rolloverTransferVerifier;
    IMintVerifier public mintVerifier;
    IMintRolloverVerifier public mintRolloverVerifier;

    /// @dev Privacy state mappings
    /// @custom:standard-required ERC-8086 requires nullifier tracking for double-spend prevention
    mapping(bytes32 => bool) public override nullifiers;        // ERC-8086 required
    /// @custom:implementation-detail Commitment deduplication is a reference implementation choice
    mapping(bytes32 => bool) public commitmentHashes;           // Prevent duplicate commitments

    /// @dev Total supply in privacy mode (internal for inheritance flexibility)
    /// @custom:standard-optional ERC-8086 totalSupply() is optional but recommended
    uint256 internal _privacySupply;

    /// @dev Merkle tree state (packed for gas efficiency)
    /// @custom:implementation-detail Dual-layer tree structure is an optimization, not required by standard
    struct ContractState {
        uint32 currentSubtreeIndex;
        uint32 nextLeafIndexInSubtree;
        uint8 subTreeHeight;
        uint8 rootTreeHeight;
        bool initialized;
    }
    ContractState public state;

    /// @dev Tree roots
    /// @custom:implementation-detail Specific tree configuration, other implementations may differ
    bytes32 public EMPTY_SUBTREE_ROOT;
    /// @custom:standard-required ERC-8086 requires activeSubtreeRoot() for proof verification
    bytes32 public override activeSubtreeRoot;    // ERC-8086 required
    /// @custom:implementation-detail Finalized root is part of dual-layer optimization
    bytes32 public finalizedRoot;
    uint256 public SUBTREE_CAPACITY;

    // ═══════════════════════════════════════════════════════════════════════
    // State Variables - Business Logic (NOT part of ERC-8086 standard)
    // ═══════════════════════════════════════════════════════════════════════

    /// @dev Platform and fee configuration
    /// @custom:business-logic These are reference implementation choices, NOT required by ERC-8086
    /// @notice Other implementations may use different fee models or no fees at all
    address public platformTreasury;
    uint256 public platformFeeBps;
    address public initiator;  // Token creator, receives fees

    /// @dev Transaction data structure for internal processing
    struct TransactionData {
        bytes32[2] nullifiers;
        bytes32[2] commitments;
        uint256[2] ephemeralPublicKey;
        uint256 viewTag;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Initialization
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal initializer for privacy state (called by derived contracts)
     * @dev This is an internal function to support different initialization patterns
     *      (e.g., standalone PrivacyToken vs. DualModeToken)
     */
    function __PrivacyToken_init(
        address platformTreasury_,
        uint256 platformFeeBps_,
        address initiator_,
        address[5] memory verifiers_,
        uint8 subtreeHeight_,
        uint8 rootTreeHeight_,
        bytes32 initialSubtreeEmptyRoot_,
        bytes32 initialFinalizedEmptyRoot_
    ) internal {
        if (state.initialized) revert AlreadyInitialized();

        // Platform configuration
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
    // ERC-8086 Interface Implementation (IZRC20)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the total supply in privacy mode
     * @dev Virtual to allow DualModeToken to combine with public supply
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _privacySupply;
    }

    /**
     * @notice Privacy-preserving transfer (IZRC20.transfer)
     * @dev Routes to appropriate internal transfer function based on proof type
     */
    function transfer(
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) external virtual override {
        _privacyTransfer(proofType, proof, encryptedNotes);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Internal: Privacy Mint (ERC-8086 Core Logic)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal privacy mint dispatcher
     * @dev Routes to regular or rollover mint based on proof type
     *      Virtual to allow derived contracts to add pre/post hooks
     */
    function _privacyMint(
        uint256 expectedAmount,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata encryptedNote
    ) internal virtual returns (bytes32 commitment) {
        if (proofType == 0) {
            commitment = _mintRegular(expectedAmount, proof, encryptedNote);
        } else if (proofType == 1) {
            commitment = _mintAndRollover(expectedAmount, proof, encryptedNote);
        } else {
            revert InvalidProofType(proofType);
        }
        _privacySupply += expectedAmount;
    }

    /**
     * @notice Regular mint (when subtree is not full)
     * @dev Verifies proof and appends commitment to active subtree
     */
    function _mintRegular(
        uint256 expectedAmount,
        bytes calldata _proof,
        bytes calldata _encryptedNote
    ) internal virtual returns (bytes32) {
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

    /**
     * @notice Rollover mint (when subtree is full, triggers finalization)
     * @dev Atomically updates both active and finalized roots
     */
    function _mintAndRollover(
        uint256 expectedAmount,
        bytes calldata _proof,
        bytes calldata _encryptedNote
    ) internal virtual returns (bytes32) {
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
    // Internal: Privacy Transfer (ERC-8086 Core Logic)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal privacy transfer dispatcher
     * @dev Routes to appropriate transfer function based on proof type
     *      Virtual to allow derived contracts to intercept
     */
    function _privacyTransfer(
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) internal virtual {
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

    /**
     * @notice Active tree transfer (spending from recent commitments)
     * @dev Supports mode conversion through isModeConversion flag (for ERC-8085)
     *      Virtual to allow derived contracts to add mode conversion logic
     */
    function _transferActive(
        bytes calldata _proof,
        bytes[] calldata _encryptedNotes,
        bool isModeConversion
    ) internal virtual returns (uint256 conversionAmount) {
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[13] memory pubSignals) =
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[13]));

        bytes32 newActiveRoot = bytes32(pubSignals[2]);
        uint256 numRealOutputs = pubSignals[3];
        conversionAmount = pubSignals[4];
        bytes32 oldActiveRoot = bytes32(pubSignals[5]);

        // Mode conversion validation (extensible via virtual function)
        if (isModeConversion) {
            _validateModeConversion(conversionAmount, pubSignals[10], pubSignals[11]);
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

    /**
     * @notice Finalized tree transfer (spending from archived commitments)
     * @dev Supports mode conversion through isModeConversion flag (for ERC-8085)
     *      Virtual to allow derived contracts to add mode conversion logic
     */
    function _transferFinalized(
        bytes calldata _proof,
        bytes[] calldata _encryptedNotes,
        bool isModeConversion
    ) internal virtual returns (uint256 conversionAmount) {
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[14] memory pubSignals) =
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[14]));

        bytes32 newActiveRoot = bytes32(pubSignals[2]);
        uint256 numRealOutputs = pubSignals[3];
        conversionAmount = pubSignals[4];
        bytes32 oldFinalizedRoot = bytes32(pubSignals[5]);
        bytes32 oldActiveRoot = bytes32(pubSignals[6]);

        // Mode conversion validation (extensible via virtual function)
        if (isModeConversion) {
            _validateModeConversion(conversionAmount, pubSignals[11], pubSignals[12]);
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

    /**
     * @notice Rollover transfer (triggers subtree finalization)
     * @dev Does not support mode conversion (incompatible with rollover mechanics)
     *      Virtual to allow derived contracts to add hooks
     */
    function _transferAndRollover(
        bytes calldata _proof,
        bytes[] calldata _encryptedNotes
    ) internal virtual {
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

    /**
     * @notice Process transaction data (spend nullifiers, append commitments, emit events)
     * @dev Virtual to allow derived contracts to add hooks
     */
    function _processTransaction(
        TransactionData memory _data,
        bytes[] calldata _encryptedNotes
    ) internal virtual {
        // Spend nullifiers (double-spend prevention)
        for (uint32 i = 0; i < _data.nullifiers.length; i++) {
            bytes32 n = _data.nullifiers[i];
            if (n != bytes32(0)) {
                if (nullifiers[n]) revert DoubleSpend(n);
                nullifiers[n] = true;
                emit NullifierSpent(n);
            }
        }

        // Append commitments to active subtree
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
    // Mode Conversion Extension Point (for ERC-8085 and other protocols)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Validate mode conversion parameters (virtual hook for derived contracts)
     * @dev Default implementation rejects mode conversion (pure ERC-8086 behavior)
     *      DualModeToken overrides this to validate BURN_ADDRESS
     * @param conversionAmount Amount being converted (must be > 0 for valid conversion)
     * @param recipientX X coordinate of recipient public key
     * @param recipientY Y coordinate of recipient public key
     */
    function _validateModeConversion(
        uint256 conversionAmount,
        uint256 recipientX,
        uint256 recipientY
    ) internal virtual {
        // Default: mode conversion not supported in pure privacy tokens
        revert ModeConversionNotSupported();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Fee Distribution (REFERENCE IMPLEMENTATION - NOT PART OF ERC-8086)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Distribute collected fees to platform and token creator
     * @dev Fees are split: platformFeeBps to platform, remainder to initiator
     *      Virtual to allow derived contracts to customize fee distribution
     *
     * ⚠️ IMPORTANT: This is NOT required by ERC-8086 standard!
     *
     * This is a REFERENCE IMPLEMENTATION business logic choice.
     * Other ERC-8086 implementations MAY:
     *   - Not charge any fees
     *   - Use different fee distribution models
     *   - Send fees to different addresses
     *   - Use different revenue mechanisms
     *
     * ERC-8086 standard does NOT mandate:
     *   - Platform fees
     *   - Fee distribution logic
     *   - Initiator/treasury addresses
     *
     * This function exists to demonstrate ONE possible revenue model.
     */
    function distributeFees() external virtual nonReentrant {
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
