---
eip: 0
title: Portable Spend Grants
description: Signed multi-asset spend grants with rolling and lifetime caps
author: Chris Madison (@tankcdr)
discussions-to: https://ethereum-magicians.org/t/erc-tbd-portable-spend-grants/29776
status: Draft
type: Standards Track
category: ERC
created: 2026-09-17
requires: 20, 712, 1271, 7528, 7702
---

## Abstract

This specification defines a portable spend grant: a typed, signed grant from a principal to a delegate that authorizes repeated spending of one or more assets under per-call, trailing-window, and lifetime caps. Native currency of the execution chain is identified by the [ERC-7528](./eip-7528.md) address; every other asset is an [ERC-20](./eip-20.md) contract. The principal signs an [EIP-712](./eip-712.md) digest bound to the execution chain and to an immutable revocation registry. The registry stores remaining usage and does not move funds. A separate executor, selected by signing that registry as the domain verifying contract, calls `consume` in the same transaction as the value movement. Contract principals validate signatures with [ERC-1271](./eip-1271.md); [EIP-7702](./eip-7702.md) delegated accounts also accept their own key's signature. Caps never treat zero as unlimited. The terms are portable: any wallet or tool can hash, render, and check them. A grant is bound to one chain and one registry, and through the registry to one executor; using a different one requires a new signature. This document is an unnumbered working draft.

## Motivation

Approvals and one-shot signatures do not give wallets, applications, and relying parties a shared object for bounded spend. An [ERC-20](./eip-20.md) allowance is usually a single-asset, uncapped, non-expiring debit right. Recurring allowances that reset at a UTC day or calendar period allow two full spends on either side of midnight. Multi-asset grants need each asset to carry its own remaining, so that one signature can cover several assets without one asset's spending drawing down another's.

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
- **NATIVE:** the [ERC-7528](./eip-7528.md) address `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`, which denotes the execution chain's native currency.

### Grant object

The exact types, field order, and integer widths are:

```solidity
struct AssetLimit {
    address asset;         // ERC-20, or NATIVE (ERC-7528) for this chain's native currency
    uint256 maxPerCall;    // one payment, raw units
    uint256 maxPerWindow;  // trailing window, raw units
    uint256 maxTotal;      // lifetime, never resets
}

struct SpendGrant {
    address principal;
    address delegate;
    uint8   recipientMode; // 0 = one address, 1 = any
    address recipient;     // required nonzero if mode is 0; MUST be address(0) if mode is 1
    uint8   assetCombine;  // MUST be 0 (independent per-asset caps); other values reserved
    uint64  windowSeconds; // trailing lookback; 86400 = 24 hours, not a UTC day
    AssetLimit[] assets;   // 1–16, unique, strictly ascending by uint160(asset)
    uint64  validAfter;    // inclusive unix seconds
    uint64  validUntil;    // exclusive unix seconds
    uint256 salt;
}
```

All fields are required. `salt` distinguishes otherwise identical grants; it is not an execution nonce. Reusing a grant permits additional executions only within remaining limits.

### Encode type

The exact `encodeType` for `SpendGrant` is the following single string, including the concatenated `AssetLimit` definition and with no spaces:

```
SpendGrant(address principal,address delegate,uint8 recipientMode,address recipient,uint8 assetCombine,uint64 windowSeconds,AssetLimit[] assets,uint64 validAfter,uint64 validUntil,uint256 salt)AssetLimit(address asset,uint256 maxPerCall,uint256 maxPerWindow,uint256 maxTotal)
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
        salt
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
- `assetCombine == 0`. Every other value is reserved for a future version of this specification and MUST be rejected.
- `windowSeconds > 0`.
- `validAfter < validUntil`.
- `assets.length` is in `1 ..= 16`.
- `assets` are strictly ascending by `uint160(asset)` and contain no duplicate addresses.
- For every asset: `maxPerCall > 0`, `maxPerWindow > 0`, `maxTotal > 0`, and `maxPerCall <= maxPerWindow <= maxTotal`.
- No asset is `address(0)`.
- At `consume` execution, every asset other than `NATIVE` MUST have code at the evaluated block (`EXTCODESIZE > 0`). `NATIVE` MUST NOT be rewritten to a wrapped-token address and MUST NOT be required to have code.

### Caps

A single `consume` spends exactly one asset. `amount` MUST be greater than zero and MUST be less than or equal to that asset's `maxPerCall`.

Each listed asset has independent remaining window and lifetime. Spending one asset MUST NOT reduce another asset's remaining. For the selected asset, let `windowSpent` be the sum of unexpired debit `amount`s and `lifetimeSpent` be the sum of all debit `amount`s. `consume` MUST revert if `windowSpent + amount > maxPerWindow` or `lifetimeSpent + amount > maxTotal`. Equality is permitted and exhausts that cap. Implementations MUST evaluate these comparisons without overflow.

### Rolling window

A debit recorded at timestamp `s` (the `block.timestamp` of the successful `consume`) counts in the window if and only if `block.timestamp < s + windowSeconds` in 256-bit arithmetic, with `windowSeconds` zero-extended. Equivalently, the debit counts while `block.timestamp - s < windowSeconds` when `block.timestamp >= s`, and it expires at age `== windowSeconds`. Midnight and UTC day boundaries have no effect. Lifetime remaining never resets.

Exact rolling requires timestamped debits. Views MUST recompute unexpired totals at the queried block and MUST NOT return a stale stored window counter.

An implementation MAY bound the number of live (unexpired) stored debits per `(grantHash, asset)`. The reference bound is 1024. If a bound is in force and a further debit would exceed it, `consume` MUST revert. That bound is an implementation limit, not a signed call cap. Expired debits MAY be dropped from storage; they MUST remain excluded from window checks and rolling views.

An implementation MAY also bound the stored width of a single debit `amount`. The reference stores amounts in 192 bits. If such a bound is in force, a `consume` whose `amount` exceeds it MUST revert with `OVER_TX_CAP`.

### Signatures

The principal signs `grantHash`.

If the principal has no code at the evaluated block, the signature MUST be exactly 65 bytes `r || s || v` of secp256k1 over `grantHash`, with `v` equal to `27` or `28`, `s` in the lower half of the curve order (`s <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0`), and recovered signer equal to `principal`.

If the principal has code at the evaluated block and that code is not an EIP-7702 delegation designator, the signature MUST be validated with [ERC-1271](./eip-1271.md) `isValidSignature(grantHash, grantSignature)` against execution-time state. The call MUST return exactly 32 bytes equal to the 32-byte word `0x1626ba7e` left-aligned (28 trailing zero bytes). A raw four-byte return, a revert, a malformed return, or any other value is invalid. Implementations MUST NOT fall back to ECDSA recovery for a code-bearing principal.

If the principal's code at the evaluated block is exactly 23 bytes beginning with `0xef0100` (an [EIP-7702](./eip-7702.md) delegation designator), the signature is valid if either (a) it satisfies the 65-byte secp256k1 rule above and recovers `principal`, or (b) the [ERC-1271](./eip-1271.md) call above succeeds against the delegated code. Implementations MUST try (a) first and MUST NOT require (b) when (a) holds.

A cached ERC-1271 success MUST NOT replace execution-time validation.

### Canonical rendering

The canonical rendering is a plain-text form of a grant, derived entirely from the signed fields and the domain. It is not signed separately and carries no information the typed data does not. Any display, log, or record that presents a grant's terms as plain text MUST use exactly these bytes, so that two implementations show the same text for the same grant. Formatted displays, such as a wallet using an [ERC-7730](./eip-7730.md) descriptor, are not constrained by this section.

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

The interchange object contains exactly `chainId`, `revocationRegistry`, and `grant`. `grant` contains exactly the SpendGrant fields: `principal`, `delegate`, `recipientMode`, `recipient`, `assetCombine`, `windowSeconds`, `assets`, `validAfter`, `validUntil`, `salt`. Each element of `assets` contains exactly `asset`, `maxPerCall`, `maxPerWindow`, `maxTotal`.

When hashing a grant from interchange JSON, implementations MUST use `chainId` as the domain `chainId` and `revocationRegistry` as `verifyingContract`.

Unsigned integers MUST be JSON strings in canonical decimal form as defined for rendering, and MUST fit the field width (`uint8`, `uint64`, or `uint256`). Addresses MUST be lowercase `0x` plus 40 hex digits. Hex MUST use `[0-9a-f]` only.

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
        "asset": "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "maxPerCall": "1000000000000000000",
        "maxPerWindow": "5000000000000000000",
        "maxTotal": "10000000000000000000"
      }
    ],
    "validAfter": "0",
    "validUntil": "1893456000",
    "salt": "1"
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
1. The grant is structurally valid, including the execution-time code check on nonzero assets (`INVALID_GRANT`).
1. The signature is valid for `grant.principal` over `grantHash` (`BAD_SIGNATURE`).
1. `block.timestamp >= grant.validAfter` (`NOT_YET_VALID`).
1. `block.timestamp < grant.validUntil` (`EXPIRED`).
1. `revoked[grant.principal][grantHash]` is false (`REVOKED`).
1. If `recipientMode == 0`, the `recipient` argument equals `grant.recipient`; if `recipientMode == 1`, this check does not constrain the argument (`WRONG_RECIPIENT`).
1. `asset` equals `grant.assets[j].asset` for exactly one `j` (`WRONG_ASSET`).
1. `amount > 0`, `amount <= grant.assets[j].maxPerCall`, and `amount` is within any implementation amount bound (`OVER_TX_CAP`).
1. The spend does not exceed the window cap as defined in [Caps](#caps) (`OVER_WINDOW_CAP`).
1. The spend does not exceed the lifetime cap (`OVER_CUMULATIVE_CAP`).
1. Recording the debit does not exceed the live-debit bound, if any (`WINDOW_FULL`).

On success the registry appends a timestamped debit for `(grantHash, asset)` with the consumed `amount`. `calls` counts successful `consume` executions for that `(grantHash, asset)` and is observation only; it is not a signed cap.

View behavior:

- `revoked(principal, grantHash)` is true if that principal has revoked that hash in this registry.
- `usage` returns lifetime raw `spent` (sum of `amount` over every successful consume of that asset, including those that have left the window) and lifetime `calls`.
- `rollingUsage` returns the same pair recomputed over unexpired debits only.

### Reason names

These names are the normative vocabulary. Encoding of revert data is implementation-defined. `consume` returns with no reason on success. On failure it MUST revert and MUST correspond to exactly one name other than `OK`. `OK` denotes success for simulators; it is not a `consume` return value. A view helper that returns `(bool, reason)` is not part of `ISpendGrantRegistry`.

| Name | Condition |
| --- | --- |
| `OK` | Success |
| `INVALID_GRANT` | Structural validation failed, including a nonzero asset with no code |
| `BAD_SIGNATURE` | EOA recovery, EIP-7702 recovery, or ERC-1271 validation failed |
| `NOT_YET_VALID` | `block.timestamp < validAfter` |
| `EXPIRED` | `block.timestamp >= validUntil` |
| `REVOKED` | Principal has revoked `grantHash` |
| `WRONG_ASSET` | `asset` is not in `grant.assets` |
| `WRONG_RECIPIENT` | `recipientMode == 0` and `recipient` is not the signed recipient |
| `OVER_TX_CAP` | `amount == 0`, `amount > maxPerCall`, or `amount` exceeds an implementation amount bound |
| `OVER_WINDOW_CAP` | Trailing-window cap would be exceeded |
| `OVER_CUMULATIVE_CAP` | Lifetime cap would be exceeded |
| `WINDOW_FULL` | Live unexpired debit bound would be exceeded |
| `UNAUTHORIZED_EXECUTOR` | `msg.sender` is not the immutable executor |

### Executor

A conformant executor MUST call `consume` in the same transaction as the value movement of `amount` of `asset` to `recipient`, and MUST revert the whole transaction if `consume` fails or the movement fails. Order of `consume` and movement is unspecified. This specification does not define account adapters, permission compilation, or how the delegate authorizes the executor.

For `asset == NATIVE`, movement is a native transfer of `amount` wei. For any other asset, movement is an ERC-20 transfer of `amount` raw units. The executor MUST NOT substitute a wrapped native token for `NATIVE`.

## Rationale

This proposal is the signed **terms** of a spend grant plus an on-chain **remaining** store. The typed object, rendering, and JSON are the terms. The registry is the v1 remaining store. Movement stays with an executor so existing ERC-20 contracts and native currency need not opt in.

[ERC-7710](./eip-7710.md) standardizes `redeemDelegations` and leaves `_permissionContexts` opaque, determined by the specific implementation. Granting a delegation is out of scope for that interface. This proposal is the terms those contexts may compile to. It is not listed in `requires`, because a remaining store and a typed grant are useful without that redemption bus.

[ERC-7715](./eip-7715.md) is wallet JSON-RPC `wallet_requestExecutionPermissions`. Its permission types are not an exhaustive list. A wallet may request a spend grant of this shape without this proposal claiming to extend 7715.

[ERC-8226](./eip-8226.md) is a regulated one-asset grant with a compliance provider, venue-agnostic `canExecute`, and `MandateReason` codes. Caps are per-transaction and cumulative. Freeze is not revoke. The object, lifecycle, and compliance role differ; reason names in this proposal match 8226 where the conditions coincide (`OK`, `NOT_YET_VALID`, `EXPIRED`, `REVOKED`, `WRONG_ASSET`, `OVER_TX_CAP`, `OVER_CUMULATIVE_CAP`).

A separate draft on bounded agent actions, still an open ERCs pull request at the time of writing, meters remaining of an opaque `capabilityRoot`. It does not enforce the capability. This proposal defines the capability. A future profile may store remaining in that draft's cursor; this registry is the v1 remaining store.

Discussion of asset-enforced spend on Magicians argued that general spend belongs at the account layer so existing ERC-20 contracts and native currency need not opt in, and that token hooks are for issuer-controlled assets. This proposal follows that split: the registry never moves funds, and tokens need not implement a spend hook.

A widely deployed smart-wallet spend permission (not an ERC) is one token with a recurring period allowance; its batch form signs several such single-token permissions at once. Each permission in a batch keeps its own period, which resets at a boundary. This proposal puts up to sixteen assets in one grant with one hash and one revocation, and uses a trailing lookback rather than a period reset.

Native currency uses the [ERC-7528](./eip-7528.md) address rather than `address(0)`. ERC-7528 is Final and is the native identifier in some deployed spend-permission systems; other deployed wallet-permission systems use `address(0)` for native currency. This proposal uses the Final standard, and an adapter for a system that uses `address(0)` translates at its boundary. It also keeps `address(0)` available as an unambiguous "unset" value: a zero asset is always invalid, and a zero recipient only ever means "any" in `recipientMode == 1`.

EIP-7702 accounts are controlled by their key for as long as the key exists: the key can replace or clear the delegation at any time. Accepting that key's ECDSA signature therefore grants nothing the key does not already hold. Without that rule, a grant signed by an EOA would change validity when the account adopts, changes, or clears a delegation, and delegated code that lacks ERC-1271 (or requires a nested format such as [ERC-7739](./eip-7739.md)) would silently invalidate every outstanding grant. Ordinary contract principals keep ERC-1271 only, because a contract's owner key is not the contract.

Trailing `lookback`: a UTC-day reset allows two full `maxPerWindow` spends across midnight. Expiry at age `== windowSeconds` is exact, independent of clock hour. `86400` is twenty-four hours, not "today".

`assetCombine` is reserved rather than removed. A shared budget across assets ("spend this much across A or B") is useful, but the only oracle-free form, dividing each spend by that asset's own cap, is not how principals budget; they budget in a unit of account, which needs a price reference this specification does not define. Keeping the field fixed at `0` means a later version can define another mode without changing `encodeType`, the type hash, the rendering, or the JSON shape, and fail-closed validation means registries built to this version reject such grants rather than misread them.

`consume` is restricted to an immutable executor because a public debit function would let any caller fill the window, exhaust caps, or grief `WINDOW_FULL`. The principal selects that executor by choosing the registry. The delegate field remains in the terms for wallets and account-layer policy; the registry does not check it at `consume` time.

The grant carries no hash of its rendering. The rendering is a function of the signed fields and the domain, so a hash of it would commit to nothing the signature does not already cover, and a wallet displays what it derives from the fields in any case. The canonical text is kept so that every text display of a grant is byte-identical. An application that needs to bind a grant to something outside it, such as a parent grant or an off-chain terms document, can derive `salt` from a commitment to that data, for example `salt = uint256(keccak256(abi.encode(parentGrantHash, index)))`, without a change to this specification. Sorted unique assets make the typed-data encoding canonical and prevent two disagreeing limits for one address. Fail-closed enumerations mean a future `recipientMode == 2` is invalid to old registries rather than silently treated as "any". No `unrevoke`: a principal who wants to spend again signs a new salt.

A non-normative [ERC-7730](./eip-7730.md) descriptor for the reference deployment is in [`spend-grant.json`](../assets/eip-0/clear-signing/spend-grant.json). It lets a wallet show the delegate, recipient, window, each asset's caps in that asset's units, and the validity dates, and it rejects a grant whose `assetCombine` is not `0`. A descriptor is bound to specific registry deployments and cannot call `executor()`, so a wallet still has to look up and show the executor itself.

The live-debit bound exists because exact rolling cannot be a single counter. Because debits are appended in timestamp order, expired debits are always the oldest ones, so an implementation can keep a running window sum and drop expired debits from the front before each check. The reference does this with a fixed ring of 1024 one-word debits (64-bit timestamp, 192-bit amount), so the cost of a `consume` does not grow with the number of live debits and slots are reused once the ring wraps. The cost does grow with the number of expired debits dropped in that call: after a full ring goes idle for longer than the window, the next `consume` drops up to 1024 entries at once. The delegate's transaction pays that cost once, and later spends return to the flat cost. 1024 is a reference storage bound, not a signed `maxCalls`. `usage.calls` is observational for the same reason.

## Backwards Compatibility

This proposal adds a new typed-data domain, JSON shape, and registry interface. It does not change consensus, [EIP-712](./eip-712.md), [ERC-1271](./eip-1271.md), or [ERC-20](./eip-20.md) token behavior. Existing tokens need not implement hooks. Native currency is identified by the [ERC-7528](./eip-7528.md) address, as in other ERC-7528 systems; an executor MUST NOT treat `address(0)` as native.

## Test Cases

Golden vectors are in [`v1.json`](../assets/eip-0/vectors/v1.json). They include domain separator, struct hash, digest, canonical rendering bytes, and an EOA signature. An implementation of the Specification reproduces those values. No additional requirements are defined here.

## Reference Implementation

A non-normative Solidity reference lives under the [assets directory](../assets/eip-0/). It is an aid to implementers. The Specification is authoritative. Hashing, rendering, JSON interchange, validation, caps, and rolling expiry are implementable from this document without those sources.

## Security Considerations

For [ERC-20](./eip-20.md) assets, the principal's allowance to the executor is the authority that actually lets funds move; the grant bounds how the executor uses it. A principal SHOULD keep that allowance no higher than the sum of remaining budgets of outstanding grants on that executor, and wallets SHOULD show the allowance next to the grants it backs. An executor with a larger allowance can move more than any grant permits if the executor is faulty.

Two asset entries can denote the same underlying balance, for example a chain whose native currency is also exposed through an ERC-20 interface at a different decimal scale. A grant that lists both has two independent budgets over one balance. Issuers SHOULD list only one identifier for such an asset; wallets SHOULD warn when a grant lists a known alias pair.

The registry never moves funds. Safety of the principal's assets depends on the executor calling `consume` in the same transaction as movement and reverting if either step fails. A dishonest executor that the principal bound by signing that registry can move value without a matching debit, or debit without moving. Choosing a registry is choosing an executor. Wallets that omit `executor()` from the pre-sign display hide that binding.

`consume` is not payable-for-value and does not inspect balance deltas. Fee-on-transfer, elastic-supply, or malicious ERC-20 tokens can make the recorded `amount` differ from the principal's balance change. That is an executor and token-selection problem; the remaining store tracks the `amount` argument.

Revocation is per principal and permanent. It does not pause the executor. A `consume` already in flight in the same block as `revoke` races on transaction order. There is no admin to freeze a stolen delegate; the principal revokes hashes they signed, and remaining caps bound a stolen delegate until then.

Code-bearing principals other than EIP-7702 accounts are ERC-1271 only. An implementation that falls back to ECDSA when `isValidSignature` fails would treat a contract with an `owner` key as that key. The EIP-7702 exception is safe only because the designator identifies an account whose key already controls it; implementations MUST match the exact 23-byte designator rather than any code that begins with `0xef`. ERC-1271 is evaluated at execution, so a principal that rotates its validation logic can invalidate outstanding grants without the registry's help. An EIP-7702 principal cannot invalidate grants its key signed by changing its delegation; it revokes them.

The 1024-live-debit bound (or any similar bound) is a grief surface: many small in-window consumes can fill the window and force `WINDOW_FULL` until the oldest debit expires. Only the executor can call `consume`, so the grief requires the executor or the delegate it serves. This is an intentional fail-closed behavior.

`block.timestamp` is proposer-influenced. Window and validity checks inherit that. Short `windowSeconds` values are more sensitive than lifetime caps.

Reentrant `consume` during an ERC-1271 callback, or during a later token hook in the executor's movement, can apply several per-call amounts in one transaction if remaining allows. The per-call cap limits each call, not the transaction. Registry authors who want a single debit per transaction add their own lock; this specification does not.

The registry cannot be paused or upgraded. A bug in remaining arithmetic is permanent for that deployment. A new registry is a new domain and requires new signatures.

Salt reuse with identical terms is the same grant. It does not reset remaining. Distinct grants need a distinct salt or a distinct field.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
