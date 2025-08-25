// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BlockHeader} from "@solarity/solidity-lib/libs/bitcoin/BlockHeader.sol";

/**
 * @notice Interface for an SPV (Simplified Payment Verification) gateway contract.
 * This contract allows for the verification of Bitcoin block headers
 * and tracking of the main Bitcoin blockchain
 */
interface ISPVGateway {
    /**
     * @notice Emitted when an initial block height is invalid.
     * This error indicates that the provided block height is not valid for initialization
     * @param blockHeight The invalid block height
     */
    error InvalidInitialBlockHeight(uint64 blockHeight);
    /**
     * @notice Emitted when a previous block does not exist.
     * This error occurs when a block header references a previous block that is not found
     * @param prevBlockHash The hash of the non-existent previous block
     */
    error PrevBlockDoesNotExist(bytes32 prevBlockHash);
    /**
     * @notice Emitted when a block already exists.
     * This error indicates an attempt to add a block that is already recorded
     * @param blockHash The hash of the block that already exists
     */
    error BlockAlreadyExists(bytes32 blockHash);

    /**
     * @notice Emitted when an empty array of block headers is provided
     */
    error EmptyBlockHeaderArray();
    /**
     * @notice Emitted when block headers are not in the correct order.
     * This error indicates that the sequence of block headers is incorrect
     */
    error InvalidBlockHeadersOrder();

    /**
     * @notice Emitted when a block's target is invalid.
     * This error occurs when the block's target does not match the network's target rules
     * @param blockTarget The invalid block target
     * @param networkTarget The expected network target
     */
    error InvalidTarget(bytes32 blockTarget, bytes32 networkTarget);
    /**
     * @notice Emitted when a block hash is invalid.
     * This error indicates that the calculated block hash does not match the expected target
     * @param actualBlockHash The actual calculated block hash
     * @param blockTarget The target against which the hash was compared
     */
    error InvalidBlockHash(bytes32 actualBlockHash, bytes32 blockTarget);
    /**
     * @notice Emitted when a block's timestamp is invalid.
     * This error occurs when the block time is less than the median time of previous blocks
     * @param blockTime The block's timestamp
     * @param medianTime The median time of previous blocks
     */
    error InvalidBlockTime(uint32 blockTime, uint32 medianTime);

    /**
     * @notice Emitted when the mainchain head is updated
     * @param newMainchainHeight The height of the new mainchain head
     * @param newMainchainHead The hash of the new mainchain head
     */
    event MainchainHeadUpdated(
        uint64 indexed newMainchainHeight,
        bytes32 indexed newMainchainHead
    );
    /**
     * @notice Emitted when a block header is successfully added
     * @param blockHeight The height of the added block
     * @param blockHash The hash of the added block
     */
    event BlockHeaderAdded(uint64 indexed blockHeight, bytes32 indexed blockHash);

    /**
     * @notice Represents the data of a block
     * @param prevBlockHash The hash of the previous block
     * @param merkleRoot The Merkle root of the transactions in the block
     * @param version The block version number
     * @param time The block's timestamp
     * @param nonce The nonce used for mining
     * @param bits The encoded difficulty target for the block
     * @param blockHeight The block height
     */
    struct BlockData {
        bytes32 prevBlockHash;
        bytes32 merkleRoot;
        uint32 version;
        uint32 time;
        uint32 nonce;
        bytes4 bits;
        uint64 blockHeight;
    }

    /**
     * @notice Provides information about a block
     * @param mainBlockData The main block data
     * @param isInMainchain The block mainchain status
     * @param cumulativeWork The block cumulative work
     */
    struct BlockInfo {
        BlockData mainBlockData;
        bool isInMainchain;
        uint256 cumulativeWork;
    }

    /**
     * @notice Adds a batch of the block headers to the contract.
     * Each block header is validated and added sequentially
     * @param blockHeaderRawArray An array of raw block header bytes
     */
    function addBlockHeaderBatch(bytes[] calldata blockHeaderRawArray) external;

    /**
     * @notice Adds a single raw block header to the contract.
     * The block header is validated before being added
     * @param blockHeaderRaw The raw block header bytes
     */
    function addBlockHeader(bytes calldata blockHeaderRaw) external;

    /**
     * @notice Checks that given txId is included in the specified block with a minimum number of confirmations.
     * @param merkleProof The array of hashes used to build the Merkle root
     * @param blockHash The hash of the block in which to verify the transaction
     * @param txId The transaction id to verify
     * @param txIndex The index of the transaction in the block's Merkle tree
     * @param minConfirmationsCount The minimum number of confirmations required for the block
     * @return True if the txId is present in the block's Merkle tree and the block has at least minConfirmationsCount confirmations, false otherwise
     */
    function checkTxInclusion(
        bytes32[] calldata merkleProof,
        bytes32 blockHash,
        bytes32 txId,
        uint256 txIndex,
        uint256 minConfirmationsCount
    ) external view returns (bool);

    /**
     * @notice Returns the hash of the current mainchain head.
     * This represents the highest block on the most accumulated work chain
     * @return The hash of the mainchain head
     */
    function getMainchainHead() external view returns (bytes32);

    /**
     * @notice Returns the height of the current mainchain head.
     * This represents the highest block number on the most accumulated work chain
     * @return The height of the mainchain head
     */
    function getMainchainHeight() external view returns (uint64);

    /**
     * @notice Returns detailed information about a block.
     * This includes its data, mainchain status, and cumulative work
     * @param blockHash The hash of the block
     * @return blockInfo The detailed information of the block
     */
    function getBlockInfo(bytes32 blockHash) external view returns (BlockInfo memory blockInfo);

    /**
     * @notice Returns the block header data for a given block hash.
     * @param blockHash The hash of the block
     * @return The block header data
     */
    function getBlockHeader(
        bytes32 blockHash
    ) external view returns (BlockHeader.HeaderData memory);

    /**
     * @notice Returns the current status of a given block
     * @param blockHash The hash of the block to check
     * @return isInMainchain True if the block is in the mainchain, false otherwise
     * @return confirmationsCount The number of blocks that have been mined on top of the given block
     */
    function getBlockStatus(bytes32 blockHash) external view returns (bool, uint64);

    /**
     * @notice Returns the Merkle root of a given block hash.
     * This function retrieves the Merkle root from the stored block header data
     * @param blockHash The hash of the block
     * @return The Merkle root of the block
     */
    function getBlockMerkleRoot(bytes32 blockHash) external view returns (bytes32);

    /**
     * @notice Returns the block height for a given block hash
     * This function retrieves the height at which the block exists in the chain
     * @param blockHash The hash of the block
     * @return The height of the block
     */
    function getBlockHeight(bytes32 blockHash) external view returns (uint64);

    /**
     * @notice Returns the block hash for a given block height.
     * This function retrieves the hash of the block from the mainchain at the specified height
     * @param blockHeight The height of the block
     * @return The hash of the block
     */
    function getBlockHash(uint64 blockHeight) external view returns (bytes32);

    /**
     * @notice Returns the target of a given block hash.
     * This function retrieves the difficulty target from the block header
     * @param blockHash The hash of the block
     * @return The target of the block
     */
    function getBlockTarget(bytes32 blockHash) external view returns (bytes32);

    /**
     * @notice Returns the cumulative work of the last epoch.
     * This represents the total difficulty accumulated up to the last epoch boundary
     * @return The cumulative work of the last epoch
     */
    function getLastEpochCumulativeWork() external view returns (uint256);

    /**
     * @notice Checks if a block exists in the contract's storage.
     * This function verifies the presence of a block by its hash
     * @param blockHash The hash of the block to check
     * @return True if the block exists, false otherwise
     */
    function blockExists(bytes32 blockHash) external view returns (bool);

    /**
     * @notice Checks if a given block is part of the mainchain.
     * This function determines if the block is on the most accumulated work chain
     * @param blockHash The hash of the block to check
     * @return True if the block is in the mainchain, false otherwise
     */
    function isInMainchain(bytes32 blockHash) external view returns (bool);
}
