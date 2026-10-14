// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title bitmap256
/// @notice User-defined value type representing a 256-bit occupancy bitmap.
/// @dev Used throughout Cento to efficiently manage fixed-capacity slot allocation.
type bitmap256 is uint256;
using LibBitmap for bitmap256 global;

/// @title Bitmap Library
/// @notice Utility library for manipulating `bitmap256`.
/// @dev Provides efficient bitmap operations for slot allocation,
/// occupancy tracking, and bit counting.
library LibBitmap {
    
    /// @dev De Bruijn multiplication constant for 64-bit trailing-zero lookup.
    uint64  private constant DEBRUIJN64_MAGIC   = 0x03f79d71b4cb0a89;
    /// @dev Lower half of the De Bruijn lookup table.
    bytes32 private constant DEBRUIJN64_TABLE_0 = 0x050c12181e21272d162b3335243b373e04111d262a323a3d031c313902300100;
    /// @dev Upper half of the De Bruijn lookup table.
    bytes32 private constant DEBRUIJN64_TABLE_1 = 0x0607080d09130e190a1f14220f281a2e0b17202c153423361025293c1b382f3f;

    /// @notice Thrown when no available bitmap slot satisfies the requested operation.
    error NoFreeSlots();

    /// @dev Truncates a `uint256` to `uint64` without a warning.
    function _unsafeToUint64(uint256 x) private pure returns (uint64 r) {
        assembly { r := x }
    }

    /// @dev Counts trailing zeroes in a 64-bit word using a De Bruijn lookup table.
    function _ctz64(uint64 x) private pure returns (uint8 r) {
        unchecked {
            uint64 prod = x * DEBRUIJN64_MAGIC;
            uint256 idx = uint256(prod >> 58);
            bytes32 word = idx < 32 ? DEBRUIJN64_TABLE_0 : DEBRUIJN64_TABLE_1;
            assembly {
                let pos := sub(31, and(idx, 31))
                r := byte(pos, word)
            }
        }
    }

    /// @dev Returns the index of the least-significant (rightmost) set bit.
    function _lsbIndex(uint256 lsb) private pure returns (uint8) {
        unchecked {
            uint64 max64 = type(uint64).max;
            if (( lsb         & max64) != 0) return _ctz64(_unsafeToUint64(lsb));
            if (((lsb >> 64)  & max64) != 0) return _ctz64(_unsafeToUint64(lsb >> 64))  + 64;
            if (((lsb >> 128) & max64) != 0) return _ctz64(_unsafeToUint64(lsb >> 128)) + 128;
                                             return _ctz64(_unsafeToUint64(lsb >> 192)) + 192;
        }
    }

    /// @notice Removes the lowest occupied slot from the bitmap.
    /// @param _bitmap Bitmap to operate on.
    /// @return nextBitmap Bitmap with the lowest occupied slot cleared.
    /// @return index Index of the removed slot.
    /// @dev Reverts if the bitmap contains no occupied slots.
    function popFirstFilledSlot(bitmap256 _bitmap) internal pure returns (bitmap256 nextBitmap, uint8 index) {
        uint256 bitmap = bitmap256.unwrap(_bitmap);
        if (bitmap == 0) revert NoFreeSlots();
        uint256 lsb;
        unchecked { lsb = bitmap & (~bitmap + 1); } 
        index = _lsbIndex(lsb);
        nextBitmap = bitmap256.wrap(bitmap ^ lsb);
    }

    /// @notice Returns the lowest available slot.
    /// @param _bitmap Bitmap to inspect.
    /// @return index Index of the first unoccupied slot.
    /// @dev Reverts if all slots are occupied.
    function getFirstEmptySlot(bitmap256 _bitmap) internal pure returns (uint8 index) {
        uint256 bitmap = bitmap256.unwrap(_bitmap); uint256 free;
        unchecked { free = ~bitmap & (bitmap + 1); }
        if (free == 0) revert NoFreeSlots();
        index = _lsbIndex(free);
    }

    /// @notice Counts occupied slots in the bitmap.
    /// @param _bitmap Bitmap to inspect.
    /// @return count Number of occupied slots.
    function countFilledSlots(bitmap256 _bitmap) internal pure returns (uint16 count) {
        uint256 bitmap = bitmap256.unwrap(_bitmap);
        for (; bitmap != 0; bitmap &= (bitmap - 1)) { unchecked { ++count; } }
    }

    /// @dev Returns a bitmap mask for the specified slot.
    function _mask(uint8 index) private pure returns (uint256) {
        return uint256(1) << index;
    }
    
    /// @notice Checks whether a slot is occupied.
    /// @param _bitmap Bitmap to inspect.
    /// @param index Slot index.
    /// @return True if the slot is occupied.
    function isSlotOccupied(bitmap256 _bitmap, uint8 index) internal pure returns (bool) {
        return (bitmap256.unwrap(_bitmap) & _mask(index)) != 0;
    }

    /// @notice Marks a slot as occupied.
    /// @param _bitmap Bitmap to modify.
    /// @param index Slot index.
    /// @return Updated bitmap.
    function fillSlotAt(bitmap256 _bitmap, uint8 index) internal pure returns (bitmap256) {
        return bitmap256.wrap(bitmap256.unwrap(_bitmap) | _mask(index));
    }

    /// @notice Clears an occupied slot.
    /// @param _bitmap Bitmap to modify.
    /// @param index Slot index.
    /// @return Updated bitmap.
    function clearSlotAt(bitmap256 _bitmap, uint8 index) internal pure returns (bitmap256) {
        return bitmap256.wrap(bitmap256.unwrap(_bitmap) & ~_mask(index));
    }
}
