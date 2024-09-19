// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "./RegistryENSName.sol";

struct ScriptData {
    string name;
    string iconURI;
    uint256 tokenId;
    string scriptURI;
    bool isAuthenticated;
}

uint256 constant MAX_PAGE_SIZE = 500;

interface IRegistryMetadata {
    function getBaseName() external view returns (string memory);

    function setBaseName(string calldata baseName) external;

    function setOrder(uint256 tokenId, uint256 order, bool isOwner) external;

    function getOrder(uint256 tokenId) external view returns (uint256);

    function setName(uint256 tokenId, string calldata name) external;

    function getName(uint256 tokenId) external view returns (string memory);

    function setIconURI(uint256 tokenId, string calldata iconURI) external;

    function getTokenMetadata(
        uint256 id,
        address contractAddress,
        string memory scriptURI
    ) external view returns (string memory);

    function getOwner(address contractAddress) external view returns (address);

    function mintedByOwner(uint256 tokenId) external view returns (bool);

    function getScriptDataList(
        uint256[] calldata tokenIds
    ) external view returns (ScriptData[] memory);

    function getScriptData(
        uint256 tokenId
    ) external view returns (ScriptData memory);
}

interface IRegistry {
    function getScriptURI(
        uint256 tokenId
    ) external view returns (string memory);
}

contract RegistryMetadata is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    RegistryENSName
{
    event UpdateIconURI(uint256 indexed tokenId, string iconURI);

    string private constant _websiteUri =
        "https://github.com/ethereum/ERCs/blob/master/ERCS/erc-7738.md";
    string private _baseName;

    address private _registry;

    modifier onlyRegistry() {
        require(msg.sender == _registry, "Must be Registry");

        _;
    }

    struct MetadataElement {
        string name;
        string iconURI;
        uint256 order;
    }

    mapping(uint256 => MetadataElement) private _metadataElements;

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function setRegistry(address registry) external onlyOwner {
        _registry = registry;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function setBaseName(string calldata baseName) external onlyRegistry {
        _baseName = baseName;
    }

    function getBaseName() external view returns (string memory) {
        return _baseName;
    }

    function setOrder(
        uint256 tokenId,
        uint256 order,
        bool isOwner
    ) public onlyRegistry {
        uint256 topBit = isOwner ? (1 << 255) : 0; // Set the top bit (bit 255) if isOwner is true
        _metadataElements[tokenId].order = order | topBit;
    }

    function setName(
        uint256 tokenId,
        string calldata name
    ) external onlyRegistry {
        _metadataElements[tokenId].name = name;
        // Note: Event is emitted in the main contract
    }

    function setIconURI(
        uint256 tokenId,
        string calldata iconURI
    ) external onlyRegistry {
        _metadataElements[tokenId].iconURI = iconURI;
        emit UpdateIconURI(tokenId, iconURI);
    }

    function getName(uint256 tokenId) external view returns (string memory) {
        return _metadataElements[tokenId].name;
    }

    function getOrder(uint256 tokenId) public view returns (uint256) {
        return _metadataElements[tokenId].order & ((1 << 255) - 1);
    }

    function mintedByOwner(uint256 tokenId) public view returns (bool) {
        return (_metadataElements[tokenId].order & (1 << 255)) > 0;
    }

    function getTokenMetadata(
        uint256 id,
        address contractAddress,
        string memory scriptURI
    ) public view returns (string memory) {
        MetadataElement memory element = _metadataElements[id];
        string memory ensName = string(
            abi.encodePacked(
                _formENSName(getOrder(id), element.name, contractAddress),
                ".",
                _baseName
            )
        );

        return
            string(
                abi.encodePacked(
                    '{"name": "',
                    (bytes(element.name).length > 0)
                        ? element.name
                        : string(
                            abi.encodePacked(
                                "ERC-7738 Registry #",
                                Strings.toString(id)
                            )
                        ),
                    '","description":"A receipt of ownership for script entry #',
                    Strings.toString(getOrder(id)),
                    " for the Token Contract: ",
                    Strings.toHexString(uint160(contractAddress), 20),
                    " ENS: ",
                    ensName,
                    '.eth","external_url":"',
                    _websiteUri,
                    '","image":"',
                    (bytes(element.iconURI).length > 0)
                        ? element.iconURI
                        : getTokenIcon(),
                    '",',
                    addAttributes(id, contractAddress, ensName, scriptURI),
                    "}"
                )
            );
    }

    function addAttributes(
        uint256 id,
        address contractAddress,
        string memory ensName,
        string memory scriptURI
    ) internal view returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '"attributes":[{"trait_type":"Contract","value":"',
                    Strings.toHexString(uint160(contractAddress), 20),
                    '"},{"trait_type":"Order","value":"',
                    Strings.toString(getOrder(id)),
                    '"},{"trait_type":"scriptURI","value":"',
                    scriptURI,
                    '"},{"trait_type":"ENS","value":"',
                    ensName,
                    '.eth"},',
                    '{"trait_type":"MintedByOwner","value":"',
                    mintedByOwner(id) ? "true" : "false",
                    '"},',
                    '{"trait_type":"name","value":"',
                    _metadataElements[id].name,
                    '"}]'
                )
            );
    }

    function getTokenIcon() internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQwIiBoZWlnaHQ9IjI0MCIgdmlld0JveD0iMCAwIDI0MCAyNDAiIGZpbGw9Im5vbmUiIHhtbG5zP",
                    "SJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyI+DQo8cmVjdCB3aWR0aD0iMjQwIiBoZWlnaHQ9IjI0MCIgZmlsbD0iYmxhY2siLz4NCjxnIGNsaXAtcGF0",
                    "aD0idXJsKCNjbGlwMF8xXzQ2NikiPg0KPHBhdGggZD0iTTE3MCA4Mi4wNDJIMTU5LjQ2M1YxNTEuNzExSDE3MFY4Mi4wNDJaIiBmaWxsPSIjMDAxOUZGIi8",
                    "+DQo8cGF0aCBkPSJNMTQ5LjQzIDEyMS4wOThWMTI2Ljk1NUwxMTQuNTgzIDE0NC45MlYxMzUuODNMMTM4LjM4OSAxMjQuMTE2TDExNC41ODMgMTEyLjQzOV",
                    "YxMDMuMzEzTDE0OS40MyAxMjEuMDk4WiIgZmlsbD0id2hpdGUiLz4NCjxwYXRoIGQ9Ik03MCAxMjYuODExVjEyMC45NTRMMTA0Ljg4MyAxMDIuOTg5VjExM",
                    "i4xMTZMODEuMDQwMSAxMjMuNzkzTDEwNC44ODMgMTM1LjUwNlYxNDQuNTk3TDcwIDEyNi44MTFaIiBmaWxsPSJ3aGl0ZSIvPg0KPC9nPg0KPGRlZnM+DQo8",
                    "Y2xpcFBhdGggaWQ9ImNsaXAwXzFfNDY2Ij4NCjxyZWN0IHdpZHRoPSIxMDAiIGhlaWdodD0iNzAuMzcwNCIgZmlsbD0id2hpdGUiIHRyYW5zZm9ybT0idHJ",
                    "hbnNsYXRlKDcwIDgxKSIvPg0KPC9jbGlwUGF0aD4NCjwvZGVmcz4NCjwvc3ZnPg0K"
                )
            );
    }

    function getScriptDataList(
        uint256[] calldata tokenIds
    ) external view returns (ScriptData[] memory scriptEntries) {
        //build script data list
        uint256 length = (tokenIds.length < MAX_PAGE_SIZE)
            ? tokenIds.length
            : MAX_PAGE_SIZE;
        scriptEntries = new ScriptData[](length);

        uint256 scriptIndex = 0;

        for (uint i = 0; i < length; i++) {
            uint256 thisId = tokenIds[i];
            if (thisId > 0) {
                scriptEntries[scriptIndex].name = formName(thisId);
                scriptEntries[scriptIndex].iconURI = _metadataElements[thisId].iconURI;
                scriptEntries[scriptIndex].tokenId = thisId;
                scriptEntries[scriptIndex].isAuthenticated = mintedByOwner(thisId);
                scriptEntries[scriptIndex].scriptURI = IRegistry(_registry).getScriptURI(
                    thisId
                );
                scriptIndex++;
            }
        }
    }

    function getScriptData(
        uint256 tokenId
    ) public view returns (ScriptData memory scriptEntry) {
        scriptEntry.name = formName(tokenId);
        scriptEntry.iconURI = _metadataElements[tokenId].iconURI;
        scriptEntry.tokenId = tokenId;
        scriptEntry.isAuthenticated = mintedByOwner(tokenId);
        scriptEntry.scriptURI = IRegistry(_registry).getScriptURI(tokenId);
    }

    function formName(uint256 tokenId) internal view returns (string memory) {
        string memory name = _metadataElements[tokenId].name;
        if (bytes(name).length == 0) {
            name = Strings.toString(getOrder(tokenId));
        }
        return name;
    }

    //Utility functions
    function getOwner(address contractAddress) public view returns (address) {
        try OwnableUpgradeable(contractAddress).owner() returns (
            address owner
        ) {
            return owner;
        } catch {
            return address(0);
        }
    }
}
