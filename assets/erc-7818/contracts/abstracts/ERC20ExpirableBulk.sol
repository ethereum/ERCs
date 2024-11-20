// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title Reference implementation of ERC-7818 but in expire in bulk.

import {IERC7818} from "../IERC7818.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract ERC20ExpirableBulk is Context, IERC20Errors, IERC7818 {
    error ERC7818TransferExpired();

    string private _name;
    string private _symbol;
    uint256 private _duration;
    uint256 private _epoch;
    uint256 private _startBlock;

    mapping(address => mapping(uint256 => uint256)) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory name_, string memory symbol_, uint256 duration_) {
        _name = name_;
        _symbol = symbol_;
        _duration = duration_;
        _startBlock = block.number;
    }

    function _calculateEpoch() internal view returns (uint256) {
        uint256 startBlock = _startBlock;
        uint256 blockNumber = block.number;
        if (blockNumber < startBlock) {
            return 0; // No epochs have passed before deployment
        }
        return (blockNumber - startBlock) / _duration;
    }

    function _expired(uint256 id) internal view returns (bool) {
        return id < _calculateEpoch();
    }

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, _calculateEpoch(), value);
    }

    function _mint(address account, uint256 id, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, id, value);
    }

    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, _calculateEpoch(), value);
    }

    function _burn(address account, uint256 id, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, id, value);
    }

    function _update(address from, address to, uint256 id, uint256 value) internal virtual {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            // do nothing.
        } else {
            uint256 fromBalance = _balances[from][id];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                _balances[from][id] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                // do nothing.
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                _balances[to][id]  += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    function _transfer(address from, address to, uint256 id, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, id, value);
    }

    /// @dev See {IERC20Metadata-name}.
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /// @dev See {IERC20Metadata-symbol}.
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /// @dev See {IERC20Metadata-decimals}.
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /// @dev See {IERC20-totalSupply}.
    /// @notice Returns 0 as there is no actual total supply due to token expiration.
    function totalSupply() public pure virtual returns (uint256) {
        return 0;
    }

    /// @notice Returns the available balance of tokens for a given account.
    /// @dev Calculates and returns the available balance based on the frame.
    /// @dev See {IERC20-balanceOf}.
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account][_calculateEpoch()];
    }

    /// @dev See {IERC20-allowance}.
    function allowance(
        address owner,
        address spender
    ) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }

    /// @dev See {IERC20-transfer}.
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address from = _msgSender();
        _transfer(from, to, _calculateEpoch(), value);
        return true;
    }

    /// @dev See {IERC20-transferFrom}.
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, _calculateEpoch(), value);
        return true;
    }

    /// @dev See {IERC20-approve}.
    function approve(
        address spender,
        uint256 value
    ) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    /// @inheritdoc IERC7818
    /// @notice implementation defined `id` with epoch
    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256) {
        if (_expired(id)) {
            return 0;
        }
        return _balances[account][id];
    }

    /// @inheritdoc IERC7818
    /// @notice implementation define duration unit in blocks
    function duration() public view virtual returns (uint256) {
        return _duration;
    }

    /// @inheritdoc IERC7818
    function epoch() public view virtual returns (uint256) {
        return _epoch;
    }

    /// @inheritdoc IERC7818
    /// @notice implementation defined `id` with epoch
    function expired(uint256 id) public view virtual returns (bool) {
        return _expired(id);
    }

    /// @inheritdoc IERC7818
    /// @notice implementation defined `id` with epoch
    function transfer(
        address to,
        uint256 id,
        uint256 value
    ) public override returns (bool) {
        if (_expired(id)) {
            revert ERC7818TransferExpired();
        }
        address owner = _msgSender();
        _transfer(owner, to, id, value);
        return true;
    }

    /// @inheritdoc IERC7818
    /// @notice implementation defined `id` with epoch
    function transferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value
    ) public virtual returns (bool) {
        if (_expired(id)) {
            revert ERC7818TransferExpired();
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, id, value);
        return true;
    }
}
