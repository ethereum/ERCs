---
title: Portable Spend Grants
description: Signed multi-asset spend grants with rolling and lifetime caps
author: Chris Madison (@tankcdr)
discussions-to: https://ethereum-magicians.org/t/placeholder
status: Draft
type: Standards Track
category: ERC
created: 2026-09-17
requires: 20, 712, 1271
---

## Abstract

This specification defines a portable spend grant: a typed, signed grant from a principal to a delegate that authorizes repeated spending of one or more assets under per-call, trailing-window, and lifetime caps. Native currency of the execution chain is identified by the zero address; every other asset is an [ERC-20](./eip-20.md) contract. The principal signs an [EIP-712](./eip-712.md) digest bound to the execution chain and to an immutable revocation registry. The registry stores remaining usage and does not move funds. A separate executor, selected by signing that registry as the domain verifying contract, calls `consume` in the same transaction as the value movement. Contract principals validate signatures with [ERC-1271](./eip-1271.md). Caps never treat zero as unlimited. This document is an unnumbered working draft.

## Motivation

Approvals and one-shot signatures do not give wallets, applications, and relying parties a shared object for bounded spend. An [ERC-20](./eip-20.md) allowance is usually a single-asset, uncapped, non-expiring debit right. Recurring allowances that reset at a UTC day or calendar period allow two full spends on either side of midnight. Multi-asset grants need either independent per-asset remaining or one shared budget that several assets draw down.

Delegation and permission RPCs exist, but they leave the meaning of the permission opaque. Two implementations can show the same hash and still disagree on window arithmetic, native-currency encoding, or whether a second asset has its own remaining. Principals also need a revocation path that does not depend on the delegate continuing to cooperate.

Existing tokens and native currency should not have to opt into a hook in order to be spent under a grant. The grant should be a portable typed-data object with a canonical rendering, a JSON interchange, and an on-chain remaining store that any conformant executor can debit atomically with movement.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

Bytes are hashed with Ethereum Keccak-256. `grantHash` denotes the complete [EIP-712](./eip-712.md) digest defined below. Amounts are raw asset units (wei for native currency, token `decimals` units for [ERC-20](./eip-20.md)). This specification does not define compilation into other permission systems.

### Terms

- **Principal:** the address that signs the grant and whose assets are spent.
- **Delegate:** the address named in the signed terms as the grantee. `consume` does not require `msg.sender` to equal `delegate`.
- **Executor:** the immutable address returned by the registry `executor()` function. Only this address may call `consume`.
- **Recipient:** the payee of a single `consume`.
- **Registry:** the immutable contract that verifies grants, records remaining, and records revocations. It NEVER transfers assets.
- **Window:** a trailing `lookback` of `windowSeconds` seconds, not a UTC calendar day.

### Grant object

The exact types, field order, and integer widths are:

```solidity
struct AssetLimit {
    address asset;         // ERC-20, or address(0) for this chain's native currency
    uint256 maxPerCall;    // one payment, raw units
    uint256 maxPerWindow;  // trailing window, raw units
    uint256 maxTotal;      // lifetime, never resets
}

struct SpendGrant {
    address principal;
    address delegate;
    uint8   recipientMode; // 0 = one address, 1 = any
    address recipient;     // required nonzero if mode is 0; MUST be address(0) if mode is 1
    uint8   assetCombine;  // 0 = and, 1 = or
    uint64  windowSeconds; // trailing lookback; 86400 = 24 hours, not a UTC day
    AssetLimit[] assets;   // 1–16, unique, strictly ascending by uint160(asset)
    uint64  validAfter;    // inclusive unix seconds
    uint64  validUntil;    // exclusive unix seconds
    uint256 salt;
    bytes32 renderingHash;
}
```

All fields are required. `salt` distinguishes otherwise identical grants; it is not an execution nonce. Reusing a grant permits additional executions only within remaining limits.

### Encode type

The exact `encodeType` for `SpendGrant` is the following single string, including the concatenated `AssetLimit` definition and with no spaces:

```
SpendGrant(address principal,address delegate,uint8 recipientMode,address recipient,uint8 assetCombine,uint64 windowSeconds,AssetLimit[] assets,uint64 validAfter,uint64 validUntil,uint256 salt,bytes32 renderingHash)AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)
```

The `AssetLimit` `encodeType` is:

```
AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)
```

`SPENDGRANT_TYPEHASH` is `keccak256` of the SpendGrant `encodeType` bytes. `ASSETLIMIT_TYPEHASH` is `keccak256` of the `AssetLimit` `encodeType` bytes.

### Domain and digest

The domain uses exactly four fields: `name = "SpendGrant"`, `version = "1"`, `chainId` equal to the execution chain ID, and `verifyingContract` equal to the registry address. The domain MUST NOT include `salt` or additional fields. The registry MUST be deployed on the execution chain. A change of chain, registry, or executor requires a new grant and a new signature.

```
EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)
```

```
domainSeparator = keccak256(
    abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256("SpendGrant"),
        keccak256("1"),
        chainId,
        registry
    )
)
```

String values are hashed as UTF-8 bytes. `abi.encode` above is the 32-byte ABI word encoding of each field.

Each `AssetLimit` element is hashed as:

```
hashStruct(AssetLimit) = keccak256(
    abi.encode(
        ASSETLIMIT_TYPEHASH,
        asset,
        maxPerCall,
        maxPerWindow,
        maxTotal
    )
)
```

The `assets` array hash is `keccak256` of the concatenation of those 32-byte element hashes in signed order. There MUST NOT be an ABI offset, a length prefix, or any other padding between element hashes. That 32-byte array hash occupies the `assets` word in the primary struct hash.

```
hashStruct(SpendGrant) = keccak256(
    abi.encode(
        SPENDGRANT_TYPEHASH,
        principal,
        delegate,
        recipientMode,
        recipient,
        assetCombine,
        windowSeconds,
        assetsArrayHash,
        validAfter,
        validUntil,
        salt,
        renderingHash
    )
)
```

Atomic types are encoded as 32-byte ABI words (uint8 and uint64 are zero-extended). `grantHash` is the digest the principal signs:

```
grantHash = keccak256(0x1901 || domainSeparator || hashStruct(SpendGrant))
```

`0x1901` is a two-byte prefix. Implementations MUST NOT substitute `hashStruct(SpendGrant)` or the domain separator for `grantHash`.

### Structural validation

A grant is structurally valid only if every condition below holds. Unknown future values of `recipientMode` and `assetCombine` MUST fail closed. Zero MUST NOT be interpreted as unlimited.

- `principal` and `delegate` are nonzero, and `delegate != principal`.
- `recipientMode` is `0` or `1`.
- If `recipientMode == 0`, `recipient` is nonzero and `recipient != principal`.
- If `recipientMode == 1`, `recipient == address(0)`.
- `assetCombine` is `0` or `1`.
- `windowSeconds > 0`.
- `validAfter < validUntil`.
- `assets.length` is in `1 ..= 16`.
- `assets` are strictly ascending by `uint160(asset)` and contain no duplicate addresses.
- For every asset: `maxPerCall > 0`, `maxPerWindow > 0`, `maxTotal > 0`, and `maxPerCall <= maxPerWindow <= maxTotal`.
- At `consume` execution, every asset with a nonzero address MUST have code at the evaluated block (`EXTCODESIZE > 0`). Native `address(0)` MUST NOT be rewritten to a wrapped-token address and MUST NOT be required to have code.

### Caps and pies

A single `consume` spends exactly one asset. `amount` MUST be greater than zero and MUST be less than or equal to that asset's `maxPerCall`.

**And (`assetCombine == 0`).** Each listed asset has independent remaining window and lifetime. Spending one asset MUST NOT reduce another asset's remaining. For the selected asset, let `windowSpent` be the sum of unexpired debit `amount`s and `lifetimeSpent` be the sum of all debit `amount`s. `consume` MUST revert if `windowSpent + amount > maxPerWindow` or `lifetimeSpent + amount > maxTotal`.

**Or (`assetCombine == 1`).** The grant has two shared pies, each of capacity `WAD = 10**18`: a rolling window pie and a lifetime pie. Let `maxPerWindow_i` and `maxTotal_i` be the signed caps of the selected asset. For a spend of `amount`:

```
windowConsume   = ceil(amount * WAD / maxPerWindow_i)
lifetimeConsume = ceil(amount * WAD / maxTotal_i)
```

`ceil(x / y)` is the smallest integer `n` such that `n * y >= x` (ceiling of the exact rational). Because `amount <= maxPerCall <= maxPerWindow_i` and `amount <= maxTotal_i`, each consume is in `1 ..= WAD`. Implementations MUST compute that rational ceiling exactly and MUST NOT wrap on the intermediate product `amount * WAD`. They MUST revert if they cannot produce the exact value.

Rounding is toward the principal (up). Example: `amount = 1`, `maxPerWindow_i = 3` yields `windowConsume = ceil(10**18 / 3) = 333333333333333334`, not `333333333333333333`.

Let `windowWad` be the sum of `windowConsume` over unexpired debits of every asset on the grant, and `lifetimeWad` the sum of `lifetimeConsume` over all debits of every asset. `consume` MUST revert if `windowWad + windowConsume > WAD` or `lifetimeWad + lifetimeConsume > WAD`. Equality with `WAD` is permitted and exhausts that pie.

Numeric example. Asset A has `maxPerWindow = 100`; asset B has `maxPerWindow = 200`. A spend of `50` of A consumes `5e17` window pie. A subsequent spend of `100` of B consumes another `5e17`. The window pie is then `WAD`; a further windowed spend reverts even if each asset's raw `maxPerWindow` still has room.

### Rolling window

A debit recorded at timestamp `s` (the `block.timestamp` of the successful `consume`) counts in the window if and only if `block.timestamp < s + windowSeconds` in 256-bit arithmetic, with `windowSeconds` zero-extended. Equivalently, the debit counts while `block.timestamp - s < windowSeconds` when `block.timestamp >= s`, and it expires at age `== windowSeconds`. Midnight and UTC day boundaries have no effect. Lifetime remaining never resets.

Exact rolling requires timestamped debits. Views MUST recompute unexpired totals at the queried block and MUST NOT return a stale stored window counter.

An implementation MAY bound the number of live (unexpired) stored debits per `(grantHash, asset)`. The reference bound is 256. If a bound is in force and a further debit would exceed it, `consume` MUST revert. That bound is an implementation limit, not a signed call cap. Expired debits MAY be dropped from storage; they MUST remain excluded from window checks and rolling views.

### Signatures

The principal signs `grantHash`.

If the principal has no code at the evaluated block, the signature MUST be exactly 65 bytes `r || s || v` of secp256k1 over `grantHash`, with `v` equal to `27` or `28`, `s` in the lower half of the curve order (`s <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0`), and recovered signer equal to `principal`.

If the principal has code at the evaluated block, the signature MUST be validated with [ERC-1271](./eip-1271.md) `isValidSignature(grantHash, grantSignature)` against execution-time state. The call MUST return exactly 32 bytes equal to the 32-byte word `0x1626ba7e` left-aligned (28 trailing zero bytes). A raw four-byte return, a revert, a malformed return, or any other value is invalid. Implementations MUST NOT fall back to ECDSA recovery for a code-bearing principal.

A cached ERC-1271 success MUST NOT replace execution-time validation.

### Canonical rendering

`renderingHash = keccak256(bytes of rendering)` and is omitted from the text. An issuer or wallet that presents the rendering MUST compute that hash over the canonical bytes below and MUST place it in the signed struct. `consume` does not re-verify the text.

The rendering is ASCII (hence UTF-8), uses LF (`0x0a`) line endings, and contains exactly one trailing LF. It MUST NOT use `CR`, `CRLF`, a `BOM`, trailing spaces, or blank lines. Addresses are `0x` followed by 40 lowercase hexadecimal digits (no mixed-case checksum). Unsigned integers are canonical decimal: `0`, or a digit `1`–`9` followed by zero or more digits, with no sign, fraction, exponent, or leading zeros.

`i` in budget lines is the 0-based index in signed `assets` order. Budget lines are repeated for each asset in that order. Labels and spacing are exact:

```
Spend grant v1
Chain: {chainId}
Revocation registry: {revocationRegistry}
Principal: {principal}
Delegate: {delegate}
Recipient mode: {recipientMode}
Recipient: {recipient}
Asset combine: {assetCombine}
Window seconds: {windowSeconds}
Budget count: {n}
Budget {i} asset: {asset}
Budget {i} maximum per call (raw units): {maxPerCall}
Budget {i} maximum per window (raw units): {maxPerWindow}
Budget {i} maximum total (raw units): {maxTotal}
Valid after (inclusive Unix seconds): {validAfter}
Valid until (exclusive Unix seconds): {validUntil}
Salt: {salt}
```

The canonical rendering does not include the executor address. A wallet SHOULD also display `executor()` of `{revocationRegistry}` before signing, because `consume` authorizes that address.

### JSON interchange

The interchange object contains exactly `chainId`, `revocationRegistry`, and `grant`. `grant` contains exactly the SpendGrant fields: `principal`, `delegate`, `recipientMode`, `recipient`, `assetCombine`, `windowSeconds`, `assets`, `validAfter`, `validUntil`, `salt`, `renderingHash`. Each element of `assets` contains exactly `asset`, `maxPerCall`, `maxPerWindow`, `maxTotal`.

When hashing a grant from interchange JSON, implementations MUST use `chainId` as the domain `chainId` and `revocationRegistry` as `verifyingContract`.

Unsigned integers MUST be JSON strings in canonical decimal form as defined for rendering, and MUST fit the field width (`uint8`, `uint64`, or `uint256`). Addresses MUST be lowercase `0x` plus 40 hex digits. `renderingHash` MUST be lowercase `0x` plus 64 hex digits. Hex MUST use `[0-9a-f]` only.

Implementations MUST reject extra fields, missing fields, duplicate JSON member names (rejected before object conversion), JSON numbers in place of integer strings, uppercase hex, leading zeros other than the value `0`, out-of-range values, wrong types, `null`, and trailing commas. Object property order and insignificant white space are not signed. Implementations MUST NOT use a JSON byte hash in place of `grantHash`.

Illustrative shape (values are examples, not vectors):

```json
{
  "chainId": "1",
  "revocationRegistry": "0x1111111111111111111111111111111111111111",
  "grant": {
    "principal": "0x2222222222222222222222222222222222222222",
    "delegate": "0x3333333333333333333333333333333333333333",
    "recipientMode": "0",
    "recipient": "0x4444444444444444444444444444444444444444",
    "assetCombine": "0",
    "windowSeconds": "86400",
    "assets": [
      {
        "asset": "0x0000000000000000000000000000000000000000",
        "maxPerCall": "1000000000000000000",
        "maxPerWindow": "5000000000000000000",
        "maxTotal": "10000000000000000000"
      }
    ],
    "validAfter": "0",
    "validUntil": "1893456000",
    "salt": "1",
    "renderingHash": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
}
```

### Registry

The registry is immutable: no admin, no pause, no upgrade, no `unrevoke`, and no proxy. The executor address is set in the constructor to a nonzero value and NEVER changes. The principal binds that executor by signing this registry as `verifyingContract`.

```solidity
interface ISpendGrantRegistry {
    event GrantRevoked(address indexed principal, bytes32 indexed grantHash);
    event GrantConsumed(
        bytes32 indexed grantHash,
        address indexed asset,
        uint256 amount,
        address indexed recipient
    );

    function executor() external view returns (address);
    function revoke(bytes32 grantHash) external;
    function revoked(address principal, bytes32 grantHash) external view returns (bool);
    function usage(bytes32 grantHash, address asset) external view returns (uint256 spent, uint256 calls);
    function rollingUsage(bytes32 grantHash, address asset) external view returns (uint256 spent, uint256 calls);
    function pieUsed(bytes32 grantHash) external view returns (uint256 lifetimeWad, uint256 windowWad);

    function consume(
        SpendGrant calldata grant,
        bytes calldata grantSignature,
        address asset,
        uint256 amount,
        address recipient
    ) external;
}
```

`revoke` sets `revoked[msg.sender][grantHash] = true`. It is idempotent and MUST emit `GrantRevoked` only on the first change. Anyone MAY revoke in their own namespace. A revocation MUST NOT affect another principal. `consume` consults `revoked[grant.principal][grantHash]`. There is no `unrevoke`.

`executor()` returns the immutable executor. `consume` MUST revert unless `msg.sender == executor()`.

`consume` MUST validate, then record the debit, then emit `GrantConsumed`, then return. It MUST NOT move tokens, send native currency, or call the selected asset for transfer. Recording before return applies to storage of the debit; signature validation MAY call the principal under ERC-1271 before recording.

`consume` MUST revert unless all of the following hold, checked in this order, using the reason names in [Reason names](#reason-names):

1. `msg.sender == executor` (`UNAUTHORIZED_EXECUTOR`).
1. The grant is structurally valid, including the execution-time code check on nonzero assets (`INVALID_MANDATE`).
1. The signature is valid for `grant.principal` over `grantHash` (`BAD_SIGNATURE`).
1. `block.timestamp >= grant.validAfter` (`NOT_YET_VALID`).
1. `block.timestamp < grant.validUntil` (`EXPIRED`).
1. `revoked[grant.principal][grantHash]` is false (`REVOKED`).
1. If `recipientMode == 0`, the `recipient` argument equals `grant.recipient`; if `recipientMode == 1`, this check does not constrain the argument (`WRONG_RECIPIENT`).
1. `asset` equals `grant.assets[j].asset` for exactly one `j` (`WRONG_ASSET`).
1. `amount > 0` and `amount <= grant.assets[j].maxPerCall` (`OVER_TX_CAP`).
1. The spend does not exceed the window cap or window pie as defined in [Caps and pies](#caps-and-pies) (`OVER_WINDOW_CAP`).
1. The spend does not exceed the lifetime cap or lifetime pie (`OVER_CUMULATIVE_CAP`).
1. Recording the debit does not exceed the live-debit bound, if any (`WINDOW_FULL`).

On success the registry appends a timestamped debit for `(grantHash, asset)` with the consumed `amount` and, when `assetCombine == 1`, the pie consumes. `calls` counts successful `consume` executions for that `(grantHash, asset)` and is observation only; it is not a signed cap.

View behavior:

- `revoked(principal, grantHash)` is true if that principal has revoked that hash in this registry.
- `usage` returns lifetime raw `spent` (sum of `amount` over every successful consume of that asset, including those that have left the window) and lifetime `calls`.
- `rollingUsage` returns the same pair recomputed over unexpired debits only.
- `pieUsed` returns `(0, 0)` when the grant's `assetCombine == 0` or when no or-mode debit exists. When `assetCombine == 1`, `lifetimeWad` is the sum of all `lifetimeConsume` values and `windowWad` is the sum of unexpired `windowConsume` values. Both are at most `WAD`. `windowWad` MUST be recomputed at the queried block.

If `pieUsed` is queried without the mandate body, the registry MUST return values consistent with recorded debits: and-mode debits do not advance pies; or-mode debits do.

### Reason names

These names are the normative vocabulary. Encoding of revert data is implementation-defined. `consume` returns with no reason on success. On failure it MUST revert and MUST correspond to exactly one name other than `OK`. `OK` denotes success for simulators; it is not a `consume` return value. A view helper that returns `(bool, reason)` is not part of `ISpendGrantRegistry`.

| Name | Condition |
| --- | --- |
| `OK` | Success |
| `INVALID_MANDATE` | Structural validation failed, including a nonzero asset with no code |
| `BAD_SIGNATURE` | EOA recovery or ERC-1271 validation failed |
| `NOT_YET_VALID` | `block.timestamp < validAfter` |
| `EXPIRED` | `block.timestamp >= validUntil` |
| `REVOKED` | Principal has revoked `grantHash` |
| `WRONG_ASSET` | `asset` is not in `grant.assets` |
| `WRONG_RECIPIENT` | `recipientMode == 0` and `recipient` is not the signed recipient |
| `OVER_TX_CAP` | `amount == 0` or `amount > maxPerCall` |
| `OVER_WINDOW_CAP` | Trailing-window raw cap or window pie would be exceeded |
| `OVER_CUMULATIVE_CAP` | Lifetime raw cap or lifetime pie would be exceeded |
| `WINDOW_FULL` | Live unexpired debit bound would be exceeded |
| `UNAUTHORIZED_EXECUTOR` | `msg.sender` is not the immutable executor |

### Executor

A conformant executor MUST call `consume` in the same transaction as the value movement of `amount` of `asset` to `recipient`, and MUST revert the whole transaction if `consume` fails or the movement fails. Order of `consume` and movement is unspecified. This specification does not define account adapters, permission compilation, or how the delegate authorizes the executor.

For native `asset == address(0)`, movement is a native transfer of `amount` wei. For any other asset, movement is an ERC-20 transfer of `amount` raw units. The executor MUST NOT substitute a wrapped native token for `address(0)`.

## Rationale

This proposal is the signed **terms** of a spend grant plus an on-chain **remaining** store. The typed object, rendering, and JSON are the terms. The registry is the v1 remaining store. Movement stays with an executor so existing ERC-20 contracts and native currency need not opt in.

[ERC-7710](./eip-7710.md) standardizes `redeemDelegations` and leaves `_permissionContexts` opaque, determined by the specific implementation. Granting a delegation is out of scope for that interface. This proposal is the terms those contexts may compile to. It is not listed in `requires`, because a remaining store and a typed grant are useful without that redemption bus.

[ERC-7715](./eip-7715.md) is wallet JSON-RPC `wallet_requestExecutionPermissions`. Its permission types are not an exhaustive list. A wallet may request a spend grant of this shape without this proposal claiming to extend 7715.

[ERC-8226](./eip-8226.md) is a regulated one-asset grant with a compliance provider, venue-agnostic `canExecute`, and `MandateReason` codes. Caps are per-transaction and cumulative. Freeze is not revoke. The object, lifecycle, and compliance role differ; reason names in this proposal match 8226 where the conditions coincide (`OK`, `NOT_YET_VALID`, `EXPIRED`, `REVOKED`, `WRONG_ASSET`, `OVER_TX_CAP`, `OVER_CUMULATIVE_CAP`).

The Bounded Agent Actions draft (ERC-8312, still an open ERCs pull request at the time of writing) meters remaining of an opaque `capabilityRoot`. It does not enforce the capability. This proposal defines the capability. A future profile may store remaining in an 8312 cursor; this registry is the v1 remaining store.

Discussion of asset-enforced spend on Magicians argued that general spend belongs at the account layer so existing ERC-20 contracts and native currency need not opt in, and that token hooks are for issuer-controlled assets. This proposal follows that split: the registry never moves funds, and tokens need not implement a spend hook.

A widely deployed smart-wallet spend permission (not an ERC) is one token with a recurring period allowance. Its native sentinel is `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`, not `address(0)`. This proposal uses `address(0)` for native currency, forbids rewriting it to a wrapped token, allows up to sixteen assets, and uses a trailing lookback rather than a period reset.

Trailing `lookback`: a UTC-day reset allows two full `maxPerWindow` spends across midnight. Expiry at age `== windowSeconds` is exact, independent of clock hour. `86400` is twenty-four hours, not "today".

Or-mode pies: independent remaining cannot express "spend this much value-like budget across A or B" without an oracle. Dividing by each asset's own cap, in WAD, gives a dimensionless pie the principal signed. Ceiling division favors the principal so dust spends cannot grind past a raw cap that rounding down would leak.

`consume` is restricted to an immutable executor because a public debit function would let any caller fill the window, exhaust pies, or grief `WINDOW_FULL`. The principal selects that executor by choosing the registry. The delegate field remains in the terms for wallets and account-layer policy; the registry does not check it at `consume` time.

`renderingHash` binds what was shown to what was signed without placing the full text on-chain. Sorted unique assets make the typed-data encoding canonical and prevent two disagreeing limits for one address. Fail-closed enumerations mean a future `recipientMode == 2` is invalid to old registries rather than silently treated as "any". No `unrevoke`: a principal who wants to spend again signs a new salt.

The live-debit bound exists because exact rolling cannot be a single counter. 256 is a reference storage bound, not a signed `maxCalls`. `usage.calls` is observational for the same reason.

## Backwards Compatibility

This proposal adds a new typed-data domain, JSON shape, and registry interface. It does not change consensus, [EIP-712](./eip-712.md), [ERC-1271](./eip-1271.md), or [ERC-20](./eip-20.md) token behavior. Existing tokens need not implement hooks. Native currency is identified by `address(0)` rather than a wrapped token or the `0xEeee…EEeE` sentinel used elsewhere. Executors that already treat that sentinel as native do not reuse that convention here.

## Test Cases

Golden vectors are in [../assets/erc-draft_spend_grants/vectors/v1.json](../assets/erc-draft_spend_grants/vectors/v1.json). They include domain separator, struct hash, digest, canonical rendering bytes, and an EOA signature. An implementation of the Specification reproduces those values. No additional requirements are defined here.

## Reference Implementation

A non-normative Solidity reference lives under [../assets/erc-draft_spend_grants/](../assets/erc-draft_spend_grants/). It is an aid to implementers. The Specification is authoritative. Hashing, rendering, JSON interchange, validation, pies, and rolling expiry are implementable from this document without those sources.

## Security Considerations

The registry never moves funds. Safety of the principal's assets depends on the executor calling `consume` in the same transaction as movement and reverting if either step fails. A dishonest executor that the principal bound by signing that registry can move value without a matching debit, or debit without moving. Choosing a registry is choosing an executor. Wallets that omit `executor()` from the pre-sign display hide that binding. Wallets that omit a `renderingHash` check can show one text and sign another.

`consume` is not payable-for-value and does not inspect balance deltas. Fee-on-transfer, elastic-supply, or malicious ERC-20 tokens can make the recorded `amount` differ from the principal's balance change. That is an executor and token-selection problem; the remaining store tracks the `amount` argument.

Revocation is per principal and permanent. It does not pause the executor. A `consume` already in flight in the same block as `revoke` races on transaction order. There is no admin to freeze a stolen delegate; the principal revokes hashes they signed, and remaining caps bound a stolen delegate until then.

Code-bearing principals are ERC-1271 only. An implementation that falls back to ECDSA when `isValidSignature` fails would treat a contract with an `owner` key as that key. ERC-1271 is evaluated at execution, so a principal that rotates its validation logic can invalidate outstanding grants without the registry's help.

The 256-live-debit bound (or any similar bound) is a grief surface: many small in-window consumes can fill the window and force `WINDOW_FULL` until the oldest debit expires. Or-mode ceiling division can exhaust a pie before raw sums reach the signed caps. Both are intentional fail-closed behaviors.

`block.timestamp` is proposer-influenced. Window and validity checks inherit that. Short `windowSeconds` values are more sensitive than lifetime caps.

Reentrant `consume` during an ERC-1271 callback, or during a later token hook in the executor's movement, can apply several per-call amounts in one transaction if remaining allows. The per-call cap limits each call, not the transaction. Registry authors who want a single debit per transaction add their own lock; this specification does not.

The registry cannot be paused or upgraded. A bug in remaining arithmetic is permanent for that deployment. A new registry is a new domain and requires new signatures.

Salt reuse with identical terms is the same grant. It does not reset remaining. Distinct grants need a distinct salt or a distinct field.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
