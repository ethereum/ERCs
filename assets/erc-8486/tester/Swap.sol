// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.35;

interface ITradeUSDC {
    function tradeUSDC() external;
}

interface IERC20 {
    function transfer(address to, uint256 amount) external;
    function withdraw(uint256 wad) external;
}

/// @title Callback for IUniswapV3PoolActions#swap
/// @notice Any contract that calls IUniswapV3PoolActions#swap must implement this interface
interface IUniswapV3SwapCallback {
    /// @notice Called to `msg.sender` after executing a swap via IUniswapV3Pool#swap.
    /// @dev In the implementation you must pay the pool tokens owed for the swap.
    /// The caller of this method must be checked to be a UniswapV3Pool deployed by the canonical UniswapV3Factory.
    /// amount0Delta and amount1Delta can both be 0 if no tokens were swapped.
    /// @param amount0Delta The amount of token0 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token0 to the pool.
    /// @param amount1Delta The amount of token1 that was sent (negative) or must be received (positive) by the pool by
    /// the end of the swap. If positive, the callback must send that amount of token1 to the pool.
    /// @param data Any data passed through by the caller via the IUniswapV3PoolActions#swap call
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

/// @title Permissionless pool actions
/// @notice Contains pool methods that can be called by anyone
interface IUniswapV3PoolActions {
    /// @notice Sets the initial price for the pool
    /// @dev Price is represented as a sqrt(amountToken1/amountToken0) Q64.96 value
    /// @param sqrtPriceX96 the initial sqrt price of the pool as a Q64.96
    function initialize(uint160 sqrtPriceX96) external;

    /// @notice Adds liquidity for the given recipient/tickLower/tickUpper position
    /// @dev The caller of this method receives a callback in the form of IUniswapV3MintCallback#uniswapV3MintCallback
    /// in which they must pay any token0 or token1 owed for the liquidity. The amount of token0/token1 due depends
    /// on tickLower, tickUpper, the amount of liquidity, and the current price.
    /// @param recipient The address for which the liquidity will be created
    /// @param tickLower The lower tick of the position in which to add liquidity
    /// @param tickUpper The upper tick of the position in which to add liquidity
    /// @param amount The amount of liquidity to mint
    /// @param data Any data that should be passed through to the callback
    /// @return amount0 The amount of token0 that was paid to mint the given amount of liquidity. Matches the value in the callback
    /// @return amount1 The amount of token1 that was paid to mint the given amount of liquidity. Matches the value in the callback
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Collects tokens owed to a position
    /// @dev Does not recompute fees earned, which must be done either via mint or burn of any amount of liquidity.
    /// Collect must be called by the position owner. To withdraw only token0 or only token1, amount0Requested or
    /// amount1Requested may be set to zero. To withdraw all tokens owed, caller may pass any value greater than the
    /// actual tokens owed, e.g. type(uint128).max. Tokens owed may be from accumulated swap fees or burned liquidity.
    /// @param recipient The address which should receive the fees collected
    /// @param tickLower The lower tick of the position for which to collect fees
    /// @param tickUpper The upper tick of the position for which to collect fees
    /// @param amount0Requested How much token0 should be withdrawn from the fees owed
    /// @param amount1Requested How much token1 should be withdrawn from the fees owed
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    /// @notice Burn liquidity from the sender and account tokens owed for the liquidity to the position
    /// @dev Can be used to trigger a recalculation of fees owed to a position by calling with an amount of 0
    /// @dev Fees must be collected separately via a call to #collect
    /// @param tickLower The lower tick of the position for which to burn liquidity
    /// @param tickUpper The upper tick of the position for which to burn liquidity
    /// @param amount How much liquidity to burn
    /// @return amount0 The amount of token0 sent to the recipient
    /// @return amount1 The amount of token1 sent to the recipient
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Swap token0 for token1, or token1 for token0
    /// @dev The caller of this method receives a callback in the form of IUniswapV3SwapCallback#uniswapV3SwapCallback
    /// @param recipient The address to receive the output of the swap
    /// @param zeroForOne The direction of the swap, true for token0 to token1, false for token1 to token0
    /// @param amountSpecified The amount of the swap, which implicitly configures the swap as exact input (positive), or exact output (negative)
    /// @param sqrtPriceLimitX96 The Q64.96 sqrt price limit. If zero for one, the price cannot be less than this
    /// value after the swap. If one for zero, the price cannot be greater than this value after the swap
    /// @param data Any data to be passed through to the callback
    /// @return amount0 The delta of the balance of token0 of the pool, exact when negative, minimum when positive
    /// @return amount1 The delta of the balance of token1 of the pool, exact when negative, minimum when positive
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice Receive token0 and/or token1 and pay it back, plus a fee, in the callback
    /// @dev The caller of this method receives a callback in the form of IUniswapV3FlashCallback#uniswapV3FlashCallback
    /// @dev Can be used to donate underlying tokens pro-rata to currently in-range liquidity providers by calling
    /// with 0 amount{0,1} and sending the donation amount(s) from the callback
    /// @param recipient The address which will receive the token0 and token1 amounts
    /// @param amount0 The amount of token0 to send
    /// @param amount1 The amount of token1 to send
    /// @param data Any data to be passed through to the callback
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    /// @notice Increase the maximum number of price and liquidity observations that this pool will store
    /// @dev This method is no-op if the pool already has an observationCardinalityNext greater than or equal to
    /// the input observationCardinalityNext.
    /// @param observationCardinalityNext The desired minimum number of observations for the pool to store
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}

contract Swap {
    uint256 constant HANDLER_SLOT = erc7201("handler.slot");

    uint256 constant CALLDATA_SLOT = erc7201("calldata.slot");
    
    /**
     * @dev Maximum number of bytes that a cache entry can contain.
     *
     * This limit protects the transient-storage cache implementation and is
     * not part of the Solver protocol semantics.
     */
    uint64 constant MAX_TOTAL_LENGTH = type(uint64).max;

    address constant USDC_POOL = 0x6418EEC70f50913ff0d756B48d32Ce7C02b47C47;

    address constant USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    address constant WETH = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    
    /**
     * @dev Reverts when transient-storage slot arithmetic overflows.
     *
     * This error protects the cache implementation and is not part of the
     * Solver protocol semantics.
     */
    error Overflow();

    /**
     * @dev Reverts when a cached `bytes` value exceeds
     *      `MAX_TOTAL_LENGTH`.
     *
     * @param totalLength The length that exceeded the implementation limit.
     */
    error TotalLengthTooLarge(uint256 totalLength);

    fallback() external payable {
        bytes memory data = _getCacheData(bytes32(CALLDATA_SLOT));
        bytes4 selector;
        assembly ("memory-safe") {
            selector := shl(224, shr(224, mload(add(data, 0x20))))
        }
        if (selector == ITradeUSDC.tradeUSDC.selector) {
            _tstore(bytes32(HANDLER_SLOT), 1);
            IUniswapV3PoolActions(USDC_POOL).swap(address(this), true, 20_000_000, 4295128740, hex"");
            (bool success, ) = payable(msg.sender).call{value : address(this).balance}("");
            require(success);
        } else if (selector == IUniswapV3SwapCallback.uniswapV3SwapCallback.selector) {
            int256 amount1Delta;
            assembly ("memory-safe") {
                amount1Delta := mload(add(add(data, 0x20), 0x24))
            }
            require(msg.sender == USDC_POOL);
            IERC20(USDC).transfer(USDC_POOL, 20_000_000);
            _tstore(bytes32(HANDLER_SLOT), 0);
            IERC20(WETH).withdraw(uint256(-amount1Delta));
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
}
