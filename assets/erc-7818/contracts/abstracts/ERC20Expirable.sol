// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title Reference implementation of ERC-7818.

import {SCDLL} from "../libraries/SCDLLLib.sol";
import {SW} from "../libraries/SWLib.sol";
import {IERC7818} from "../IERC7818.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract ERC20Expirable is Context, IERC20Errors, IERC7818 {
    using SCDLL for SCDLL.List;
    using SW for SW.State;

    error ERC7818TransferExpired();

    string private _name;
    string private _symbol;
    SW.State private _window;

    /// @notice Struct representing a slot containing balances mapped by blocks.
    struct Slot {
        uint256 slotBalance;
        mapping(uint256 blockNumber => uint256 balance) blockBalances;
        SCDLL.List list;
    }

    mapping(address account => mapping(uint256 era => mapping(uint8 slot => Slot)))
        private _balances;
    mapping(address account => mapping(address spneder => uint256 balance))
        private _allowances;
    mapping(uint256 blockNumber => uint256 balance) private _worldBlockBalances;

    /// @notice Constructor function to initialize the token contract with specified parameters.
    /// @dev Initializes the token contract by setting the name, symbol, and initializing the sliding window parameters.
    /// @param name_ The name of the token.
    /// @param symbol_ The symbol of the token.
    /// @param blockNumber_ The starting block number for the sliding window.
    /// @param blockTime_ The duration of each block in milliseconds..
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 blockNumber_,
        uint16 blockTime_,
        uint8 frameSize_,
        uint8 slotSize_
    ) {
        _name = name_;
        _symbol = symbol_;
        _window._startBlockNumber = blockNumber_ != 0
            ? blockNumber_
            : _blockNumberProvider();
        _updateSlidingWindow(blockTime_, frameSize_, slotSize_);
    }

    /// @notice Allows for  in subsecond blocktime network.
    /// @dev Returns the current block number.
    /// This function can be overridden in derived contracts to provide custom
    /// block number logic, useful in networks with subsecond block times.
    /// @return The current network block number.
    function _blockNumberProvider() internal view virtual returns (uint256) {
        return block.number;
    }

    /// @notice Updates the parameters of the sliding window based on the given block time and frame size.
    /// @dev This function adjusts internal parameters such as blockPerEra, blockPerSlot, and frame sizes
    /// based on the provided blockTime and frameSize. It ensures that block time is within valid limits
    /// and frame size is appropriate for the sliding window. The calculations depend on constants like
    /// YEAR_IN_MILLISECONDS , MINIMUM_BLOCK_TIME_IN_MILLISECONDS , MAXIMUM_BLOCK_TIME_IN_MILLISECONDS ,
    /// MINIMUM_FRAME_SIZE, MAXIMUM_FRAME_SIZE, and SLOT_PER_ERA.
    /// @param blockTime The time duration of each block in milliseconds.
    /// @param frameSize The size of the frame in slots.
    /// @param slotSize The size of the slot per era.
    function _updateSlidingWindow(
        uint24 blockTime,
        uint8 frameSize,
        uint8 slotSize
    ) internal virtual {
        _window.updateSlidingWindow(blockTime, frameSize, slotSize);
    }

    /// @notice Calculates the current era and slot within the sliding window based on the given block number.
    /// @dev This function computes both the era and slot using the provided block number and the sliding
    /// window state parameters such as _startBlockNumber, _blockPerEra, and _slotSize. It delegates era
    /// calculation to the `calculateEra` function and slot calculation to the `calculateSlot` function.
    /// The era represents the number of complete eras that have passed since the sliding window started,
    /// while the slot indicates the specific position within the current era.
    /// @param blockNumber The block number to calculate the era and slot from.
    /// @return era The current era derived from the block number.
    /// @return slot The current slot within the era derived from the block number.
    function _calculateEraAndSlot(
        uint256 blockNumber
    ) internal view virtual returns (uint256 era, uint8 slot) {
        (era, slot) = _window.calculateEraAndSlot(blockNumber);
    }

    /// @notice Determines the sliding window frame based on the provided block number.
    /// @dev This function computes the sliding window frame based on the provided `blockNumber` and the state `self`.
    /// It determines the `toEra` and `toSlot` using `calculateEraAndSlot`, then calculates the block difference
    /// using `_calculateBlockDifferent` to adjust the `blockNumber`. Finally, it computes the `fromEra` and `fromSlot`
    /// using `calculateEraAndSlot` with the adjusted `blockNumber`, completing the determination of the sliding window frame.
    /// @param blockNumber The current block number to calculate the sliding window frame from.
    /// @return fromEra The starting era of the sliding window frame.
    /// @return toEra The ending era of the sliding window frame.
    /// @return fromSlot The starting slot within the starting era of the sliding window frame.
    /// @return toSlot The ending slot within the ending era of the sliding window frame.
    function _frame(
        uint256 blockNumber
    )
        internal
        view
        virtual
        returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot)
    {
        return _window.frame(blockNumber);
    }

    /// @notice Computes a safe frame of eras and slots relative to a given block number.
    /// @dev This function computes a safe frame of eras and slots relative to the provided `blockNumber`.
    /// It first calculates the frame using the `frame` function and then adjusts the result to ensure safe indexing.
    /// @param blockNumber The block number used as a reference point for computing the frame.
    /// @return fromEra The starting era of the safe frame.
    /// @return toEra The ending era of the safe frame.
    /// @return fromSlot The starting slot within the starting era of the safe frame.
    /// @return toSlot The ending slot within the ending era of the safe frame.
    function _safeFrame(
        uint256 blockNumber
    )
        internal
        view
        virtual
        returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot)
    {
        return _window.safeFrame(blockNumber);
    }

    /// @notice Retrieves the number of blocks per era from the sliding window state.
    /// @dev Uses the sliding window state to fetch the blocks per era.
    /// @return The number of blocks per era.
    function _getBlockPerEra() internal view virtual returns (uint40) {
        return _window.getBlockPerEra();
    }

    /// @notice Retrieves the number of blocks per slot from the sliding window state.
    /// @dev Uses the sliding window state to fetch the blocks per slot.
    /// @return The number of blocks per slot.
    function _getBlockPerSlot() internal view virtual returns (uint40) {
        return _window.getBlockPerSlot();
    }

    /// @notice Retrieves the frame size in block length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of block length.
    /// @return The frame size in block length.
    function _getFrameSizeInBlockLength()
        internal
        view
        virtual
        returns (uint40)
    {
        return _window.getFrameSizeInBlockLength();
    }

    /// @notice Retrieves the frame size in era length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of era length.
    /// @return The frame size in era length.
    function _getFrameSizeInEraLength() internal view virtual returns (uint8) {
        return _window.getFrameSizeInEraLength();
    }

    /// @notice Retrieves the frame size in slot length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of slot length.
    /// @return The frame size in slot length.
    function _getFrameSizeInSlotLength() internal view virtual returns (uint8) {
        return _window.getFrameSizeInSlotLength();
    }

    /// @notice Retrieves the number of slots per era from the sliding window state.
    /// @dev This function returns the `_slotSize` attribute from the provided sliding window state `self`,
    /// which represents the number of slots per era in the sliding window configuration.
    /// @return The number of slots per era configured in the sliding window state.
    function _getSlotPerEra() internal view virtual returns (uint8) {
        return _window.getSlotPerEra();
    }

    /// @notice Retrieves the total slot balance for the specified account and era,
    /// iterating through the range of slots from startSlot to endSlot inclusive.
    /// This function reads slot balances stored in a mapping `_balances`.
    /// @dev This function assumes that the provided `startSlot` is less than or equal to `endSlot`.
    /// It calculates the cumulative balance by summing the `slotBalance` of each slot within the specified range.
    /// @param account The address of the account for which the balance is being queried.
    /// @param era The era (time period) from which to retrieve balances.
    /// @param startSlot The starting slot index within the era to retrieve balances.
    /// @param endSlot The ending slot index within the era to retrieve balances.
    /// @return balance The total balance across the specified slots within the era.
    function _slotBalance(
        address account,
        uint256 era,
        uint8 startSlot,
        uint8 endSlot
    ) private view returns (uint256 balance) {
        unchecked {
            for (; startSlot <= endSlot; startSlot++) {
                balance += _balances[account][era][startSlot].slotBalance;
            }
        }
        return balance;
    }

    /// @notice Calculates the total buffered balance within a specific era and slot for the given account,
    /// considering all block balances that have not expired relative to the current block number.
    /// This function iterates through a sorted list of block indices and sums up corresponding balances.
    /// @dev This function is used to determine the total buffered balance for an account within a specific era and slot.
    /// It loops through a sorted list of block indices stored in `_spender.list` and sums up the balances from `_spender.blockBalances`.
    /// @param account The address of the account for which the balance is being calculated.
    /// @param era The era (time period) from which to retrieve balances.
    /// @param slot The specific slot within the era to retrieve balances.
    /// @param blockNumber The current block number for determining balance validity.
    /// @return balance The total buffered balance within the specified era and slot.
    /// @custom:gas-inefficiency This function can consume significant gas due to potentially
    /// iterating through a large array of block indices.
    function _bufferSlotBalance(
        address account,
        uint256 era,
        uint8 slot,
        uint256 blockNumber
    ) private view returns (uint256 balance) {
        Slot storage _spender = _slotOf(account,era,slot);
        uint256 key = _locateUnexpiredBlockBalance(
            _spender.list,
            blockNumber,
            _getFrameSizeInBlockLength()
        );
        while (key > 0) {
            unchecked {
                balance += _spender.blockBalances[key];
            }
            key = _spender.list.next(key);
        }
    }

    /// @notice Optimized to assume fromEra and fromSlot are already buffered, covering
    /// the gap between fromEra and toEra using slotBalance and summing to balance.
    /// @dev Returns the available balance from the given account, eras, and slots.
    /// @param account The address of the account for which the balance is being queried.
    /// @param fromEra The starting era for the balance lookup.
    /// @param toEra The ending era for the balance lookup.
    /// @param fromSlot The starting slot within the starting era for the balance lookup.
    /// @param toSlot The ending slot within the ending era for the balance lookup.
    /// @param blockNumber The current block number.
    /// @return balance The available balance.
    function _lookBackBalance(
        address account,
        uint256 fromEra,
        uint256 toEra,
        uint8 fromSlot,
        uint8 toSlot,
        uint256 blockNumber
    ) private view returns (uint256 balance) {
        unchecked {
            balance = _bufferSlotBalance(
                account,
                fromEra,
                fromSlot,
                blockNumber
            );
            // Go to the next slot. Increase the era if the slot is over the limit.
            uint8 slotSizeCache = _getSlotPerEra();
            fromSlot = (fromSlot + 1) % slotSizeCache;
            if (fromSlot == 0) {
                fromEra++;
            }

            // It is not possible if the fromEra is more than toEra.
            if (fromEra == toEra) {
                balance += _slotBalance(account, fromEra, fromSlot, toSlot);
            } else {
                // Keep it simple stupid first by spliting into 3 part then sum.
                // Part1: calulate balance at fromEra in naive in naive way O(n)
                uint8 maxSlotCache = slotSizeCache - 1;
                balance += _slotBalance(
                    account,
                    fromEra,
                    fromSlot,
                    maxSlotCache
                );
                // Part2: calulate balance betaween fromEra and toEra in naive way O(n)
                for (uint256 era = fromEra + 1; era < toEra; era++) {
                    balance += _slotBalance(account, era, 0, maxSlotCache);
                }
                // Part3:calulate balance at toEra in navie way O(n)
                balance += _slotBalance(account, toEra, 0, toSlot);
            }
        }
    }

    function _expired(uint256 epoch) internal view returns (bool) {
        unchecked {
            if (_blockNumberProvider() - epoch >= _getFrameSizeInBlockLength()) {
                return true;
            }
        }
    }

    /// @notice Internal function to update token balances during token transfers or operations.
    /// @dev Handles various scenarios including minting, burning, and transferring tokens with expiration logic.
    /// @param from The address from which tokens are being transferred (or minted/burned).
    /// @param to The address to which tokens are being transferred (or burned to if `to` is `zero address`).
    /// @param value The amount of tokens being transferred, minted, or burned.
    function _update(address from, address to, uint256 value) internal virtual {
        uint256 blockNumberCache = _blockNumberProvider();
        uint256 blockLengthCache = _getFrameSizeInBlockLength();
        uint8 slotSizeCache = _getSlotPerEra();

        if (from == address(0)) {
            // Mint token.
            (uint256 currentEra, uint8 currentSlot) = _calculateEraAndSlot(
                blockNumberCache
            );
            Slot storage _recipient = _slotOf(to,currentEra,currentSlot);
            unchecked {
                _recipient.slotBalance += value;
                _recipient.blockBalances[blockNumberCache] += value;
            }
            _recipient.list.insert(blockNumberCache, (""));
            _worldBlockBalances[blockNumberCache] += value;
        } else {
            // Burn token.
            (
                uint256 fromEra,
                uint256 toEra,
                uint8 fromSlot,
                uint8 toSlot
            ) = _frame(blockNumberCache);
            uint256 balance = _lookBackBalance(
                from,
                fromEra,
                toEra,
                fromSlot,
                toSlot,
                blockNumberCache
            );
            if (balance < value) {
                revert ERC20InsufficientBalance(from, balance, value);
            }

            uint256 pendingValue = value;
            uint256 balanceCache = 0;

            if (to == address(0)) {
                while (
                    (fromEra < toEra ||
                        (fromEra == toEra && fromSlot <= toSlot)) &&
                    pendingValue > 0
                ) {
                    Slot storage _spender = _slotOf(from,fromEra,fromSlot);

                    uint256 key = _locateUnexpiredBlockBalance(
                        _spender.list,
                        blockNumberCache,
                        blockLengthCache
                    );

                    while (key > 0 && pendingValue > 0) {
                        balanceCache = _spender.blockBalances[key];

                        if (balanceCache <= pendingValue) {
                            unchecked {
                                pendingValue -= balanceCache;
                                _spender.slotBalance -= balanceCache;
                                _spender.blockBalances[key] -= balanceCache;
                                _worldBlockBalances[key] -= balanceCache;
                            }
                            key = _spender.list.next(key);
                            _spender.list.remove(_spender.list.previous(key));
                        } else {
                            unchecked {
                                _spender.slotBalance -= pendingValue;
                                _spender.blockBalances[key] -= pendingValue;
                                _worldBlockBalances[key] -= pendingValue;
                            }
                            pendingValue = 0;
                        }
                    }

                    // Go to the next slot. Increase the era if the slot is over the limit.
                    if (pendingValue > 0) {
                        unchecked {
                            fromSlot = (fromSlot + 1) % slotSizeCache;
                            if (fromSlot == 0) {
                                fromEra++;
                            }
                        }
                    }
                }
            } else {
                // Transfer token.
                while (
                    (fromEra < toEra ||
                        (fromEra == toEra && fromSlot <= toSlot)) &&
                    pendingValue > 0
                ) {
                    Slot storage _spender = _slotOf(from,fromEra,fromSlot);
                    Slot storage _recipient = _slotOf(to,fromEra,fromSlot);

                    uint256 key = _locateUnexpiredBlockBalance(
                        _spender.list,
                        blockNumberCache,
                        blockLengthCache
                    );

                    while (key > 0 && pendingValue > 0) {
                        balanceCache = _spender.blockBalances[key];

                        if (balanceCache <= pendingValue) {
                            unchecked {
                                pendingValue -= balanceCache;
                                _spender.slotBalance -= balanceCache;
                                _spender.blockBalances[key] -= balanceCache;

                                _recipient.slotBalance += balanceCache;
                                _recipient.blockBalances[key] += balanceCache;
                                _recipient.list.insert(key, (""));
                            }
                            key = _spender.list.next(key);
                            _spender.list.remove(_spender.list.previous(key));
                        } else {
                            unchecked {
                                _spender.slotBalance -= pendingValue;
                                _spender.blockBalances[key] -= pendingValue;

                                _recipient.slotBalance += pendingValue;
                                _recipient.blockBalances[key] += pendingValue;
                            }
                            _recipient.list.insert(key, (""));
                            pendingValue = 0;
                        }
                    }

                    // Go to the next slot. Increase the era if the slot is over the limit.
                    if (pendingValue > 0) {
                        unchecked {
                            fromSlot = (fromSlot + 1) % slotSizeCache;
                            if (fromSlot == 0) {
                                fromEra++;
                            }
                        }
                    }
                }
            }
        }

        emit Transfer(from, to, value);
    }

    function _updateSpecific(
        address from,
        address to,
        uint256 id,
        uint256 value
    ) internal virtual {
        (uint256 era, uint8 slot) = _calculateEraAndSlot(id);
        if (from == address(0)) {
            Slot storage _recipient = _balances[to][era][slot];
            unchecked {
                _recipient.slotBalance += value;
                _recipient.blockBalances[id] += value;
            }
            _worldBlockBalances[id] += value;
        } else {
            Slot storage _spender = _slotOf(from,era,slot);
            uint256 balanceCache = _spender.blockBalances[id];
            if (balanceCache < value) {
                revert ERC20InsufficientBalance(from, balanceCache, value);
            }
            if (to == address(0)) {
                _spender.slotBalance -= value;
                _spender.blockBalances[id] -= value;
                _worldBlockBalances[id] -= value;
            } else {
                Slot storage _recipient = _slotOf(to,era,slot);
                _spender.slotBalance -= value;
                _spender.blockBalances[id] -= value;
                _recipient.slotBalance += value;
                _recipient.blockBalances[id] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    /// @notice Retrieves the Slot storage for a given account, era, and slot.
    /// @dev This function accesses the `_balances` mapping to return the Slot associated with the specified account, era, and slot.
    /// @param account The address of the account whose slot is being queried.
    /// @param fromEra The era during which the slot was created or updated.
    /// @param fromSlot The slot identifier within the era for the account.
    /// @return slot The storage reference to the Slot structure for the given account, era, and slot.
    function _slotOf(
        address account,
        uint256 fromEra,
        uint8 fromSlot
    ) internal view returns (Slot storage) {
        return _balances[account][fromEra][fromSlot];
    }

    /// @notice Finds the index of the first valid block balance in a sorted list of block numbers.
    /// A block balance index is considered valid if the difference between the current blockNumber
    /// and the block number at the index (key) is less than the expirationPeriodInBlockLength.
    /// @dev This function is used to determine the first valid block balance index within a sorted circular doubly linked list.
    /// It iterates through the list starting from the head and stops when it finds a valid index or reaches the end of the list.
    /// @param list The sorted circular doubly linked list of block numbers.
    /// @param blockNumber The current block number.
    /// @param expirationPeriodInBlockLength The maximum allowed difference between blockNumber and the key.
    /// @return key The index of the first valid block balance.
    function _locateUnexpiredBlockBalance(
        SCDLL.List storage list,
        uint256 blockNumber,
        uint256 expirationPeriodInBlockLength
    ) internal view returns (uint256 key) {
        key = list.head();
        unchecked {
            while (blockNumber - key >= expirationPeriodInBlockLength) {
                if (key == 0) {
                    break;
                }
                key = list.next(key);
            }
        }
    }

    /// @notice Mints new tokens to a specified account.
    /// @dev This function updates the token balance by minting `value` amount of tokens to the `account`.
    /// Reverts if the `account` address is zero.
    /// @param account The address of the account to receive the minted tokens.
    /// @param value The amount of tokens to be minted.
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }

    /// @notice Burns a specified amount of tokens from an account.
    /// @dev This function updates the token balance by burning `value` amount of tokens from the `account`.
    /// Reverts if the `account` address is zero.
    /// @param account The address of the account from which tokens will be burned.
    /// @param value The amount of tokens to be burned.
    function _burn(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        _update(account, address(0), value);
    }

    /// @notice Spends the specified allowance by reducing the allowance of the spender.
    /// @dev This function deducts the `value` amount from the current allowance of the `spender` by the `owner`.
    /// If the current allowance is less than `value`, the function reverts with an error.
    /// If the current allowance is the maximum `uint256`, the allowance is not reduced.
    /// @param owner The address of the token owner.
    /// @param spender The address of the spender.
    /// @param value The amount of tokens to spend from the allowance.
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

    /// @notice Approves the `spender` to spend `value` tokens on behalf of `owner`.
    /// @dev Calls an overloaded `_approve` function with an additional parameter to emit an event.
    /// @param owner The address of the token owner.
    /// @param spender The address allowed to spend the tokens.
    /// @param value The amount of tokens to be approved for spending.
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }

    /// @notice Approves the specified allowance for the spender on behalf of the owner.
    /// @dev Sets the allowance of the `spender` by the `owner` to `value`.
    /// If `emitEvent` is true, an `Approval` event is emitted.
    /// The function reverts if the `owner` or `spender` address is zero.
    /// @param owner The address of the token owner.
    /// @param spender The address of the spender.
    /// @param value The amount of tokens to allow.
    /// @param emitEvent Boolean flag indicating whether to emit the `Approval` event.
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

    /// @notice Transfers tokens from one address to another.
    /// @dev Moves `value` tokens from `from` to `to`.
    /// The function reverts if the `from` or `to` address is zero.
    /// @param from The address from which the tokens are transferred.
    /// @param to The address to which the tokens are transferred.
    /// @param value The amount of tokens to transfer.
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }

    function _transferSpecific(
        address from,
        address to,
        uint256 id,
        uint256 value
    ) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _updateSpecific(from, to, id, value);
    }

    /// @notice Retrieves the total balance stored at a specific block.
    /// @dev This function returns the balance of the given block from the internal `_worldBlockBalances` mapping.
    /// @param blockNumber The block number for which the balance is being queried.
    /// @return balance The total balance stored at the given block number.
    function getBlockBalance(
        uint256 blockNumber
    ) external view virtual returns (uint256) {
        return _worldBlockBalances[blockNumber];
    }

    /// @custom:gas-inefficiency if not limit the size of array
    function tokenList(
        address account,
        uint256 era,
        uint8 slot
    ) external view virtual returns (uint256[] memory list) {
        list = _balances[account][era][slot].list.ascending();
    }

    function currentEraAndSlot()
        external
        view
        virtual
        returns (uint256 era, uint8 slot)
    {
        (era, slot) = _calculateEraAndSlot(_blockNumberProvider());
    }

    function frame() external view virtual returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot) {
        return _frame(_blockNumberProvider());
    }

    function safeFrame() external view virtual returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot) {
        return _safeFrame(_blockNumberProvider());
    }

    function getBlockPerEra() external view virtual returns (uint40) {
        return _getBlockPerEra();
    }

    function getBlockPerSlot() external view virtual returns (uint40) {
        return _getBlockPerSlot();
    }

    function getFrameSizeInEraLength() external view virtual returns (uint8) {
        return _getFrameSizeInEraLength();
    }

    function getFrameSizeInSlotLength() external view virtual returns (uint8) {
        return _getFrameSizeInSlotLength();
    }

    function getSlotPerEra() external view virtual returns (uint8) {
        return _getSlotPerEra();
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
    /// @dev Calculates and returns the available balance based on the frame.
    /// @dev See {IERC20-balanceOf}.
    function balanceOf(address account) public view virtual returns (uint256) {
        uint256 blockNumberCache = _blockNumberProvider();
        (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot) = _frame(
            blockNumberCache
        );
        return
            _lookBackBalance(
                account,
                fromEra,
                toEra,
                fromSlot,
                toSlot,
                blockNumberCache
            );
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
        address account,
        uint256 epoch
    ) external view returns (uint256) {
        if (_expired(epoch)) {
            return 0;
        }
        (uint256 era, uint8 slot) = _calculateEraAndSlot(epoch);
        return _balances[account][era][slot].blockBalances[epoch];
    }

    /// @inheritdoc IERC7818
    function epochLength() public view virtual returns (uint256) {
        return _getBlockPerEra();
    }

    /// @inheritdoc IERC7818
    function validityPeriod() public view virtual returns (uint256) {
        return _getFrameSizeInBlockLength();
    }

    /// @inheritdoc IERC7818
    function currentEpoch() public view virtual returns (uint256) {
        (uint256 era, ) = _calculateEraAndSlot(_blockNumberProvider());
        return era;
    }

    /// @inheritdoc IERC7818
    function epochType() public pure returns (EPOCH_TYPE) {
        return EPOCH_TYPE.BLOCKS_BASED;
    }

    /// @inheritdoc IERC7818
    function isEpochExpired(uint256 epoch) public view virtual returns (bool) {
        return _expired(epoch);
    }

    /// @inheritdoc IERC7818
    function transferAtEpoch(
        address to,
        uint256 epoch,
        uint256 value
    ) public override returns (bool) {
        if (_expired(epoch)) {
            revert ERC7818TransferExpired();
        }
        address owner = _msgSender();
        _transferSpecific(owner, to, epoch, value);
        return true;
    }

    /// @inheritdoc IERC7818
    /// @notice implementation defined `id` with token id
    function transferFromAtEpoch(
        address from,
        address to,
        uint256 epoch,
        uint256 value
    ) public virtual returns (bool) {
        if (_expired(epoch)) {
            revert ERC7818TransferExpired();
        }
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transferSpecific(from, to, epoch, value);
        return true;
    }
}
