// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

/// @title IBalanceProxy
/// @notice Interface for the BalanceProxy contract
/// @dev This interface is used to proxy calls to a target contract with specified balances and approvals
interface IBalanceProxy {
    /// @notice Struct to represent balance or value of specific token by target address
    /// @param target Target address
    /// @param token Token address
    /// @param balance Balance
    struct Balance {
        address target;
        address token;
        int256 balance;
    }

    /// @notice Error when actual diff != expected
    /// @param token    Token address
    /// @param target   Target address
    /// @param expected Expected diff
    /// @param actual   Actual diff
    error UnexpectedBalanceDiff(
        address token,
        address target,
        int256 expected,
        int256 actual
    );

    /// @notice Struct to represent metadata of a balance
    /// @param target Target address
    /// @param token Token address
    /// @param balance Balance struct
    /// @param symbol Symbol of the token
    /// @param decimals Decimals of the token
    struct BalanceMetadata {
        Balance balance;
        string symbol;
        uint8 decimals;
    }

    /// @notice Error thrown when a balance is insufficient
    /// @param token Token address
    /// @param target Target address
    /// @param balance Balance
    error InsufficientBalance(
        address token,
        address target,
        int256 balance,
        uint256 actual
    );

    /// @notice Error thrown when a call fails
    /// @param target Target address
    /// @param data Data passed to the target contract
    /// @param returnData Return data from the target contract
    error CallFailed(address target, bytes data, bytes returnData);

    /// @notice Error thrown when metadata is invalid
    /// @param token Token address
    /// @param expectedSymbol Expected symbol of the token
    /// @param expectedDecimals Expected decimals of the token
    /// @param actualSymbol Actual symbol of the token
    /// @param actualDecimals Actual decimals of the token
    error InvalidMetadata(
        address token,
        string expectedSymbol,
        uint8 expectedDecimals,
        string actualSymbol,
        uint8 actualDecimals
    );

    /// @notice Proxy call to a target contract with specified balances and approvals
    /// @param postBalances Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return Result of the call
    function proxyCall(
        Balance[] memory postBalances,
        Balance[] memory approvals,
        address target,
        bytes memory data,
        Balance[] memory withdrawals
    ) external payable returns (bytes memory);

    /// @notice Calldata version of proxy call to a target contract with specified balances and approvals
    /// @param postBalances Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return result Result of the call
    function proxyCallCalldata(
        Balance[] calldata postBalances,
        Balance[] calldata approvals,
        address target,
        bytes calldata data,
        Balance[] calldata withdrawals
    ) external payable returns (bytes memory);

    /// @notice Proxy call to a target contract with specified balances and approvals
    /// @param postBalances Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return Result of the call
    function proxyCallMetadata(
        BalanceMetadata[] memory postBalances,
        BalanceMetadata[] memory approvals,
        address target,
        bytes memory data,
        BalanceMetadata[] memory withdrawals
    ) external payable returns (bytes memory);

    /// @notice Calldata version of proxy call to a target contract with specified balances and approvals
    /// @param postBalances Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return result Result of the call
    function proxyCallMetadataCalldata(
        BalanceMetadata[] calldata postBalances,
        BalanceMetadata[] calldata approvals,
        address target,
        bytes calldata data,
        BalanceMetadata[] calldata withdrawals
    ) external payable returns (bytes memory);

    /// @notice Proxy call to a target contract with specified balances and approvals
    /// @param diffs Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return Result of the call
    function proxyCallDiffs(
        Balance[] memory diffs,
        Balance[] memory approvals,
        address target,
        bytes memory data,
        Balance[] memory withdrawals
    ) external payable returns (bytes memory);

    /// @notice Calldata version of proxy call to a target contract with specified balances and approvals
    /// @param diffs Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return result Result of the call
    function proxyCallCalldataDiffs(
        Balance[] calldata diffs,
        Balance[] calldata approvals,
        address target,
        bytes calldata data,
        Balance[] calldata withdrawals
    ) external payable returns (bytes memory);

    /// @notice Proxy call to a target contract with specified balances and approvals
    /// @param diffs Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return Result of the call
    function proxyCallMetadataDiffs(
        BalanceMetadata[] memory diffs,
        BalanceMetadata[] memory approvals,
        address target,
        bytes memory data,
        BalanceMetadata[] memory withdrawals
    ) external payable returns (bytes memory);

    /// @notice Calldata version of proxy call to a target contract with specified balances and approvals
    /// @param diffs Balances to check after the call
    /// @param approvals Approvals to make before the call
    /// @param target Target contract to call
    /// @param data Data to pass to the target contract
    /// @param withdrawals Withdrawals to make after the call
    /// @return result Result of the call
    function proxyCallMetadataCalldataDiffs(
        BalanceMetadata[] calldata diffs,
        BalanceMetadata[] calldata approvals,
        address target,
        bytes calldata data,
        BalanceMetadata[] calldata withdrawals
    ) external payable returns (bytes memory);
}
