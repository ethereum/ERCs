// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "./IERC7007.sol";
import "./IOpmlLib.sol";

/**
 * @dev Implementation of the {IERC7007} interface.
 */
contract ERC7007_opml is ERC165, IERC7007, ERC721URIStorage {
    address public immutable opmlLib;
    mapping(uint256 => uint256) tokenIdToRequestId;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address opmlLib_
    ) ERC721(name_, symbol_) {
        opmlLib = opmlLib_;
    }

    /**
     * @dev See {IERC7007-mint}.
     */
    function mint(
        bytes calldata prompt,
        bytes calldata aigcData,
        string calldata uri,
        bytes calldata proof
    ) public virtual override returns (uint256 tokenId) {
        tokenId = uint256(keccak256(prompt));
        _safeMint(msg.sender, tokenId);
        string memory tokenUri = string(
            abi.encodePacked(
                "{",
                uri,
                ', "prompt": "',
                string(prompt),
                '", "aigc_data": "',
                string(aigcData),
                '"}'
            )
        );
        _setTokenURI(tokenId, tokenUri);
        tokenIdToRequestId[tokenId] = IOpmlLib(opmlLib).initOpmlRequest(prompt);
        IOpmlLib(opmlLib).uploadResult(tokenIdToRequestId[tokenId], aigcData);

        emit Mint(tokenId, prompt, aigcData, uri, proof);
    }

    /**
     * @dev See {IERC7007-verify}.
     */
    function verify(
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata proof
    ) public view virtual override returns (bool success) {
        uint256 tokenId = uint256(keccak256(prompt));
        bytes32 output = bytes32(IOpmlLib(opmlLib).getOutput(tokenIdToRequestId[tokenId]));
        return IOpmlLib(opmlLib).isFinalized(tokenIdToRequestId[tokenId]) && (output == keccak256(aigcData));
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165, ERC721URIStorage) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
