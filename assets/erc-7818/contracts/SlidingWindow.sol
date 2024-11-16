// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {SlidingWindow as slidingwindow} from "./libraries/SlidingWindowLib.sol";

abstract contract SlidingWindow {
    using slidingwindow for slidingwindow.State;

    slidingwindow.State private _slidingWindow;

    /// @notice Constructs the Sliding Window Contract with the initial parameters.
    /// @dev Initializes the sliding window with the provided parameters.
    /// If `blockNumber_` is zero, the current block number is fetched using `_blockNumberProvider()`.
    /// @param blockNumber_ The initial block number for the sliding window. If zero, the current block number is used.
    /// @param blockTime_ The block time to be used for the sliding window.
    /// @param frameSize_ The frame size for the sliding window.
    /// @param slotSize_ The slot size for the sliding window.
    constructor(uint256 blockNumber_, uint16 blockTime_, uint8 frameSize_, uint8 slotSize_) {
        _slidingWindow._startBlockNumber = blockNumber_ != 0 ? blockNumber_ : _blockNumberProvider();
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
    function _updateSlidingWindow(uint24 blockTime, uint8 frameSize, uint8 slotSize) internal virtual {
        _slidingWindow.updateSlidingWindow(blockTime, frameSize, slotSize);
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
    function _calculateEraAndSlot(uint256 blockNumber) internal view virtual returns (uint256 era, uint8 slot) {
        (era, slot) = _slidingWindow.calculateEraAndSlot(blockNumber);
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
    ) internal view virtual returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot) {
        return _slidingWindow.frame(blockNumber);
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
    ) internal view virtual returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot) {
        return _slidingWindow.safeFrame(blockNumber);
    }

    /// @notice Retrieves the number of blocks per era from the sliding window state.
    /// @dev Uses the sliding window state to fetch the blocks per era.
    /// @return The number of blocks per era.
    function _getBlockPerEra() internal view virtual returns (uint40) {
        return _slidingWindow.getBlockPerEra();
    }

    /// @notice Retrieves the number of blocks per slot from the sliding window state.
    /// @dev Uses the sliding window state to fetch the blocks per slot.
    /// @return The number of blocks per slot.
    function _getBlockPerSlot() internal view virtual returns (uint40) {
        return _slidingWindow.getBlockPerSlot();
    }

    /// @notice Retrieves the frame size in block length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of block length.
    /// @return The frame size in block length.
    function _getFrameSizeInBlockLength() internal view virtual returns (uint40) {
        return _slidingWindow.getFrameSizeInBlockLength();
    }

    /// @notice Retrieves the frame size in era length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of era length.
    /// @return The frame size in era length.
    function _getFrameSizeInEraLength() internal view virtual returns (uint8) {
        return _slidingWindow.getFrameSizeInEraLength();
    }

    /// @notice Retrieves the frame size in slot length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of slot length.
    /// @return The frame size in slot length.
    function _getFrameSizeInSlotLength() internal view virtual returns (uint8) {
        return _slidingWindow.getFrameSizeInSlotLength();
    }

    /// @notice Retrieves the frame size in era and slot length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of era and slot length.
    /// @return An array containing frame size in era and slot length.
    function _getFrameSizeInEraAndSlotLength() internal view virtual returns (uint8[2] memory) {
        return _slidingWindow.getFrameSizeInEraAndSlotLength();
    }

    /// @notice Retrieves the number of slots per era from the sliding window state.
    /// @dev This function returns the `_slotSize` attribute from the provided sliding window state `self`,
    /// which represents the number of slots per era in the sliding window configuration.
    /// @return The number of slots per era configured in the sliding window state.
    function _getSlotPerEra() internal view virtual returns (uint8) {
        return _slidingWindow.getSlotPerEra();
    }

    function currentEraAndSlot() external view virtual returns (uint256 era, uint8 slot) {
        return _calculateEraAndSlot(_blockNumberProvider());
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

    function getFrameSizeInBlockLength() external view virtual returns (uint40) {
        return _getFrameSizeInBlockLength();
    }

    function getFrameSizeInEraLength() external view virtual returns (uint8) {
        return _getFrameSizeInEraLength();
    }

    function getFrameSizeInSlotLength() external view virtual returns (uint8) {
        return _getFrameSizeInSlotLength();
    }

    function getFrameSizeInEraAndSlotLength() external view virtual returns (uint8[2] memory) {
        return _getFrameSizeInEraAndSlotLength();
    }

    function getSlotPerEra() external view virtual returns (uint8) {
        return _getSlotPerEra();
    }
}