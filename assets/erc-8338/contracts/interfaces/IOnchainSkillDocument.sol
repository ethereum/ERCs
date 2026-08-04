// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  On-chain document extension (KERNEL v4.3, frozen) — own ERC-165 id.
/// @notice The on-chain document is exclusively the plaintext primary Markdown
///         document; the sha256(document) == mdHash invariant makes this structural.
interface IOnchainSkillDocument {
    /// @notice Whether a plaintext on-chain copy of the primary document exists.
    /// @dev MUST revert for nonexistent tokenId. Once true, remains true permanently.
    function hasOnchainSkillDocument(uint256 tokenId) external view returns (bool);

    /// @notice The exact plaintext UTF-8 bytes of the primary Skill document.
    /// @dev MUST revert when hasOnchainSkillDocument(tokenId) == false.
    function skillDocument(uint256 tokenId) external view returns (bytes memory document);

    /// @notice Atomically update the on-chain document together with the binding.
    /// @dev mdHash is computed in-contract as sha256(document).
    function updateSkillWithDocument(uint256 tokenId, bytes calldata document, bytes32 packageHash) external;

    /// @notice Publish the current primary document on-chain without a version change.
    /// @dev MUST revert unless sha256(document) == skillOf(tokenId).mdHash.
    ///      MUST NOT change packageHash or version. Sets existence permanently true.
    function publishSkillDocument(uint256 tokenId, bytes calldata document) external;

    event SkillDocumentPublished(uint256 indexed tokenId, bytes32 mdHash);
}
