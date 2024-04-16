---
eip: 7550
title: Transient ERC-20 Approvals
description: Transient ERC-20 approvals via function calls and EIP-712 secp256k1 signatures
author: Alex Kroeger (@akroeger-circle), Joey Santoro (@joeysantoro), Moody Salem (@moodysalem)
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: 2023-10-26
requires: 20, 712, 1153, 2612
---

## Abstract
This standard specifies a time-bound transient [ERC-20](./erc-20.md) token approval mechanism as a cheap augmentation of standard token approval functionality.

It includes a separate transient (single transaction) mapping of `transientAllowance` which can be set via a `transientApprove` call or a `transientPermit` signature.

`transientPermit` signatures allow the approved contract to spend an unlimited amount of tokens until the specified deadline. The approval is *intentionally replayable* in order to save an additional SSTORE and remove the need for nonces.

## Motivation

[ERC-20](./erc-20.md) approvals empower complex smart contract operation of token balances. These are typically achieved either natively or via [ERC-2612](./erc-2612.md) `permit`.

The `allowance` of a token is persistent until revoked or used. This has two drawbacks:
* gas expensive: requires an SSTORE to set and allowance and a second to use it
* security risk: if an approved contract is later found to be insecure then approved funds are at risk

EIP-1153 Transient Storage allows a parallel cheap approval mechanism which is bound to a single transaction. This simultaneously addresses both issues of persistent allowances.

## Specification

Compliant contracts must implement 3 new functions + 1 event in addition to ERC-20 and ERC-2612:

```sol
function transientAllowance(address owner, address spender) external view returns (uint)
function transientPermit(address owner, address spender, uint deadline, uint8 v, bytes32 r, bytes32 s) external
function transientApprove(address spender, uint amount) external

event TransientApproval(address indexed _owner, address indexed _spender, uint256 _value)
```

`transientAllowance`, `transientApprove`, and `TransientApproval` function identically to `allowance`, `approve`, `Approval` respectively, with the caveats that:
 - `transientAllowance` is uses EIP-1153 transient storage to track transient approvals
 - tokens SHOULD exclusively exhaust the transient allowance before checking or using the persistent allowance for `transferFrom`.


`transientPermit` functions as follows:

For all addresses `owner`, `spender`, uint256 `deadline`, uint8 `v`, bytes32 `r` and `s`,
a call to `transientPermit(owner, spender, deadline, v, r, s)` will set
`transientAllowance[owner][spender]` to `type(uint256).max`,
and emit a corresponding `TransientApproval` event,
if and only if the following conditions are met:

- The current blocktime is less than or equal to `deadline`.
- `owner` is not the zero address.
- `r`, `s` and `v` is a valid `secp256k1` signature from `owner` of the message:

If any of these conditions are not met, the `transientPermit` call must revert.

```sol
keccak256(abi.encodePacked(
   hex"1901",
   DOMAIN_SEPARATOR,
   keccak256(abi.encode(
            keccak256("TransientPermit(address owner,address spender,uint256 deadline)"),
            owner,
            spender,
            deadline))
))
```

where `DOMAIN_SEPARATOR` is defined according to EIP-712. The `DOMAIN_SEPARATOR` should be unique to the contract and chain to prevent replay attacks from other domains,
and satisfy the requirements of EIP-712, but is otherwise unconstrained.
A common choice for `DOMAIN_SEPARATOR` is:

```solidity
DOMAIN_SEPARATOR = keccak256(
    abi.encode(
        keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
        keccak256(bytes(name)),
        keccak256(bytes(version)),
        chainid,
        address(this)
));
```

In other words, the message is the EIP-712 typed structure:

```js
{
  "types": {
    "EIP712Domain": [
      {
        "name": "name",
        "type": "string"
      },
      {
        "name": "version",
        "type": "string"
      },
      {
        "name": "chainId",
        "type": "uint256"
      },
      {
        "name": "verifyingContract",
        "type": "address"
      }
    ],
    "TransientPermit": [
      {
        "name": "owner",
        "type": "address"
      },
      {
        "name": "spender",
        "type": "address"
      },
      {
        "name": "deadline",
        "type": "uint256"
      }
    ],
  },
  "primaryType": "TransientPermit",
  "domain": {
    "name": erc20name,
    "version": version,
    "chainId": chainid,
    "verifyingContract": tokenAddress
  },
  "message": {
    "owner": owner,
    "spender": spender,
    "deadline": deadline
  }
}
```

Note that nowhere in this definition we refer to `msg.sender`. The caller of the `transientPermit` function can be any address.

## Rationale

The main design changes from ERC-20 and ERC-2612 revolve around the decision to not include `nonce` or `value` in `transientPermit`.

The entire point of the transient approval mechnism is to provide an ultra cheap alternative to persistent approvals. Therefore, removing the usage of `nonce` (which require an additional SSTORE) is in line with the goal of making transient approvals as cheap as possible. The security tradeoffs of removing replay protection are worth it because users can simply use persistent approvals where security is of higher concern.

Because transient permit can be replayed, the `value` argument becomes useless and even misleading as it provides a false sense of security. Therefore only unlimited transientPermit is allowed.

## Backwards Compatibility

Transient Approval is fully backwards compatible with ERC-20, ERC-2612 and all other known EIPs and contracts.

## Security Considerations

All security considerations of EIP-2612 apply to `TransientPermit`.

Additionally, due to the lack of replay protection from the non-inclusion of nonces it is strongly recommended to use tight time bounds on any TransientPermit signatures.

If an unlimited transient approval is signed intentionally or unintentionally, it can be witheld indefinitely by any Relayer effectively acting as a secret approval not visible to the signer in any way.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
