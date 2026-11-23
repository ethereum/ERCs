// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title ITextResource
 * @notice On-chain storage for immutable text resources, such as the ERC-8100 xml templates
 *      returned by IXMLRepresentableState.stateXmlTemplate().
 *      In XML the individual text resources can be references (and thus composed)
 *      via xinclude using web3 url.
 *      Implementation of this interface have to return a web3 url to the corresponding
 *      text resource, once it is finalized.
 *
 * @dev LIFECYCLE
 *      A resource is published in two phases:
 *        1. Content is written (in one or more chunks).
 *        2. The resource is finalized and becomes immutable.
 *      Read functions (`content`, `text`, `web3Url`) are only valid after
 *      finalization.
 *
 * @dev CONTENT HASH SCHEME (canonical, reproducible off-chain)
 *      ----------------------------------------------------------------
 *      contentHash == keccak256(content())
 *      ----------------------------------------------------------------
 *      The hash is computed over the FULL reconstructed content as a single
 *      byte string. It is INDEPENDENT of how the content was stored
 *      (number of chunks, chunk sizes, storage pointers).
 *
 *      This guarantees that the same logical content always yields the same
 *      hash, regardless of the concrete ITextResource implementation used.
 *
 *      Off-chain verification (frontend integrity check), e.g. with viem:
 *          keccak256(fetchedBytes) === resource.contentHash()
 *
 *      NOTE: A consuming registry MAY expose this hash to clients for an
 *            integrity check but is NOT required to verify it on-chain.
 *
 * @dev GAS / MEMORY LIMITATIONS
 *      Implementations may reconstruct the full resource content in memory
 *      when serving content(), text(), or when computing/verifying contentHash.
 *      Very large resources can therefore become expensive or even fail due to
 *      gas or memory limits, even if the content was written in multiple
 *      chunks.
 *
 *      Consumers SHOULD treat ITextResource as suitable for bounded-size text
 *      artifacts such as product terms templates, product documentation
 *      templates, or metadata.
 *      Implementations MAY enforce their own maximum total content size.
 *
 * @author Christian Fries
 * @author Raphael Prandtl
 **/
interface ITextResource is IERC165 {
    /*
     * Custom errors
     */

    /**
     * @notice Thrown when a zero address is provided as owner.
     **/
    error ZeroOwner();

    /**
     * @notice Thrown when a non-owner calls an owner-only function.
     **/
    error NotOwner(address caller);

    /**
     * @notice Thrown when an empty resource type (bytes32(0)) is provided.
     **/
    error ZeroResourceType();

    /**
     * @notice Thrown when an empty media type string is provided.
     **/
    error EmptyMediaType();

    /**
     * @notice Thrown when the resource content is empty.
     **/
    error EmptyContent();

    /**
     * @notice Thrown when a zero content hash (bytes32(0)) is provided.
     **/
    error ZeroContentHash();

    /**
     * @notice Thrown when the provided content hash does not match
     *         keccak256 of the stored content.
     **/
    error ContentHashMismatch(bytes32 expected, bytes32 actual);

    /**
     * @notice Thrown when a write/finalize is attempted after finalization.
     **/
    error AlreadyFinalized();

    /**
     * @notice Thrown when a read is attempted before finalization.
     **/
    error NotFinalized();

    /*
     * Events
     */

    /**
     * @notice Emitted once when the resource is finalized and becomes immutable.
     **/
    event ResourceFinalized(bytes32 indexed resourceType, uint256 contentLength, bytes32 indexed contentHash);

    /*
     * Metadata / state
     */

    /**
     * @notice Returns the owner authorized to publish and finalize the resource.
     **/
    function owner() external view returns (address);

    /**
     * @notice Returns the application-defined type of the resource.
     * @dev Lets consumers accept only specific resource types.
     **/
    function resourceType() external view returns (bytes32);

    /**
     * @notice Returns the IANA media type of the content, e.g. "application/xml"
     *         or "application/xslt+xml".
     **/
    function mediaType() external view returns (string memory);

    /**
     * @notice Returns the total length of the content in bytes.
     **/
    function contentLength() external view returns (uint256);

    /**
     * @notice Returns keccak256 of the full content.
     **/
    function contentHash() external view returns (bytes32);

    /**
     * @notice Returns whether the resource is finalized (and thus immutable).
     **/
    function isFinalized() external view returns (bool);

    /*
     * Content read
     */

    /**
     * @notice Returns the full content as raw bytes.
     **/
    function content() external view returns (bytes memory);

    /**
     * @notice Returns the full content decoded as a UTF-8 string.
     **/
    function text() external view returns (string memory);

    /**
     * @notice Returns the canonical ERC-4804/6860 Web3 URL for the finalized
     *         resource content.
     * @dev The URL resolves to `content()` and reverts with `NotFinalized` until
     *      the resource has been finalized.
     **/
    function web3Url() external view returns (string memory);
}
