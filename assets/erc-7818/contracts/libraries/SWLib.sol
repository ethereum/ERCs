// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title An implemation sliding window algorithm in Solidity, the sliding frame relying on block-height rather than block-timestmap.
/// @dev This library designed to compatible with subsecond blocktime on both Layer 1 Network (L1) and Layer 2 Network (L2).
// inspiration: 
// https://github.com/stonecoldpat/slidingwindow

library SW {
    uint8 private constant MINIMUM_SLOT_PER_ERA = 1;
    uint8 private constant MAXIMUM_SLOT_PER_ERA = 12;
    uint8 private constant MINIMUM_FRAME_SIZE = 1;
    uint8 private constant MAXIMUM_FRAME_SIZE = 64;
    uint8 private constant MINIMUM_BLOCK_TIME_IN_MILLISECONDS = 100;
    uint24 private constant MAXIMUM_BLOCK_TIME_IN_MILLISECONDS = 600_000;
    uint40 private constant YEAR_IN_MILLISECONDS = 31_556_926_000;

    struct State {
        uint40 _blockPerEra;
        uint40 _blockPerSlot;
        uint40 _frameSizeInBlockLength;
        uint8[2] _frameSizeInEraAndSlotLength;
        uint8 _slotSize;
        uint256 _startBlockNumber;
    }

    error InvalidBlockTime();
    error InvalidFrameSize();
    error InvalidSlotPerEra();

    /// @notice Calculates the difference between the current block number and the start of the sliding window frame.
    /// @dev This function computes the difference in blocks between the current block number and the start of
    /// the sliding window frame, as defined by `_frameSizeInBlockLength` in the sliding window state `self`.
    /// It checks if the `blockNumber` is greater than or equal to `_frameSizeInBlockLength`. If true, it calculates
    /// the difference; otherwise, it returns zero blocks indicating the block number is within the sliding window frame.
    /// @param self The sliding window state to use for calculations.
    /// @param blockNumber The current block number to calculate the difference from.
    /// @return blocks The difference in blocks between the current block and the start of the sliding window frame.
    function _calculateBlockDifferent(
        State storage self,
        uint256 blockNumber
    ) private view returns (uint256 blocks) {
        uint256 frameSizeInBlockLengthCache = self._frameSizeInBlockLength;
        unchecked {
            if (blockNumber >= frameSizeInBlockLengthCache) {
                // If the current block is beyond the expiration period
                blocks = blockNumber - frameSizeInBlockLengthCache;
            }
        }
    }

    /// @notice Calculates the era based on the provided block number and sliding window state.
    /// @dev Computes the era by determining the difference between the current block number and the start block number,
    /// then dividing this difference by the number of blocks per era. Uses unchecked arithmetic for performance considerations.
    /// @param self The sliding window state.
    /// @param blockNumber The block number for which to calculate the era.
    /// @return era corresponding to the given block number.
    function _calculateEra(State storage self, uint256 blockNumber) private view returns (uint256 era) {
        unchecked {
            uint256 startblockNumberCache = self._startBlockNumber;
            // Calculate era based on the difference between the current block and start block
            if (startblockNumberCache > 0 && blockNumber > startblockNumberCache) {
                era = (blockNumber - startblockNumberCache) / self._blockPerEra;
            }
        }
    }

    /// @notice Calculates the slot based on the provided block number and sliding window state.
    /// @dev Computes the slot by determining the difference between the current block number and the
    /// start block number, then mapping this difference to a slot based on the number of blocks per era
    /// and slot size. Uses unchecked arithmetic for performance considerations.
    /// @param self The sliding window state.
    /// @param blockNumber The block number for which to calculate the slot.
    /// @return slot corresponding to the given block number.
    function _calculateSlot(State storage self, uint256 blockNumber) private view returns (uint8 slot) {
        unchecked {
            uint256 startblockNumberCache = self._startBlockNumber;
            uint40 blockPerYearCache = self._blockPerEra;
            if (blockNumber > startblockNumberCache) {
                slot = uint8(
                    ((blockNumber - startblockNumberCache) % blockPerYearCache) / (blockPerYearCache / self._slotSize)
                );
            }
        }
    }

    /// @notice Adjusts the block number to handle buffer operations within the sliding window.
    /// @dev The adjustment is based on the number of blocks per slot. If the current block number
    /// is greater than the number of blocks per slot, it subtracts the block per slot from
    /// the block number to obtain the adjusted block number.
    /// @param self The sliding window state.
    /// @param blockNumber The current block number.
    /// @return Updated block number after adjustment.
    function _frameBuffer(State storage self, uint256 blockNumber) private view returns (uint256) {
        unchecked {
            uint256 blockPerSlotCache = self._blockPerSlot;
            if (blockNumber > blockPerSlotCache) {
                blockNumber = blockNumber - blockPerSlotCache;
            }
        }
        return blockNumber;
    }

    /// @notice Updates the parameters of the sliding window based on the given block time and frame size.
    /// @dev This function adjusts internal parameters such as blockPerEra, blockPerSlot, and frame sizes
    /// based on the provided blockTime and frameSize. It ensures that block time is within valid limits
    /// and frame size is appropriate for the sliding window. The calculations depend on constants like
    /// YEAR_IN_MILLISECONDS , MINIMUM_BLOCK_TIME_IN_MILLISECONDS , MAXIMUM_BLOCK_TIME_IN_MILLISECONDS ,
    /// MINIMUM_FRAME_SIZE, MAXIMUM_FRAME_SIZE, and SLOT_PER_ERA.
    /// @param self The sliding window state to update.
    /// @param blockTime The time duration of each block in milliseconds.
    /// @param frameSize The size of the frame in slots.
    /// @param slotSize The size of the slot per era.
    function updateSlidingWindow(
        State storage self,
        uint24 blockTime,
        uint8 frameSize,
        uint8 slotSize
    ) internal {
        if (blockTime < MINIMUM_BLOCK_TIME_IN_MILLISECONDS || blockTime > MAXIMUM_BLOCK_TIME_IN_MILLISECONDS) {
            revert InvalidBlockTime();
        }
        if (frameSize < MINIMUM_FRAME_SIZE || frameSize > MAXIMUM_FRAME_SIZE) {
            revert InvalidFrameSize();
        }
        if (slotSize < MINIMUM_SLOT_PER_ERA || slotSize > MAXIMUM_SLOT_PER_ERA) {
            revert InvalidSlotPerEra();
        }
        unchecked {
            /// @custom:truncate https://docs.soliditylang.org/en/latest/types.html#division
            uint40 blockPerSlotCache = (YEAR_IN_MILLISECONDS / blockTime) / slotSize;
            uint40 blockPerEraCache = blockPerSlotCache * slotSize;
            self._blockPerEra = blockPerEraCache;
            self._blockPerSlot = blockPerSlotCache;
            self._frameSizeInBlockLength = blockPerSlotCache * frameSize;
            self._slotSize = slotSize;
            if (frameSize <= slotSize) {
                self._frameSizeInEraAndSlotLength[0] = 0;
                self._frameSizeInEraAndSlotLength[1] = frameSize;
            } else {
                self._frameSizeInEraAndSlotLength[0] = frameSize / slotSize;
                self._frameSizeInEraAndSlotLength[1] = frameSize % slotSize;
            }
        }
    }

    /// @notice Calculates the current era and slot within the sliding window based on the given block number.
    /// @dev This function computes both the era and slot using the provided block number and the sliding
    /// window state parameters such as _startBlockNumber, _blockPerEra, and _slotSize. It delegates era
    /// calculation to the `calculateEra` function and slot calculation to the `calculateSlot` function.
    /// The era represents the number of complete eras that have passed since the sliding window started,
    /// while the slot indicates the specific position within the current era.
    /// @param self The sliding window state to use for calculations.
    /// @param blockNumber The block number to calculate the era and slot from.
    /// @return era The current era derived from the block number.
    /// @return slot The current slot within the era derived from the block number.
    function calculateEraAndSlot(
        State storage self,
        uint256 blockNumber
    ) internal view returns (uint256 era, uint8 slot) {
        era = _calculateEra(self, blockNumber);
        slot = _calculateSlot(self, blockNumber);
        return (era, slot);
    }

    /// @notice Determines the sliding window frame based on the provided block number.
    /// @dev This function computes the sliding window frame based on the provided `blockNumber` and the state `self`.
    /// It determines the `toEra` and `toSlot` using `calculateEraAndSlot`, then calculates the block difference
    /// using `_calculateBlockDifferent` to adjust the `blockNumber`. Finally, it computes the `fromEra` and `fromSlot`
    /// using `calculateEraAndSlot` with the adjusted `blockNumber`, completing the determination of the sliding window frame.
    /// @param self The sliding window state to use for calculations.
    /// @param blockNumber The current block number to calculate the sliding window frame from.
    /// @return fromEra The starting era of the sliding window frame.
    /// @return toEra The ending era of the sliding window frame.
    /// @return fromSlot The starting slot within the starting era of the sliding window frame.
    /// @return toSlot The ending slot within the ending era of the sliding window frame.
    function frame(
        State storage self,
        uint256 blockNumber
    ) internal view returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot) {
        (toEra, toSlot) = calculateEraAndSlot(self, blockNumber);
        blockNumber = _calculateBlockDifferent(self, blockNumber);
        (fromEra, fromSlot) = calculateEraAndSlot(self, blockNumber);
    }

    /// @notice Computes a safe frame of eras and slots relative to a given block number.
    /// @dev This function computes a safe frame of eras and slots relative to the provided `blockNumber`.
    /// It first calculates the frame using the `frame` function and then adjusts the result to ensure safe indexing.
    /// @param self The sliding window state containing the configuration.
    /// @param blockNumber The block number used as a reference point for computing the frame.
    /// @return fromEra The starting era of the safe frame.
    /// @return toEra The ending era of the safe frame.
    /// @return fromSlot The starting slot within the starting era of the safe frame.
    /// @return toSlot The ending slot within the ending era of the safe frame.
    function safeFrame(
        State storage self,
        uint256 blockNumber
    ) internal view returns (uint256 fromEra, uint256 toEra, uint8 fromSlot, uint8 toSlot) {
        (toEra, toSlot) = calculateEraAndSlot(self, blockNumber);
        blockNumber = _calculateBlockDifferent(self, blockNumber);
        blockNumber = _frameBuffer(self, blockNumber);
        (fromEra, fromSlot) = calculateEraAndSlot(self, blockNumber);
    }

    /// @notice Retrieves the number of blocks per era from the sliding window state.
    /// @dev Uses the sliding window state to fetch the blocks per era.
    /// @param self The sliding window state.
    /// @return The number of blocks per era.
    function getBlockPerEra(State storage self) internal view returns (uint40) {
        return self._blockPerEra;
    }

    /// @notice Retrieves the number of blocks per slot from the sliding window state.
    /// @dev Uses the sliding window state to fetch the blocks per slot.
    /// @param self The sliding window state.
    /// @return The number of blocks per slot.
    function getBlockPerSlot(State storage self) internal view returns (uint40) {
        return self._blockPerSlot;
    }

    /// @notice Retrieves the frame size in block length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of block length.
    /// @param self The sliding window state.
    /// @return The frame size in block length.
    function getFrameSizeInBlockLength(State storage self) internal view returns (uint40) {
        return self._frameSizeInBlockLength;
    }

    /// @notice Retrieves the frame size in era length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of era length.
    /// @param self The sliding window state.
    /// @return The frame size in era length.
    function getFrameSizeInEraLength(State storage self) internal view returns (uint8) {
        return self._frameSizeInEraAndSlotLength[0];
    }

    /// @notice Retrieves the frame size in slot length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of slot length.
    /// @param self The sliding window state.
    /// @return The frame size in slot length.
    function getFrameSizeInSlotLength(State storage self) internal view returns (uint8) {
        return self._frameSizeInEraAndSlotLength[1];
    }

    /// @notice Retrieves the frame size in era and slot length from the sliding window state.
    /// @dev Uses the sliding window state to fetch the frame size in terms of era and slot length.
    /// @param self The sliding window state.
    /// @return An array containing frame size in era and slot length.
    function getFrameSizeInEraAndSlotLength(State storage self) internal view returns (uint8[2] memory) {
        return self._frameSizeInEraAndSlotLength;
    }

    /// @notice Retrieves the number of slots per era from the sliding window state.
    /// @dev This function returns the `_slotSize` attribute from the provided sliding window state `self`,
    /// which represents the number of slots per era in the sliding window configuration.
    /// @param self The sliding window state containing the configuration.
    /// @return The number of slots per era configured in the sliding window state.
    function getSlotPerEra(State storage self) internal view returns (uint8) {
        return self._slotSize;
    }
}