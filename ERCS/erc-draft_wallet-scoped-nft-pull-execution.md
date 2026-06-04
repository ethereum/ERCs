---
title: Wallet-Scoped NFT Pull Execution
description: Wallet primitive for temporary NFT pull authorization during one external call.
author: Xiang (@wenzhenxiang)
discussions-to: https://ethereum-magicians.org/t/erc-8285-wallet-nft-pull-execution/28693
status: Draft
type: Standards Track
category: ERC
created: 2026-06-03
requires: 165, 721
---

## Abstract

This standard defines a wallet-native primitive for temporary NFT pull authorization during one external call.

A compliant account exposes `executeWithNftPull`, which opens a transient pull context for one target, one [ERC-721](./eip-721.md) asset, and one token id. During that call, the bound target may pull the NFT by calling `nftPullToCaller`. Outside the active call window, pull attempts MUST fail.

## Motivation

Many NFT settlement flows need a transfer authorization that is narrower than persistent operator approval and more execution-local than a separate signature-based transfer path. A plain wallet-side `safeTransferFrom` is often too inflexible for targets that decide during execution whether to take custody.

This standardizes a narrow pattern:

- the wallet wants to call an external target;
- the target may need to collect one specific NFT during that call;
- the wallet wants temporary, target-bound, asset-bound, and token-id-bound authorization; and
- the wallet does not want to leave behind a reusable operator approval.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Account**: a smart contract wallet or equivalent smart account that implements this standard.
- **Target**: the external contract that is called through `executeWithNftPull`.
- **Pull context**: the active execution-local authorization tuple `(target, asset, tokenId)`.

### Interface

Accounts implementing this standard MUST expose the following interface:

```solidity
pragma solidity ^0.8.23;

interface IERCWalletNftPullExecutor {
    function executeWithNftPull(
        address target,
        bytes calldata data,
        address asset,
        uint256 tokenId
    ) external;

    function nftPullToCaller(address asset, uint256 tokenId) external;
}
```

Accounts implementing this standard MUST also implement [ERC-165](./eip-165.md).

- `supportsInterface(type(IERCWalletNftPullExecutor).interfaceId)` MUST return `true`.
- `supportsInterface(type(IERC165).interfaceId)` MUST return `true`.

### Execution Semantics

`executeWithNftPull(target, data, asset, tokenId)` performs one external call while exposing a temporary NFT-pull capability to `target`.

An implementation of `executeWithNftPull`:

1. MUST create an active pull context bound to:
   - `target` as the only authorized caller of `nftPullToCaller`;
   - `asset` as the only transferable ERC-721 asset; and
   - `tokenId` as the only transferable token id.
2. MUST perform exactly one external `call` to `target` using `data`.
3. MUST clear the active pull context before returning.
4. MUST clear the active pull context before propagating a revert from the external call.
5. MUST return successfully if the external call succeeds.
6. MUST bubble revert data from the external call when revert data is available. If no revert data is available, it MUST revert with an implementation-defined error.

An implementation MAY reject unsupported or unsafe parameters or execution shapes, such as zero-address targets, zero-address assets, unsupported NFT contracts, concurrent pull contexts, or active runtime contexts. Those restrictions are outside the scope of this ERC and SHOULD be documented for integrators.

The authorization model for who may call `executeWithNftPull` is outside the scope of this ERC. An account MAY restrict it to owners, to the account itself, to an entry point, or to another account-defined authority model.

### Pull Semantics

`nftPullToCaller(asset, tokenId)` transfers the bound NFT from the implementing account to the caller, subject to the active pull context.

An implementation of `nftPullToCaller`:

1. MUST revert if no NFT pull context is active.
2. MUST revert unless `msg.sender` equals the `target` bound in the active pull context.
3. MUST revert unless `asset` equals the `asset` bound in the active pull context.
4. MUST revert unless `tokenId` equals the `tokenId` bound in the active pull context.
5. MUST transfer exactly that NFT from the implementing account to `msg.sender`.

After `executeWithNftPull` returns or reverts, subsequent calls to `nftPullToCaller` for that context MUST revert.

### ERC-721 Transfer Behavior

The `asset` contract is expected to follow ERC-721 transfer semantics.

Implementations:

- MUST treat a failed or reverting NFT transfer as a failure of `nftPullToCaller`;
- SHOULD use `safeTransferFrom` unless an implementation has a strong reason to prefer another ERC-721 transfer method; and
- MUST NOT silently ignore transfer failure.

## Rationale

The core design goal is to authorize one transfer window rather than a reusable operator relationship. Binding the pull to one `target`, one `asset`, and one `tokenId` keeps the wallet authorization surface narrow while still allowing the target to decide whether to take custody during execution.

`nftPullToCaller` transfers only to `msg.sender`, so the address authorized to pull is also the recipient. Nested pull contexts, runtime-context interactions, and account authorization models are left to implementations.

## Backwards Compatibility

This standard is additive. It does not modify ERC-721 transfer behavior and does not require changes to existing token contracts. It introduces a new wallet-native settlement path rather than changing approval semantics.

## Test Cases

Implementations SHOULD cover at least the following cases:

- `executeWithNftPull` succeeds when `target` pulls the exact bound NFT.
- `nftPullToCaller` reverts after the outer execution has finished.
- `nftPullToCaller` reverts when called by a contract other than the bound `target`.
- `nftPullToCaller` reverts when the requested `asset` does not match the bound `asset`.
- `nftPullToCaller` reverts when the requested `tokenId` does not match the bound `tokenId`.
- `executeWithNftPull` clears context and bubbles revert data when the external call fails.
- the account reports support for this standard through ERC-165.

## Reference Implementation

The following example uses transient storage for the pull context:

```solidity
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IERCWalletNftPullExecutor {
    function executeWithNftPull(
        address target,
        bytes calldata data,
        address asset,
        uint256 tokenId
    ) external;

    function nftPullToCaller(address asset, uint256 tokenId) external;
}

abstract contract ERCWalletNftPullReference is IERC165, IERCWalletNftPullExecutor {
    bytes32 private constant TARGET_SLOT = bytes32(uint256(keccak256("walletNftPull.target")) - 1);
    bytes32 private constant ASSET_SLOT = bytes32(uint256(keccak256("walletNftPull.asset")) - 1);
    bytes32 private constant TOKEN_ID_SLOT = bytes32(uint256(keccak256("walletNftPull.tokenId")) - 1);

    error PullInactive();
    error UnauthorizedPull();
    error AssetMismatch();
    error TokenIdMismatch();

    function executeWithNftPull(
        address target,
        bytes calldata data,
        address asset,
        uint256 tokenId
    ) external override {
        _authorizeExecuteWithNftPull();
        _setPullContext(target, asset, tokenId);
        (bool success, bytes memory response) = target.call(data);
        _clearPullContext();

        if (!success) {
            assembly ("memory-safe") {
                revert(add(response, 32), mload(response))
            }
        }
    }

    function nftPullToCaller(address asset, uint256 tokenId) external override {
        (address target, address configuredAsset, uint256 configuredTokenId) = _pullContext();
        if (target == address(0)) revert PullInactive();
        if (msg.sender != target) revert UnauthorizedPull();
        if (asset != configuredAsset) revert AssetMismatch();
        if (tokenId != configuredTokenId) revert TokenIdMismatch();

        IERC721(asset).safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERCWalletNftPullExecutor).interfaceId;
    }

    function _authorizeExecuteWithNftPull() internal view virtual;

    function _pullContext() internal view returns (address target, address asset, uint256 tokenId) {
        assembly {
            target := tload(TARGET_SLOT)
            asset := tload(ASSET_SLOT)
            tokenId := tload(TOKEN_ID_SLOT)
        }
    }

    function _setPullContext(address target, address asset, uint256 tokenId) internal {
        assembly {
            tstore(TARGET_SLOT, target)
            tstore(ASSET_SLOT, asset)
            tstore(TOKEN_ID_SLOT, tokenId)
        }
    }

    function _clearPullContext() internal {
        _setPullContext(address(0), address(0), 0);
    }
}
```

## Security Considerations

The bound target is intentionally allowed to decide whether to take custody of the NFT during the call. Integrators SHOULD treat `target` as a real trust boundary.

Implementations MUST clear the pull context on both success and failure and reason carefully about reentrancy into account code, target code, and NFT code.

If `safeTransferFrom` is used, the target or its receiving hooks may execute additional logic during receipt. Implementers SHOULD account for that when reasoning about reentrancy and settlement behavior.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
