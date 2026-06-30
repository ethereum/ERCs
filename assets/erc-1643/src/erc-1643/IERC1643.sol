// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC1643 Document Management
interface IERC1643 {
    /// @notice Reverts when `setDocument` is called with `name == bytes32(0)`.
    error ERC1643InvalidName();

    /// @notice Reverts when `removeDocument` is called for a missing document.
    error ERC1643MissingDocument();

    /// @notice Returns metadata for a document identified by `name`.
    /// @return uri Document location.
    /// @return documentHash Hash of the document contents.
    /// @return lastModified Last update timestamp.
    function getDocument(bytes32 name) external view returns (string memory uri, bytes32 documentHash, uint256 lastModified);

    /// @notice Creates or updates a document entry.
    /// @dev MUST emit `DocumentUpdated` on success.
    function setDocument(bytes32 name, string calldata uri, bytes32 documentHash) external;

    /// @notice Removes an existing document entry.
    /// @dev MUST emit `DocumentRemoved` on success.
    function removeDocument(bytes32 name) external;

    /// @notice Returns all document names currently tracked by the contract.
    function getAllDocuments() external view returns (bytes32[] memory documentNames);

    /// @notice Emitted when a document is created or updated.
    event DocumentUpdated(bytes32 indexed name, string uri, bytes32 documentHash);

    /// @notice Emitted when a document is removed.
    event DocumentRemoved(bytes32 indexed name, string uri, bytes32 documentHash);
}
