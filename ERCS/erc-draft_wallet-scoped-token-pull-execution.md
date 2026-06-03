---
title: Wallet-Scoped Token Pull Execution
description: Wallet primitive for temporary ERC-20 pull authorization during one external call.
author: Xiang (@wenzhenxiang)
discussions-to: https://ethereum-magicians.org/t/erc-wallet-scoped-token-pull-execution/28691
status: Draft
type: Standards Track
category: ERC
created: 2026-06-03
requires: 20, 165
---

## Abstract

This ERC defines a wallet-native primitive for temporary [ERC-20](./eip-20.md) pull authorization during one external call.

A compliant account exposes `executeWithTokenPull`, which opens a transient pull context for one target, one asset, and one maximum amount. During that call, the bound target may pull tokens by calling `tokenPullToCaller`. Outside the active call window, pull attempts MUST fail.

## Motivation

Many ERC-20 settlement flows need something narrower than `approve` and more execution-local than a separate signature-based transfer path. Persistent allowances are broader than users usually intend, while a plain wallet-side `transfer` is often too inflexible for targets that determine the final amount during execution.

The common `approve`-then-call pattern is also cumbersome and gas-expensive. It often requires a separate approval transaction before settlement, plus a later revocation if the user wants to remove the allowance.

This ERC standardizes a narrow pattern:

- the wallet wants to call an external target;
- the target may need to collect one specific ERC-20 token during that call;
- the wallet wants temporary, target-bound, asset-bound, and amount-capped authorization; and
- the wallet does not want to leave behind a reusable allowance.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Account**: a smart contract wallet or equivalent smart account that implements this ERC.
- **Target**: the external contract that is called through `executeWithTokenPull`.
- **Pull context**: the active execution-local authorization tuple `(target, asset, remainingAmount)`.

### Interface

Accounts implementing this ERC MUST expose the following interface:

```solidity
pragma solidity ^0.8.23;

interface IERCWalletTokenPullExecutor {
    function executeWithTokenPull(
        address target,
        bytes calldata data,
        address asset,
        uint256 maxAmount
    ) external;

    function tokenPullToCaller(address asset, uint256 amount) external;
}
```

Accounts implementing this ERC MUST also implement [ERC-165](./eip-165.md).

- `supportsInterface(type(IERCWalletTokenPullExecutor).interfaceId)` MUST return `true`.
- `supportsInterface(type(IERC165).interfaceId)` MUST return `true`.

### Execution Semantics

`executeWithTokenPull(target, data, asset, maxAmount)` performs one external call while exposing a temporary ERC-20 pull capability to `target`.

An implementation of `executeWithTokenPull`:

1. MUST create an active pull context bound to:
   - `target` as the only authorized caller of `tokenPullToCaller`;
   - `asset` as the only transferable ERC-20 asset; and
   - `maxAmount` as the maximum total amount that may be pulled during the active execution.
2. MUST perform exactly one external `call` to `target` using `data`.
3. MUST clear the active pull context before returning.
4. MUST clear the active pull context before propagating a revert from the external call.
5. MUST return successfully if the external call succeeds.
6. MUST bubble revert data from the external call when revert data is available. If no revert data is available, it MUST revert with an implementation-defined error.

An implementation MAY reject unsupported or unsafe parameters or execution shapes, such as zero-address targets, zero-address assets, unsupported token contracts, concurrent pull contexts, or active runtime contexts. Those restrictions are outside the scope of this ERC and SHOULD be documented for integrators.

The authorization model for who may call `executeWithTokenPull` is outside the scope of this ERC. An account MAY restrict it to owners, to the account itself, to an entry point, or to another account-defined authority model.

### Pull Semantics

`tokenPullToCaller(asset, amount)` transfers the requested ERC-20 amount from the implementing account to the caller, subject to the active pull context.

An implementation of `tokenPullToCaller`:

1. MUST revert if no token-pull context is active.
2. MUST revert unless `msg.sender` equals the `target` bound in the active pull context.
3. MUST revert unless `asset` equals the `asset` bound in the active pull context.
4. MUST revert unless `amount` is less than or equal to the remaining authorized amount in the active pull context.
5. MUST reduce the remaining authorized amount by `amount` before transferring tokens.
6. MUST transfer exactly `amount` of the bound token from the implementing account to `msg.sender`.

After `executeWithTokenPull` returns or reverts, subsequent calls to `tokenPullToCaller` for that context MUST revert.

### ERC-20 Transfer Behavior

The `asset` contract is expected to follow ERC-20 transfer semantics.

Implementations:

- MUST treat a failed or reverting token transfer as a failure of `tokenPullToCaller`;
- SHOULD use a transfer helper equivalent to `safeTransfer`;
- MUST NOT silently ignore transfer failure; and
- MUST NOT permit the bound target to exceed the active cap by splitting requests across multiple `tokenPullToCaller` calls.

## Rationale

The core design goal is to authorize one transfer window rather than a reusable allowance relationship. Binding the pull to one `target`, one `asset`, and one remaining amount keeps the wallet authorization surface narrow while still allowing the target to determine the final amount during execution.

`tokenPullToCaller` transfers only to `msg.sender`, so the address authorized to pull is also the recipient. Nested pull contexts, runtime-context interactions, and account authorization models are left to implementations.

## Backwards Compatibility

This ERC is additive. It does not modify ERC-20 transfer behavior and does not require changes to existing token contracts. It introduces a new wallet-native settlement path rather than changing allowance semantics.

## Test Cases

Implementations SHOULD cover at least the following cases:

- `executeWithTokenPull` succeeds when `target` pulls one amount within the bound cap.
- `executeWithTokenPull` succeeds when `target` pulls multiple amounts whose sum stays within the bound cap.
- `tokenPullToCaller` reverts after the outer execution has finished.
- `tokenPullToCaller` reverts when called by a contract other than the bound `target`.
- `tokenPullToCaller` reverts when the requested `asset` does not match the bound `asset`.
- `tokenPullToCaller` reverts when the requested amount exceeds the remaining authorized amount.
- `executeWithTokenPull` clears context and bubbles revert data when the external call fails.
- the account reports support for this ERC through ERC-165.

## Reference Implementation

The following example uses transient storage for the pull context:

```solidity
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IERCWalletTokenPullExecutor {
    function executeWithTokenPull(
        address target,
        bytes calldata data,
        address asset,
        uint256 maxAmount
    ) external;

    function tokenPullToCaller(address asset, uint256 amount) external;
}

abstract contract ERCWalletTokenPullReference is IERC165, IERCWalletTokenPullExecutor {
    using SafeERC20 for IERC20;

    bytes32 private constant TARGET_SLOT = bytes32(uint256(keccak256("walletTokenPull.target")) - 1);
    bytes32 private constant ASSET_SLOT = bytes32(uint256(keccak256("walletTokenPull.asset")) - 1);
    bytes32 private constant REMAINING_SLOT = bytes32(uint256(keccak256("walletTokenPull.remaining")) - 1);

    error PullInactive();
    error UnauthorizedPull();
    error AssetMismatch();
    error AmountExceeded();

    function executeWithTokenPull(
        address target,
        bytes calldata data,
        address asset,
        uint256 maxAmount
    ) external override {
        _authorizeExecuteWithTokenPull();
        _setPullContext(target, asset, maxAmount);
        (bool success, bytes memory response) = target.call(data);
        _clearPullContext();

        if (!success) {
            assembly ("memory-safe") {
                revert(add(response, 32), mload(response))
            }
        }
    }

    function tokenPullToCaller(address asset, uint256 amount) external override {
        (address target, address configuredAsset, uint256 remaining) = _pullContext();
        if (target == address(0)) revert PullInactive();
        if (msg.sender != target) revert UnauthorizedPull();
        if (asset != configuredAsset) revert AssetMismatch();
        if (amount > remaining) revert AmountExceeded();

        _setRemaining(remaining - amount);
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERCWalletTokenPullExecutor).interfaceId;
    }

    function _authorizeExecuteWithTokenPull() internal view virtual;

    function _pullContext() internal view returns (address target, address asset, uint256 remaining) {
        assembly {
            target := tload(TARGET_SLOT)
            asset := tload(ASSET_SLOT)
            remaining := tload(REMAINING_SLOT)
        }
    }

    function _setPullContext(address target, address asset, uint256 remaining) internal {
        assembly {
            tstore(TARGET_SLOT, target)
            tstore(ASSET_SLOT, asset)
            tstore(REMAINING_SLOT, remaining)
        }
    }

    function _setRemaining(uint256 remaining) internal {
        assembly {
            tstore(REMAINING_SLOT, remaining)
        }
    }

    function _clearPullContext() internal {
        _setPullContext(address(0), address(0), 0);
    }
}
```

## Security Considerations

The bound target is intentionally allowed to decide whether and how much token balance to collect during the call, subject to the cap. Integrators SHOULD treat `target` as a real trust boundary.

Implementations MUST clear the pull context on both success and failure and reason carefully about reentrancy into account code, target code, and token code.

Some ERC-20 tokens have non-standard return values or fee-on-transfer behavior. Implementers SHOULD use transfer helpers that correctly handle transfer failure and SHOULD document any exact-debit assumptions.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
