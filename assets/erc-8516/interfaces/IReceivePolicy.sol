// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/**
 * @title IReceivePolicy
 * @notice External policy interface queried by protected ERC-20 tokens to authorize incoming transfers.
 * @dev Implementations MUST be read-only (`view`) and deterministic for a given block state so that
 *      tokens can safely query them via `staticcall` inside `_update` without reentrancy risk.
 */
interface IReceivePolicy {
    /**
     * @notice Checks whether `to` is permitted to receive `amount` of `token` from `from`.
     * @dev Called by a protected ERC-20 token when `to` has enabled protection, no embedded one-time
     *      permit or embedded allowlist entry matched, and `to` has configured this policy contract.
     *      Returning `false` or reverting causes the token transfer to fail-closed.
     * @param token The address of the ERC-20 token contract querying the policy.
     * @param from The economic sender address (`address(0)` for mints).
     * @param to The protected recipient address.
     * @param amount The token amount being transferred or minted.
     * @param data Optional ABI-encoded context supplied by the token contract (e.g., `msg.sender`,
     *             allowance, token-specific flags, or sender/recipient account metadata such as
     *             tiers or compliance attributes; empty bytes `""` by default).
     * @return allowed True if the incoming transfer is permitted, false otherwise.
     */
    function canReceive(address token, address from, address to, uint256 amount, bytes calldata data)
        external
        view
        returns (bool allowed);
}

