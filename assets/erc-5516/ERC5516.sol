//SPDX-License-Identifier: CC0-1.0

/**
 * @notice Reference implementation of the eip-5516 interface.
 * @author Matias Arazi <matiasarazi@gmail.com> , Lucas Martín Grasso Ramos <lucasgrassoramos@gmail.com>
 * See https://github.com/ethereum/EIPs/pull/5516
 */

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./IERC5516.sol";

contract ERC5516 is Context, ERC165, IERC5516 {
    // Used for making each token unique, Maintains ID registry and quantity of tokens minted.
    uint256 private _nextTokenId;

    // Used as the URI for all token types by relying on ID substitution, e.g. https://ipfs.io/ipfs/token.data
    string private _uri;

    // Mapping from token ID to account balances
    mapping(address => mapping(uint256 => bool)) private _holdings;

    // Mapping from ID to minter address.
    mapping(uint256 => address) private _minters;

    // Mapping from ID to URI.
    mapping(uint256 => string) private _tokenURIs;

    /**
     * @dev Sets base uri for tokens. Preferably "https://ipfs.io/ipfs/"
     */
    constructor(string memory uri_) {
        _uri = uri_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IERC5516).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC5516-issue}.
     */
    function issue(
        address[] memory recipients,
        string calldata metadataURI
    ) external virtual override returns (uint256 tokenId) {
        require(recipients.length > 0, "EIP5516: Empty recipients list");

        tokenId = _nextTokenId++;

        address minter = _msgSender();
        _minters[tokenId] = minter;

        _tokenURIs[tokenId] = metadataURI;

        for (uint256 i = 0; i < recipients.length; ) {
            address recipient = recipients[i];

            require(
                recipient != address(0),
                "EIP5516: Transfer to address zero"
            );
            require(
                !_holdings[recipient][tokenId],
                "EIP5516: Token already owned"
            );

            _holdings[recipient][tokenId] = true;

            unchecked {
                ++i;
            }
        }

        emit Issued(tokenId, minter, recipients, metadataURI);
        return tokenId;
    }

    /**
     * @dev See {IERC5516-renounce}.
     */
    function renounce(uint256 tokenId) public virtual override {
        address sender = _msgSender();
        require(
            _holdings[sender][tokenId],
            "EIP5516: Sender does not own a token under `tokenId`"
        );

        delete _holdings[sender][tokenId];

        emit Renounced(tokenId, sender);
    }

    /**
     * @dev See {IERC5516-has}.
     */
    function has(
        address who,
        uint256 tokenId
    ) external view virtual override returns (bool) {
        return _holdings[who][tokenId];
    }

    /**
     * @dev See {IERC5516-uri}.
     */
    function uri(
        uint256 tokenId
    ) external view virtual override returns (string memory) {
        require(
            bytes(_tokenURIs[tokenId]).length > 0,
            "EIP5516: Token does not exist"
        );
        return string(abi.encodePacked(_uri, _tokenURIs[tokenId]));
    }
}
