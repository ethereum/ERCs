// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  On-chain task document extension (TASK-KERNEL v1.0) — own ERC-165 id.
/// @notice The on-chain document is exclusively the plaintext primary Markdown
///         task document; the sha256(document) == tdHash invariant makes this
///         structural. Semantics mirror IOnchainSkillDocument exactly.
interface IOnchainTaskDocument {
    /// @notice Whether a plaintext on-chain copy of the primary document exists.
    /// @dev MUST revert for nonexistent tokenId. Once true, remains true permanently.
    function hasOnchainTaskDocument(uint256 tokenId) external view returns (bool);

    /// @notice The exact plaintext UTF-8 bytes of the primary task document.
    /// @dev MUST revert when hasOnchainTaskDocument(tokenId) == false.
    function taskDocument(uint256 tokenId) external view returns (bytes memory document);

    /// @notice Atomically update the on-chain document together with the binding.
    /// @dev tdHash is computed in-contract as sha256(document).
    function updateTaskWithDocument(uint256 tokenId, bytes calldata document, bytes32 taskHash) external;

    /// @notice Publish the current primary document on-chain without a version change.
    /// @dev MUST revert unless sha256(document) == taskOf(tokenId).tdHash.
    ///      MUST NOT change taskHash or version. Sets existence permanently true.
    function publishTaskDocument(uint256 tokenId, bytes calldata document) external;

    event TaskDocumentPublished(uint256 indexed tokenId, bytes32 tdHash);
}
