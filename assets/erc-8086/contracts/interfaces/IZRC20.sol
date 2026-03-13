// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/**
 * @title IZRC20
 * @notice Minimal interface for native privacy assets on Ethereum (ERC-8086)
 * @dev This standard defines the foundation for privacy-preserving tokens
 *      that can be used directly or as building blocks for wrapper protocols
 *      and dual-mode protocols implementations.
 */
interface IZRC20 {

    // ═══════════════════════════════════════════════════════════════════════
    // Events
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a commitment is added to the Merkle tree
     * @param subtreeIndex Subtree index (0 for single-tree implementations)
     * @param commitment The cryptographic commitment hash
     * @param leafIndex Position within subtree (or global index)
     * @param timestamp Block timestamp of insertion
     * @dev For single-tree: subtreeIndex SHOULD be 0, leafIndex is global position
     * @dev For dual-tree: subtreeIndex identifies which subtree, leafIndex is position within it
     */
    event CommitmentAppended(
        uint32 indexed subtreeIndex,
        bytes32 commitment,
        uint32 indexed leafIndex,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a nullifier is spent (note consumed)
     * @param nullifier The unique nullifier hash
     * @dev Once spent, nullifier can never be reused (prevents double-spending)
     */
    event NullifierSpent(bytes32 indexed nullifier);

    /**
     * @notice Emitted when tokens are minted directly into privacy mode
     * @param minter Address that initiated the mint
     * @param commitment The commitment created for minted value
     * @param encryptedNote Encrypted note for recipient
     * @param subtreeIndex Subtree where commitment was added
     * @param leafIndex Position within subtree
     * @param timestamp Block timestamp of mint
     */
    event Minted(
        address indexed minter,
        bytes32 commitment,
        bytes encryptedNote,
        uint32 subtreeIndex,
        uint32 leafIndex,
        uint256 timestamp
    );

    /**
     * @notice Emitted on privacy transfers with public scanning data
     * @param newCommitments Output commitments created (typically 1-2)
     * @param encryptedNotes Encrypted notes for recipients
     * @param ephemeralPublicKey Ephemeral public key for ECDH key exchange (if used)
     * @param viewTag Scanning optimization byte (0 if not used)
     * @dev Provides data for recipients to detect and decrypt their notes
     */
    event Transaction(
        bytes32[2] newCommitments,
        bytes[] encryptedNotes,
        uint256[2] ephemeralPublicKey,
        uint256 viewTag
    );

    // ═══════════════════════════════════════════════════════════════════════
    // Metadata (ERC-20 compatible, OPTIONAL but RECOMMENDED)
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the token name
     * @return Token name string
     * @dev OPTIONAL but RECOMMENDED for UX and interoperability
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the token symbol
     * @return Token symbol string
     * @dev OPTIONAL but RECOMMENDED for UX and interoperability
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the number of decimals
     * @return Number of decimals (typically 18)
     * @dev OPTIONAL but RECOMMENDED for amount formatting
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the total supply across all privacy notes
     * @return Total token supply
     * @dev OPTIONAL - May be required for certain economic models (e.g., fixed cap)
     *      Individual balances remain private; only aggregate supply is visible
     */
    function totalSupply() external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════
    // Core Functions
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Mints new privacy tokens
     * @param proofType Type of proof to support multiple proof strategies.
     * @param proof Zero-knowledge proof of valid transfer
     * @param encryptedNote Encrypted note for minter's wallet
     * @dev Proof must demonstrate valid commitment creation and payment
     *      Implementations define minting rules
     */
    function mint(
        uint8 proofType,
        bytes calldata proof,
        bytes calldata encryptedNote
    ) external payable;

    /**
     * @notice Executes a privacy-preserving transfer
     * @param proofType Implementation-specific proof type identifier
     * @param proof Zero-knowledge proof of valid transfer
     * @param encryptedNotes Encrypted output notes (for recipient and/or change)
     * @dev Proof must demonstrate:
     *      1. Input commitments exist in Merkle tree
     *      2. Prover knows private keys
     *      3. Nullifiers not spent
     *      4. Value conservation: sum(inputs) = sum(outputs)
     */
    function transfer(
        uint8 proofType,
        bytes calldata proof,
        bytes[] calldata encryptedNotes
    ) external;

    // ═══════════════════════════════════════════════════════════════════════
    // Query Functions
    // ═══════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if a nullifier has been spent
     * @param nullifier The nullifier to check
     * @return True if nullifier spent, false otherwise
     * @dev Implementations using `mapping(bytes32 => bool) public nullifiers`
     *      will auto-generate this function.
     */
    function nullifiers(bytes32 nullifier) external view returns (bool);

    /**
     * @notice Returns the current active subtree Merkle root
     * @return The root hash of the active subtree
     * @dev The active subtree stores recent commitments for faster proof computation.
     *      For dual-tree implementations, this is the root of the current working subtree.
     */
    function activeSubtreeRoot() external view returns (bytes32);
}
