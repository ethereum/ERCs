// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {BasePuller} from "../base/BasePuller.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title ERC4626Puller
 * @notice A Puller implementation that sources tokens by withdrawing from an
 * ERC-4626 vault.
 *
 * @dev The owner must first approve the vault shares to this puller contract.
 * When `pullFrom` is called, this contract:
 * 1. Transfers vault shares from the owner (via the ERC-20 allowance)
 * 2. Withdraws the underlying asset from the vault
 * 3. Transfers the asset to the destination
 *
 * @custom:example
 * ```solidity
 * // Owner deposits 1000 USDC into a vault, gets 1000 shares back.
 * // Owner approves vault shares to ERC4626Puller.
 * // Owner approves pull allowance to a spender.
 * // Spender calls puller.pullFrom(USDC, owner, merchant, 100).
 * // Puller transfers shares from owner, redeems from vault, sends 100 USDC to merchant.
 * ```
 */
contract ERC4626Puller is BasePuller {
    // =============================================================
    // State
    // =============================================================

    /// @notice The ERC-4626 vault this puller is paired with.
    IERC4626 public immutable vault;

    /// @notice The underlying asset of the vault.
    address public immutable asset;

    // =============================================================
    // Errors
    // =============================================================

    /// @notice The puller does not support pulling this token.
    error UnsupportedToken(address requested, address supported);

    // =============================================================
    // Constructor
    // =============================================================

    /**
     * @notice Configures the puller for a single ERC-4626 vault.
     * @param vault_ The ERC-4626 vault address
     */
    constructor(IERC4626 vault_) {
        vault = vault_;
        asset = vault_.asset();
    }

    // =============================================================
    // External functions
    // =============================================================

    /**
     * @inheritdoc BasePuller
     *
     * @dev Returns the maximum amount of `token` that can be pulled from `owner`,
     * considering:
     * - The owner's vault share balance (via `vault.maxWithdraw(owner)`)
     * - The `upTo` cap
     *
     * This does NOT factor in the caller's pull allowance; the caller should
     * apply that filter: `maxPullable(token, owner, pullAllowance(token, owner, spender))`.
     */
    function maxPullable(address token, address owner, uint256 upTo) external view override returns (uint256) {
        if (token != asset) {
            return 0;
        }

        uint256 maxWithdraw = vault.maxWithdraw(owner);

        return maxWithdraw > upTo ? upTo : maxWithdraw;
    }

    // =============================================================
    // Internal: sourcing logic
    // =============================================================

    /**
     * @inheritdoc BasePuller
     *
     * @dev Calls `vault.withdraw(amount, to, owner)` which:
     * 1. Consumes the vault share allowance the owner granted to this puller
     * 2. Burns the equivalent shares from the owner
     * 3. Transfers the underlying asset directly to `to`
     *
     * The owner must have previously approved this puller via `vault.approve`.
     */
    function _sourceTokens(address token, address owner, address to, uint256 amount) internal override {
        if (token != asset) {
            revert UnsupportedToken(token, asset);
        }

        vault.withdraw(amount, to, owner);
    }
}
