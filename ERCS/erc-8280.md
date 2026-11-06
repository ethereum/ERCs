---
eip: 8280
title: Contract Runtime Apps
description: Minimal runtime interfaces for smart contracts that host third-party runtime apps.
author: Xiang (@wenzhenxiang)
discussions-to: https://ethereum-magicians.org/t/erc-8280-contract-runtime-apps/28685
status: Draft
type: Standards Track
category: ERC
created: 2026-06-02
requires: 165, 7201
---

## Abstract

This ERC defines a minimal interface for smart contracts that host third-party runtime apps. A compliant host exposes local app enablement and a permissionless execution entry point for enabled apps.

Runtime app execution MUST occur in the host's context rather than as a plain external call into app-owned state. Shared-storage hosts and apps MUST isolate persistent state with [ERC-7201](./eip-7201.md)-compatible namespaced storage.

## Motivation

Smart contracts, especially smart accounts, increasingly host long-lived behavior such as inheritance rules, settlement flows, recurring payments, treasury policies, and trading logic. These features often need to run as extensions of the host, using host authority and host-owned state, rather than as unrelated external dapps.

This ERC standardizes a narrow runtime surface for executing enabled apps and inspecting local app enablement. Registries, app distribution, entitlement policy, and upgrade management are out of scope.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Runtime host**: a smart contract that implements this ERC and hosts one or more runtime apps.
- **Runtime app**: an application contract that a runtime host executes through `executeRuntimeApp`.
- **Host-context execution**: execution in which app code runs with the host's authority and, when persistent state is written by app code, against host-owned storage.
- **Shared-storage runtime**: a host-context runtime in which app code may read or write persistent state at the runtime host's storage address, commonly through `delegatecall` or an equivalent mechanism.

### Interfaces

Runtime hosts MUST implement:

```solidity
pragma solidity ^0.8.23;

interface IERCRuntimeAppHost {
    event AppEnabled(address indexed host, address indexed app);
    event AppDisabled(address indexed host, address indexed app);

    function executeRuntimeApp(address app, bytes calldata data)
        external
        payable
        returns (bytes memory result);

    function enableApp(address app) external;

    function disableApp(address app) external;

    function isAppEnabled(address app) external view returns (bool);
}
```

Runtime hosts MUST implement [ERC-165](./eip-165.md) and:

- `supportsInterface(type(IERCRuntimeAppHost).interfaceId)` MUST return `true`;
- `supportsInterface(type(IERC165).interfaceId)` MUST return `true`.

### Execution Requirements

1. `executeRuntimeApp(app, data)` MUST initiate execution of `app` as a runtime app of the runtime host.
2. `executeRuntimeApp` MUST revert if `app` is the zero address.
3. `executeRuntimeApp` MUST revert if `app` is not enabled at the time of execution.
4. `executeRuntimeApp` MUST be externally callable by arbitrary addresses. A runtime host MUST NOT restrict it exclusively to owners, administrators, entry points, or upgrade authorities.
5. Permissionless execution only grants permissionless triggering. It MUST NOT be interpreted as granting the caller host-owner authority.
6. Runtime app execution MUST occur in host context. A plain external `call` into storage owned exclusively by `app` does not satisfy this ERC.
7. `executeRuntimeApp` MUST be `payable`.
8. On success, `executeRuntimeApp` MUST return the raw return data from the runtime app.
9. If runtime app execution reverts and revert data is available, `executeRuntimeApp` MUST bubble that revert data. If revert data is unavailable, it MUST revert with an implementation-defined error.
10. A runtime host MUST reject nested runtime execution.
11. A runtime host MAY impose additional non-standard execution preconditions beyond local enablement state. Such preconditions are outside the scope of this ERC.

This ERC does not require a specific internal execution mechanism. A runtime host MAY use `delegatecall` or another equivalent mechanism, provided execution remains in host context. This ERC standardizes the observable execution semantics, not the internal dispatch mechanism.

### Enablement Requirements

1. `enableApp(app)` MUST mark `app` as enabled for future runtime execution on the calling runtime host.
2. `disableApp(app)` MUST mark `app` as disabled for future runtime execution on the calling runtime host.
3. `enableApp` and `disableApp` MUST revert if `app` is the zero address.
4. `enableApp` and `disableApp` MUST be protected by the runtime host's authorization model.
5. `isAppEnabled(app)` MUST return whether `app` is currently enabled on the runtime host as local host state.
6. On a successful enablement change, the runtime host MUST emit `AppEnabled` or `AppDisabled` respectively.

This ERC does not define who may call `enableApp` or `disableApp`; that policy is delegated to the host authorization model. A host MAY layer additional non-standard execution policy, provided `isAppEnabled` continues to describe local enablement state.

### Runtime Context

During runtime app execution, app code MUST observe `address(this)` as the runtime host.

During the top-level runtime app frame, app code MUST observe `msg.sender` as the external caller of `executeRuntimeApp`.

This ERC does not add runtime context getter functions because app code can use `address(this)` for the runtime host and `msg.sender` for the caller of `executeRuntimeApp`.

### Storage Isolation

Shared-storage runtime hosts and runtime apps:

- MUST use independent namespaced storage for host state and each app's persistent state; and
- MUST use storage locations compatible with ERC-7201.

They MUST NOT rely on default Solidity storage slot ordering to separate host state from app state or one app's state from another app's state. This requirement is equivalent in spirit to diamond storage, but this ERC does not require a diamond proxy architecture.

## Rationale

The runtime app is the interoperable unit exposed to users and tools. Internal facets, libraries, and helper APIs remain implementation details.

This ERC is architecture-neutral. A host may use account, proxy, or other modular patterns, but this ERC does not define upgrade or internal dispatch mechanics.

`enableApp`, `disableApp`, and `isAppEnabled` describe local runtime activation state. They intentionally do not encode external marketplace, registry, entitlement, or distribution policy.

Host-context execution is required so apps behave like host extensions rather than unrelated external calls.

Permissionless triggering allows counterparties, relayers, keepers, and executors to invoke enabled apps without requiring a host-owner transaction. This does not grant host-owner authority; apps remain responsible for authorization.

Rejecting nested runtime execution keeps caller, storage, and reentrancy semantics simple across implementations.

ERC-7201-compatible namespaced storage is required for shared-storage runtimes because storage collisions can let one app overwrite host state or another app's state.

## Backwards Compatibility

This ERC is additive and does not change the behavior of existing accounts, modular contracts, or app frameworks. Existing hosts can implement this interface without changing their internal execution or upgrade architecture, provided they satisfy the runtime semantics defined above.

## Test Cases

Implementers SHOULD cover at least the following cases:

- `executeRuntimeApp` succeeds for an enabled runtime app and returns the app's raw return data.
- `executeRuntimeApp` reverts for a disabled runtime app.
- `executeRuntimeApp` bubbles revert data from the runtime app when available.
- arbitrary external callers can invoke `executeRuntimeApp` for an enabled runtime app.
- during runtime app execution, app code observes `address(this)` as the runtime host.
- during the top-level runtime app frame, app code observes `msg.sender` as the caller of `executeRuntimeApp`.
- nested `executeRuntimeApp` calls revert.
- `executeRuntimeApp`, `enableApp`, and `disableApp` reject the zero address app.
- `enableApp` and `disableApp` change the value returned by `isAppEnabled`.
- `AppEnabled` and `AppDisabled` are emitted with the expected arguments.
- if a host layers additional non-standard execution conditions, `isAppEnabled` still reflects local enablement state rather than aggregate execution eligibility.
- the runtime host reports support for this ERC through ERC-165.
- shared-storage runtimes isolate host state and each app's state through ERC-7201-compatible namespaced storage.

## Reference Implementation

No reference implementation is included in this draft.

## Security Considerations

Runtime apps executed by a runtime host become part of the host's trust boundary. Implementers and integrators SHOULD treat app authorization and enablement as security-sensitive.

Because arbitrary external callers may invoke `executeRuntimeApp`, runtime apps MUST NOT assume that the caller is an owner or trusted operator. Permissionless triggering is not permissionless authority. Apps SHOULD make explicit authorization decisions using app-specific state, signed data, host-owned state, or another documented policy.

Runtime apps MUST NOT modify the host's app enablement state except through the host's authorized enablement mechanism. Shared-storage hosts MUST treat enablement storage as host state and isolate it from app storage.

Shared-storage runtimes are particularly sensitive to storage collisions. ERC-7201-compatible namespaced storage is REQUIRED because otherwise a runtime app may overwrite host-owned state or another app's state.

Any execution-local runtime state is security-sensitive. Implementations MUST prevent leakage across executions.

Runtime apps MUST NOT rely on nested runtime execution. Runtime hosts MUST reject nested `executeRuntimeApp` calls.

Runtime apps SHOULD be immutable application contracts. This ERC does not define proxy administration, app upgrade authorization, or app code replacement.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
