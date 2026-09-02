---
eip: XXXX
title: Extensible Contract Metadata
description: A key-value string metadata interface that lets contracts adopt new metadata conventions without changing their code.
author: Conner Swenberg (@ilikesymmetry), Steve Katzman (@stevieraykatz)
discussions-to: https://ethereum-magicians.org/t/extensible-contract-metadata-adopt-new-metadata-conventions-without-upgrading/29565
status: Draft
type: Standards Track
category: ERC
created: 2026-09-02
requires: 165
---

## Abstract

This proposal defines a minimal interface that gives any contract a generic, string-keyed metadata store. A reader retrieves the value at a key with a single view function, and the empty string denotes an unset key. An optional writable extension standardizes updating and removing entries, emitting an event on every change. Support is advertised through [ERC-165](./eip-165.md), so a consumer can detect the capability before calling. Because arbitrary keys can be written at any time, a contract that implements this interface once can adopt future metadata conventions without adding new functions.

## Motivation

Onchain metadata is conventionally exposed through purpose-built functions, each returning one specific value. Adopting a new piece of metadata therefore requires adding a new function, which means changing the contract's code. For an already-deployed contract that is an upgrade, and upgrades are frequently impractical: many contracts are non-upgradeable by design, have no privileged owner able to upgrade them, or are too widely integrated to migrate safely. The result is that useful metadata conventions stall, because the contracts that would carry them cannot economically adopt them.

This proposal changes the adoption model. A contract exposes a single generic key/value surface once. From then on, adopting any new metadata convention is a matter of writing a value at a new key — no new function, no new code, and no upgrade. The convention that gives a key its meaning can be defined independently, and after the contract was deployed.

This proposal deliberately covers only the transport: how a key/value entry is read, written, observed, and discovered. It does not define any particular key, nor the value expected at any key. Subsequent proposals are encouraged to build on this one by enshrining specific keys and their expected values; those definitions are out of scope here.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This specification defines two interfaces. The first, `IExtraMetadata`, is the read interface that consumers depend on. The second, `IExtraMetadataWritable`, is an optional extension that standardizes writes. Both require [ERC-165](./eip-165.md).

### Read interface

```solidity
interface IExtraMetadata /* is IERC165 */ {
    /// @notice Emitted whenever the value at `key` changes. An empty `value` indicates removal.
    event ExtraMetadataUpdated(string key, string value);

    /// @notice Returns the value stored at `key`, or the empty string if none is set.
    function extraMetadata(string calldata key) external view returns (string memory value);
}
```

- `extraMetadata` MUST return the value currently associated with `key`, or the empty string if none is set. The empty string is the canonical representation of an unset key; an implementation MUST NOT distinguish between a key that was never set and a key set to the empty string.
- Whenever the value associated with a key changes, the implementation MUST emit `ExtraMetadataUpdated(key, value)` with `value` set to the new value. A removal MUST be signalled by emitting the event with an empty `value`.
- An implementation of `IExtraMetadata` MUST implement ERC-165 and MUST return `true` from `supportsInterface` for the interface id `0x4ddf9da0`.

### Writable extension

```solidity
interface IExtraMetadataWritable /* is IExtraMetadata */ {
    /// @notice Sets, updates, or removes the value at `key`. An empty `value` removes the entry.
    function updateExtraMetadata(string calldata key, string calldata value) external;
}
```

- An implementation of `IExtraMetadataWritable` MUST also implement `IExtraMetadata`.
- `updateExtraMetadata` MUST set the value associated with `key` to `value`. If `value` is the empty string, the implementation MUST remove the entry, such that a subsequent call to `extraMetadata(key)` returns the empty string.
- `updateExtraMetadata` MUST revert if `key` is the empty string.
- On success, `updateExtraMetadata` MUST emit `ExtraMetadataUpdated(key, value)`, as required by the read interface.
- The set of accounts permitted to call `updateExtraMetadata` is implementation-defined. Implementations SHOULD restrict it to a trusted role. An implementation that permits unauthorized callers to write metadata SHOULD document that explicitly.
- An implementation of `IExtraMetadataWritable` MUST return `true` from `supportsInterface` for the interface id `0xb2851ef5`, in addition to the read interface id.

### Interface identifiers

Interface identifiers are computed as defined by ERC-165: the XOR of the function selectors declared in each interface. Each interface here declares a single function, so the identifiers equal those selectors: `0x4ddf9da0` for `extraMetadata(string)` and `0xb2851ef5` for `updateExtraMetadata(string,string)`. Events do not contribute to an interface identifier.

## Rationale

A generic key/value surface, rather than one typed getter per feature, is the mechanism that lets a contract adopt a new metadata convention without changing its code — the central goal of this proposal. Once the surface exists, a new convention is adopted by writing a key, not by shipping a new function.

The empty string denotes both an unset key and a removed key. This avoids a separate existence flag, keeping reads and storage simple and cheap. The trade-off is that a key cannot hold a semantically meaningful empty value; this is acceptable because metadata values are descriptive, and a convention that needs to express emptiness can define a sentinel.

The read and writable interfaces are split so that a consumer only needs the read interface, and a contract may expose read-only metadata fixed at construction while remaining fully conformant to the read interface without a public writer. Separate ERC-165 identifiers let a consumer distinguish a contract that merely has metadata from one that offers a standardized write path.

Keys and values are strings because they are human-readable and match existing metadata conventions; a governing convention may define an encoding within the string, such as a URI or a JSON document, without changing this interface. The interface is contract-level, with no token identifier, to keep it universal across tokens, registries, and other contracts; a token-scoped variant can be defined by a separate proposal. The event carries the full new value so that offchain indexers can reconstruct current state from logs alone.

Alternatives considered: per-convention typed function interfaces, which is the status quo this proposal is designed to replace and which requires an upgrade to adopt; an external metadata registry contract, which adds an indirection and a separate trust domain; and offchain metadata documents referenced by a URI, which are not composable onchain and require a resolver.

## Backwards Compatibility

No backward compatibility issues found. The interfaces are additive: they introduce new functions and a new event, and do not modify the behaviour of any existing interface. A contract MAY implement this proposal alongside existing URI-based metadata mechanisms.

## Test Cases

Let `C` be a contract implementing `IExtraMetadataWritable` with writes restricted to an authorized account `A`.

- `C.extraMetadata("category")` returns `""` before any value is set.
- `A` calls `C.updateExtraMetadata("category", "bond")`; afterwards `C.extraMetadata("category")` returns `"bond"`, and the call emitted `ExtraMetadataUpdated("category", "bond")`.
- `A` calls `C.updateExtraMetadata("category", "")`; afterwards `C.extraMetadata("category")` returns `""`, and the call emitted `ExtraMetadataUpdated("category", "")`.
- `A` calls `C.updateExtraMetadata("", "x")`; the call reverts.
- An account other than `A` calling `C.updateExtraMetadata` reverts, given `C`'s chosen authorization policy.
- `C.supportsInterface(0x4ddf9da0)` returns `true` and `C.supportsInterface(0xb2851ef5)` returns `true`.
- A read-only contract `R` implementing only `IExtraMetadata` returns `true` for `R.supportsInterface(0x4ddf9da0)` and `false` for `R.supportsInterface(0xb2851ef5)`.

## Reference Implementation

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IExtraMetadata is IERC165 {
    event ExtraMetadataUpdated(string key, string value);

    function extraMetadata(string calldata key) external view returns (string memory value);
}

interface IExtraMetadataWritable is IExtraMetadata {
    function updateExtraMetadata(string calldata key, string calldata value) external;
}

abstract contract ExtraMetadata is IExtraMetadataWritable {
    mapping(string => string) private _extraMetadata;

    error InvalidMetadataKey();

    function extraMetadata(string calldata key) external view returns (string memory) {
        return _extraMetadata[key];
    }

    function updateExtraMetadata(string calldata key, string calldata value) external {
        _authorizeMetadataUpdate(key, value);
        if (bytes(key).length == 0) revert InvalidMetadataKey();

        if (bytes(value).length == 0) {
            delete _extraMetadata[key];
        } else {
            _extraMetadata[key] = value;
        }

        emit ExtraMetadataUpdated(key, value);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IExtraMetadata).interfaceId
            || interfaceId == type(IExtraMetadataWritable).interfaceId;
    }

    /// @dev Implement to restrict who may write metadata. Revert to deny the caller.
    function _authorizeMetadataUpdate(string calldata key, string calldata value) internal virtual;
}
```

## Security Considerations

The interface intentionally leaves the write-authorization policy to the implementation. An implementation that does not restrict `updateExtraMetadata` lets any account set or remove metadata, which can mislead consumers that rely on it. An implementation that exposes the writable extension should gate it behind a trusted role and treat the metadata surface as privileged state.

A consumer must not treat a value as authoritative merely because it is present. The meaning and trustworthiness of a value depend on the governing convention and on the trust model of the account that set it; a consumer should establish who is permitted to write a given key on a given contract before relying on the value.

Values are arbitrary strings supplied by the writer. A consumer that renders a value, for example in a web interface, must sanitize it: a value may contain markup or control characters chosen to attack a downstream renderer.

The interface provides no onchain enumeration of keys. Offchain indexers reconstruct current state from `ExtraMetadataUpdated` logs, so an implementation that mutates metadata without emitting the event, in violation of this specification, will cause indexers to serve stale data. A consumer that requires completeness should read values directly with `extraMetadata` rather than relying solely on logs.

Because any convention may choose any key, uncoordinated conventions can collide on the same key with incompatible meanings. Conventions defined in later proposals should choose specific, descriptive keys to reduce collisions; this specification does not enforce a namespace. Finally, keys and values are unbounded, so very large values raise the gas cost of writes and of any onchain reader; an implementation may bound their length.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
