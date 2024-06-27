// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "./lib/FactoryOperatorable.sol";

contract ERC7662 is FactoryOperatorable, ERC721URIStorage {

    uint256 public tokenIds;

    //NFT Base URI
    string public baseURI;


    struct Agent { 
        string name;
        string description;
        string model;
        string userPromptURI;
        string systemPromptURI;
        string imageURI;
        string category;
        bool promptsEncrypted;
    }

    mapping(address => uint256[]) public collectionIds;
    mapping(uint => Agent) public Agents;

    event AgentCreated(string name, string description, string model, string category, address recipient, uint256 tokenId);
    
    constructor( 
        string memory collectionBaseURI,
        address admin,
        address operator) ERC721("Agent NFTs", "AGENTS") FactoryOperatorable(admin, operator) {

        baseURI = collectionBaseURI;

    }

     /**
     * @dev Override supportInterface.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }


    /**
     * @dev Mint an Agent NFT and attach its data to the token id
     *
     * @param _recipient address to receive NFT
     * @param _name string Name of the Agent
     * @param _description string Description of the Agent
     * @param _model string AI Model of the Agent
     * @param _userPromptURI string URI of the Agent's User Prompt
     * @param _systemPromptURI string URI of the Agent's System Prompt
     * @param _imageURI string URI of the NFT image
     * @param _category string Category of Agent
     * @param _tokenURI string URI of the NFT
     *
     * Emits an AgentCreated event.
     */
    function mintAgent(address _recipient, string memory _name, string memory _description, string memory _model, string memory _userPromptURI, string memory _systemPromptURI, string memory _imageURI, string memory _category, string memory _tokenURI) public {
        tokenIds++;
        bool _promptsEncrypted = false;
        Agents[tokenIds] = Agent(_name, _description, _model, _userPromptURI, _systemPromptURI, _imageURI, _category, _promptsEncrypted);

        _mint(_recipient, tokenIds);
        collectionIds[_recipient].push(tokenIds);
        _setTokenURI(tokenIds, _tokenURI);
        emit AgentCreated(_name, _description, _model, _category, _recipient, tokenIds);
    }

     /**
     * @dev Update NFT with Encrypted Prompts as token id needed first for encryption params
     *
     * @param _tokenId uint256 Id of the NFT to update
     * @param _encryptedUserPromptURI string Encrypted URI of the Agent's User Prompt
     * @param _encryptedSystemPromptURI string Encrypted URI of the Agent's System Prompt
     */
    function addEncryptedPrompts(uint256 _tokenId, string memory _encryptedUserPromptURI, string memory _encryptedSystemPromptURI) public {
        require(ownerOf(_tokenId) == msg.sender, "Sender must be token owner");
        Agent storage agent = Agents[_tokenId];
        agent.userPromptURI = _encryptedUserPromptURI;
        agent.systemPromptURI = _encryptedSystemPromptURI;
        agent.promptsEncrypted = true;
    }

    /**
     * @dev Return base URI
     * Override {ERC721:_baseURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Return all token ids owned by address
     * @param _address address Address to check for
     */
    function getCollectionIds(address _address) public view returns (uint256[] memory) {
        return collectionIds[_address];
    }


    /**
     * @dev Remove the given token from collectionIds. 
     *
     * @param from address from
     * @param tokenId tokenId to remove
     */
    function _popId(address from, uint256 tokenId) internal {
        uint256[] storage _collectionIds = collectionIds[from];
        for (uint256 i = 0; i < _collectionIds.length; i++) {
            if (_collectionIds[i] == tokenId) {
                if (i != _collectionIds.length - 1) {
                    _collectionIds[i] = _collectionIds[_collectionIds.length - 1];
                }
                _collectionIds.pop();
                break;
            }
        }
    }

     /**
     * @dev Transfers `tokenId` from `from` to `to`. 
     *
     * Requirements:
     *
     * - `tokenId` token must be owned by `from`.
     *
     * @param from address from
     * @param to address to
     * @param tokenId tokenId to transfer
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        super._transfer(from, to, tokenId);
        _popId(from, tokenId);
        collectionIds[to].push(tokenId);
    }

    
}