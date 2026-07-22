// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC165} from "openzeppelin-contracts/contracts/utils/introspection/ERC165.sol";
import {IERC1643} from "./IERC1643.sol";

/// @title ERC1643
/// @notice Reusable ERC-1643 document management module with owner-restricted writes.
abstract contract ERC1643 is IERC1643, Ownable, ERC165 {
    struct Document {
        string uri;
        bytes32 documentHash;
        uint256 lastModified;
        bool exists;
    }

    mapping(bytes32 name => Document document) private _documents;
    bytes32[] private _documentNames;
    mapping(bytes32 name => uint256 indexPlusOne) private _documentIndex;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function getDocument(bytes32 name)
        public
        view
        virtual
        returns (string memory uri, bytes32 documentHash, uint256 lastModified)
    {
        Document storage doc = _documents[name];
        return (doc.uri, doc.documentHash, doc.lastModified);
    }

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

    function getAllDocuments() public view virtual returns (bytes32[] memory documentNames) {
        return _documentNames;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC1643).interfaceId || super.supportsInterface(interfaceId);
    }
}
