// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ITextResource.sol";
import {SSTORE2} from "solady/utils/SSTORE2.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title TextResource.sol
 * @notice Immutable on-chain storage for a text resource, such as the ERC-8100 xml templates
 *      returned by IXMLRepresentableState.stateXmlTemplate().
 *      In XML the individual text resources can be references (and thus composed)
 *      via xinclude using web3 url.
 *      Implementation of this interface have to return a web3 url to the corresponding
 *      text resource, once it is finalized.
 *
 * @dev PUBLISHING MODES
 *      1. One-shot  – pass the full content to the constructor. It is chunked,
 *                     hash-verified and finalized atomically in a single tx.
 *                     Limited by the EIP-3860 init-code size limit (~49 KB),
 *                     so suitable for small to medium resources.
 *      2. Staged    – deploy with empty content and the intended full-content
 *                     hash, then append chunks across several transactions via
 *                     appendChunkAt and finalize() at the end. Use this for
 *                     large resources.
 *
 * @dev GAS / MEMORY LIMITATIONS
 *      Staged publishing splits writes across transactions, but this
 *      implementation still reconstructs the full content in memory when
 *      finalize(), content(), or text() is called. Therefore, staged publishing
 *      helps with upload transaction size, but it does not make arbitrarily
 *      large resources practical.
 *
 * @dev CONTENT HASH SCHEME (see ITextResource):
 *      contentHash == keccak256(content())
 *      The hash is verified ON-CHAIN at finalization against the caller-
 *      supplied expected hash, so contentHash() is always reproducible
 *      off-chain from the raw bytes (frontend integrity check).
 *
 * @dev EVM TARGET: does not rely on the MCOPY opcode. For pre-Cancun
 *      compatibility, compile explicitly for the Paris EVM target.
 *
 * @author Raphael Prandtl
 * @author Christian Fries
 **/
contract TextResource is ITextResource {

    using Strings for address;
    using Strings for uint256;

    /*
     * Constants
     */

    /**
     * @notice Maximum total content size in bytes.
     **/
    uint256 public constant MAX_CONTENT_SIZE = 200_000;

    /**
     * @notice Maximum size of a single chunk in bytes.
     * @dev Bounded by the SSTORE2 / contract-code size limit (24_576 bytes).
     **/
    uint256 public constant MAX_CHUNK_SIZE = 20_000;

    /**
     * @notice Maximum number of storage pointers used by one resource.
     * @dev Bounds the per-pointer work performed during finalization and reads,
     *      while leaving publishers flexibility to use chunks below MAX_CHUNK_SIZE.
     **/
    uint256 public constant MAX_CHUNK_COUNT = 32;

    /*
     * Storage
     */

    /**
     * @dev SSTORE2 storage pointers, in content order.
     **/
    address[] internal _pointers;

    address public immutable owner;
    bytes32 public immutable resourceType;
    /** Full-content hash committed at deployment. */
    bytes32 public immutable committedContentHash;
    string public mediaType;

    bytes32 public contentHash;
    uint256 public contentLength;

    /*
     * Custom errors
     */

    /**
     * @notice Thrown when an empty chunk is appended.
     **/
    error EmptyChunk(uint256 index);

    /**
     * @notice Thrown when the content exceeds MAX_CONTENT_SIZE.
     **/
    error ContentTooLarge(uint256 length, uint256 maxLength);

    /**
     * @notice Thrown when a chunk exceeds MAX_CHUNK_SIZE.
     **/
    error ChunkTooLarge(uint256 index, uint256 length, uint256 maxLength);

    /**
     * @notice Thrown when appending would make full-content reconstruction too expensive.
     **/
    error TooManyChunks(uint256 count, uint256 maxCount);

    /**
     * @notice Thrown when a compare-and-append call observes a different current length.
     **/
    error UnexpectedContentLength(uint256 expectedLength, uint256 actualLength);

    /**
     * @notice Thrown when finalization does not use the hash committed at deployment.
     **/
    error ContentHashCommitmentMismatch(bytes32 committedHash, bytes32 suppliedHash);

    /*
     * Events
     */

    /**
     * @notice Content chunk appended.
     **/
    event ChunkAppended(address indexed sender, address indexed pointer, uint256 indexed chunkIndex, uint256 chunkLength);

    /*
     * Constructor / modifiers
     */

    /**
     * @notice Deploys a text resource, optionally publishing content one-shot.
     * @param owner_               Address authorized to publish / finalize.
     * @param resourceType_        Application-defined resource type.
     * @param mediaType_           IANA media type, e.g. "application/xml".
     * @param content_             Full content for one-shot mode, or empty
     *                             bytes to publish later via the staged API.
     * @param expectedContentHash_ Required in both modes. For staged publishing
     *                             it commits the resource address to the intended
     *                             full content before any chunks are written.
     **/
    constructor(address owner_, bytes32 resourceType_, string memory mediaType_, bytes memory content_, bytes32 expectedContentHash_) {
        if (owner_ == address(0)) revert ZeroOwner();
        if (resourceType_ == bytes32(0)) revert ZeroResourceType();
        if (bytes(mediaType_).length == 0) revert EmptyMediaType();
        if (expectedContentHash_ == bytes32(0)) revert ZeroContentHash();

        owner = owner_;
        resourceType = resourceType_;
        committedContentHash = expectedContentHash_;
        mediaType = mediaType_;

        // One-shot mode: publish and finalize atomically.
        if (content_.length != 0) {
            if (content_.length > MAX_CONTENT_SIZE) {
                revert ContentTooLarge(content_.length, MAX_CONTENT_SIZE);
            }
            bytes32 actualContentHash = keccak256(content_);
            if (actualContentHash != expectedContentHash_) {
                revert ContentHashMismatch(expectedContentHash_, actualContentHash);
            }
            _appendContentInChunks(content_);
            // Chunks come directly from the already verified constructor input.
            // Avoid reconstructing the entire resource a second time in this transaction.
            _completeFinalization(actualContentHash);
        }
        // Otherwise: staged mode – content is appended later by the owner.
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;
    }

    modifier onlyBeforeFinalized() {
        if (contentHash != bytes32(0)) revert AlreadyFinalized();
        _;
    }

    /*
     * Resource publishing
     */

    /**
     * @notice Appends a single pre-chunked data segment (staged mode).
     * @dev Caller is responsible for splitting data into MAX_CHUNK_SIZE pieces.
     **/
    function appendChunk(bytes calldata chunk) external onlyOwner onlyBeforeFinalized {
        _appendChunk(chunk);
    }

    /**
     * @notice Appends a chunk only if the resource still has the expected length.
     * @dev This compare-and-append operation prevents two concurrent resumptions
     *      from both appending the same suffix after inspecting the same prefix.
     */
    function appendChunkAt(uint256 expectedContentLength, bytes calldata chunk)
        external
        onlyOwner
        onlyBeforeFinalized
    {
        uint256 actualLength = contentLength;
        if (actualLength != expectedContentLength) {
            revert UnexpectedContentLength(expectedContentLength, actualLength);
        }
        _appendChunk(chunk);
    }

    /**
     * @notice Finalizes the resource and locks it as immutable (staged mode).
     * @param expectedContentHash Hash the caller expects; verified on-chain
     *        as keccak256 of the full stored content.
     **/
    function finalize(bytes32 expectedContentHash) external onlyOwner onlyBeforeFinalized {
        _finalize(expectedContentHash);
    }

    /*
     * ERC-165
     */

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(ITextResource).interfaceId;
    }

    /*
     * Metadata / state
     */

    function isFinalized() external view virtual override returns (bool) {
        return contentHash != bytes32(0);
    }

    /**
     * @notice Returns the number of stored chunks.
     **/
    function chunkCount() external view returns (uint256) {
        return _pointers.length;
    }

    /**
     * @notice Returns the hash of all content stored so far, including before finalization.
     * @dev This is deliberately not part of ITextResource: consumers should continue to use the
     *      immutable contentHash after finalization. Publishers use this extension to prove that
     *      an interrupted staged upload is a prefix of the file they are about to resume.
     **/
    function currentContentHash() external view returns (bytes32) {
        return keccak256(_readContent());
    }

    /*
     * Content read
     */

    function content() external view virtual override returns (bytes memory) {
        _requireFinalized();
        return _readContent();
    }

    function text() external view virtual override returns (string memory) {
        _requireFinalized();
        return string(_readContent());
    }

    /// @inheritdoc ITextResource
    function web3Url() external view virtual override returns (string memory) {
        _requireFinalized();
        return string.concat(
            "web3://",
            address(this).toHexString(),
            ":",
            block.chainid.toString(),
            "/content"
        );
    }

    /*
     * Internal write helpers
     */

    /**
     * @notice Appends a single pre-chunked data segment.
     **/
    function _appendChunk(bytes memory chunk_) private {
        uint256 index = _pointers.length;
        uint256 chunkLength = chunk_.length;

        if (chunkLength == 0) {
            revert EmptyChunk(index);
        }
        if (chunkLength > MAX_CHUNK_SIZE) {
            revert ChunkTooLarge(index, chunkLength, MAX_CHUNK_SIZE);
        }
        if (index >= MAX_CHUNK_COUNT) {
            revert TooManyChunks(index + 1, MAX_CHUNK_COUNT);
        }
        uint256 newContentLength = contentLength + chunkLength;
        if (newContentLength > MAX_CONTENT_SIZE) {
            revert ContentTooLarge(newContentLength, MAX_CONTENT_SIZE);
        }
        address pointer = SSTORE2.write(chunk_);
        _pointers.push(pointer);
        contentLength = newContentLength;

        emit ChunkAppended(msg.sender, pointer, index, chunkLength);
    }

    /**
     * @notice Splits full content into MAX_CHUNK_SIZE segments and appends them.
     **/
    function _appendContentInChunks(bytes memory content_) private {
        uint256 totalLength = content_.length;
        if (totalLength == 0) {
            revert EmptyContent();
        }

        uint256 offset;
        while (offset < totalLength) {
            uint256 remaining = totalLength - offset;
            uint256 chunkLength = remaining > MAX_CHUNK_SIZE ? MAX_CHUNK_SIZE : remaining;
            bytes memory chunk = new bytes(chunkLength);

            /*
             * Copy 32 bytes per iteration instead of using MCOPY, preserving
             * compatibility with pre-Cancun EVM targets.
             */
            assembly ("memory-safe") {
                let source := add(add(content_, 0x20), offset)
                let target := add(chunk, 0x20)
                let end := add(target, chunkLength)

                for {} lt(target, end) {
                    source := add(source, 0x20)
                    target := add(target, 0x20)
                } {
                    mstore(target, mload(source))
                }
            }

            _appendChunk(chunk);
            unchecked { offset += chunkLength; }
        }
    }

    /**
     * @dev Recomputes keccak256 over the full stored content and verifies it
     *      against the caller-supplied expected hash.
     **/
    function _finalize(bytes32 expectedContentHash) private {
        if (_pointers.length == 0 || contentLength == 0) revert EmptyContent();
        if (expectedContentHash == bytes32(0)) revert ZeroContentHash();

        bytes32 commitment = committedContentHash;
        if (commitment != expectedContentHash) {
            revert ContentHashCommitmentMismatch(commitment, expectedContentHash);
        }

        bytes32 computedHash = keccak256(_readContent());
        if (computedHash != expectedContentHash) {
            revert ContentHashMismatch(expectedContentHash, computedHash);
        }

        _completeFinalization(computedHash);
    }

    function _completeFinalization(bytes32 computedHash) private {
        contentHash = computedHash;
        emit ResourceFinalized(resourceType, contentLength, computedHash);
    }

    /*
     * Internal read helpers
     */

    /**
     * @notice Reconstructs the full content from all chunks.
     **/
    function _readContent() private view returns (bytes memory result) {
        result = new bytes(contentLength);

        uint256 offset;
        uint256 pointersLength = _pointers.length;

        for (uint256 i; i < pointersLength; ) {
            address pointer = _pointers[i];
            uint256 chunkLength;

            /*
             * SSTORE2 stores the payload in the pointer contract's runtime bytecode as
             * [STOP byte | data]. Copying from code offset 1 directly into `result`
             * avoids allocating and copying through a temporary bytes object.
             *
             * This also relies on the Solidity memory layout of bytes:
             * [32-byte length | data | padding].
             */
            assembly ("memory-safe") {
                // SSTORE2 prefixes the stored data with one STOP byte.
                chunkLength := sub(extcodesize(pointer), 1)
                extcodecopy(pointer, add(add(result, 0x20), offset), 1, chunkLength)
            }

            unchecked {
                offset += chunkLength;
                ++i;
            }
        }
    }

    /*
     * Internal validation helpers
     */

    function _requireFinalized() private view {
        if (contentHash == bytes32(0)) revert NotFinalized();
    }
}
