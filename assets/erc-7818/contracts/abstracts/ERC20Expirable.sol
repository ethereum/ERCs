// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title Reference implementation of ERC-7818.

import {SortedList} from "../libraries/SortedList.sol";
import {SlidingWindow} from "../libraries/SlidingWindow.sol";
import {IERC7818} from "../IERC7818.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract ERC20Expirable is Context, IERC20Errors, IERC7818 {
    using SortedList for SortedList.List;
    using SlidingWindow for SlidingWindow.Window;

    error ERC7818TransferredExpiredToken();
    error ERC7818InvalidEpoch();

    string private _name;
    string private _symbol;
    SlidingWindow.Window private _window;

    struct Epoch {
        uint256 totalBalance;
        mapping(uint256 => uint256) balances;
        SortedList.List list;
    }

    mapping(uint256 => mapping(address => Epoch)) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(uint256 => uint256) private _worldStateBalances;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 blockNumber_,
        uint40 blockTime_,
        uint8 windowSize_,
        bool development_
    ) {
        _name = name_;
        _symbol = symbol_;
        _window.initialBlockNumber = (
            blockNumber_ != 0 ? blockNumber_ : _blockNumberProvider()
        );
        _window.initializedState(blockTime_, windowSize_, development_);
    }

    function _blockNumberProvider() internal view virtual returns (uint256) {
        return block.number;
    }

    function _computeBalanceOverEpochRange(
        uint256 fromEpoch,
        uint256 toEpoch,
        address account
    ) private view returns (uint256 balance) {
        unchecked {
            for (; fromEpoch <= toEpoch; fromEpoch++) {
                balance += _balances[fromEpoch][account].totalBalance;
            }
        }
    }

    function _computeBalanceAtEpoch(
        uint256 epoch,
        address account,
        uint256 blockNumber,
        uint256 duration
    ) private view returns (uint256 balance) {
        uint256 element = _findValidBalance(
            account,
            epoch,
            blockNumber,
            duration
        );
        Epoch storage _account = _balances[epoch][account];
        unchecked {
            while (element > 0) {
                balance += _account.balances[element];
                element = _account.list.next(element);
            }
        }
        return balance;
    }

    function _findValidBalance(
        address account,
        uint256 epoch,
        uint256 blockNumber,
        uint256 duration
    ) private view returns (uint256 element) {
        SortedList.List storage list = _balances[epoch][account].list;
        element = list.head();
        unchecked {
            while (blockNumber - element >= duration) {
                if (element == 0) {
                    break;
                }
                element = list.next(element);
            }
        }
    }

    function _refreshBalanceAtEpoch(
        address account,
        uint256 epoch,
        uint256 blockNumber,
        uint256 duration
    ) private {
        Epoch storage _account = _balances[epoch][account];
        if (_account.list.size() > 0) {
            uint256 element = _account.list.head();
            uint256 balance;
            unchecked {
                while (blockNumber - element >= duration) {
                    if (element == 0) {
                        break;
                    }
                    balance += _account.balances[element];
                    element = _account.list.next(element);
                }
            }
            if (balance > 0) {
                _account.list.shrink(element);
                _account.totalBalance -= balance;
            }
        }
    }

    function _expired(uint256 epoch) internal view returns (bool) {
        unchecked {
            (uint256 fromEpoch, ) = _window.safeWindowRange(
                _blockNumberProvider()
            );
            if (epoch < fromEpoch) {
                return true;
            }
        }
    }

    function _update(
        uint256 blockNumber,
        address from,
        address to,
        uint256 value
    ) private {
        if (from == address(0)) {
            // mint token to current epoch.
            uint256 epoch = _window.epoch(blockNumber);
            Epoch storage _recipient = _balances[epoch][to];
            unchecked {
                _recipient.totalBalance += value;
                _recipient.balances[blockNumber] += value;
                _worldStateBalances[blockNumber] += value;
            }
            _recipient.list.insert(blockNumber);
        } else {
            uint256 blockLengthCache = _window.blocksInWindow();
            (uint256 fromEpoch, uint256 toEpoch) = _window.safeWindowRange(
                blockNumber
            );
            _refreshBalanceAtEpoch(
                from,
                fromEpoch,
                blockNumber,
                blockLengthCache
            );
            uint256 balance = _computeBalanceOverEpochRange(
                fromEpoch,
                toEpoch,
                from
            );
            if (balance < value) {
                revert ERC20InsufficientBalance(from, balance, value);
            }
            uint256 pendingValue = value;
            if (to == address(0)) {
                // burn token from
                while (fromEpoch <= toEpoch && pendingValue > 0) {
                    Epoch storage _spender = _balances[fromEpoch][from];
                    uint256 element = _spender.list.head();
                    while (element > 0 && pendingValue > 0) {
                        balance = _spender.balances[element];
                        if (balance <= pendingValue) {
                            unchecked {
                                pendingValue -= balance;
                                _spender.totalBalance -= balance;
                                _spender.balances[element] -= balance;
                                _worldStateBalances[element] -= balance;
                            }
                            element = _spender.list.next(element);
                            _spender.list.remove(
                                _spender.list.previous(element)
                            );
                        } else {
                            unchecked {
                                _spender.totalBalance -= pendingValue;
                                _spender.balances[element] -= pendingValue;
                                _worldStateBalances[element] -= pendingValue;
                            }
                            pendingValue = 0;
                        }
                    }
                    if (pendingValue > 0) {
                        fromEpoch++;
                    }
                }
            } else {
                // Transfer token.
                while (fromEpoch <= toEpoch && pendingValue > 0) {
                    Epoch storage _spender = _balances[fromEpoch][from];
                    Epoch storage _recipient = _balances[fromEpoch][to];
                    uint256 element = _spender.list.head();
                    while (element > 0 && pendingValue > 0) {
                        balance = _spender.balances[element];
                        if (balance <= pendingValue) {
                            unchecked {
                                pendingValue -= balance;
                                _spender.totalBalance -= balance;
                                _spender.balances[element] -= balance;
                                _recipient.totalBalance += balance;
                                _recipient.balances[element] += balance;
                            }
                            _recipient.list.insert(element);
                            element = _spender.list.next(element);
                            _spender.list.remove(
                                _spender.list.previous(element)
                            );
                        } else {
                            unchecked {
                                _spender.totalBalance -= pendingValue;
                                _spender.balances[element] -= pendingValue;
                                _recipient.totalBalance += pendingValue;
                                _recipient.balances[element] += pendingValue;
                            }
                            _recipient.list.insert(element);
                            pendingValue = 0;
                        }
                    }
                    if (pendingValue > 0) {
                        fromEpoch++;
                    }
                }
            }
        }

        emit Transfer(from, to, value);
    }

    function _update(address from, address to, uint256 value) internal virtual {
        _update(_blockNumberProvider(), from, to, value);
    }

    /// @notice in this implementation not allowing to mint/burn token from past epoch and future epoch
    function _updateAtEpoch(
        uint256 epoch,
        address from,
        address to,
        uint256 value
    ) internal virtual {
        uint256 blockNumber = _blockNumberProvider();
        (uint256 fromEpoch, uint256 toEpoch) = _window.safeWindowRange(
            blockNumber
        );
        if (epoch == toEpoch) {
            _update(blockNumber, from, to, value);
        } else if (epoch >= fromEpoch && epoch < toEpoch) {
            blockNumber = _balances[epoch][from].list.head();
            _update(blockNumber, from, to, value);
        } else {
            revert ERC7818InvalidEpoch();
        }
        emit Transfer(from, to, value);
    }

    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 value
    ) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(
                    spender,
                    currentAllowance,
                    value
                );
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }

    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value,
        bool emitEvent
    ) internal {
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

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    function _transferAtEpoch(
        uint256 epoch,
        address from,
        address to,
        uint256 value
    ) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _updateAtEpoch(epoch, from, to, value);
    }

    function getBlockBalance(
        uint256 blockNumber
    ) external view virtual returns (uint256) {
        return _worldStateBalances[blockNumber];
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

    /// @notice Returns 0 as there is no actual total supply due to token expiration.
    /// @dev This function returns the total supply of tokens, which is constant and set to 0.
    /// @dev See {IERC20-totalSupply}.
    function totalSupply() public pure virtual returns (uint256) {
        return 0;
    }

    /// @notice Returns the available balance of tokens for a given account.
    /// @dev Calculates and returns the available balance based on the sliding window.
    /// @dev See {IERC20-balanceOf}.
    function balanceOf(address account) public view virtual returns (uint256) {
        uint256 blockNumber = _blockNumberProvider();
        (uint256 fromEpoch, uint256 toEpoch) = _window.safeWindowRange(
            blockNumber
        );
        uint256 balance = _computeBalanceAtEpoch(
            fromEpoch,
            account,
            blockNumber,
            _window.blocksInWindow()
        );
        if (fromEpoch == toEpoch) {
            return balance;
        }
        if (fromEpoch < toEpoch) {
            fromEpoch += 1;
        }
        balance += _computeBalanceOverEpochRange(fromEpoch, toEpoch, account);
        return balance;
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
        _transfer(from, to, value);
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
        _transfer(from, to, value);
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
    function balanceOfAtEpoch(
        uint256 epoch,
        address account
    ) external view returns (uint256) {
        uint256 blockNumber = _blockNumberProvider();
        (uint256 fromEpoch, uint256 toEpoch) = _window.safeWindowRange(
            blockNumber
        );
        if (epoch < fromEpoch || epoch > toEpoch) {
            return 0;
        }
        if (epoch == fromEpoch) {
            return
                _computeBalanceAtEpoch(
                    epoch,
                    account,
                    blockNumber,
                    _window.blocksInWindow()
                );
        }
        return _balances[epoch][account].totalBalance;
    }

    /// @inheritdoc IERC7818
    function currentEpoch() public view virtual returns (uint256) {
        return _window.epoch(_blockNumberProvider());
    }

    /// @inheritdoc IERC7818
    function epochLength() public view virtual returns (uint256) {
        return _window.blocksInEpoch();
    }

    /// @inheritdoc IERC7818
    /// @dev unit in number of blocks.
    function epochType() public pure returns (EPOCH_TYPE) {
        return IERC7818.EPOCH_TYPE.BLOCKS_BASED;
    }

    /// @inheritdoc IERC7818
    function validityDuration() public view virtual returns (uint256) {
        return _window.windowSize;
    }

    /// @inheritdoc IERC7818
    function isEpochExpired(uint256 id) public view virtual returns (bool) {
        return _expired(id);
    }

    /// @inheritdoc IERC7818
    function transferAtEpoch(
        uint256 epoch,
        address to,
        uint256 value
    ) public virtual returns (bool) {
        if (_expired(epoch)) {
            revert ERC7818TransferredExpiredToken();
        }
        address owner = _msgSender();
        _transferAtEpoch(epoch, owner, to, value);
        return true;
    }

    /// @inheritdoc IERC7818
    function transferFromAtEpoch(
        uint256 epoch,
        address from,
        address to,
        uint256 value
    ) public virtual returns (bool) {
        if (_expired(epoch)) {
            revert ERC7818TransferredExpiredToken();
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transferAtEpoch(epoch, from, to, value);
        return true;
    }
}
