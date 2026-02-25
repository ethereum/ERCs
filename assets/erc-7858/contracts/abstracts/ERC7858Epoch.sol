// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {SlidingWindow} from "../libraries/SlidingWindow.sol";
import {SortedList} from "../libraries/SortedList.sol";
import {IERC7858} from "../interfaces/IERC7858.sol";
import {IERC7858Epoch} from "../interfaces/IERC7858Epoch.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC165, ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC721Utils} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Utils.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

abstract contract ERC7858Epoch is
    Context,
    ERC165,
    IERC721,
    IERC721Errors,
    IERC721Metadata,
    IERC7858Epoch
{
    using SlidingWindow for SlidingWindow.Window;
    using SortedList for SortedList.List;
    using Strings for uint256;

    string private _name;
    string private _symbol;
    SlidingWindow.Window private _window;

    struct Epoch {
        uint256 totalBalance;
        mapping(uint256 pointer => uint256[]) tokens; // it's possible to contains more than one tokenId.
        mapping(uint256 pointer => mapping(uint256 tokenId => uint256)) tokenIndex;
        SortedList.List list;
    }

    mapping(uint256 tokenId => uint256) private _tokenPointers;
    mapping(uint256 tokenId => address) private _owners;
    mapping(uint256 => mapping(address => Epoch)) private _epochBalances;
    mapping(address => uint256) _balances;
    mapping(uint256 tokenId => address) private _tokenApprovals;
    mapping(address owner => mapping(address operator => bool))
        private _operatorApprovals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint16 blockTime_,
        uint8 windowSize_
    ) {
        _name = name_;
        _symbol = symbol_;
        _window.initializedBlock(block.number);
        _window.initializedState(blockTime_, windowSize_, false);
    }

    /**
     * @dev Returns the owner of the `tokenId`. Does NOT revert if token doesn't exist
     *
     * IMPORTANT: Any overrides to this function that add ownership of tokens not tracked by the
     * core ERC-721 logic MUST be matched with the use of {_increaseBalance} to keep balances
     * consistent with ownership. The invariant to preserve is that for any address `a` the value returned by
     * `balanceOf(a)` must be equal to the number of tokens such that `_ownerOf(tokenId)` is `a`.
     */
    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        return _owners[tokenId];
    }

    function _getApproved(
        uint256 tokenId
    ) internal view virtual returns (address) {
        return _tokenApprovals[tokenId];
    }

    function _computeBalanceOverEpochRange(
        uint256 fromEpoch,
        uint256 toEpoch,
        address account
    ) private view returns (uint256 balance) {
        unchecked {
            for (; fromEpoch <= toEpoch; fromEpoch++) {
                balance += _epochBalances[fromEpoch][account].totalBalance;
            }
        }
    }

    function _computeBalanceAtEpoch(
        uint256 epoch,
        address account,
        uint256 pointer,
        uint256 duration
    ) private view returns (uint256 balance) {
        (uint256 element, ) = _findUnexpiredBalance(
            account,
            epoch,
            pointer,
            duration
        );
        Epoch storage _account = _epochBalances[epoch][account];
        unchecked {
            while (element > 0) {
                balance += _account.tokens[element].length;
                element = _account.list.next(element);
            }
        }
        return balance;
    }

    function _findUnexpiredBalance(
        address account,
        uint256 epoch,
        uint256 pointer,
        uint256 duration
    ) internal view returns (uint256 element, uint256 value) {
        SortedList.List storage list = _epochBalances[epoch][account].list;
        if (list.size() != 0) {
            element = list.head();
            unchecked {
                while (pointer - element >= duration) {
                    if (element == 0) {
                        break;
                    }
                    element = list.next(element);
                }
            }
            value = _epochBalances[epoch][account].tokens[element].length;
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            interfaceId == type(IERC7858).interfaceId ||
            interfaceId == type(IERC7858Epoch).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual {
        if (to == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        // Setting an "auth" arguments enables the `_isAuthorized` check which verifies that the token exists
        // (from != 0). Therefore, it is not needed to verify that the return value is not 0 here.
        address previousOwner = _update(to, tokenId, _msgSender());
        if (previousOwner != from) {
            revert ERC721IncorrectOwner(from, tokenId, previousOwner);
        }
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public virtual {
        transferFrom(from, to, tokenId);
        ERC721Utils.checkOnERC721Received(
            _msgSender(),
            from,
            to,
            tokenId,
            data
        );
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual returns (uint256) {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(address(0));
        }
        return _balances[owner];
    }

    function unexpiredBalanceOf(
        address owner
    ) public view virtual returns (uint256) {
        if (owner == address(0)) {
            revert ERC721InvalidOwner(address(0));
        }
        uint256 pointer = _blockNumberProvider();
        (uint256 fromEpoch, uint256 toEpoch) = _window.safeWindowRange(pointer);
        uint256 balance = _computeBalanceAtEpoch(
            fromEpoch,
            owner,
            pointer,
            _window.blocksInWindow()
        );
        if (fromEpoch == toEpoch) {
            return balance;
        } else {
            fromEpoch += 1;
        }
        balance += _computeBalanceOverEpochRange(fromEpoch, toEpoch, owner);
        return balance;
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return _requireOwned(tokenId);
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual returns (string memory) {
        _requireOwned(tokenId);

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string.concat(baseURI, tokenId.toString())
                : "";
    }

    /**
     * @dev Reverts if the `tokenId` doesn't have a current owner (it hasn't been minted, or it has been burned).
     * Returns the owner.
     *
     * Overrides to ownership logic should be done to {_ownerOf}.
     */
    function _requireOwned(uint256 tokenId) internal view returns (address) {
        address owner = _ownerOf(tokenId);
        if (owner == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
        return owner;
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual {
        _approve(to, tokenId, _msgSender());
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(
        uint256 tokenId
    ) public view virtual returns (address) {
        _requireOwned(tokenId);

        return _getApproved(tokenId);
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(
        address owner,
        address operator
    ) public view virtual returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function _expired(uint256 epoch) internal view returns (bool) {
        unchecked {
            (uint256 fromEpoch, ) = _window.windowRange(_blockNumberProvider());
            if (epoch < fromEpoch) {
                return true;
            }
            return false;
        }
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual returns (address) {
        uint256 tokenPointer = _tokenPointers[tokenId];
        uint256 pointer = tokenPointer;
        address from = _ownerOf(tokenId);
        // if the tokenId is not exist before minting it
        if (to == address(0)) {
            _tokenPointers[tokenId] = 0;
        }
        if (tokenPointer == 0) {
            pointer = _blockNumberProvider(); // current block or timestamp
            tokenPointer = pointer;
            _tokenPointers[tokenId] = pointer;

            emit TokenExpiryUpdated(
                tokenId,
                pointer,
                pointer + _window.blocksInWindow()
            );
        }
        uint256 epoch = _window.epoch(pointer);

        // Perform (optional) operator check
        if (auth != address(0)) {
            _checkAuthorized(from, auth, tokenId);
        }

        Epoch storage _sender = _epochBalances[epoch][from];
        Epoch storage _recipient = _epochBalances[epoch][to];

        // Execute the update
        if (from != address(0)) {
            // Clear approval. No need to re-authorize or emit the Approval event
            _approve(address(0), tokenId, address(0), false);

            unchecked {
                _balances[from] -= 1;
                _sender.totalBalance -= 1;
                _sender.tokenIndex[tokenPointer][
                    _sender.tokens[tokenPointer].length - 1
                ] = _sender.tokenIndex[tokenPointer][tokenId];
                _sender.tokens[tokenPointer].pop();
                _sender.list.remove(tokenPointer);
                delete _sender.tokenIndex[tokenPointer][tokenId];
            }
        }

        if (to != address(0)) {
            unchecked {
                _balances[to] += 1;
                _recipient.totalBalance += 1;
                _recipient.tokens[tokenPointer].push(tokenId);
                _recipient.tokenIndex[tokenPointer][tokenId] =
                    _recipient.tokens[tokenPointer].length -
                    1;
                _recipient.list.insert(tokenPointer);
            }
        }

        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        return from;
    }

    function _isAuthorized(
        address owner,
        address spender,
        uint256 tokenId
    ) internal view virtual returns (bool) {
        return
            spender != address(0) &&
            (owner == spender ||
                isApprovedForAll(owner, spender) ||
                _getApproved(tokenId) == spender);
    }

    function _checkAuthorized(
        address owner,
        address spender,
        uint256 tokenId
    ) internal view virtual {
        if (!_isAuthorized(owner, spender, tokenId)) {
            if (owner == address(0)) {
                revert ERC721NonexistentToken(tokenId);
            } else {
                revert ERC721InsufficientApproval(spender, tokenId);
            }
        }
    }

    function _mint(address account, uint256 tokenId) internal {
        if (account == address(0)) {
            revert ERC721InvalidReceiver(address(0));
        }
        address previousOwner = _update(account, tokenId, address(0));
        if (previousOwner != address(0)) {
            revert ERC721InvalidSender(address(0));
        }
    }

    function _safeMint(address account, uint256 tokenId) internal {
        _safeMint(account, tokenId, "");
    }

    function _safeMint(
        address account,
        uint256 tokenId,
        bytes memory data
    ) internal virtual {
        _mint(account, tokenId);
        ERC721Utils.checkOnERC721Received(
            _msgSender(),
            address(0),
            account,
            tokenId,
            data
        );
    }

    function _burn(uint256 tokenId) internal {
        address previousOwner = _update(address(0), tokenId, address(0));
        if (previousOwner == address(0)) {
            revert ERC721NonexistentToken(tokenId);
        }
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * The `auth` argument is optional. If the value passed is non 0, then this function will check that `auth` is
     * either the owner of the token, or approved to operate on all tokens held by this owner.
     *
     * Emits an {Approval} event.
     *
     * Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.
     */
    function _approve(address to, uint256 tokenId, address auth) internal {
        _approve(to, tokenId, auth, true);
    }

    function _approve(
        address to,
        uint256 tokenId,
        address auth,
        bool emitEvent
    ) internal virtual {
        // Avoid reading the owner unless necessary
        if (emitEvent || auth != address(0)) {
            address owner = _requireOwned(tokenId);

            // We do not use _isAuthorized because single-token approvals should not be able to call approve
            if (
                auth != address(0) &&
                owner != auth &&
                !isApprovedForAll(owner, auth)
            ) {
                revert ERC721InvalidApprover(auth);
            }

            if (emitEvent) {
                emit Approval(owner, to, tokenId);
            }
        }

        _tokenApprovals[tokenId] = to;
    }

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        if (operator == address(0)) {
            revert ERC721InvalidOperator(operator);
        }
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /// @dev See {IERC7858-unexpiredBalanceOfAtEpoch}.
    function unexpiredBalanceOfAtEpoch(
        uint256 epoch,
        address owner
    ) external view returns (uint256) {
        if (isEpochExpired(epoch)) return 0;
        return
            _computeBalanceAtEpoch(
                epoch,
                owner,
                _blockNumberProvider(),
                _window.blocksInWindow()
            );
    }

    /// @dev See {IERC7858-startTime}.
    function startTime(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _tokenPointers[tokenId];
    }

    /// @dev See {IERC7858-endTime}.
    function endTime(uint256 tokenId) external view returns (uint256) {
        _requireOwned(tokenId);
        return _tokenPointers[tokenId] + _window.blocksInWindow();
    }

    /// @dev See {IERC7858-isTokenExpired}.
    function isTokenExpired(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return
            _tokenPointers[tokenId] + _window.blocksInWindow() <=
            _blockNumberProvider();
    }

    /// @dev See {IERC7858-expiryType}.
    function expiryType() public pure virtual returns (EXPIRY_TYPE) {
        return IERC7858.EXPIRY_TYPE.BLOCK_BASED;
    }

    /// @dev See {IERC7858Epoch-currentEpoch}.
    function currentEpoch() public view virtual returns (uint256) {
        return _window.epoch(_blockNumberProvider());
    }

    /// @dev See {IERC7858Epoch-epochLength}.
    function epochLength() public view virtual returns (uint256) {
        return _window.blocksInEpoch();
    }

    /// @dev See {IERC7858Epoch-validityDuration}.
    function validityDuration() public view virtual returns (uint256) {
        return _window.windowSize;
    }

    /// @dev See {IERC7858Epoch-isEpochExpired}.
    function isEpochExpired(uint256 id) public view virtual returns (bool) {
        return _expired(id);
    }

    function _blockNumberProvider() internal view returns (uint256) {
        return block.number;
    }
}
