---
title: Management Token Permit
description: Off-chain permit flow for ERC-7204 token managers
author: Xiang (@wenzhenxiang)
discussions-to: https://ethereum-magicians.org/t/contract-wallet-management-token-permit-extensions/25985
status: Draft
type: Standards Track
category: ERC
requires: 7204, 712
created: 2025-10-28
---

## Abstract

This proposal extends [ERC-7204](https://eips.ethereum.org/ERCS/erc-7204) smart-wallet token managers with an off-chain authorization flow similar to `permit`. It introduces nonce-tracked `tokenTransferWithSig`, `tokenApproveWithSig`, and `tokenSetApprovalForAllWithSig` functions so that transfers, individual allowances, and global operators can all be delegated after a typed-data signature is presented by the wallet owner. The extension defines canonical EIP-712 schemas, nonce accounting, and execution requirements for compliant implementations.

## Motivation

ERC-7204 describes a token management module for smart contract wallets, but stops short of standardising an off-chain signing workflow. Systems that wish to provide "red packet" transfers or delegated approvals must invent bespoke encodings and nonce tracking, reducing interoperability. A shared permit definition lets wallets, relayers, and user interfaces exchange signed transfer authorisations without bespoke integrations.

Goals:

- Allow wallets to hand out single-use, replay-protected transfer rights and operator approvals without on-chain transactions.
- Produce predictable EIP-712 schemas so that wallet UIs, SDKs, and relayers can sign and validate authorisations in a uniform manner.
- Maintain backwards compatibility with existing ERC-7204 deployments that do not implement permit extensions.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

The following additions are REQUIRED for an ERC-7204 compliant module that implements this extension.

### Interface

```solidity
interface IERC7204Permit {
    function tokenTransferNonce(address owner, address asset, address caller) external view returns (uint256);

    function tokenTransferWithSig(
        address owner,
        address asset,
        address to,
        uint256 value,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bool success);

    function tokenApproveNonce(address owner, address asset, address operator, address caller)
        external
        view
        returns (uint256);

    function tokenApproveWithSig(
        address owner,
        address asset,
        address operator,
        uint256 value,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bool success);

    function tokenApprovalForAllNonce(address owner, address caller) external view returns (uint256);

    function tokenSetApprovalForAllWithSig(
        address owner,
        address operator,
        bool approved,
        uint256 deadline,
        bytes calldata signature
    ) external returns (bool success);
}
```

- `tokenTransferNonce` MUST return a monotonically increasing nonce scoped to `(owner, asset, caller)`.
- `tokenTransferWithSig` MUST verify the signature via `isValidSignature`, require `msg.sender` to equal the signed `caller`, reject expired signatures (unless `deadline == 0`), increment the nonce before performing the transfer, and execute the same logic as `tokenTransfer` in ERC-7204.
- `tokenApproveWithSig` MUST mirror `tokenApprove`, using a nonce scoped to `(owner, asset, operator, caller)`.
- `tokenSetApprovalForAllWithSig` MUST mirror `tokenApproveForAll`, using a nonce scoped to `(owner, caller)`.

Implementations MUST support wallets that validate signatures through [ERC-1271](https://eips.ethereum.org/EIPS/eip-1271). Wallets MAY wrap signatures but the module MUST unwrap them prior to verification.

### Typed Data

Compliant implementations MUST hash the following payload and pass it to the wallet's signature validation logic. The `wallet` field identifies the smart wallet that owns the module. 

| Function | Primary Type | Fields |
|----------|--------------|--------|
| `tokenTransferWithSig` | `TokenTransferWithSig` | `wallet`, `owner`, `caller`, `asset`, `to`, `value`, `nonce`, `deadline` |
| `tokenApproveWithSig` | `TokenApproveWithSig` | `wallet`, `owner`, `caller`, `asset`, `operator`, `value`, `nonce`, `deadline` |
| `tokenSetApprovalForAllWithSig` | `TokenApprovalForAllWithSig` | `wallet`, `owner`, `caller`, `operator`, `approved`, `nonce`, `deadline` |

Every permit MUST use the EIP-712 domain:

- `name = "TokenManager Permit"`
- `version = "1"`
- `chainId` equal to the executing chain
- `verifyingContract = address(this)`

### Nonce Semantics

- `tokenTransferNonce` MUST be scoped per `(owner, asset, caller)`.
- `tokenApproveNonce` MUST be scoped per `(owner, asset, operator, caller)` to allow independent relayers.
- `tokenApprovalForAllNonce` MUST be scoped per `(owner, caller)`.

Each `WithSig` function MUST increment its nonce immediately before state changes and MUST revert on signature reuse.

### Execution Requirements

Implementations MUST:

1. Treat `deadline = 0` as non-expiring; otherwise enforce `block.timestamp <= deadline`.
2. Increment the scoped nonce before invoking the underlying ERC-7204 function.
3. Emit the same events as the underlying ERC-7204 functions.
4. Revert if signature validation fails, inputs mismatch, or deadlines are exceeded.

Wallets MAY offer helper wrappers, but they MUST NOT alter the semantics described above.

## Rationale

- Binding `caller` prevents relayers from reusing signatures intended for other executors.
- Independent nonce scopes prevent cross-operation replay while supporting multiple relayers per owner.
- Reusing the existing ERC-7204 entry points keeps events and accounting compatible with current deployments.

## Backwards Compatibility

Existing ERC-7204 modules remain valid. Clients SHOULD feature-detect permit support by checking for `IERC7204Permit` via ERC-165 or probing the new function selectors.

## Reference Implementation

A reference implementation will be published after community review. It validates the typed-data digest, increments the scoped nonce before external calls, and delegates to existing ERC-7204 functions so that storage and events remain unchanged.

## Security Considerations

- Nonces MUST increment even if downstream token interactions revert.
- Wallet owners SHOULD bound permit deadlines to reduce the risk of long-lived signatures.
- Relayers MUST ensure their transaction sender equals the signed `caller` to avoid wasted gas.

## Test Cases

A public test suite will accompany the reference implementation. Implementers are encouraged to cover:

- successful submissions for transfers, allowances, and operator approvals by authorised relayers,
- rejection of expired, replayed, or mismatched signatures,
- nonce increment behaviour when token interactions revert,
- replay protection across all nonce scopes.

## Copyright

Copyright and related rights waived via [CC0-1.0](https://creativecommons.org/publicdomain/zero/1.0/).
