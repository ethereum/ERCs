// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.35;

/**
 * @author Helkomine (@Helkomine)
 */
contract FlashLoanProxy {
    /**
     * @dev Maximum number of bytes that a cache entry can contain.
     *
     * This limit protects the transient-storage cache implementation
     */
    uint64 constant MAX_TOTAL_LENGTH = type(uint64).max;

    uint256 constant HANDLER_SLOT = erc7201("handler.slot");

    uint256 constant DEPTH_SLOT = erc7201("depth.slot");

    uint256 constant BYTECODE_SLOT = erc7201("bytecode.slot");

    uint256 constant CALLDATA_SLOT = erc7201("calldata.slot");

    address immutable IMPLEMENTATION;

    /**
     * @dev Reverts when arithmetic overflows.
     */
    error Overflow();

    /**
     * @dev Reverts when a cached `bytes` value exceeds
     *      `MAX_TOTAL_LENGTH`.
     *
     * @param totalLength The length that exceeded the implementation limit.
     */
    error TotalLengthTooLarge(uint256 totalLength);

    constructor(address implementation) {
        IMPLEMENTATION = implementation;
    }

    fallback() external payable {
        uint256 depth = _tload(bytes32(DEPTH_SLOT));
        bool success = true;
        bytes memory retData;
        if (depth == 0) {
            unchecked { _tstore(bytes32(DEPTH_SLOT), ++depth); }
            (bytes calldata bytecode, bytes calldata data) = _decodeRawBytes(msg.data);
            _setCacheCallData(bytes32(BYTECODE_SLOT), bytecode);
            _setCacheCallData(bytes32(CALLDATA_SLOT), data);
            (success, retData) = IMPLEMENTATION.delegatecall(bytecode);
            _tstore(bytes32(HANDLER_SLOT), 0);
            unchecked { _tstore(bytes32(DEPTH_SLOT), --depth); }
            _setCacheCallData(bytes32(BYTECODE_SLOT), msg.data[0 : 0]);
            _setCacheCallData(bytes32(CALLDATA_SLOT), msg.data[0 : 0]);
        } else {
            if (_tload(bytes32(HANDLER_SLOT)) != 0) {
                _tstore(bytes32(DEPTH_SLOT), ++depth);
                _setCacheCallData(bytes32(CALLDATA_SLOT), msg.data);
                (success, retData) = IMPLEMENTATION.delegatecall(_getCacheData(bytes32(BYTECODE_SLOT)));
                unchecked { _tstore(bytes32(DEPTH_SLOT), --depth); }
            }
        }
        assembly ("memory-safe") {
            switch success
            case 0 { revert(add(retData, 0x20), mload(retData)) }
            default { return(add(retData, 0x20), mload(retData)) }
        }
    }

    function _decodeRawBytes(bytes calldata input) internal pure returns (
        bytes calldata bytecode,
        bytes calldata data
    ) {
        assembly ("memory-safe") {
            let start := input.offset
            let size := input.length
            let end := add(start, size)

            if lt(size, 0x40) { revert(0, 0) }

            // First dynamic offset
            if iszero(eq(calldataload(start), 0x40)) { revert(0, 0) }

            // Second dynamic offset
            let dataRelativeOffset := calldataload(add(start, 0x20))

            // Bytecode length
            let bytecodeLengthPos := add(start, 0x40)
            let bytecodeLength := calldataload(bytecodeLengthPos)

            // Validate bytecode length and prevent overflow
            if gt(bytecodeLength, sub(size, 0x60)) { revert(0, 0) }

            let bytecodePaddedLength := and(
                add(bytecodeLength, 0x1f),
                not(0x1f)
            )

            let expectedDataOffset := add(0x60, bytecodePaddedLength)

            if iszero(eq(dataRelativeOffset, expectedDataOffset)) { revert(0, 0) }

            // Data length position
            let dataLengthPos := add(start, dataRelativeOffset)

            if gt(dataLengthPos, sub(end, 0x20)) { revert(0, 0) }

            let dataLength := calldataload(dataLengthPos)

            let remaining := sub(end, add(dataLengthPos, 0x20))

            if gt(dataLength, remaining) { revert(0, 0) }

            let dataPaddedLength := and(
                add(dataLength, 0x1f),
                not(0x1f)
            )

            if iszero(eq(add(dataLengthPos, add(0x20, dataPaddedLength)), end)) { revert(0, 0) }

            // Return calldata slices
            bytecode.offset := add(bytecodeLengthPos, 0x20)
            bytecode.length := bytecodeLength

            data.offset := add(dataLengthPos, 0x20)
            data.length := dataLength
        }
    }

    /**
     * @dev Copies a `bytes` value from calldata into transient storage.
     *
     * The value is stored as a length word followed by its data words. If the
     * length is not a multiple of 32 bytes, the unused bytes in the final word
     * are zeroed to produce a canonical representation.
     *
     * If the new value is shorter than the previously cached value at the same
     * namespace, trailing transient storage slots are cleared to prevent stale
     * data from remaining in the cache.
     *
     * Reverts with `TotalLengthTooLarge` if the value or previous cached value
     * exceeds `MAX_TOTAL_LENGTH`, or with `Overflow` if the transient storage
     * slot arithmetic overflows.
     *
     * @param namespace The transient storage namespace used to cache the value.
     * @param data The calldata bytes to cache.
     */
    function _setCacheCallData(bytes32 namespace, bytes calldata data) internal {
        bytes4 lengthTooLargeSelector = TotalLengthTooLarge.selector;
        bytes4 overflowSelector = Overflow.selector;
        uint64 maxTotalLength = MAX_TOTAL_LENGTH;
        assembly ("memory-safe") {
            let length := data.length
            if gt(length, maxTotalLength) {
                mstore(0, lengthTooLargeSelector)
                mstore(4, length)
                revert(0, 36)
            }
            let totalSlot := shr(5, add(length, 31))
            let cacheLength := tload(namespace)
            if gt(cacheLength, maxTotalLength) {
                mstore(0, lengthTooLargeSelector)
                mstore(4, cacheLength)
                revert(0, 36)
            }
            let totalCacheSlot := add(cacheLength, 31)
            if gt(cacheLength, totalCacheSlot) {
                mstore(0, overflowSelector)
                revert(0, 4)
            }
            totalCacheSlot := shr(5, totalCacheSlot)
            tstore(namespace, length)
            namespace := add(namespace, 1)
            if gt(1, namespace) {
                mstore(0, overflowSelector)
                revert(0, 4)
            }
            if length {
                let floorTotalSlot := shr(5, length)
                let lastSlot := add(namespace, floorTotalSlot)
                if gt(namespace, lastSlot) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                let offset := data.offset
                for { let i } lt(i, floorTotalSlot) { i := add(i, 1) } {
                    tstore(add(namespace, i), calldataload(add(offset, shl(5, i))))
                }
                let roundingLength := shl(5, floorTotalSlot)
                let bytesLeft := sub(length, roundingLength)
                if bytesLeft {
                    let bitsLeft := shl(3, bytesLeft)
                    let bitPadding := sub(256, bitsLeft)
                    let rawWord := calldataload(add(offset, roundingLength))
                    let mask := shl(bitPadding, shr(bitPadding, rawWord))
                    tstore(lastSlot, mask)
                }
            }
            if gt(totalCacheSlot, totalSlot) {
                if gt(namespace, add(namespace, totalCacheSlot)) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                let slotLeft := sub(totalCacheSlot, totalSlot)
                namespace := add(namespace, totalSlot)
                for { let j } lt(j, slotLeft) { j := add(j, 1) } {
                    tstore(add(namespace, j), 0)
                }
            }
        }
    }

    /**
     * @dev Loads a cached `bytes` value from transient storage into memory.
     *
     * The value is expected to be stored as a length word followed by its data
     * words. If the length is not a multiple of 32 bytes, only the bytes within
     * the logical length are copied into memory; unused bytes in the final word
     * are ignored.
     *
     * Reverts with `TotalLengthTooLarge` if the cached length exceeds
     * `MAX_TOTAL_LENGTH`, or with `Overflow` if the transient storage slot
     * arithmetic overflows.
     *
     * @param namespace The transient storage namespace containing the cached value.
     * @return data The cached bytes value reconstructed in memory.
     */
    function _getCacheData(bytes32 namespace) 
        internal 
        view 
        returns (bytes memory data) 
    {
        bytes4 lengthTooLargeSelector = TotalLengthTooLarge.selector;
        bytes4 overflowSelector = Overflow.selector;
        uint64 maxTotalLength = MAX_TOTAL_LENGTH;
        assembly ("memory-safe") {
            data := mload(64)
            let length := tload(namespace)
            if gt(length, maxTotalLength) {
                mstore(0, lengthTooLargeSelector)
                mstore(4, length)
                revert(0, 36)
            }
            mstore(data, length)
            let offset := add(data, 32)
            if length {
                let floorTotalSlot := shr(5, length)
                let totalSlot := shr(5, add(length, 31))
                namespace := add(namespace, 1)
                if gt(1, namespace) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                let lastSlot := add(namespace, floorTotalSlot)
                if gt(namespace, lastSlot) {
                    mstore(0, overflowSelector)
                    revert(0, 4)
                }
                for { let i } lt(i, floorTotalSlot) { i := add(i, 1) } {
                    mstore(add(offset, shl(5, i)), tload(add(namespace, i)))
                }
                let roundingLength := shl(5, floorTotalSlot)
                let bytesLeft := sub(length, roundingLength)
                if bytesLeft {
                    let bitsLeft := shl(3, bytesLeft)
                    let bitPadding := sub(256, bitsLeft)
                    let rawWord := tload(lastSlot)
                    let mask := shl(bitPadding, shr(bitPadding, rawWord))
                    mstore(add(offset, roundingLength), mask)
                }
                offset := add(offset, shl(5, totalSlot))
            }
            mstore(64, offset)
        }
    }

    /**
     * @dev Stores a value in transient storage at `key`.
     *
     * This helper provides a high-level Solidity-callable wrapper around the
     * `TSTORE` instruction.
     *
     * @param key The transient storage key.
     * @param value The value to store.
     */
    function _tstore(bytes32 key, uint256 value) internal {
        assembly ("memory-safe") {
            tstore(key, value)
        }
    }

    /**
     * @dev Loads a value from transient storage at `key`.
     *
     * This helper provides a high-level Solidity-callable wrapper around the
     * `TLOAD` instruction.
     *
     * @param key The transient storage key.
     * @return value The value stored at `key`.
     */
    function _tload(bytes32 key) internal view returns (uint256 value) {
        assembly ("memory-safe") {
            value := tload(key)
        }
    }
}
