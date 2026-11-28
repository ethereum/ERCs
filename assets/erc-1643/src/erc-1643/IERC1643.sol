// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IERC1643 Document Management
interface IERC1643 {
    /// @notice Emitted when a document is created or updated.
    /// @param name Identifier of the document.
    /// @param uri Document location.
    /// @param documentHash Hash of the document contents.
    event DocumentUpdated(bytes32 indexed name, string uri, bytes32 documentHash);

    /// @notice Emitted when a document is removed.
    /// @param name Identifier of the document.
    /// @param uri Document location at the time of removal.
    /// @param documentHash Hash of the document contents at the time of removal.
    event DocumentRemoved(bytes32 indexed name, string uri, bytes32 documentHash);

    /// @notice Reverts when `setDocument` is called with `name == bytes32(0)`.
    error ERC1643InvalidName();

    /// @notice Reverts when `removeDocument` is called for a missing document.
    error ERC1643MissingDocument();

    /// @notice Creates or updates a document entry.
    /// @dev MUST emit `DocumentUpdated` on success.
    /// @param name Identifier of the document.
    /// @param uri Document location.
    /// @param documentHash Hash of the document contents.
    function setDocument(bytes32 name, string calldata uri, bytes32 documentHash) external;

    /// @notice Removes an existing document entry.
    /// @dev MUST emit `DocumentRemoved` on success.
    /// @param name Identifier of the document to remove.
    function removeDocument(bytes32 name) external;

    /// @notice Returns metadata for a document identified by `name`.
    /// @param name Identifier of the document.
    /// @return uri Document location.
    /// @return documentHash Hash of the document contents.
    /// @return lastModified Last update timestamp.
    function getDocument(bytes32 name)
        external
        view
        returns (string memory uri, bytes32 documentHash, uint256 lastModified);

    /// @notice Returns all document names currently tracked by the contract.
    /// @return documentNames Names of all documents that are currently set.
    function getAllDocuments() external view returns (bytes32[] memory documentNames);
}
