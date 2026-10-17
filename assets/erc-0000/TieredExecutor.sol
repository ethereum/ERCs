// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

// Illustrative contract written for the non-ABI-dispatch companion ERC.
// It is NOT deployed anywhere; it exists to demonstrate a real pattern
// (a small trusted relayer that accepts one numeric operation tag and
// re-dispatches the call to one of several unrelated target interfaces,
// each with its own function signature and its own argument order) using
// concrete, compilable Solidity rather than pseudocode.
//
// See example-tiered-executor.json in this same folder for the ERC-7730
// descriptor that clear-signs calls to `executeOperation`, and
// example-reward-vault.json / example-legacy-token.json for the
// descriptors of the two target interfaces it dispatches into.

interface IRewardVault {
    function grantReward(address to, uint256 amount) external;
}

interface ILegacyToken {
    function creditAccount(uint256 amount, address to) external;
}

contract TieredExecutor {
    enum Operation {
        None, // 0 - unused, always rejected
        GrantReward, // 1 - IRewardVault.grantReward(address,uint256)
        CreditLegacy // 2 - ILegacyToken.creditAccount(uint256,address)
    }

    event Executed(Operation indexed op, address indexed target, address indexed account, uint256 amount);

    /// @param target The contract to route the call to.
    /// @param op Which trusted operation to perform.
    /// @param account The account argument for that operation.
    /// @param amount The amount argument for that operation.
    function executeOperation(address target, Operation op, address account, uint256 amount) external {
        if (op == Operation.GrantReward) {
            IRewardVault(target).grantReward(account, amount);
        } else if (op == Operation.CreditLegacy) {
            ILegacyToken(target).creditAccount(amount, account);
        } else {
            revert("TieredExecutor: unsupported operation");
        }
        emit Executed(op, target, account, amount);
    }
}
