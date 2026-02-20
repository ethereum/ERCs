// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBalanceProxy} from "./interfaces/IBalanceProxy.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title BalanceProxy
/// @notice Proxy contract for calling contracts with specified balances and approvals
/// @dev This contract is used to proxy calls to a target contract with specified balances and approvals
contract BalanceProxy is IBalanceProxy, ReentrancyGuard {
    /// @dev Internal function to check if a balance is sufficient
    /// @param balance Balance to check
    function _balanceCheck(Balance memory balance) internal view {
        uint256 actual = balance.token == address(0)
            ? balance.target.balance
            : IERC20(balance.token).balanceOf(balance.target);
        if (actual < SignedMath.abs(balance.balance)) {
            revert ERC8009BalanceConstraintViolation(
                balance.token,
                balance.target,
                balance.balance,
                actual
            );
        }
    }

    /// @dev Calldata version of internal function to check if a balance is sufficient
    /// @param balance Balance to check
    function _balanceCheckCalldata(Balance calldata balance) internal view {
        uint256 actual = balance.token == address(0)
            ? balance.target.balance
            : IERC20(balance.token).balanceOf(balance.target);
        if (actual < SignedMath.abs(balance.balance)) {
            revert ERC8009BalanceConstraintViolation(
                balance.token,
                balance.target,
                balance.balance,
                actual
            );
        }
    }

    /// @dev Internal function to apply approval instruction (memory)
    function _applyApproval(Approval memory approval) internal {
        Balance memory bal = approval.balance;
        uint256 amount = uint256(bal.balance);
        if (approval.useTransfer) {
            IERC20(bal.token).transfer(bal.target, amount);
        } else {
            IERC20(bal.token).approve(bal.target, amount);
        }
    }

    /// @dev Internal function to transfer a balance
    /// @param balance Balance to transfer
    function _transfer(Balance memory balance) internal {
        if (balance.token == address(0)) {
            payable(balance.target).transfer(SignedMath.abs(balance.balance));
        } else {
            IERC20(balance.token).transfer(
                balance.target,
                SignedMath.abs(balance.balance)
            );
        }
    }

    function _currentBalance(
        address token,
        address who
    ) internal view returns (uint256) {
        return token == address(0) ? who.balance : IERC20(token).balanceOf(who);
    }

    function proxyCall(
        Balance[] memory postBalances,
        Approval[] memory approvals,
        address target,
        bytes memory data,
        Balance[] memory withdrawals
    ) external payable override nonReentrant returns (bytes memory) {
        uint256 i;
        for (i = 0; i < approvals.length; i++) {
            _applyApproval(approvals[i]);
        }
        (bool success, bytes memory result) = target.call{value: msg.value}(
            data
        );
        if (!success) revert ERC8009CallFailed(target, data, result);
        for (i = 0; i < withdrawals.length; i++) {
            _transfer(withdrawals[i]);
        }
        for (i = 0; i < postBalances.length; i++) {
            _balanceCheck(postBalances[i]);
        }
        return result;
    }

    function proxyCallDiffs(
        Balance[] memory diffs,
        Approval[] memory approvals,
        address target,
        bytes memory data,
        Balance[] memory withdrawals
    ) external payable override nonReentrant returns (bytes memory) {
        uint256 i;
        uint256 len = diffs.length;
        uint256[] memory before = new uint256[](len);
        for (i = 0; i < len; i++)
            before[i] = _currentBalance(diffs[i].token, diffs[i].target);
        for (i = 0; i < approvals.length; i++) _applyApproval(approvals[i]);
        (bool success, bytes memory result) = target.call{value: msg.value}(
            data
        );
        if (!success) revert ERC8009CallFailed(target, data, result);
        for (i = 0; i < withdrawals.length; i++) _transfer(withdrawals[i]);
        for (i = 0; i < len; i++) {
            uint256 afterBal = _currentBalance(diffs[i].token, diffs[i].target);
            int256 actualDiff = int256(afterBal) - int256(before[i]);
            if (actualDiff < diffs[i].balance)
                revert ERC8009BalanceDiffConstraintViolation(
                    diffs[i].token,
                    diffs[i].target,
                    diffs[i].balance,
                    actualDiff
                );
        }
        return result;
    }

    receive() external payable {}
}
