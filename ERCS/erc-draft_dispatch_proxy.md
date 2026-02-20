---
eip: TBD
title: Modular Dispatch Proxies
description: Proxy-level function dispatch via delegatecall
author: William Morriss (@wjmelements), Radek Svarz (@radeksvarz)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-02-16
---

## Abstract

This proposal standardizes dispatch proxies, which dispatch calls to logic modules, called delegates, according to function selector.
A modular proxy architecture facilitates upgrades, extensions, and hardening, while working around codesize limits.
This minimal standard interface allows tooling to discover the ABI of these proxies and examine their upgrade history.

## Motivation

Proxy contracts utilizing `delegatecall` are widely used for both code sharing and upgradeability.
Most common proxies forward calldata to a single implementation contract.
Sometimes the implementation address is hardcoded, a pattern used by cloning factories to reduce deployment costs, and sometimes the implementation address is mutable, a pattern used by upgradeable proxies.
However, monolithic proxy architectures can bump into codesize limits.
Additionally, replacing the implementation of an entire contract at once can be riskier than smaller, more incremental changes.

### Shared Logic Modules

Many contracts share common code for things like tokens but cannot share their entire implementation because of their own unique characteristics.
For example, two tokens might share their balance logic and transfer interface but differ in their name metadata and monetary policy.
With a monolithic architecture, these differences require two separate contracts.
With a logic module architecture, they can share a standardized token implementation but customize their metadata and monetary policy.

### Extension

Sometimes new standards arise that provide new functionality or guarantees.
For example, a popular token interface extension might arise to provide a new and better method for modifying allowances.
With a monolithic architecture, token implementations must be wrapped or wholly replaced to support the new method.
With logic modules, the interface could be extended with a new module to support the new method.

### Upgrade

Monolithic proxy architectures require replacing the entire implementation during an upgrade.
Such upgrades batch changesets but introduce risk and are difficult to test and verify.
Modular dispatch proxies can still atomically batch upgrades, but their modular architecture allows incremental improvements and fixes without unintentionally breaking unrelated components.

### Hardening

Upgradeable dispatch proxies can be permanently hardened into immutable systems by uninstalling the upgrade methods.

### Standardization

A standard interface for the modular proxy architecture can help tools, user interfaces, and indexers determine the ABI of these proxies.
Such systems may also want to surface the full upgrade history of these proxies to facilitate investigation.

## Specification

A modular dispatch proxy MUST use `delegatecall` to relay the entire calldata to the delegate corresponding to the first four bytes of the calldata.
If the delegate for that selector is not set, the proxy MUST revert, and SHOULD revert with `FunctionNotFound(bytes4)`.

```solidity
interface IDispatchProxy {
    // REQUIRED
    // Emitted when assigning a delegate logic module to a selector
    // An address(0) delegate signals removal
    event SetDelegate(bytes4 indexed selector, address indexed delegate);

    // REQUIRED
    // Returns the delegate for the selector, using address(0) for function not found
    function implementation(bytes4 selector) external view returns (address);

    // RECOMMENDED
    // Surfaces the ABI
    // SHOULD return all function selectors with implementations
    function selectors() external view returns (bytes4[] memory);

    // RECOMMENDED
    error FunctionNotFound(bytes4 selector);
}
```

`IDispatchProxy` functions SHOULD be implemented by delegates rather than in the proxy.

A modular dispatch proxy constructor SHOULD configure at least one delegate.

## Rationale

### `bytes4 selector`

The most widely-supported ABI is Solidity's 4-byte ABI, which uses the first four bytes of calldata, called the selector, to dispatch functions.
The dispatch proxy also uses those same four bytes to dispatch function calls to their delegate.

### `implementation(bytes4)`

While implementations can be discovered with `eth_getStorageAt`, a common interface can support a variety of possible storage layouts and implementations.

This function's naming is consistent with monolithic proxies, but with a parameter.

### `selectors()`

This is a minimal function to surface ABI to tools.
While selectors are ambiguous, they can be resolved if their delegate has a verified ABI.
Together, these steps produce the ABI of the proxy:
1. For each `selector` in `selectors()`, query `implementation(selector)`.
2. For each unique implementation, check if its code is verified. If verified, retrieve the ABI. If not, allow the user to supply the missing ABI.
3. Identify the functions supported by the proxy by matching its selectors with their implementation's ABI.

Although selectors are also retrievable by querying `SetDelegate` events, the `selectors` function provides a way to get this information without access to the logs.
Log queries can be slow without a database index.

While a packed encoding would reduce memory allocation, an array of `bytes4` is the simplest for tooling to decode.
It is anticipated that this method will primarily be used by tooling.

### Upgrades

This standard does not specify an upgrade function.
Other standards could extend this one with versioning frameworks for atomic batch upgrades.

### Storage Layout

This standard does not specify a storage layout.
Other standards could suggest patterns to protect against storage collisions and other mistakes.

## Backwards Compatibility

This standard improves upon [ERC-2535](./eip-2535.md) in the following ways:

1. Removal of diamond jargon.
2. Fewer and simpler introspection functions.
3. Simpler upgrade event.

Existing upgradeable monolithic proxies MAY upgrade to this standard using the following upgrade plan:
1. Upgrade to an implementation with a method to populate the selector delegate mapping.
2. Populate the selector delegate mapping for all methods in the ABI.
3. Set the implementation to a dispatch proxy using the populated selector delegate mapping.

Existing modular proxies MAY upgrade to this standard by performing an upgrade that:

1. Adds the new introspection functions.
2. Emits a `SetDelegate` event for every installed function.

## Reference Implementation

TODO

### Example Proxy Bytecode

```hex
5f5f365f60045f5f3760405f205480602457635416eb985f5260045f6020376024601cfd5b365f5f375af43d5f5f3e6035573d5ffd5b3d5ff3
```
This proxy consults a Solidity mapping at storage index 0 to look up the delegate for the selector.

## Security Considerations

### Access control

Upgrade functions should have some form of access control.
Access control designs are outside the scope of this standard.

### Avoid self-destruct

Delegates MUST NOT self-destruct.
If a delegate can self-destruct, it can break proxies that use it.

### Storage Layout

Proxy upgrades must take care not to shift storage indices because this corrupts contract data.

Delegates should be designed to minimize the risk of storage layout overlap between them.
There are two known approaches to protect storage layouts against such collisions.

The first is to define a single shared proxy storage layout in a common superclass inherited by all of the proxy's delegates.
Such subclasses SHOULD NOT declare additional storage.

The second is to use storage namespaces, such as [ERC-7201](./eip-7201.md) and [ERC-8042](./eip-8042.md).
This approach is appropriate for shared libraries.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
