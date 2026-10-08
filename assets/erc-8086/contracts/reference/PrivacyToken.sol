// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IVerifier.sol";
import "../interfaces/IZRC20.sol";


/**
 * @title PrivacyToken
 * @dev Refactored implementation with a standard, robust, and readable Merkle tree.
 */
contract PrivacyToken is IZRC20, ReentrancyGuard {

    // ===================================
    //        CUSTOM ERRORS (GAS OPTIMIZATION)
    // ===================================
    // --- General Errors ---
    error AlreadyInitialized();
    error InvalidProofType(uint8 receivedType);
    error InvalidProof();
    error InvalidPublicSignalLength(uint256 expected, uint256 received);

    // --- Minting Errors ---
    error IncorrectMintPrice(uint256 expected, uint256 sent);
    error MaxSupplyExceeded();
    error IncorrectMintAmount(uint256 expected, uint256 proven);
    error CommitmentAlreadyExists(bytes32 commitment);

    // --- Transfer Errors ---
    error DoubleSpend(bytes32 nullifier);
    
    // --- State & Root Mismatch Errors ---
    error OldActiveRootMismatch(bytes32 expected, bytes32 received);
    error OldFinalizedRootMismatch(bytes32 expected, bytes32 received);
    error IncorrectSubtreeIndex(uint256 expected, uint256 received);

    // --- Capacity & State Condition Errors ---
    error InvalidStateForRegularMint();
    error InvalidStateForRollover();
    error SubtreeCapacityExceeded(uint256 needed, uint256 available);
    
    // --- Fee Distribution Errors ---
    error NoFeesToDistribute();
    error FeeTransferFailed();

    struct ContractState {
        uint32 currentSubtreeIndex;
        uint32 nextLeafIndexInSubtree;
        uint8 subTreeHeight;
        uint8 rootTreeHeight;
        bool initialized; 
    }

    // ===================================
    //        STATE VARIABLES
    // ===================================
    // --- Configuration (Set once) ---
    string private _name;
    string private _symbol;
    uint256 public MAX_SUPPLY;
    uint256 public MINT_PRICE;
    uint256 public MINT_AMOUNT;
    address public initiator;
    address public platformTreasury;
    uint256 public platformFeeBps;

     // --- Verifiers ---
    IActiveTransferVerifier public activeTransferVerifier;
    IFinalizedTransferVerifier public finalizedTransferVerifier;
    ITransferRolloverVerifier public rolloverTransferVerifier;
    IMintVerifier public mintVerifier; 
    IMintRolloverVerifier public mintRolloverVerifier; 

   // --- Dynamic State ---
    mapping(bytes32 => bool) public nullifiers;
    mapping(bytes32 => bool) public commitmentHashes;
    uint256 public override totalSupply;
    
    // --- Packed State (For Gas Savings on SSTORE) ---
    ContractState public state;

    // --- Tree Roots ---
    bytes32 public EMPTY_SUBTREE_ROOT;
    bytes32 public override activeSubtreeRoot;
    bytes32 public finalizedRoot;
    uint256 public SUBTREE_CAPACITY;

    /**
     * @dev A struct to hold the relevant data extracted from the ZK proof's public signals.
     * This decouples the business logic from the specific layout of the circuit's output.
     */
    struct TransactionData {
        bytes32[2] nullifiers;
        bytes32[2] commitments;
        uint256[2] ephemeralPublicKey;
        uint256 viewTag;
    }

    constructor(){}

    /**
     * @notice Initializes the state of the cloned contract.
     * @dev This function replaces the original constructor and can only be called once.
     *      It's called by the factory immediately after cloning.
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 max_supply_,
        uint256 mintPrice_,
        uint256 mint_amount_,
        address initiator_,
        address platformTreasury_,
        uint256 platformFeeBps_,
        address[5] memory verifiers_,
        uint8 subtreeHeight_,
        uint8 rootTreeHeight_,
        bytes32 initialSubtreeEmptyRoot_,
        bytes32 initialFinalizedEmptyRoot_
    ) external {
        if (state.initialized) revert AlreadyInitialized();
        state.initialized = true;

        initiator = initiator_;
        _name = name_;
        _symbol = symbol_;
        MAX_SUPPLY = max_supply_;
        MINT_PRICE = mintPrice_;
        MINT_AMOUNT = mint_amount_;
        platformTreasury = platformTreasury_;
        platformFeeBps = platformFeeBps_;

        mintVerifier = IMintVerifier(verifiers_[0]);
        mintRolloverVerifier = IMintRolloverVerifier(verifiers_[1]);
        activeTransferVerifier = IActiveTransferVerifier(verifiers_[2]);
        finalizedTransferVerifier = IFinalizedTransferVerifier(verifiers_[3]);
        rolloverTransferVerifier = ITransferRolloverVerifier(verifiers_[4]);

        
        state.subTreeHeight = subtreeHeight_;
        SUBTREE_CAPACITY = 1 << subtreeHeight_;
        state.rootTreeHeight = rootTreeHeight_;
        EMPTY_SUBTREE_ROOT = initialSubtreeEmptyRoot_;

        activeSubtreeRoot = initialSubtreeEmptyRoot_;
        finalizedRoot = initialFinalizedEmptyRoot_;
        state.nextLeafIndexInSubtree = 0;
    }

    // --- Metadata Views ---
    function name() external view override returns (string memory) { return _name; }
    function symbol() external view override returns (string memory) { return _symbol; }
    function decimals() external pure override returns (uint8) { return 18; } // Standard


    // =============================================================
    // ===               PUBLIC MINTING INTERFACE                ===
    // =============================================================
    
    /**
     * @notice A single, unified, and permissionless entry point for minting new tokens.
     * @dev Anyone can call this function by paying the MINT_PRICE. It routes the request
     *      to the appropriate internal function based on the state of the active subtree.
     *      This function is protected against re-entrancy attacks.
     * @param proofType 0 for a regular mint, 1 for a mint that triggers a rollover.
     * @param proof The abi-encoded ZK-SNARK proof, which includes pA, pB, pC, and all public signals.
     * @param encryptedNote The encrypted note data for the new owner.
     */
    function mint(
        uint8 proofType,
        bytes calldata proof,
        bytes calldata encryptedNote
    ) external override payable nonReentrant{
        // --- 1. Initial Business Logic Checks ---
        if (msg.value != MINT_PRICE) revert IncorrectMintPrice(MINT_PRICE, msg.value);
        if (totalSupply + MINT_AMOUNT > MAX_SUPPLY) revert MaxSupplyExceeded();

        // --- 2. Dispatch to the correct internal logic ---
        if (proofType == 0) { // Regular Mint
            _mintRegular(proof, encryptedNote);
        } else if (proofType == 1) { // Rollover Mint
            _mintAndRollover(proof, encryptedNote);
        } else {
            revert InvalidProofType(proofType);
        }
    }

    // =============================================================
    // ===        INTERNAL SPECIALIZED MINTING LOGIC             ===
    // =============================================================

    /**
     * @dev Handles the logic for a regular mint that does NOT trigger a subtree rollover.
     *      It verifies the proof against the ProveMint circuit and updates the activeSubtreeRoot.
     */
    function _mintRegular(bytes calldata _proof, bytes calldata _encryptedNote) internal {
        // --- Pre-condition Check ---
        // A stricter check could be 
        if (state.nextLeafIndexInSubtree >= SUBTREE_CAPACITY) revert InvalidStateForRegularMint();

        // --- Decode Proof ---
        // The proof must be decoded according to the ProveMint circuit's public signals.
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[4] memory pubSignals) = 
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[4]));

        // --- Extract and Verify Public Signals ---
        bytes32 newActiveRoot = bytes32(pubSignals[0]);
        bytes32 oldActiveRoot_from_proof = bytes32(pubSignals[1]);
        bytes32 newCommitment = bytes32(pubSignals[2]);
        uint256 mintAmount_from_proof = pubSignals[3];

        if (commitmentHashes[newCommitment]) revert CommitmentAlreadyExists(newCommitment);
        commitmentHashes[newCommitment] = true;

        // --- On-Chain State Validation ---
        if (activeSubtreeRoot != oldActiveRoot_from_proof) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveRoot_from_proof);
        if (MINT_AMOUNT != mintAmount_from_proof) revert IncorrectMintAmount(MINT_AMOUNT, mintAmount_from_proof);
        if (!mintVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        // --- State Updates (Effects) ---
        totalSupply += MINT_AMOUNT;
        activeSubtreeRoot = newActiveRoot; // Atomically update the root to the proven new state.
        
        emit CommitmentAppended(state.currentSubtreeIndex, newCommitment, state.nextLeafIndexInSubtree, block.timestamp);

        state.nextLeafIndexInSubtree++;
        
        // --- Event Emission for Scanners ---
        emit Minted(msg.sender, newCommitment, _encryptedNote, state.currentSubtreeIndex, state.nextLeafIndexInSubtree-1, block.timestamp);
    }

    /**
     * @dev Handles the logic for a mint that triggers a subtree rollover.
     *      It verifies the proof against the ProveMintAndRollover circuit and updates BOTH roots.
     */
    function _mintAndRollover(bytes calldata _proof, bytes calldata _encryptedNote) internal {
        // --- Pre-condition Check ---
        if (state.nextLeafIndexInSubtree != SUBTREE_CAPACITY) revert InvalidStateForRollover();
        
        // --- Decode Proof ---
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[7] memory pubSignals) = 
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[7]));
            
        // --- Extract and Verify Public Signals ---
        bytes32 newActiveRoot = bytes32(pubSignals[0]);
        bytes32 newFinalizedRoot = bytes32(pubSignals[1]);
        bytes32 oldActiveRoot_from_proof = bytes32(pubSignals[2]);
        bytes32 oldFinalizedRoot_from_proof = bytes32(pubSignals[3]);
        bytes32 newCommitment = bytes32(pubSignals[4]);
        uint256 mintAmount_from_proof = pubSignals[5];
        uint256 subtreeIndex_from_proof = pubSignals[6];

        if (commitmentHashes[newCommitment]) revert CommitmentAlreadyExists(newCommitment);
        commitmentHashes[newCommitment] = true;

        // --- On-Chain State Validation ---
        if (activeSubtreeRoot != oldActiveRoot_from_proof) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveRoot_from_proof);
        if (finalizedRoot != oldFinalizedRoot_from_proof) revert OldFinalizedRootMismatch(finalizedRoot, oldFinalizedRoot_from_proof);
        if (MINT_AMOUNT != mintAmount_from_proof) revert IncorrectMintAmount(MINT_AMOUNT, mintAmount_from_proof);

        if (state.currentSubtreeIndex != subtreeIndex_from_proof) revert IncorrectSubtreeIndex(state.currentSubtreeIndex, subtreeIndex_from_proof);

        // --- ZK Proof Verification ---
        if (!mintRolloverVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        activeSubtreeRoot = newActiveRoot;
        finalizedRoot = newFinalizedRoot;
        state.currentSubtreeIndex++;
        state.nextLeafIndexInSubtree = 0;
        
        totalSupply += MINT_AMOUNT;
        
        // This commitment is the FIRST leaf of the NEW subtree.
        emit CommitmentAppended(state.currentSubtreeIndex, newCommitment, state.nextLeafIndexInSubtree, block.timestamp);        
        state.nextLeafIndexInSubtree++;

        // --- Event Emission for Scanners ---
        emit Minted(msg.sender, newCommitment, _encryptedNote, state.currentSubtreeIndex, state.nextLeafIndexInSubtree-1, block.timestamp);
    }

    // =============================================================
    // ===           UNIFIED TRANSFER INTERFACE                  ===
    // =============================================================
    function transfer(
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) external override {
        if (proofType == 0) { // Active
            _transferActive(proof, encryptedNotes);
        } else if (proofType == 1) { // Finalized
            _transferFinalized(proof, encryptedNotes);
        } else if (proofType == 2) { // Rollover
            _transferAndRollover(proof, encryptedNotes);
        } else {
            revert InvalidProofType(proofType);        
        }
    }

    // =============================================================
    // ===        INTERNAL SPECIALIZED TRANSFER LOGIC            ===
    // =============================================================

    function _transferActive(bytes calldata _proof, bytes[] calldata _encryptedNotes) internal {

        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[12] memory pubSignals) = 
        abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[12]));
        
        bytes32 newActiveSubTreeRoot = bytes32(pubSignals[2]);
        uint256 numRealOutputs = pubSignals[3];
        bytes32 oldActiveSubTreeRoot = bytes32(pubSignals[4]);

        uint256 availableCapacity = uint256(SUBTREE_CAPACITY - state.nextLeafIndexInSubtree);
        if (numRealOutputs > availableCapacity) revert SubtreeCapacityExceeded(numRealOutputs, availableCapacity);
        if (activeSubtreeRoot != oldActiveSubTreeRoot) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveSubTreeRoot);
        if (!activeTransferVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        activeSubtreeRoot = newActiveSubTreeRoot;

        TransactionData memory data;
        data.ephemeralPublicKey = [pubSignals[0], pubSignals[1]];
        data.nullifiers         = [bytes32(pubSignals[5]), bytes32(pubSignals[6])]; 
        data.commitments        = [bytes32(pubSignals[7]), bytes32(pubSignals[8])]; 
        data.viewTag            = pubSignals[11]; 

        _processTransaction(data, _encryptedNotes);
    }


    function _transferFinalized(bytes calldata _proof, bytes[] calldata _encryptedNotes) internal {
        
        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[13] memory pubSignals) = 
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[13]));

        bytes32 newActiveRoot = bytes32(pubSignals[2]);
        uint256 numRealOutputs = pubSignals[3];
        bytes32 oldFinalizedRoot = bytes32(pubSignals[4]);
        bytes32 oldActiveRoot = bytes32(pubSignals[5]);
        
        uint256 availableCapacity = uint32(SUBTREE_CAPACITY - state.nextLeafIndexInSubtree);
        if (numRealOutputs > availableCapacity) revert SubtreeCapacityExceeded(numRealOutputs, availableCapacity);
        if (activeSubtreeRoot != oldActiveRoot) revert OldActiveRootMismatch(activeSubtreeRoot, oldActiveRoot);
        if (finalizedRoot != oldFinalizedRoot) revert OldFinalizedRootMismatch(finalizedRoot, oldFinalizedRoot);
        if (!finalizedTransferVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        activeSubtreeRoot = newActiveRoot;

        TransactionData memory data;
        data.ephemeralPublicKey = [pubSignals[0], pubSignals[1]];
        data.nullifiers         = [bytes32(pubSignals[6]), bytes32(pubSignals[7])]; 
        data.commitments        = [bytes32(pubSignals[8]), bytes32(pubSignals[9])];
        data.viewTag            = pubSignals[12]; 

        _processTransaction(data, _encryptedNotes);
    }

    function _transferAndRollover(bytes calldata _proof, bytes[] calldata _encryptedNotes) internal {

        (uint[2] memory a, uint[2][2] memory b, uint[2] memory c, uint[12] memory pubSignals) = 
            abi.decode(_proof, (uint[2], uint[2][2], uint[2], uint[12]));
        
        bytes32 newActive = bytes32(pubSignals[2]);
        bytes32 newFinalized = bytes32(pubSignals[3]);
        bytes32 oldActive = bytes32(pubSignals[4]);
        bytes32 oldFinalized = bytes32(pubSignals[5]);
        uint256 subtreeIndex_from_proof = pubSignals[11];

        // A rollover transfer must be happening when the subtree is nearly full.
        if (state.nextLeafIndexInSubtree != SUBTREE_CAPACITY) revert InvalidStateForRollover();
        if (activeSubtreeRoot != oldActive) revert OldActiveRootMismatch(activeSubtreeRoot, oldActive);
        if (finalizedRoot != oldFinalized) revert OldFinalizedRootMismatch(finalizedRoot, oldFinalized);

        if (state.currentSubtreeIndex != subtreeIndex_from_proof) revert IncorrectSubtreeIndex(state.currentSubtreeIndex, subtreeIndex_from_proof);
        if (!rolloverTransferVerifier.verifyProof(a, b, c, pubSignals)) revert InvalidProof();

        // Atomically update both roots and all indices
        activeSubtreeRoot = newActive;
        finalizedRoot = newFinalized;

        state.currentSubtreeIndex++;
        state.nextLeafIndexInSubtree = 0;

        TransactionData memory data;
        data.ephemeralPublicKey = [pubSignals[0], pubSignals[1]];
        data.nullifiers         = [bytes32(pubSignals[6]), bytes32(0)]; 
        data.commitments        = [bytes32(pubSignals[7]), bytes32(0)]; 
        data.viewTag            = pubSignals[10]; 

        _processTransaction(data, _encryptedNotes);
    }

    /**
     * @dev Internal function to distribute fees to the platform and token creator.
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

    /**
     * @dev Processes a verified transaction by spending nullifiers and appending new commitments.
     * This is the single, refactored function for all transfer types.
     * @param _data The structured transaction data, extracted from public signals.
     * @param _encryptedNotes The encrypted output notes.
     */
    function _processTransaction(
        TransactionData memory _data,
        bytes[] calldata _encryptedNotes
    ) internal {
        // Spend Nullifiers
        for (uint32 i = 0; i < _data.nullifiers.length; i++) {
            bytes32 n = _data.nullifiers[i];
            if (n != bytes32(0)) {
                if (nullifiers[n]) revert DoubleSpend(n);
                nullifiers[n] = true;
                emit NullifierSpent(n);
            }
        }
        
        // Append Commitments
        for (uint i = 0; i < _data.commitments.length; i++) {
            bytes32 c = _data.commitments[i];
            if (c != bytes32(0)) {
                // Note: The logic for subtree and leaf index updates might need to be
                // passed in or handled just before this call if it differs.

                emit CommitmentAppended(state.currentSubtreeIndex, c, state.nextLeafIndexInSubtree, block.timestamp);
                state.nextLeafIndexInSubtree++;
            }
        }
        emit Transaction(_data.commitments, _encryptedNotes, _data.ephemeralPublicKey, _data.viewTag);
    }

}