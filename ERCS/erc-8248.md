---
title: Keyed Transfer With Authorization
description: ERC-20 transfer authorization with two-dimensional sequential nonces
author: Brian Bland (@brianbland)
discussions-to: https://ethereum-magicians.org/t/erc-keyed-transfer-with-authorization
status: Draft
type: Standards Track
category: ERC
created: 2026-04-22
requires: 20, 712
---

## Abstract

This ERC defines a signed transfer authorization scheme for [ERC-20](./eip-20.md) tokens that uses a two-dimensional nonce: a 192-bit `nonceKey` selects an independent sequence, and a 64-bit `nonce` is consumed sequentially within that sequence. The encoding matches [ERC-4337](./eip-4337.md)'s "Semi-abstracted Nonce Support" exactly.

It addresses the same use case as [ERC-3009](./eip-3009.md) "Transfer With Authorization" — gasless meta-transaction transfers signed off-chain — but is optimized for repeat-counterparty access patterns. When a payer authorizes many transfers to the same counterparty (e.g. a buyer agent paying a single seller), all of those authorizations consume one storage slot per `(payer, key)` pair instead of one slot per authorization. This reduces persistent storage growth by orders of magnitude for the repeat-counterparty patterns now common in agentic and machine-to-machine payments.

## Motivation

ERC-3009's random `bytes32` nonces require one persistent storage slot per authorization, with no opportunity for reuse. This works well for one-shot transfers but accumulates storage indefinitely under high-frequency repeat-counterparty patterns.

Two access patterns are observed in practice:

- **Loyal-customer**: a single payer issues many authorizations to a small set of counterparties.
- **Explorer**: a single payer (typically a marketplace or aggregator contract) issues authorizations across many distinct counterparties.

An analysis of 60 days of USDC `transferWithAuthorization` traffic on Base (4,403,045 authorization events across 80,374 unique authorizers) shows that the loyal-customer pattern strongly dominates among high-volume payers: **17 of the top 20 authorizers** paid a small fixed set of counterparties, with 13 of those paying exactly one counterparty. The top authorizer issued 81,731 authorizations to a single payee over the period. Three authorizers followed the explorer pattern, paying thousands of distinct counterparties.

For the loyal-customer pattern, two-dimensional sequential nonces collapse storage to one slot per `(payer, counterparty)` pair:

| Scheme | Slots (81,731 authorizations, 1 counterparty) | vs. ERC-3009 |
| --- | --- | --- |
| ERC-3009 (random `bytes32`) | 81,731 | 1× |
| Bitmap (256 nonces per slot) | 320 | 256× |
| Keyed sequential (this ERC) | 1 | 81,731× |

Across all 17 loyal-customer buyers in the sample, keyed sequential nonces require fewer than 60 total nonce storage slots for over 780,000 authorizations — compared to over 2,800 slots for a bitmap scheme.

For the explorer pattern a bitmap is a better match, and implementations MAY expose a bitmap entry point alongside this one. Specifying both schemes in a single ERC was considered and rejected as overscoped; this ERC standardizes only the keyed sequential entry point.

The `(uint192, uint64)` partition is identical to the encoding ERC-4337 uses for UserOperation nonces (see its "Semi-abstracted Nonce Support" section), and is a natural fit for any payer that holds independent payment relationships with multiple counterparties. The 192-bit key is wide enough to hold a counterparty address (160 bits) with 32 bits of subkey for channel separation; payers SHOULD use the upper 32 bits as a channel identifier to keep distinct agents acting under the same payee on independent counters.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Storage

A compliant contract MUST maintain a mapping from `(authorizer, nonceKey)` to the next expected sequence value:

```solidity
mapping(address => mapping(uint192 => uint64)) internal _keyedNonces;
```

For any `(authorizer, nonceKey)` pair never used, the value MUST be `0`. The first authorization signed under a new key therefore uses `nonce = 0`.

### Events

```solidity
event KeyedAuthorizationUsed(
    address indexed authorizer,
    uint192 indexed nonceKey,
    uint64 indexed nonce
);
```

The OPTIONAL cancellation event:

```solidity
event KeyedAuthorizationCanceled(
    address indexed authorizer,
    uint192 indexed nonceKey,
    uint64 indexed nonce
);
```

### Type hashes

```solidity
bytes32 public constant TRANSFER_WITH_KEYED_AUTHORIZATION_TYPEHASH = keccak256(
    "TransferWithKeyedAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,uint192 nonceKey,uint64 nonce)"
);

bytes32 public constant RECEIVE_WITH_KEYED_AUTHORIZATION_TYPEHASH = keccak256(
    "ReceiveWithKeyedAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,uint192 nonceKey,uint64 nonce)"
);

// OPTIONAL
bytes32 public constant CANCEL_KEYED_AUTHORIZATION_TYPEHASH = keccak256(
    "CancelKeyedAuthorization(address authorizer,uint192 nonceKey,uint64 nonce)"
);
```

Each type hash binds the full parameter set including the split `(uint192 nonceKey, uint64 nonce)`. A digest signed under one of these type hashes cannot be reinterpreted as a digest under any type hash with a different parameter shape; this provides structural isolation from any other signed-authorization scheme a token contract might also implement.

### Functions

```solidity
/**
 * @notice Returns the next expected nonce for an (authorizer, nonceKey) pair,
 *         packed in the ERC-4337 form: (uint256(nonceKey) << 64) | sequence.
 * @dev    The low 64 bits hold the next expected sequence value; the high 192
 *         bits echo `nonceKey`. For an unused key, the return value equals
 *         `uint256(nonceKey) << 64`. The next valid signed authorization under
 *         that key must specify `nonce` equal to the low 64 bits.
 */
function keyedAuthorizationNonce(address authorizer, uint192 nonceKey)
    external view returns (uint256);

/**
 * @notice Execute a transfer with a signed keyed authorization.
 * @param from         Payer's address (Authorizer)
 * @param to           Payee's address
 * @param value        Amount to be transferred
 * @param validAfter   The time after which this is valid (unix time)
 * @param validBefore  The time before which this is valid (unix time)
 * @param nonceKey     Independent 192-bit sequence selector (e.g. payee address)
 * @param nonce        Sequential 64-bit counter within nonceKey
 * @param v            v of the signature
 * @param r            r of the signature
 * @param s            s of the signature
 */
function transferWithKeyedAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    uint192 nonceKey,
    uint64 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
) external;

/**
 * @notice Receive a transfer with a signed keyed authorization from the payer.
 * @dev    Requires `to == msg.sender` to prevent front-running of wrapper calls.
 *         All other parameters as in transferWithKeyedAuthorization.
 */
function receiveWithKeyedAuthorization(
    address from,
    address to,
    uint256 value,
    uint256 validAfter,
    uint256 validBefore,
    uint192 nonceKey,
    uint64 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
) external;
```

OPTIONAL:

```solidity
/**
 * @notice Cancel all unused authorizations under (authorizer, nonceKey) with
 *         sequence values up to and including `nonce`.
 * @dev    Reverts unless `nonce >= keyedAuthorizationNonce(authorizer, nonceKey)`.
 *         On success, sets the stored sequence to `nonce + 1` without performing
 *         a transfer. Any signed authorization with sequence value <= `nonce`
 *         that was not yet consumed becomes permanently unusable.
 */
function cancelKeyedAuthorization(
    address authorizer,
    uint192 nonceKey,
    uint64 nonce,
    uint8 v,
    bytes32 r,
    bytes32 s
) external;
```

### Validation rules

A compliant `transferWithKeyedAuthorization` (and `receiveWithKeyedAuthorization`) implementation MUST reject the call unless ALL of the following hold:

- `from != address(0)`.
- `block.timestamp > validAfter`.
- `block.timestamp < validBefore`.
- `nonce == _keyedNonces[from][nonceKey]`. (This single equality enforces both replay protection and in-order consumption.)
- For `receiveWithKeyedAuthorization` only: `to == msg.sender`.
- The signer recovered from `(v, r, s)` over the EIP-712 digest of the appropriate type hash and parameters equals `from`. The zero address MUST NOT be accepted as the recovered signer (the explicit `from != address(0)` check above is required because `ecrecover` returns the zero address on invalid signatures, so omitting it would let any garbage signature pass when `from == address(0)`).

On a successful call, the implementation MUST:

1. Set `_keyedNonces[from][nonceKey] = nonce + 1`.
2. Emit `KeyedAuthorizationUsed(from, nonceKey, nonce)`.
3. Execute the underlying ERC-20 transfer of `value` from `from` to `to`.

Implementations MUST NOT accept `nonce` values that skip ahead of or fall behind the stored counter. The 64-bit width of `nonce` admits 2⁶⁴ authorizations per key before saturation; in Solidity 0.8+ the increment in step 1 reverts on overflow. Payers approaching saturation can rotate to a new `nonceKey`.

A compliant `cancelKeyedAuthorization` implementation MUST reject the call unless ALL of the following hold:

- `authorizer != address(0)`.
- `nonce >= _keyedNonces[authorizer][nonceKey]`.
- The signer recovered from `(v, r, s)` over the EIP-712 digest of `CANCEL_KEYED_AUTHORIZATION_TYPEHASH` equals `authorizer`. The zero address MUST NOT be accepted as the recovered signer.

On a successful cancel, the implementation MUST:

1. Set `_keyedNonces[authorizer][nonceKey] = nonce + 1`.
2. Emit `KeyedAuthorizationCanceled(authorizer, nonceKey, nonce)`.

### EIP-712 message construction

The signed digest follows [EIP-712](./eip-712.md):

```
TypeHash := keccak256(
  "TransferWithKeyedAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,uint192 nonceKey,uint64 nonce)"
)
StructHash := keccak256(abi.encode(TypeHash, from, to, value, validAfter, validBefore, nonceKey, nonce))
Digest := keccak256(0x1901 ‖ DomainSeparator ‖ StructHash)
{ v, r, s } := Sign(Digest, PrivateKey)
```

## Rationale

### Why `(uint192, uint64)` and not a bitmap

The two designs target different patterns:

- **Keyed sequential** (this ERC): one slot per `(payer, key)` pair. Optimal when a payer issues many authorizations to a small number of counterparties.
- **Bitmap** (256 nonces per slot, allowing out-of-order consumption): optimal when a payer issues authorizations to many distinct counterparties.

The Motivation section explains why the loyal-customer pattern dominates and is the primary target of this ERC. The two designs are not mutually exclusive: a token contract MAY expose a bitmap entry point alongside this ERC for payers whose access pattern fits the explorer model.

### Equivalence with ERC-4337 nonce encoding

The pair `(nonceKey, nonce)` corresponds bit-for-bit to the `uint256` nonce used by ERC-4337 (see its "Semi-abstracted Nonce Support" section):

```
uint256 packed = (uint256(nonceKey) << 64) | uint256(nonce);
uint192 nonceKey = uint192(packed >> 64);
uint64  nonce    = uint64(packed);
```

Implementations MAY expose helper views that accept the packed `uint256` form for tooling that already speaks ERC-4337 nonces, but the canonical EIP-712 type uses the split form for clarity and type safety.

### Why per-counterparty as the canonical key

The 192-bit key is opaque to the contract; payers MAY use any value. The recommended convention for payer-to-payee transfers is `nonceKey = uint192(uint160(payeeAddress))`, with the upper 32 bits available as a subkey for channel separation (e.g. distinguishing different agents that share a payer key). This convention:

- Lets the payee propose its own `nonce` value with no coordination beyond reading `keyedAuthorizationNonce(payer, key)`.
- Preserves independence across counterparties: a stuck or dropped authorization to one payee does not block authorizations to any other payee.
- Maps naturally onto request/response payment protocols where the payee specifies payment terms.

### Why sequential within a key (not random)

Random nonces within a key would defeat the storage saving: the contract would have to retain a per-nonce used-bit, collapsing the design back to one storage slot per authorization. Sequential consumption is what makes the storage collapse to a single counter.

The downside is that out-of-order submission within a key fails. This is acceptable for the target pattern because the payee proposes the nonce as part of the payment request, so concurrent in-flight authorizations under the same key are already a coordination error on the payee's side. Payers that need parallelism can use distinct keys (e.g. one per concurrent payment channel).

### Why `(v, r, s)` rather than `bytes memory signature`

This ERC uses the `(v, r, s)` triple rather than a packed `bytes` signature to minimize calldata overhead and avoid in-contract signature splitting. Smart-contract-wallet support via [ERC-1271](./eip-1271.md) is orthogonal and can be added in a follow-on extension that introduces parallel function variants accepting `bytes signature`.

### Cancellation semantics

`cancelKeyedAuthorization` advances the sequence to `nonce + 1` and accepts any `nonce` greater than or equal to the current expected value. This invalidates every signed authorization with sequence value at most `nonce` that has not yet been consumed. Cancellation operates on the counter directly because the keyed scheme stores no per-nonce used-bit (which would defeat the storage benefit).

To invalidate a single in-flight authorization, the payer signs a cancel with `nonce` equal to the current expected value. To invalidate every outstanding authorization at once, the payer signs a cancel with `nonce` equal to the highest sequence value they have ever signed under the key. A cancel with a `nonce` less than the current expected value is stale and reverts; replays of an executed cancel are therefore impossible because the counter only advances.

## Backwards Compatibility

No backward compatibility issues found. This ERC introduces new function selectors, a new EIP-712 type hash, and a new storage region; it does not modify any prior standard.

## Test Cases

### Authorization consumption

| # | Setup | Action | Expected |
| --- | --- | --- | --- |
| 1 | Fresh `(payer, key)`; signed authorization with `nonce = 0` | Submit | Succeeds; counter → 1 |
| 2 | Counter at 1; signed authorization with `nonce = 0` | Submit | Reverts (replay) |
| 3 | Counter at 1; signed authorization with `nonce = 1` | Submit | Succeeds; counter → 2 |
| 4 | Counter at 1; signed authorization with `nonce = 2` | Submit | Reverts (skip ahead) |
| 5 | Counter at 0 for keyA; submit authorization for keyB with `nonce = 0` | Submit | Succeeds; keyA counter unchanged |
| 6 | Two authorizations under same key with `nonce = 0` | Submit both | First succeeds, second reverts |
| 7 | Authorization with `validAfter = block.timestamp` | Submit | Reverts (not yet valid) |
| 8 | Authorization with `validBefore = block.timestamp` | Submit | Reverts (expired) |

### Cross-replay isolation

| # | Setup | Action | Expected |
| --- | --- | --- | --- |
| 9 | Signed `TransferWithKeyedAuthorization` digest | Submit to ERC-3009 `transferWithAuthorization` | Reverts (signature does not recover to `from`) |
| 10 | Signed ERC-3009 `TransferWithAuthorization` digest | Submit to `transferWithKeyedAuthorization` | Reverts (signature does not recover to `from`) |
| 11 | Signed `TransferWithKeyedAuthorization` digest from chain A | Submit on chain B with same contract address | Reverts (EIP-712 chainId binding rejects cross-chain replay) |

### Receive front-running protection

| # | Setup | Action | Expected |
| --- | --- | --- | --- |
| 12 | Signed `ReceiveWithKeyedAuthorization`; `to = X`; submitted by `Y` | Submit | Reverts (`to != msg.sender`) |
| 13 | Signed `ReceiveWithKeyedAuthorization`; `to = X`; submitted by `X` | Submit | Succeeds |
| 14 | Signed `TransferWithKeyedAuthorization`; `to = X`; submitted by `Y` | Submit | Succeeds (transfer variant has no caller restriction) |

### Cancellation

| # | Setup | Action | Expected |
| --- | --- | --- | --- |
| 15 | Counter at 5; signed cancel with `nonce = 5` | Submit | Succeeds; counter → 6 |
| 16 | Counter at 5; signed cancel with `nonce = 7` | Submit | Succeeds; counter → 8 (invalidates outstanding nonces 5, 6, 7) |
| 17 | Counter at 5; signed cancel with `nonce = 4` | Submit | Reverts (stale) |
| 18 | After cancel(7); previously-signed authorization with `nonce = 6` | Submit | Reverts (counter has advanced past) |
| 19 | After cancel(7); previously-signed authorization with `nonce = 8` | Submit | Succeeds (above the cancel threshold) |
| 20 | Counter at 8; replay of executed cancel(`nonce = 7`) | Submit | Reverts (stale) |

## Reference Implementation

The reference implementation assumes the surrounding token contract provides:

- An internal `_transfer(address from, address to, uint256 value)` performing the underlying ERC-20 transfer.
- A `DOMAIN_SEPARATOR` immutable computed per [EIP-712](./eip-712.md).
- An `EIP712.recover(bytes32 domain, uint8 v, bytes32 r, bytes32 s, bytes32 structHash)` helper that computes the EIP-712 digest from the domain separator and struct hash and recovers the signer address.

```solidity
abstract contract KeyedTransferAuthorization is IERC20Transfer, EIP712Domain {
    bytes32 public constant TRANSFER_WITH_KEYED_AUTHORIZATION_TYPEHASH =
        keccak256(
            "TransferWithKeyedAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,uint192 nonceKey,uint64 nonce)"
        );

    bytes32 public constant RECEIVE_WITH_KEYED_AUTHORIZATION_TYPEHASH =
        keccak256(
            "ReceiveWithKeyedAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,uint192 nonceKey,uint64 nonce)"
        );

    bytes32 public constant CANCEL_KEYED_AUTHORIZATION_TYPEHASH =
        keccak256(
            "CancelKeyedAuthorization(address authorizer,uint192 nonceKey,uint64 nonce)"
        );

    mapping(address => mapping(uint192 => uint64)) internal _keyedNonces;

    event KeyedAuthorizationUsed(
        address indexed authorizer,
        uint192 indexed nonceKey,
        uint64 indexed nonce
    );

    event KeyedAuthorizationCanceled(
        address indexed authorizer,
        uint192 indexed nonceKey,
        uint64 indexed nonce
    );

    function keyedAuthorizationNonce(address authorizer, uint192 nonceKey)
        external
        view
        returns (uint256)
    {
        return (uint256(nonceKey) << 64) | uint256(_keyedNonces[authorizer][nonceKey]);
    }

    function transferWithKeyedAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        uint192 nonceKey,
        uint64 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _consume(
            TRANSFER_WITH_KEYED_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonceKey,
            nonce,
            v,
            r,
            s
        );
        _transfer(from, to, value);
    }

    function receiveWithKeyedAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        uint192 nonceKey,
        uint64 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(to == msg.sender, "KeyedAuth: caller is not payee");
        _consume(
            RECEIVE_WITH_KEYED_AUTHORIZATION_TYPEHASH,
            from,
            to,
            value,
            validAfter,
            validBefore,
            nonceKey,
            nonce,
            v,
            r,
            s
        );
        _transfer(from, to, value);
    }

    function cancelKeyedAuthorization(
        address authorizer,
        uint192 nonceKey,
        uint64 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(authorizer != address(0), "KeyedAuth: zero authorizer");
        require(nonce >= _keyedNonces[authorizer][nonceKey], "KeyedAuth: stale cancel");

        bytes32 structHash = keccak256(
            abi.encode(CANCEL_KEYED_AUTHORIZATION_TYPEHASH, authorizer, nonceKey, nonce)
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, structHash) == authorizer,
            "KeyedAuth: invalid signature"
        );

        _keyedNonces[authorizer][nonceKey] = nonce + 1;
        emit KeyedAuthorizationCanceled(authorizer, nonceKey, nonce);
    }

    function _consume(
        bytes32 typeHash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        uint192 nonceKey,
        uint64 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        require(from != address(0), "KeyedAuth: zero from");
        require(block.timestamp > validAfter, "KeyedAuth: not yet valid");
        require(block.timestamp < validBefore, "KeyedAuth: expired");
        require(_keyedNonces[from][nonceKey] == nonce, "KeyedAuth: nonce mismatch");

        bytes32 structHash = keccak256(
            abi.encode(typeHash, from, to, value, validAfter, validBefore, nonceKey, nonce)
        );
        require(
            EIP712.recover(DOMAIN_SEPARATOR, v, r, s, structHash) == from,
            "KeyedAuth: invalid signature"
        );

        _keyedNonces[from][nonceKey] = nonce + 1;
        emit KeyedAuthorizationUsed(from, nonceKey, nonce);
    }
}
```

## Security Considerations

### Front-running of wrapper contracts

Smart contracts that wrap a keyed authorization in their own logic (e.g. a `deposit(authData)` function that calls `transferWithKeyedAuthorization` internally) are vulnerable to front-running. An observer can submit the raw `transferWithKeyedAuthorization` call directly, advancing the payer's nonce and stranding the wrapper's downstream logic. Wrapper contracts MUST use `receiveWithKeyedAuthorization` (which enforces `to == msg.sender`) instead.

### Counter advancement only on full validation

The counter MUST be advanced only when every check (validity period, nonce equality, optional `to == msg.sender`, and signature recovery to `from`) succeeds. An implementation that advances the counter on partial validation enables a denial-of-service vector: an attacker could submit garbage signatures to burn the payer's nonce sequence. The reference implementation places `_keyedNonces[from][nonceKey] = nonce + 1` after the signature check, satisfying this requirement.

### Choice of `nonceKey`

The `nonceKey` is opaque and chosen by the payer. With the recommended convention `nonceKey = uint192(uint160(payeeAddress))`, the cast is zero-extending and lossless: distinct payee addresses always produce distinct keys. A payer that issues authorizations to multiple distinct agents acting on behalf of the same payee SHOULD use the upper 32 bits as a channel identifier to keep those agents on independent counters.

### `ecrecover` zero-address handling

`ecrecover` returns the zero address on invalid signatures. Implementations MUST reject `from == address(0)` (or `authorizer == address(0)` for cancel) explicitly *before* the signature check; otherwise any garbage signature submitted with `from = address(0)` would pass the `recovered == from` equality and consume a counter at that key. The reference implementation enforces this with a dedicated `require` at the top of `_consume` and `cancelKeyedAuthorization`.

### Signature malleability

ECDSA signatures are malleable: for any valid `(v, r, s)` there exists a second `(v', r, s')` valid for the same digest. This ERC does not require the canonical `s ≤ secp256k1n / 2` form because replay protection comes from the nonce counter, not from signature uniqueness. A malleated signature for an unconsumed authorization simply consumes the same authorization; no double-spend is possible.

### Cross-chain and cross-contract replay

EIP-712 domain separation (chainId + verifyingContract) prevents replay across chains and across distinct token contracts.

### Sequence saturation and key bricking via cancel

A 64-bit counter permits 2⁶⁴ authorizations per key before saturation; in Solidity 0.8+ the post-validation increment reverts on overflow. Payers approaching this limit can rotate to a new `nonceKey`.

The same overflow path can be triggered immediately by a single signed cancel: a cancel with `nonce = type(uint64).max` advances the counter to `type(uint64).max`, after which any further consumption attempt under that key (transfer, receive, or cancel) reverts. This is intended — it is the key-revocation primitive — but it also means that a payer who signs a cancel for a counter value derived from a stale view of on-chain state can permanently brick the key. Wallets and SDKs that surface cancellation SHOULD warn users when the requested cancel `nonce` is significantly higher than the current `keyedAuthorizationNonce` value, and SHOULD prefer a sequence of small cancels over one large jump when invalidating a known set of in-flight authorizations.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
