// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "./IERC7007.sol";
import "./IVerifier.sol";

/**
 * @dev Implementation of the {IERC7007} interface.
 */
contract ERC7007Zkml is ERC165, IERC7007, ERC721URIStorage {
    address public immutable verifier;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address verifier_
    ) ERC721(name_, symbol_) {
        verifier = verifier_;
    }

    function mint(
        address to,
        bytes calldata prompt,
        bytes calldata aigcData,
        string calldata uri,
        bytes calldata proof
    ) public virtual returns (uint256 tokenId) {
        tokenId = uint256(keccak256(prompt));
        _safeMint(to, tokenId);
        addAigcData(tokenId, prompt, aigcData, proof);

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
    }

    /**
     * @dev See {IERC7007-addAigcData}.
     */
    function addAigcData(
        uint256 tokenId,
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata proof
    ) public virtual override {
        require(ownerOf(tokenId) != address(0), "ERC7007: nonexistent token");
        require(verify(prompt, aigcData, proof), "ERC7007: invalid proof");
        emit AigcData(tokenId, prompt, aigcData, proof);
    }

    /**
     * @dev See {IERC7007-verify}.
     */
    function verify(
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata proof
    ) public view virtual override returns (bool success) {
        return
            IVerifier(verifier).verifyProof(
                proof,
                abi.encodePacked(prompt, aigcData)
            );
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, ERC721, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
