//SPDX-License-Identifier: CC0-1.0

/**
 * @notice Reference implementation of the erc-5516 interface.
 * @author Lucas Martín Grasso Ramos <lucasgrassoramos@gmail.com>, Matias Arazi <matiasarazi@gmail.com>
 */

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./IERC5516.sol";

contract ERC5516 is Context, ERC165, IERC5516 {
    // Used as the URI for all token types by relying on ID substitution, e.g. https://ipfs.io/ipfs/token.data
    string private _uri;

    // Mapping from account to token IDs it holds
    mapping(address => mapping(uint256 => bool)) private _holdings;

    // Mapping from token ID to addresses that have renounced and are permanently barred from re-issuance.
    mapping(uint256 => mapping(address => bool)) private _renounced;

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
        require(recipients.length > 0, "ERC5516: Empty recipients list");

        address minter = _msgSender();

        tokenId = _deriveTokenId(minter, metadataURI);

        if (_minters[tokenId] == address(0)) {
            _minters[tokenId] = minter;
            _tokenURIs[tokenId] = metadataURI;
        } else {
            // Re-issuance path: the same `tokenId` already exists.
            //
            // This equality check is defense-in-depth. Because `_deriveTokenId`
            // mixes `msg.sender` into the hash, no other address can produce
            // this `tokenId` via `issue()` in the first place, so the check is
            // structurally redundant for this implementation. It is kept for
            // two reasons:
            //   1. A clearer revert reason than the downstream "Token already
            //      owned" error a wrong caller would otherwise hit.
            //   2. To guard subclasses that introduce additional mint paths
            //      (e.g. a privileged admin mint) from accidentally letting a
            //      non-original issuer overwrite or extend an existing
            //      credential.
            require(
                _minters[tokenId] == minter,
                "ERC5516: Not original issuer"
            );
        }

        for (uint256 i = 0; i < recipients.length; ) {
            address recipient = recipients[i];

            require(
                recipient != address(0),
                "ERC5516: Transfer to address zero"
            );
            require(
                !_holdings[recipient][tokenId],
                "ERC5516: Token already owned"
            );
            require(
                !_renounced[tokenId][recipient],
                "ERC5516: Recipient renounced this token"
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
            "ERC5516: Sender does not own a token under `tokenId`"
        );

        delete _holdings[sender][tokenId];
        _renounced[tokenId][sender] = true;

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
     * @dev See {IERC5516-issuerOf}.
     */
    function issuerOf(
        uint256 tokenId
    ) external view virtual override returns (address) {
        return _minters[tokenId];
    }

    /**
     * @dev See {IERC5516-uri}.
     */
    function uri(
        uint256 tokenId
    ) external view virtual override returns (string memory) {
        require(
            bytes(_tokenURIs[tokenId]).length > 0,
            "ERC5516: Token does not exist"
        );
        return string(abi.encodePacked(_uri, _tokenURIs[tokenId]));
    }

    /**
     * @dev Deterministically derives a token ID from the issuer's address and the metadata URI.
     * @dev See {IERC5516-issue}.
     *
     * @param issuer The address of the token issuer.
     * @param metadataURI The metadata URI associated with the token.
     * @return tokenId The unique identifier of the token derived from the issuer and metadata URI.
     */
    function _deriveTokenId(
        address issuer,
        string calldata metadataURI
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(issuer, metadataURI)));
    }
}
