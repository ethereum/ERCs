// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol"; // Import EnumerableSet

contract MultiOwnerNFT is Context, ERC165, IERC721, Ownable {
    using Address for address;
    using EnumerableSet for EnumerableSet.AddressSet; // Use EnumerableSet for address sets

    uint256 private _nextTokenId;

    // Replace array with EnumerableSet for owners
    mapping(uint256 => EnumerableSet.AddressSet) internal _owners;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(address => uint256) private _balances;
    // Mapping to track archived status for each token-owner pair
    mapping(uint256 => mapping(address => bool)) private _archivedStatus;

    // Modifier to check if the owner has archived the token's transfer ability
    modifier isNotArchived(uint256 tokenId, address owner) {
        require(
            !_archivedStatus[tokenId][owner],
            "MO-NFT: Owner's transfer ability is archived for this token"
        );
        _;
    }

    event TokenMinted(uint256 tokenId, address owner);
    event TokenTransferred(uint256 tokenId, address from, address to);
    // Emit an event when the archived status is updated for a specific owner
    event ArchivedStatusUpdated(
        uint256 indexed tokenId,
        address indexed owner,
        bool archived
    );

    constructor(address owner) Ownable(owner) {}

    function mintToken() public onlyOwner returns (uint256) {
        _nextTokenId++;

        // Add the sender to the set of owners for the new token
        _owners[_nextTokenId].add(_msgSender());

        // Increment the balance of the owner
        _balances[_msgSender()] += 1;

        emit TokenMinted(_nextTokenId, _msgSender());
        return _nextTokenId;
    }

    function isOwner(
        uint256 tokenId,
        address account
    ) public view returns (bool) {
        require(_exists(tokenId), "MO-NFT: Token does not exist");

        // Check if the account is in the owners set for the token
        return _owners[tokenId].contains(account);
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId].length() > 0;
    }

    // IERC721 Functions

    function totalSupply() public view returns (uint256) {
        return _nextTokenId;
    }

    function balanceOf(
        address owner
    ) external view override returns (uint256 balance) {
        require(
            owner != address(0),
            "MO-NFT: Balance query for the zero address"
        );

        // Return the balance from the _balances mapping
        return _balances[owner];
    }

    function ownerOf(
        uint256 tokenId
    ) external view override returns (address owner) {
        require(_exists(tokenId), "MO-NFT: Owner query for nonexistent token");

        // Return the first owner in the set (since this is an EnumerableSet, order is not guaranteed)
        return _owners[tokenId].at(0);
    }

    function getOwnersCount(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "MO-NFT: Token does not exist");

        // Return the number of owners for the given tokenId
        return EnumerableSet.length(_owners[tokenId]);
    }

    // Public function to check if a specific owner has archived their transfer ability for a token
    function isArchived(
        uint256 tokenId,
        address owner
    ) external view returns (bool) {
        return _archivedStatus[tokenId][owner];
    }

    // Overrides for approvals
    function approve(address to, uint256 tokenId) public override {
        revert("MO-NFT: approvals not supported");
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override {
        revert("MO-NFT: approvals not supported");
    }

    function getApproved(
        uint256 tokenId
    ) public view override returns (address) {
        revert("MO-NFT: approvals not supported");
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view override returns (bool) {
        revert("MO-NFT: approvals not supported");
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override isNotArchived(tokenId, from) {
        require(
            isOwner(tokenId, _msgSender()),
            "MO-NFT: Transfer from incorrect account"
        );
        require(to != address(0), "MO-NFT: Transfer to the zero address");

        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override isNotArchived(tokenId, from) {
        // 1. Perform the multi-owner transfer logic
        transferFrom(from, to, tokenId);

        // 2. Call the internal function to check if `to` can handle ERC-721 tokens
        require(
            _checkOnERC721Received(from, to, tokenId, ""),
            "MO-NFT: transfer to non ERC721Receiver implementer"
        );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override isNotArchived(tokenId, from) {
        // 1. Perform the multi-owner transfer logic
        transferFrom(from, to, tokenId);

        // 2. Call the internal function to check if `to` can handle ERC-721 tokens
        require(
            _checkOnERC721Received(from, to, tokenId, _data),
            "MO-NFT: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Private helper to call `onERC721Received` on a target contract.
     * Returns true if the target contract returns the correct function selector.
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        // If `to` is not a contract, there's nothing to check.
        if (to.code.length == 0) {
            return true;
        }

        try
            IERC721Receiver(to).onERC721Received(
                msg.sender,
                from,
                tokenId,
                _data
            )
        returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert("MO-NFT: transfer to non ERC721Receiver implementer");
            } else {
                // Bubble up any custom revert reason returned by the contract call
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(
            isOwner(tokenId, from),
            "MO-NFT: Transfer from incorrect owner"
        );
        require(to != address(0), "MO-NFT: Transfer to the zero address");
        require(!isOwner(tokenId, to), "MO-NFT: Recipient is already an owner");

        // Add the new owner to the EnumerableSet
        _owners[tokenId].add(to);

        // Update balances
        _balances[to] += 1;

        emit TokenTransferred(tokenId, from, to);
    }

    // Function to update the archived status for a specific owner of a token (permanent change)
    function archive(uint256 tokenId) external {
        require(
            isOwner(tokenId, msg.sender),
            "MO-NFT: Caller is not the owner of this token"
        );
        // Once archived, the status cannot be reversed
        require(
            _archivedStatus[tokenId][msg.sender] == false,
            "MO-NFT: Token can only be archived once for an owner"
        );
        _archivedStatus[tokenId][msg.sender] = true;
        emit ArchivedStatusUpdated(tokenId, msg.sender, archived);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
