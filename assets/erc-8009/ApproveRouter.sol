// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IBalanceProxy} from "./interfaces/IBalanceProxy.sol";
import {BalanceMetadata} from "./interfaces/IMetadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title ApproveRouter
/// @notice Handles allowance + pull tokens then delegates to BalanceProxy core
contract ApproveRouter {
    /// @notice Error thrown when metadata and balances array lengths don't match
    error MetadataBalancesLengthMismatch(
        uint256 metaLength,
        uint256 balancesLength
    );

    /// @notice Error thrown when metadata doesn't match actual token properties
    error InvalidMetadata(
        address token,
        string expectedSymbol,
        uint8 expectedDecimals,
        string actualSymbol,
        uint8 actualDecimals
    );

    /// @dev Internal function to validate metadata matches actual token properties
    /// @param meta Metadata array to validate
    /// @param balances Corresponding balances array
    function _checkMetadata(
        BalanceMetadata[] memory meta,
        IBalanceProxy.Balance[] memory balances
    ) internal view {
        if (meta.length != balances.length) {
            revert MetadataBalancesLengthMismatch(meta.length, balances.length);
        }

        for (uint256 i = 0; i < meta.length; i++) {
            string memory actualSymbol;
            uint8 actualDecimals;

            if (balances[i].token == address(0)) {
                actualSymbol = "ETH";
                actualDecimals = 18;
            } else {
                actualSymbol = IERC20Metadata(balances[i].token).symbol();
                actualDecimals = IERC20Metadata(balances[i].token).decimals();
            }

            if (
                keccak256(abi.encodePacked(actualSymbol)) !=
                keccak256(abi.encodePacked(meta[i].symbol)) ||
                actualDecimals != meta[i].decimals
            ) {
                revert InvalidMetadata(
                    balances[i].token,
                    meta[i].symbol,
                    meta[i].decimals,
                    actualSymbol,
                    actualDecimals
                );
            }
        }
    }

    /// @notice Execute proxyCall with pre-approved tokens (router as spender)
    function approveProxyCall(
        IBalanceProxy balanceProxy,
        IBalanceProxy.Balance[] memory postBalances,
        IBalanceProxy.Approval[] memory approvals,
        address target,
        bytes memory data,
        IBalanceProxy.Balance[] memory withdrawals
    ) external payable returns (bytes memory) {
        for (uint256 i = 0; i < approvals.length; i++) {
            IBalanceProxy.Balance memory bal = approvals[i].balance;
            uint256 amount = uint256(bal.balance);
            IERC20(bal.token).transferFrom(
                msg.sender,
                address(balanceProxy),
                amount
            );
        }
        return
            balanceProxy.proxyCall{value: msg.value}(
                postBalances,
                approvals,
                target,
                data,
                withdrawals
            );
    }

    /// @notice proxyCallDiffs with pre-approved tokens
    function approveProxyCallDiffs(
        IBalanceProxy balanceProxy,
        IBalanceProxy.Balance[] memory diffs,
        IBalanceProxy.Approval[] memory approvals,
        address target,
        bytes memory data,
        IBalanceProxy.Balance[] memory withdrawals
    ) external payable returns (bytes memory) {
        for (uint256 i = 0; i < approvals.length; i++) {
            IBalanceProxy.Balance memory bal = approvals[i].balance;
            uint256 amount = uint256(bal.balance);
            IERC20(bal.token).transferFrom(
                msg.sender,
                address(balanceProxy),
                amount
            );
        }
        return
            balanceProxy.proxyCallDiffs{value: msg.value}(
                diffs,
                approvals,
                target,
                data,
                withdrawals
            );
    }

    /// @notice Execute proxyCall with pre-approved tokens and calldata metadata (metadata is ignored on-chain)
    function approveProxyCallWithMeta(
        IBalanceProxy balanceProxy,
        BalanceMetadata[] memory meta,
        IBalanceProxy.Balance[] memory balances,
        IBalanceProxy.Approval[] memory approvals,
        address target,
        bytes memory data,
        IBalanceProxy.Balance[] memory withdrawals
    ) external payable returns (bytes memory) {
        // Validate metadata against balances
        _checkMetadata(meta, balances);

        // Pull tokens for approvals
        for (uint256 i = 0; i < approvals.length; i++) {
            IBalanceProxy.Balance memory bal = approvals[i].balance;
            uint256 amount = uint256(bal.balance);
            IERC20(bal.token).transferFrom(
                msg.sender,
                address(balanceProxy),
                amount
            );
        }

        // Delegate to BalanceProxy
        return
            balanceProxy.proxyCall{value: msg.value}(
                balances,
                approvals,
                target,
                data,
                withdrawals
            );
    }

    /// @notice proxyCallDiffs with pre-approved tokens and calldata metadata (metadata is ignored on-chain)
    function approveProxyCallDiffsWithMeta(
        IBalanceProxy balanceProxy,
        BalanceMetadata[] memory meta,
        IBalanceProxy.Balance[] memory diffs,
        IBalanceProxy.Approval[] memory approvals,
        address target,
        bytes memory data,
        IBalanceProxy.Balance[] memory withdrawals
    ) external payable returns (bytes memory) {
        // Validate metadata against diffs
        _checkMetadata(meta, diffs);

        // Pull tokens for approvals
        for (uint256 i = 0; i < approvals.length; i++) {
            IBalanceProxy.Balance memory bal = approvals[i].balance;
            uint256 amount = uint256(bal.balance);
            IERC20(bal.token).transferFrom(
                msg.sender,
                address(balanceProxy),
                amount
            );
        }

        // Delegate to BalanceProxy
        return
            balanceProxy.proxyCallDiffs{value: msg.value}(
                diffs,
                approvals,
                target,
                data,
                withdrawals
            );
    }
}
