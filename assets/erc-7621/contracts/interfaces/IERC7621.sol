// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title ERC-7621 Basket Token Standard
/// @dev See https://eips.ethereum.org/EIPS/eip-7621
///      Conforming contracts MUST also implement IERC20, IERC165, and IERC173.
interface IERC7621 {

    // --- Errors ---

    /// @dev Array lengths do not match.
    error LengthMismatch(uint256 expected, uint256 actual);

    /// @dev Weights do not sum to 10000.
    error InvalidWeights(uint256 weightSum);

    /// @dev Amount is zero where a non-zero value is required.
    error ZeroAmount();

    /// @dev Token is not a constituent of the basket.
    error NotConstituent(address token);

    /// @dev Slippage tolerance exceeded on share minting.
    error InsufficientShares(uint256 minimum, uint256 actual);

    /// @dev Slippage tolerance exceeded on constituent withdrawal.
    error InsufficientAmount(uint256 index, uint256 minimum, uint256 actual);

    /// @dev Duplicate constituent token address.
    error DuplicateConstituent(address token);

    /// @dev Constituent address is the zero address.
    error ZeroAddress();

    // --- Events ---

    /// @notice MUST be emitted when assets are contributed to the basket.
    /// @param caller The address that called `contribute`.
    /// @param receiver The address that received the minted shares.
    /// @param lpAmount The number of shares minted.
    /// @param amounts The constituent token amounts deposited.
    event Contributed(
        address indexed caller,
        address indexed receiver,
        uint256 lpAmount,
        uint256[] amounts
    );

    /// @notice MUST be emitted when shares are burned and assets withdrawn.
    /// @param caller The address that called `withdraw`.
    /// @param receiver The address that received the constituent tokens.
    /// @param lpAmount The number of shares burned.
    /// @param amounts The constituent token amounts returned.
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        uint256 lpAmount,
        uint256[] amounts
    );

    /// @notice MUST be emitted when the constituent set or weights change.
    /// @param newTokens The new constituent token addresses.
    /// @param newWeights The new target weights in basis points.
    event Rebalanced(address[] newTokens, uint256[] newWeights);

    // --- View Functions ---

    /// @notice Returns the constituent tokens and their target weights.
    /// @dev The ordering of the returned arrays is stable between calls to
    ///      `rebalance`. The `amounts` arrays in `contribute`, `withdraw`,
    ///      and their preview counterparts MUST follow this same ordering.
    /// @return tokens Constituent addresses.
    /// @return weights Target weights in basis points, summing to 10000.
    function getConstituents()
        external view returns (address[] memory tokens, uint256[] memory weights);

    /// @notice Returns the number of constituents.
    /// @return count The number of constituent tokens.
    function totalConstituents() external view returns (uint256 count);

    /// @notice Returns the accounted reserve balance of a constituent.
    /// @dev Returns the reserve recognized by the basket for share accounting,
    ///      which MAY differ from `IERC20(token).balanceOf(address(this))`.
    /// @param token The constituent token address.
    /// @return balance The accounted reserve of `token`.
    function getReserve(address token) external view returns (uint256 balance);

    /// @notice Returns the target weight of a specific constituent.
    /// @dev MUST revert with `NotConstituent` if `token` is not a constituent.
    /// @param token The constituent token address.
    /// @return weight The target weight in basis points.
    function getWeight(address token) external view returns (uint256 weight);

    /// @notice Returns whether an address is a current constituent.
    /// @param token The token address to check.
    /// @return True if `token` is a constituent.
    function isConstituent(address token) external view returns (bool);

    /// @notice Returns the total basket value in the implementation's accounting unit.
    /// @dev The accounting unit and valuation method are implementation-defined
    ///      but MUST be deterministic and consistent with `previewContribute`.
    ///      The returned value is only meaningful within this implementation's
    ///      accounting model and MUST NOT be assumed comparable across
    ///      different basket implementations.
    /// @return value The total basket value in the implementation's unit.
    function totalBasketValue() external view returns (uint256 value);

    // --- Actions ---

    /// @notice Deposits constituent tokens and mints shares to `receiver`.
    /// @dev The caller MUST have approved this contract to spend the required
    ///      amounts of each constituent prior to calling.
    ///      `amounts` MUST be ordered to match `getConstituents`.
    ///      MUST emit `Contributed`.
    ///      MUST revert with `LengthMismatch` if `amounts.length` does not
    ///      equal `totalConstituents()`.
    ///      MUST revert with `ZeroAmount` if all amounts are zero.
    ///      MUST revert with `InsufficientShares` if shares minted is less
    ///      than `minShares`.
    ///      Shares minted MUST be monotonically non-decreasing with respect
    ///      to amounts contributed — contributing more MUST NOT yield fewer shares.
    ///      When rounding, MUST round shares minted down (favoring the basket).
    /// @param amounts Ordered array of constituent token amounts to deposit.
    /// @param receiver The address that will receive minted shares.
    /// @param minShares Minimum acceptable shares to mint. Reverts if not met.
    /// @return lpAmount Shares minted.
    function contribute(uint256[] calldata amounts, address receiver, uint256 minShares)
        external returns (uint256 lpAmount);

    /// @notice Burns shares and transfers proportional reserves to `receiver`.
    /// @dev MUST emit `Withdrawn`.
    ///      MUST revert with `ZeroAmount` if `lpAmount` is zero.
    ///      MUST revert if the caller holds fewer than `lpAmount` shares.
    ///      MUST revert with `LengthMismatch` if `minAmounts.length` does not
    ///      equal `totalConstituents()`.
    ///      MUST revert with `InsufficientAmount` if any returned amount is
    ///      less than the corresponding entry in `minAmounts`.
    ///      For each constituent: `amount_i = reserve_i * lpAmount / totalSupply`,
    ///      rounding down (favoring the basket).
    ///      Shares MUST be burned before constituent tokens are transferred out.
    /// @param lpAmount The number of shares to burn.
    /// @param receiver The address that will receive constituent tokens.
    /// @param minAmounts Minimum acceptable amounts per constituent. Reverts if not met.
    /// @return amounts Constituent amounts returned, ordered by `getConstituents`.
    function withdraw(uint256 lpAmount, address receiver, uint256[] calldata minAmounts)
        external returns (uint256[] memory amounts);

    /// @notice Updates the constituent set and target weights.
    /// @dev MUST revert if caller is not `owner()` per ERC-173.
    ///      MUST revert with `LengthMismatch` if array lengths differ.
    ///      MUST revert with `InvalidWeights` if weights do not sum to 10000.
    ///      MUST revert with `DuplicateConstituent` if `newTokens` contains duplicates.
    ///      MUST revert with `ZeroAddress` if any entry in `newTokens` is `address(0)`.
    ///      MUST emit `Rebalanced`.
    ///      The standardized effect of this function is updating the constituent
    ///      set and target weights. Any reserve realignment (swaps) is an
    ///      implementation concern and MUST NOT be inferred by integrators
    ///      from this call alone.
    /// @param newTokens The new ordered set of constituent token addresses.
    /// @param newWeights The new ordered set of target weights in basis points.
    function rebalance(address[] calldata newTokens, uint256[] calldata newWeights)
        external;

    // --- Preview Functions ---

    /// @notice Estimates shares that would be minted for given amounts.
    /// @dev MUST return the same value as `contribute` would return if called
    ///      in the same transaction. MUST NOT revert except for invalid inputs.
    ///      MUST NOT vary by caller. MUST round down.
    ///      MUST use the same valuation function as `contribute`.
    /// @param amounts Ordered array of constituent token amounts.
    /// @return lpAmount Estimated shares that would be minted.
    function previewContribute(uint256[] calldata amounts)
        external view returns (uint256 lpAmount);

    /// @notice Estimates constituent amounts returned for burning shares.
    /// @dev MUST return the same value as `withdraw` would return if called
    ///      in the same transaction. MUST NOT revert except for invalid inputs.
    ///      MUST round down.
    /// @param lpAmount The number of shares to simulate burning.
    /// @return amounts Estimated constituent amounts, ordered by `getConstituents`.
    function previewWithdraw(uint256 lpAmount)
        external view returns (uint256[] memory amounts);
}
