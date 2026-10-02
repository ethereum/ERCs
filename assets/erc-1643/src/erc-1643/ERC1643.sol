// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC1643} from "./IERC1643.sol";

/// @title ERC1643
/// @notice Reusable ERC-1643 document management module with owner-restricted writes.
abstract contract ERC1643 is IERC1643, Ownable, ERC165 {
    /**
     * @notice Metadata stored for a single document entry.
     * @dev `exists` distinguishes a live entry from a default-initialized slot, so a document
     * whose `uri` and `documentHash` are both empty is still tracked by the enumeration.
     */
    struct Document {
        // Off-chain location of the document.
        string uri;
        // Hash of the document contents, for integrity checks.
        bytes32 documentHash;
        // Block timestamp of the most recent write.
        uint256 lastModified;
        // True while the entry is tracked by the enumeration.
        bool exists;
    }

    /// @notice Document metadata keyed by document name.
    mapping(bytes32 name => Document document) private _documents;

    /// @notice Names of all documents currently tracked, in unspecified order.
    bytes32[] private _documentNames;

    /// @notice Position of each name in `_documentNames`, stored as index + 1 so that 0 means absent.
    mapping(bytes32 name => uint256 indexPlusOne) private _documentIndex;

    /**
     * @notice Sets the address allowed to create, update and remove documents.
     * @param initialOwner Account granted ownership of the document module.
     */
    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Creates a document entry or overwrites an existing one, refreshing its timestamp.
     * @dev Reverts with `ERC1643InvalidName` when `name` is zero. Emits `DocumentUpdated`.
     * @param name Identifier of the document.
     * @param uri Off-chain location of the document; MAY be empty.
     * @param documentHash Hash of the document contents; MAY be zero.
     */
    function setDocument(bytes32 name, string calldata uri, bytes32 documentHash) public virtual onlyOwner {
        if (name == bytes32(0)) revert ERC1643InvalidName();
        Document storage doc = _documents[name];

        if (!doc.exists) {
            doc.exists = true;
            _documentNames.push(name);
            _documentIndex[name] = _documentNames.length;
        }

        doc.uri = uri;
        doc.documentHash = documentHash;
        doc.lastModified = block.timestamp;

        emit DocumentUpdated(name, uri, documentHash);
    }

    /**
     * @notice Removes an existing document entry and drops it from the enumeration.
     * @dev Uses swap-and-pop for O(1) removal, so the position of an unrelated name may change.
     * Reverts with `ERC1643MissingDocument` when the entry does not exist. Emits `DocumentRemoved`.
     * @param name Identifier of the document to remove.
     */
    function removeDocument(bytes32 name) public virtual onlyOwner {
        Document storage doc = _documents[name];
        if (!doc.exists) revert ERC1643MissingDocument();

        string memory removedUri = doc.uri;
        bytes32 removedHash = doc.documentHash;

        uint256 idx = _documentIndex[name] - 1;
        uint256 last = _documentNames.length - 1;

        if (idx != last) {
            bytes32 lastName = _documentNames[last];
            _documentNames[idx] = lastName;
            _documentIndex[lastName] = idx + 1;
        }

        _documentNames.pop();
        delete _documentIndex[name];
        delete _documents[name];

        emit DocumentRemoved(name, removedUri, removedHash);
    }

    /**
     * @notice Returns the metadata stored for a document.
     * @dev Never reverts. An entry that was never set, or that has been removed, yields
     * `("", bytes32(0), 0)`; a live entry always has a non-zero `lastModified`.
     * @param name Identifier of the document.
     * @return uri Off-chain location of the document.
     * @return documentHash Hash of the document contents.
     * @return lastModified Timestamp of the most recent write, or zero when absent.
     */
    function getDocument(bytes32 name)
        public
        view
        virtual
        returns (string memory uri, bytes32 documentHash, uint256 lastModified)
    {
        Document storage doc = _documents[name];
        return (doc.uri, doc.documentHash, doc.lastModified);
    }

    /**
     * @notice Returns the names of every document currently tracked.
     * @dev Order is unspecified and may change when any document is removed. Callers must not
     * treat a change in position as a change to a document.
     * @return documentNames Names of all live documents.
     */
    function getAllDocuments() public view virtual returns (bytes32[] memory documentNames) {
        return _documentNames;
    }

    /**
     * @notice Reports whether this contract implements a given interface.
     * @param interfaceId ERC-165 identifier to query.
     * @return True for `IERC1643`, for ERC-165 itself, and for any interface a base supports.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1643).interfaceId || super.supportsInterface(interfaceId);
    }
}
