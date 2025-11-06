// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC7943MultiToken} from "./interfaces/IERC7943.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Utils} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Utils.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";

/// @title uRWA-1155 Token Contract
/// @notice An ERC-1155 token implementation adhering to the IERC-7943 interface for Real World Assets.
/// @dev Combines standard ERC-1155 functionality with RWA-specific features like whitelisting,
/// controlled minting/burning, asset forced transfers and freezing. Managed via AccessControl.
contract uRWA1155 is Context, ERC1155, AccessControlEnumerable, IERC7943MultiToken {
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
    /// @dev It gives the amount of tokens corresponding to a `tokenId` that are frozen in `account` wallet.
    mapping(address account => mapping(uint256 tokenId => uint256 amount)) internal _frozenTokens;

    /// @notice Emitted when an account's whitelist status is changed.
    /// @param account The address whose status was changed.
    /// @param status The new whitelist status (true = whitelisted, false = not whitelisted).
    event Whitelisted(address indexed account, bool status);

    /// @notice Contract constructor.
    /// @dev Initializes the ERC-1155 token with a URI and grants all roles
    /// (Admin, Minter, Burner, Freezer, Force Transfer, Whitelist) to the `initialAdmin`.
    /// @param uri The URI for the token metadata.
    /// @param initialAdmin The address to receive initial administrative and operational roles.
    constructor(string memory uri, address initialAdmin) ERC1155(uri) {
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(MINTER_ROLE, initialAdmin);
        _grantRole(BURNER_ROLE, initialAdmin);
        _grantRole(FREEZING_ROLE, initialAdmin);
        _grantRole(WHITELIST_ROLE, initialAdmin);
        _grantRole(FORCE_TRANSFER_ROLE, initialAdmin);
    }

    /// @inheritdoc IERC7943MultiToken
    function canTransfer(address from, address to, uint256 tokenId, uint256 amount) public view virtual override returns (bool allowed) {
        uint256 fromBalance = balanceOf(from, tokenId);
        if (fromBalance < _frozenTokens[from][tokenId]) return allowed;
        if (amount > fromBalance - _frozenTokens[from][tokenId]) return allowed;
        if (!canTransact(from) || !canTransact(to)) return allowed;
        allowed = true;
    }

    /// @inheritdoc IERC7943MultiToken
    function canTransact(address account) public view virtual override returns (bool allowed) {
        allowed = _whitelist[account] ? true : false;
    }

    /// @inheritdoc IERC7943MultiToken
    function getFrozenTokens(address account, uint256 tokenId) external view returns (uint256 amount) {
        amount = _frozenTokens[account][tokenId];
    }

    /// @notice Updates the whitelist status for a given account.
    /// @dev Can only be called by accounts holding the `WHITELIST_ROLE`.
    /// Emits a {Whitelisted} event upon successful update.
    /// @param account The address whose whitelist status is to be changed.
    /// @param status The new whitelist status (true = whitelisted, false = not whitelisted).
    function changeWhitelist(address account, bool status) external onlyRole(WHITELIST_ROLE) {
        _whitelist[account] = status;
        emit Whitelisted(account, status);
    }

    /// @notice Safely creates `amount` new tokens of `id` and assigns them to `to`.
    /// @dev Can only be called by accounts holding the `MINTER_ROLE`.
    /// Requires `to` to be allowed according to {canTransact}.
    /// Emits a {TransferSingle} event with `operator` set to the caller.
    /// @param to The address that will receive the minted tokens.
    /// @param id The ID of the token to mint.
    /// @param amount The amount of tokens to mint.
    function mint(address to, uint256 id, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, id, amount, "");
    }

    /// @notice Destroys `amount` tokens of `id` from the caller's account.
    /// @dev Can only be called by accounts holding the `BURNER_ROLE`.
    /// Emits a {TransferSingle} event with `to` set to the zero address.
    /// @param id The ID of the token to burn.
    /// @param amount The amount of tokens to burn.
    function burn(uint256 id, uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(_msgSender(), id, amount);
    }

    /// @inheritdoc IERC7943MultiToken
    /// @dev Can only be called by accounts holding the `FREEZING_ROLE`
    function setFrozenTokens(address account, uint256 tokenId, uint256 amount) public onlyRole(FREEZING_ROLE) returns(bool result) {        
        _frozenTokens[account][tokenId] = amount;        
        emit Frozen(account, tokenId, amount);
        result = true;
    }

    /// @inheritdoc IERC7943MultiToken
    /// @dev Can only be called by accounts holding the `FORCE_TRANSFER_ROLE`.
    function forcedTransfer(address from, address to, uint256 tokenId, uint256 amount) public onlyRole(FORCE_TRANSFER_ROLE) returns(bool result) {
        require(canTransact(to), ERC7943CannotTransact(to));

        // Reimplementing _safeTransferFrom to avoid the check on _update
        if (to == address(0)) {
            revert ERC1155InvalidReceiver(address(0));
        }
        if (from == address(0)) {
            revert ERC1155InvalidSender(address(0));
        }

        _excessFrozenUpdate(from, tokenId, amount);

        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        ids[0] = tokenId;
        values[0] = amount;

        super._update(from, to, ids, values);
        
        if (to != address(0)) {
            address operator = _msgSender();
            if (ids.length == 1) {
                uint256 id = ids[0];
                uint256 value = values[0];
                ERC1155Utils.checkOnERC1155Received(operator, from, to, id, value, "");
            } else {
                ERC1155Utils.checkOnERC1155BatchReceived(operator, from, to, ids, values, "");
            }
        } 

        emit ForcedTransfer(from, to, tokenId, amount);
        result = true;
    }

    /// @notice Updates frozen token amount when a forced transfer or burn exceeds the unfrozen balance.
    /// @dev This function reduces the frozen token amount to ensure consistency when tokens are forcibly
    /// moved or burned beyond the unfrozen balance. Emits a {Frozen} event when frozen amount is reduced.
    /// @param account The address whose frozen tokens may need adjustment.
    /// @param tokenId The ID of the token being transferred or burned.
    /// @param amount The amount being forcibly transferred or burned.
    function _excessFrozenUpdate(address account, uint256 tokenId, uint256 amount) internal {
        uint256 unfrozenBalance = _unfrozenBalance(account, tokenId);
        if(amount > unfrozenBalance && amount <= balanceOf(account, tokenId)) { 
            _frozenTokens[account][tokenId] -= amount - unfrozenBalance;
            emit Frozen(account, tokenId, _frozenTokens[account][tokenId]);
        }
    }

    /// @notice Calculates the unfrozen token balance for an account.
    /// @dev Returns the amount of tokens that are available for transfer, which is the total balance
    /// minus the frozen amount. If frozen tokens exceed the balance, returns 0 to prevent underflow.
    /// This is a helper function used throughout the contract for transfer validation.
    /// @param account The address to calculate unfrozen balance for
    /// @param tokenId The ID of the token to check
    /// @return unfrozenBalance The amount of tokens available for transfer.
    function _unfrozenBalance(address account, uint256 tokenId) internal view returns(uint256 unfrozenBalance) {
        unfrozenBalance = balanceOf(account, tokenId) < _frozenTokens[account][tokenId] ? 0 : balanceOf(account, tokenId) - _frozenTokens[account][tokenId];
    }

    /// @notice Hook that is called before any token transfer, including minting and burning.
    /// @dev Overrides the ERC-1155 `_update` hook. Enforces transfer restrictions based on {canTransfer} and {canTransact} logic.
    /// Reverts with {ERC7943CannotTransact} | {ERC7943InsufficientUnfrozenBalance} | {ERC1155InsufficientBalance} 
    /// if any `canTransfer`/`canTransact` or other check fails.
    /// @param from The address sending tokens (zero address for minting).
    /// @param to The address receiving tokens (zero address for burning).
    /// @param ids The array of ids.
    /// @param values The array of amounts being transferred.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {
        if (ids.length != values.length) {
            revert ERC1155InvalidArrayLength(ids.length, values.length);
        }

        if (from != address(0) && to != address(0)) { // Transfer
            for (uint256 i = 0; i < ids.length; ++i) {
                uint256 id = ids[i];
                uint256 value = values[i];
                uint256 unfrozenBalance = _unfrozenBalance(from, id);

                require(value <= balanceOf(from, id), ERC1155InsufficientBalance(from, balanceOf(from, id), value, id));
                require(value <= unfrozenBalance, ERC7943InsufficientUnfrozenBalance(from, id, value, unfrozenBalance));
                require(canTransact(from), ERC7943CannotTransact(from));
                require(canTransact(to), ERC7943CannotTransact(to));
            }
        } else if (from == address(0) && to != address(0)) { // Mint
            require(canTransact(to), ERC7943CannotTransact(to));
        } else if (to == address(0)) { // Burn
            for (uint256 j = 0; j < ids.length; ++j) {
                _excessFrozenUpdate(from, ids[j], values[j]);
            }
        }

        super._update(from, to, ids, values);
    }

    /// @notice See {IERC165-supportsInterface}.
    /// @dev Indicates support for the {IERC7943MultiToken} interface in addition to inherited interfaces.
    /// @param interfaceId The interface identifier, as specified in ERC-165.
    /// @return True if the contract implements `interfaceId`, false otherwise.
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IERC7943MultiToken).interfaceId ||
               super.supportsInterface(interfaceId);
    }
}
