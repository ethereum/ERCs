---
title: Bound Signatures
description: Binding y-parity compresses ECDSA signatures
author: William Morriss (@wjmelements)
discussions-to: https://ethereum-magicians.org/t/eip-2-signature-malleability-why-low-s-instead-of-dropping-v/
status: Draft
type: Standards Track
category: ERC
created: 2025-12-23
---

## Abstract
Recoverable ECDSA signatures can flip `s` and `v` while remaining valid, so they can be compressed to 64 bytes by restricting `v`.

## Motivation

ECDSA signatures are often encoded with three parameters: `v`, `r`, and `s`.
In the Solidity ABI encoding, this is 96 bytes.
By eliminating the degree of freedom, `v`, the encoded size of a recoverable signature can be reduced to 64 bytes.
Additionally, such signatures are not malleable.

## Specification

Smart contracts accepting bound signatures MUST supply `27` for `v`.

```solidity
ecrecover(digest, 27, r, s)
```

ECDSA signatures MUST be bound before supplied to such contracts. 

```ts
const SECP256K1_N: bigint = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n

function bind(sig: Signature, v: 27 | 28 = 27): Signature {
    if (sig.v === v) {
        return sig
    }
    const s = SECP256K1_N - sig.s
    return new Signature(sig.r, s, v)
}
```

## Rationale

Another signature compression approach, [ERC 2098](./erc-2098.md), stores the y-parity bit in the upper bit of the low `s`.
Bound signatures are preferrable because they are valid inputs to the `ecrecover` precompile.
They require less gas because they do not need to be unpacked by the smart contract.

`27` was chosen over `28` to make the y-parity falsy.

## Backwards Compatiblity

Bound signatures are compatible with `ecrecover` if 27 is supplied for the `v` parameter.
They cannot be used for transaction signatures because they permit high `s`, in violation of EIP-2.

## Test Cases

| Signer | Digest | `r` | `s` |
| ------ | ------ | --- | --- |
| `0x4a6f6B9fF1fc974096f9063a45Fd12bD5B928AD1` | `0xb0922c37cafd247fe3ada4eb1d1e3735b7d2837437c1178e9af120d535214270` | `0xdb7f75635124c807ec1f8b03e34cd76b633dc3a189e3c85fc5aee7e7d71df38c` | `0x5f1e6c6edf21cacfc2acba2815b253b9048b894eec5aaf70343389bb596c48bc` |
| `0x4a6f6B9fF1fc974096f9063a45Fd12bD5B928AD1` | `0xd92ff06caae7253883627416a425414d79e9003b91d6208add30e73735ef13c3` | `0xaa40efd534ac7f96b85babd7df9228fa131e8523115ca1ebc025698c37f3867d` | `0xaa40efd534ac7f96b85babd7df9228fa131e8523115ca1ebc025698c37f3867d` |
| `0x6B93E3bB9C0780C0f9042346Ffc379530a5882c1` | `0xfa75eba87f076cf22489da7c53a651bb3869473f78d09d4814afb7ab2d54ed45` | `0xaf4a877600ab6d14ebac626830cf1063d624487932b3cc73a7cd98ae7fbf337f` | `0xbc41d29acfcd3a1e7b5cb2dde1b85fe8882739312639b5f16d476a87584c040f` |

## Reference Implementation

[BoundSignatures.sol](https://github.com/wjmelements/bound-signatures)

## Copyright

Copyright and related rights waived via [CC0](https://raw.githubusercontent.com/ethereum/ERCs/master/LICENSE.md).
