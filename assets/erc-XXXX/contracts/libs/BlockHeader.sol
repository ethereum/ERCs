// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibBit} from "solady/src/utils/LibBit.sol";

/**
 * @notice Represents the essential data contained within a Bitcoin block header
 * @param prevBlockHash The hash of the previous block
 * @param merkleRoot The Merkle root of the transactions in the block
 * @param version The block version number
 * @param time The block's timestamp
 * @param nonce The nonce used for mining
 * @param bits The encoded difficulty target for the block
 */
struct BlockHeaderData {
    bytes32 prevBlockHash;
    bytes32 merkleRoot;
    uint32 version;
    uint32 time;
    uint32 nonce;
    bytes4 bits;
}

/**
 * @notice A utility library for handling Bitcoin block headers.
 * Provides functions for parsing, hashing, and converting block header data
 */
library BlockHeader {
    using LibBit for uint256;

    /**
     * @notice The standard length of a Bitcoin block header in bytes
     */
    uint256 public constant BLOCK_HEADER_DATA_LENGTH = 80;

    /**
     * @notice Emitted when the provided block header data has an invalid length.
     * This error ensures that only correctly sized block headers are processed
     */
    error InvalidBlockHeaderDataLength();

    /**
     * @notice Calculates the double SHA256 hash of a raw block header.
     * This is the standard method for deriving a Bitcoin block hash
     * @param blockHeaderRaw The raw bytes of the block header
     * @return The calculated block hash
     */
    function getBlockHeaderHash(bytes calldata blockHeaderRaw) internal pure returns (bytes32) {
        bytes32 rawBlockHash = sha256(abi.encode(sha256(blockHeaderRaw)));

        return _reverseHash(rawBlockHash);
    }

    /**
     * @notice Parses a raw byte array into a structured `BlockHeaderData` and calculates its hash.
     * It validates the length of the input and correctly decodes each field
     * @param blockHeaderRaw The raw bytes of the block header
     * @return headerData The parsed `BlockHeaderData` structure
     * @return blockHash The calculated hash of the block header
     */
    function parseBlockHeaderData(
        bytes calldata blockHeaderRaw
    ) internal pure returns (BlockHeaderData memory headerData, bytes32 blockHash) {
        require(
            blockHeaderRaw.length == BLOCK_HEADER_DATA_LENGTH,
            InvalidBlockHeaderDataLength()
        );

        headerData = BlockHeaderData({
            version: uint32(_reverseBytes(blockHeaderRaw[0:4])),
            prevBlockHash: _reverseHash(bytes32(blockHeaderRaw[4:36])),
            merkleRoot: _reverseHash(bytes32(blockHeaderRaw[36:68])),
            time: uint32(_reverseBytes(blockHeaderRaw[68:72])),
            bits: bytes4(uint32(_reverseBytes(blockHeaderRaw[72:76]))),
            nonce: uint32(_reverseBytes(blockHeaderRaw[76:80]))
        });
        blockHash = getBlockHeaderHash(blockHeaderRaw);
    }

    /**
     * @notice Converts a `BlockHeaderData` structure back into its raw byte representation.
     * This function reconstructs the original byte sequence of the block header
     * @param headerData The `BlockHeaderData` structure to convert
     * @return The raw byte representation of the block header
     */
    function toRawBytes(BlockHeaderData memory headerData) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                _reverseUint32(headerData.version),
                _reverseHash(headerData.prevBlockHash),
                _reverseHash(headerData.merkleRoot),
                _reverseUint32(headerData.time),
                _reverseUint32(uint32(headerData.bits)),
                _reverseUint32(headerData.nonce)
            );
    }

    function _reverseHash(bytes32 blockHash) private pure returns (bytes32) {
        return bytes32(uint256(blockHash).reverseBytes());
    }

    function _reverseBytes(bytes calldata bytesToConvert) private pure returns (uint256) {
        return uint256(bytes32(bytesToConvert)).reverseBytes();
    }

    function _reverseUint32(uint32 input_) private pure returns (uint32) {
        return
            ((input_ & 0x000000FF) << 24) |
            ((input_ & 0x0000FF00) << 8) |
            ((input_ & 0x00FF0000) >> 8) |
            ((input_ & 0xFF000000) >> 24);
    }
}
