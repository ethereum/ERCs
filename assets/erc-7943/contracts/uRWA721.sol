// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC7943NonFungible} from "./interfaces/IERC7943.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Utils} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Utils.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title uRWA-721 Token Contract
/// @notice An ERC-721 token implementation adhering to the IERC-7943 interface for Real World Assets.
/// @dev Combines standard ERC-721 functionality with RWA-specific features like whitelisting,
/// controlled minting/burning, asset forced transfers, and freezing. Managed via AccessControl.
contract uRWA721 is Context, ERC721, AccessControlEnumerable, IERC7943NonFungible {
    /// @notice Role identifiers.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant FREEZING_ROLE = keccak256("FREEZING_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    bytes32 public constant FORCE_TRANSFER_ROLE = keccak256("FORCE_TRANSFER_ROLE");  

    /// @notice Mapping storing the whitelist status for each account address.
    /// @dev True indicates the account is whitelisted and allowed to interact, false otherwise.
    mapping(address account => bool whitelisted) internal _whitelist;

    /// @notice Mapping storing the freezing status of assets for each account address.
    /// @dev It gives true or false on whether the `tokenId` is frozen for `account`.
    mapping(address account => mapping(uint256 tokenId => bool frozen)) internal _frozenTokens;

    /// @notice Emitted when an account's whitelist status is changed.
    /// @param account The address whose status was changed.
    /// @param status The new whitelist status (true = whitelisted, false = not whitelisted).
    event Whitelisted(address indexed account, bool status);

    /// @notice Contract constructor.
    /// @dev Initializes the ERC-721 token with name and symbol, and grants all roles
    /// (Admin, Minter, Burner, Freezer, Force Transfer, Whitelist) to the `initialAdmin`.
    /// @param name The name of the token collection.
    /// @param symbol The symbol of the token collection.
    /// @param initialAdmin The address to receive initial administrative and operational roles.
    constructor(string memory name, string memory symbol, address initialAdmin) ERC721(name, symbol) {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MINTER_ROLE, initialAdmin);
        _grantRole(BURNER_ROLE, initialAdmin);
        _grantRole(FREEZING_ROLE, initialAdmin);
        _grantRole(WHITELIST_ROLE, initialAdmin);
        _grantRole(FORCE_TRANSFER_ROLE, initialAdmin);
    }

    /// @inheritdoc IERC7943NonFungible
    function canTransfer(address from, address to, uint256 tokenId) public view virtual override returns (bool allowed) {
        address owner = _ownerOf(tokenId);
        if (owner != from || owner == address(0)) return allowed;
        if (_frozenTokens[from][tokenId]) return allowed;
        if (!canTransact(from) || !canTransact(to)) return allowed;

        allowed = true;
    }

    /// @inheritdoc IERC7943NonFungible
    function canTransact(address account) public view virtual override returns (bool allowed) {
        allowed = _whitelist[account] ? true : false;
    }

    /// @inheritdoc IERC7943NonFungible
    function getFrozenTokens(address account, uint256 tokenId) public virtual override view returns (bool frozenStatus) {
        frozenStatus = _frozenTokens[account][tokenId];
    }

    /// @notice Updates the whitelist status for a given account.
    /// @dev Can only be called by accounts holding the `WHITELIST_ROLE`.
    /// Emits a {Whitelisted} event upon successful update.
    /// @param account The address whose whitelist status is to be changed. Must not be the zero address.
    /// @param status The new whitelist status (true = whitelisted, false = not whitelisted).
    function changeWhitelist(address account, bool status) external virtual onlyRole(WHITELIST_ROLE) {
        _whitelist[account] = status;
        emit Whitelisted(account, status);
    }

    /// @notice Safely creates a new token with `tokenId` and assigns it to `to`.
    /// @dev Can only be called by accounts holding the `MINTER_ROLE`.
    /// Requires `to` to be allowed according to {canTransact} (enforced by the `_update` hook).
    /// Performs an ERC721 receiver check on `to` if it is a contract.
    /// Emits a {Transfer} event with `from` set to the zero address.
    /// @param to The address that will receive the minted token.
    /// @param tokenId The specific token identifier to mint.
    function safeMint(address to, uint256 tokenId) external virtual onlyRole(MINTER_ROLE) {
        _safeMint(to, tokenId);
    }

    /// @notice Destroys the token with `tokenId`.
    /// @dev Can only be called by accounts holding the `BURNER_ROLE`.
    /// Requires the caller (`_msgSender()`) to be the owner or approved for `tokenId`.
    /// Emits a {Transfer} event with `to` set to the zero address.
    /// @param tokenId The specific token identifier to burn. 
    function burn(uint256 tokenId) external virtual onlyRole(BURNER_ROLE) {
        address previousOwner = _update(address(0), tokenId, _msgSender()); 
        if (previousOwner == address(0)) revert ERC721NonexistentToken(tokenId);
    }

    /// @inheritdoc IERC7943NonFungible
    /// @dev Can only be called by accounts holding the `FREEZING_ROLE`
    function setFrozenTokens(address account, uint256 tokenId, bool frozenStatus) public virtual override onlyRole(FREEZING_ROLE) returns(bool result) {        
        _frozenTokens[account][tokenId] = frozenStatus;
        emit Frozen(account, tokenId, frozenStatus);
        result = true;
    }

    /// @inheritdoc IERC7943NonFungible
    /// @dev Can only be called by accounts holding the `FORCE_TRANSFER_ROLE`.
    function forcedTransfer(address from, address to, uint256 tokenId) public virtual override onlyRole(FORCE_TRANSFER_ROLE) returns(bool result) {
        require(to != address(0), ERC721InvalidReceiver(address(0)));
        require(canTransact(to), ERC7943CannotTransact(to));
        require(ownerOf(tokenId) == from, ERC721IncorrectOwner(from, tokenId, ownerOf(tokenId)));
        _excessFrozenUpdate(from , tokenId);
        super._update(to, tokenId, address(0)); // Skip _update override
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, "");
        emit ForcedTransfer(from, to, tokenId);
        result = true;
    }

    /// @notice Unfreezes a token when it's being forcibly transferred or burned.
    /// @dev This function ensures that frozen tokens are automatically unfrozen when subjected to
    /// forced transfers or burns. This maintains consistency in the frozen state since the token
    /// is leaving the account anyway. Only unfreezes if the token was previously frozen.
    /// Emits a {Frozen} event with frozenStatus=false when unfreezing occurs.
    /// @param from The address that currently owns the token.
    /// @param tokenId The ID of the token that may need to be unfrozen.
    function _excessFrozenUpdate(address from, uint256 tokenId) internal {
        if(_frozenTokens[from][tokenId]) {
            delete _frozenTokens[from][tokenId];
            emit Frozen(from, tokenId, false);
        }
    }

    /// @notice Hook that is called during any token transfer, including minting and burning.
    /// @dev Overrides the ERC-721 `_update` hook. Enforces transfer restrictions based on {canTransfer} and {canTransact} logics.
    /// Reverts with {ERC721IncorrectOwner} | {ERC7943FrozenTokenId} | {ERC7943CannotTransact} if any `canTransfer`/`canTransact` or other check fails.
    /// @param to The address receiving tokens (zero address for burning).
    /// @param tokenId The if of the token being transferred.
    /// @param auth The address initiating the transfer.
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns(address) {
        address from = _ownerOf(tokenId);

        if (auth != address(0)) {
            _checkAuthorized(from, auth, tokenId);
        }

        if (from == address(0) && to != address(0)) { // Mint
            require(canTransact(to), ERC7943CannotTransact(to));
        } else if (from != address(0) && to == address(0)) { // Burn
            _excessFrozenUpdate(from, tokenId);
        } else if (from != address(0) && to != address(0)) { // Transfer
            require(from == _ownerOf(tokenId), ERC721IncorrectOwner(from, tokenId, _ownerOf(tokenId)));
            require(!_frozenTokens[from][tokenId], ERC7943FrozenTokenId(from, tokenId));
            require(canTransact(from), ERC7943CannotTransact(from));
            require(canTransact(to), ERC7943CannotTransact(to));
        } else {
            revert ERC721NonexistentToken(tokenId);
        }

        return super._update(to, tokenId, auth);
    }

    /// @notice See {IERC165-supportsInterface}.
    /// @dev Indicates support for the {IERC7943NonFungible} interface in addition to inherited interfaces.
    /// @param interfaceId The interface identifier, as specified in ERC-165.
    /// @return True if the contract implements `interfaceId`, false otherwise.
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC7943NonFungible).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
