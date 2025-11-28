// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./IERC7738.sol";
import {IENSSubdomainAssigner} from "./ENSSubdomainAssigner.sol";
import {IRegistryMetadata, ScriptData, MAX_PAGE_SIZE} from "./RegistryMetadata.sol";
import {IERC5169} from "stl-contracts/ERC/ERC5169.sol";

contract DecentralisedRegistryNFT is
    ERC721EnumerableUpgradeable,
    UUPSUpgradeable,
    IERC7738,
    OwnableUpgradeable
{
    event UpdateBaseENS(string newBaseENS);
    event UpdateENSSubdomain(
        uint256 indexed tokenId,
        address indexed tokenContract
    );

    error EmptyScriptURI();
    error ScriptOrderOutOfRange();
    error MaxPageSize(uint maxPageSize);
    error ScriptOwnerOnly();

    struct ScriptElement {
        string scriptURI;
        address contractAddress;
    }

    mapping(uint256 => ScriptElement) _scriptElements;
    mapping(address => uint256[]) _tokenEntries;

    address private _metadata;
    address private _ensAssigner;

    modifier onlyScriptOwner(uint256 id) {
        if (ownerOf(id) != msg.sender) {
            revert ScriptOwnerOnly();
        }

        _;
    }

    function initialize(
        string calldata name,
        string calldata symbol,
        address metadataContract,
        address ensAssigner
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Enumerable_init();
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        _ensAssigner = ensAssigner;
        _metadata = metadataContract;
    }

    function updateENSBase(string calldata ensLabel) external onlyOwner {
        IRegistryMetadata(_metadata).setBaseName(ensLabel);
        IENSSubdomainAssigner(_ensAssigner).setBaseLabel(ensLabel);
        emit UpdateBaseENS(ensLabel);
    }

    function getENSInfo()
        public
        view
        returns (bytes32 baseLabel, address resolver)
    {
        return IENSSubdomainAssigner(_ensAssigner).getENSInfo();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // Updates a specific scriptURI using an issued token
    function updateScriptURI(
        uint256 tokenId,
        string memory newScriptURI
    ) external onlyScriptOwner(tokenId) {
        //need to update the entry pointed to by NFT entry
        _scriptElements[tokenId].scriptURI = newScriptURI;
        string[] memory scriptURIs = new string[](1);
        scriptURIs[0] = newScriptURI;
        emit ScriptUpdate(
            _scriptElements[tokenId].contractAddress,
            msg.sender,
            scriptURIs
        );
    }

    function setScriptURI(
        address contractAddress,
        string[] memory newScriptURIs
    ) external override {
        //set multiple scripts
        if (newScriptURIs.length == 0) {
            revert EmptyScriptURI();
        }

        for (uint256 i = 0; i < newScriptURIs.length; ) {
            _setScriptURI(contractAddress, newScriptURIs[i]);
            unchecked {
                i += 1;
            }
        }
        emit ScriptUpdate(contractAddress, msg.sender, newScriptURIs);
    }

    function _setScriptURI(
        address contractAddress,
        string memory newScriptURI
    ) internal {
        //create new entry and mint token
        uint256 tokenId = totalSupply() + 1;
        _safeMint(msg.sender, tokenId);

        //if no entries so far, reserve first slot for owner
        bool isTokenOwner = (IRegistryMetadata(_metadata).getOwner(
            contractAddress
        ) == msg.sender);
        uint256 index = _tokenEntries[contractAddress].length;
        if (index == 0 && !isTokenOwner) {
            //reserve first slot for owner
            _tokenEntries[contractAddress].push(0);
            index = 1;
        }

        // Add new entry
        _scriptElements[tokenId].scriptURI = newScriptURI;
        _scriptElements[tokenId].contractAddress = contractAddress;
        if (
            isTokenOwner && index > 0 && _tokenEntries[contractAddress][0] == 0
        ) {
            _tokenEntries[contractAddress][0] = tokenId;
            index = 0;
        } else {
            _tokenEntries[contractAddress].push(tokenId);
        }

        index++;
        IENSSubdomainAssigner(_ensAssigner).createSubdomain(
            "",
            contractAddress,
            msg.sender,
            index
        );
        IRegistryMetadata(_metadata).setOrder(tokenId, index, isTokenOwner);
        emit UpdateENSSubdomain(tokenId, contractAddress);
    }

    function scriptDataElement(
        uint256 tokenId
    ) external view returns (ScriptData memory) {
        _requireOwned(tokenId);
        // pick from the list (note that the entry in the list for human readable starts at 1, whereas 1 will be the zeroeth entry)
        return (IRegistryMetadata(_metadata).getScriptData(tokenId));
    }

    function scriptData(
        address contractAddress
    ) public view returns (ScriptData[] memory) {
        return
            IRegistryMetadata(_metadata).getScriptDataList(
                _tokenEntries[contractAddress]
            );
    }

    function scriptURI(
        address contractAddress
    ) public view returns (string[] memory) {
        return scriptURI(contractAddress, 1, MAX_PAGE_SIZE);
    }

    function scriptURI(
        address contractAddress,
        uint256 page,
        uint256 pageSize
    ) public view returns (string[] memory ownerScripts) {
        if (pageSize > MAX_PAGE_SIZE) {
            revert MaxPageSize(MAX_PAGE_SIZE);
        }

        uint256[] memory tokenList = _tokenEntries[contractAddress];
        uint256 startPoint = pageSize * (page - 1);

        if (startPoint >= tokenList.length) {
            return new string[](0);
        }

        uint256 arrayLen = tokenList.length - startPoint;
        uint256 actualArrayLen = 0;

        arrayLen = arrayLen < pageSize ? arrayLen : pageSize;

        for (uint256 i = startPoint; i < arrayLen + startPoint; i++) {
            uint256 tokenId = tokenList[i];
            if (tokenId > 0) {
                actualArrayLen++;
            }
        }

        ownerScripts = new string[](actualArrayLen);
        uint256 scriptIndex = 0;

        //populate array
        for (uint256 i = startPoint; i < arrayLen + startPoint; i++) {
            uint256 tokenId = tokenList[i];
            if (tokenId > 0) {
                ownerScripts[scriptIndex++] = _scriptElements[tokenId]
                    .scriptURI;
            }
        }
    }

    function getScriptURI(
        uint256 tokenId
    ) external view returns (string memory) {
        _requireOwned(tokenId);
        return _scriptElements[tokenId].scriptURI;
    }

    // Return Procedural Metadata
    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        return
            IRegistryMetadata(_metadata).getTokenMetadata(
                id,
                _scriptElements[id].contractAddress,
                _scriptElements[id].scriptURI
            );
    }

    function setName(
        uint256 tokenId,
        string memory name
    ) external onlyScriptOwner(tokenId) {
        IRegistryMetadata(_metadata).setName(tokenId, name);
        IENSSubdomainAssigner(_ensAssigner).createSubdomain(
            name,
            _scriptElements[tokenId].contractAddress,
            ownerOf(tokenId),
            IRegistryMetadata(_metadata).getOrder(tokenId)
        );
        emit UpdateENSSubdomain(
            tokenId,
            _scriptElements[tokenId].contractAddress
        );
    }

    function setIconURI(
        uint256 tokenId,
        string memory iconURI
    ) external onlyScriptOwner(tokenId) {
        IRegistryMetadata(_metadata).setIconURI(tokenId, iconURI);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        //update domain name ownership if required
        if (_ownerOf(tokenId) != address(0)) {
            IENSSubdomainAssigner(_ensAssigner).updateResolverAddress(
                IRegistryMetadata(_metadata).getName(tokenId),
                _scriptElements[tokenId].contractAddress,
                to,
                IRegistryMetadata(_metadata).getOrder(tokenId)
            );
        }
        return super._update(to, tokenId, auth);
    }
}
