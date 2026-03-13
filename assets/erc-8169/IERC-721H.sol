// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title IERC721H — Historical Ownership Extension for ERC-721
 * @author Emiliano Solazzi — 2026
 *
 * @notice Interface for NFTs that preserve complete ownership history on-chain.
 *
 * @dev ERC-721 tracks only the *current* owner of a token. Once Alice transfers
 *      to Bob, there is no on-chain proof that Alice ever held it — you must
 *      rely on fragile event indexing. ERC-721H fixes this with a three-layer
 *      ownership model:
 *
 *        Layer 1 — Immutable Origin    : who minted / created the token
 *        Layer 2 — Historical Trail    : append-only list of every past owner
 *        Layer 3 — Current Authority   : standard ERC-721 ownerOf()
 *
 *      A compliant contract MUST implement IERC721 and IERC165, then expose the
 *      functions below. The interface ID for IERC721H is computed as:
 *
 *        bytes4(keccak256("originalCreator(uint256)"))         ^
 *        bytes4(keccak256("mintBlock(uint256)"))               ^
 *        bytes4(keccak256("isOriginalOwner(uint256,address)")) ^
 *        bytes4(keccak256("isCurrentOwner(uint256,address)"))  ^
 *        bytes4(keccak256("hasEverOwned(uint256,address)"))    ^
 *        bytes4(keccak256("getOwnershipHistory(uint256)"))     ^
 *        bytes4(keccak256("getTransferCount(uint256)"))        ^
 *        bytes4(keccak256("getEverOwnedTokens(address)"))      ^
 *        bytes4(keccak256("getOriginallyCreatedTokens(address)")) ^
 *        bytes4(keccak256("isEarlyAdopter(address,uint256)"))  ^
 *        bytes4(keccak256("getProvenanceReport(uint256)"))     ^
 *        bytes4(keccak256("totalSupply()"))                    ^
 *        bytes4(keccak256("burn(uint256)"))
 *
 * @custom:eip-status Draft
 * @custom:version 2.0.0
 */
interface IERC721H {
    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    /// @notice Emitted every time a token's ownership history is extended.
    /// @param tokenId  The token whose history grew.
    /// @param newOwner The address appended to the history.
    /// @param timestamp Block timestamp of the event.
    event OwnershipHistoryRecorded(
        uint256 indexed tokenId,
        address indexed newOwner,
        uint256 timestamp
    );

    /// @notice Emitted once at mint to record the immutable creator.
    /// @param tokenId The newly minted token.
    /// @param creator The address that created it.
    event OriginalCreatorRecorded(
        uint256 indexed tokenId,
        address indexed creator
    );

    /// @notice Emitted when a token is burned (Layer 3 cleared, Layer 1 & 2 preserved).
    /// @dev Signals to indexers that this is a Layer-3-only deletion, not full destruction.
    ///      After this event, ownerOf() will revert but getOwnershipHistory() still works.
    /// @param tokenId The token that was burned.
    event HistoricalTokenBurned(uint256 indexed tokenId);

    // ──────────────────────────────────────────────
    //  Layer 1 — Immutable Origin
    // ──────────────────────────────────────────────

    /// @notice Returns the address that originally minted `tokenId`.
    /// @dev MUST be set once at mint and MUST never change, even after burn.
    function originalCreator(uint256 tokenId) external view returns (address);

    /// @notice Returns the block number at which `tokenId` was minted.
    function mintBlock(uint256 tokenId) external view returns (uint256);

    /// @notice Returns `true` if `account` was the original minter of `tokenId`.
    function isOriginalOwner(uint256 tokenId, address account) external view returns (bool);

    // ──────────────────────────────────────────────
    //  Layer 2 — Historical Trail
    // ──────────────────────────────────────────────

    /// @notice Returns `true` if `account` has ever owned `tokenId`.
    /// @dev MUST be an O(1) lookup (mapping, not array scan).
    function hasEverOwned(uint256 tokenId, address account) external view returns (bool);

    /// @notice Returns the complete chronological ownership chain for `tokenId`.
    /// @dev The first element is always the original creator.
    ///      MUST revert if `tokenId` does not exist.
    /// @return owners     Ordered array of owner addresses.
    /// @return timestamps Parallel array of block timestamps.
    function getOwnershipHistory(uint256 tokenId)
        external
        view
        returns (address[] memory owners, uint256[] memory timestamps);

    /// @notice Returns how many times `tokenId` has been transferred (excludes mint).
    function getTransferCount(uint256 tokenId) external view returns (uint256);

    /// @notice Returns every token `account` has ever owned (historical, deduplicated).
    function getEverOwnedTokens(address account) external view returns (uint256[] memory);

    /// @notice Returns every token `creator` originally minted.
    function getOriginallyCreatedTokens(address creator) external view returns (uint256[] memory);

    /// @notice Returns `true` if `account` minted any token at or before `blockThreshold`.
    function isEarlyAdopter(address account, uint256 blockThreshold) external view returns (bool);

    /// @notice Returns the owner of `tokenId` at any arbitrary `blockNumber`.
    /// @dev Uses O(log n) binary search over chronological ownership blocks.
    ///      Returns the owner who held the token at `blockNumber`, even if no
    ///      transfer happened at that exact block. Returns address(0) if the
    ///      token was not yet minted at `blockNumber`.
    function getOwnerAtBlock(uint256 tokenId, uint256 blockNumber) external view returns (address);

    /// @notice DEPRECATED: Use getOwnerAtBlock() instead.
    /// @dev Always returns address(0). Kept for backwards compatibility.
    function getOwnerAtTimestamp(uint256 tokenId, uint256 timestamp) external pure returns (address);

    // ──────────────────────────────────────────────
    //  Layer 3 — Current Authority (supplements ERC-721)
    // ──────────────────────────────────────────────

    /// @notice Returns `true` if `account` is the current owner of `tokenId`.
    function isCurrentOwner(uint256 tokenId, address account) external view returns (bool);

    // ──────────────────────────────────────────────
    //  Pagination Helpers (Anti-Griefing)
    // ──────────────────────────────────────────────

    /// @notice Returns the total number of entries in `tokenId`'s ownership history.
    function getHistoryLength(uint256 tokenId) external view returns (uint256);

    /// @notice Returns a paginated slice of ownership history.
    /// @param tokenId The token to query.
    /// @param start   Zero-based start index.
    /// @param count   Maximum entries to return.
    /// @return owners     Slice of owner addresses.
    /// @return timestamps Parallel slice of block timestamps.
    function getHistorySlice(uint256 tokenId, uint256 start, uint256 count)
        external view returns (address[] memory owners, uint256[] memory timestamps);

    // ──────────────────────────────────────────────
    //  Per-Address Pagination (Anti-Griefing)
    // ──────────────────────────────────────────────

    /// @notice Returns the number of distinct tokens `account` has ever owned.
    function getEverOwnedTokensLength(address account) external view returns (uint256);

    /// @notice Returns a paginated slice of tokens `account` has ever owned.
    function getEverOwnedTokensSlice(address account, uint256 start, uint256 count)
        external view returns (uint256[] memory tokenIds);

    /// @notice Returns the number of tokens `creator` originally minted.
    function getCreatedTokensLength(address creator) external view returns (uint256);

    /// @notice Returns a paginated slice of tokens `creator` originally minted.
    function getCreatedTokensSlice(address creator, uint256 start, uint256 count)
        external view returns (uint256[] memory tokenIds);

    // ──────────────────────────────────────────────
    //  Aggregate Queries
    // ──────────────────────────────────────────────

    /// @notice Returns a full provenance report for `tokenId` in a single call.
    function getProvenanceReport(uint256 tokenId)
        external
        view
        returns (
            address creator,
            uint256 creationBlock,
            address currentOwnerAddress,
            uint256 totalTransfers,
            address[] memory allOwners,
            uint256[] memory transferTimestamps
        );

    /// @notice Returns the total number of tokens currently in existence (excludes burned).
    function totalSupply() external view returns (uint256);

    /// @notice Returns the total number of tokens ever minted (includes burned).
    function totalMinted() external view returns (uint256);

    // ──────────────────────────────────────────────
    //  Lifecycle
    // ──────────────────────────────────────────────

    /// @notice Burns `tokenId`. Layer 1 and Layer 2 data MUST be preserved.
    /// @dev MUST revert if caller is not the owner or approved.
    function burn(uint256 tokenId) external;
}
