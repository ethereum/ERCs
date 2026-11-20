// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.27;

/// @title IBalanceProxy
/// @notice Minimal interface for the BalanceProxy core contract
/// @dev Core is source-agnostic: it never pulls tokens, only uses its own balances
interface IBalanceProxy {
    /// @notice Struct to represent balance or value of specific token by target address
    /// @param target Target address
    /// @param token Token address (address(0) for ETH)
    /// @param balance Expected absolute balance (post) or diff (signed)
    struct Balance {
        address target;
        address token;
        int256 balance;
    }

    /// @notice Approval instruction: either transfer tokens to target or approve target to spend
    struct Approval {
        Balance balance; // token, target, amount(>=0 expected)
        bool useTransfer; // true: transfer to target; false: approve target
    }

    /// @notice Error when actual diff != expected
    error ERC8009BalanceDiffConstraintViolation(
        address token,
        address target,
        int256 expected,
        int256 actual
    );

    /// @notice Error thrown when a balance is insufficient
    error ERC8009BalanceConstraintViolation(
        address token,
        address target,
        int256 balance,
        uint256 actual
    );

    /// @notice Error thrown when a call fails
    error ERC8009CallFailed(address target, bytes data, bytes returnData);

    /// @notice Proxy call to a target contract with specified post-balance checks
    function proxyCall(
        Balance[] memory postBalances,
        Approval[] memory approvals,
        address target,
        bytes memory data,
        Balance[] memory withdrawals
    ) external payable returns (bytes memory);

    /// @notice Proxy call with balance diffs
    function proxyCallDiffs(
        Balance[] memory diffs,
        Approval[] memory approvals,
        address target,
        bytes memory data,
        Balance[] memory withdrawals
    ) external payable returns (bytes memory);
}
