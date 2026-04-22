---
eip: 0
title: Contract Deactivation Interface
description: Interface for permanently deactivating a token contract and exposing its deactivation status
author: Ryan Sauge (@rya-sge)
discussions-to: https://ethereum-magicians.org/t/contract-deactivation-interface/0
status: Draft
type: Standards Track
category: ERC
created: 2026-02-12
requires: 165
---



## Abstract

This ERC defines a minimal interface for permanently deactivating a contract and exposing that terminal state on-chain. It introduces a one-way `deactivateContract()` operation and a `deactivated()` status view so wallets, exchanges, custodians, and protocols can reliably detect that a contract is no longer active.

The proposal is motivated by regulated Real-World Asset (RWA) use cases where issuers may need to irreversibly stop token operations due to corporate actions, legal migration, or end-of-life lifecycle events. It is also useful for DeFi applications (for example lending markets or AMM pools) that need to publish a clear on-chain signal that an instance is no longer active. The interface is intentionally small and can be combined with existing token standards such as [ERC-20](./eip-20.md), [ERC-721](./eip-721.md), or [ERC-1155](./eip-1155.md). The proposal adopts [ERC-165](./eip-165.md) so integrators can discover support programmatically.

## Motivation

Pause mechanisms are useful for temporary incidents. They are not enough for terminal lifecycle events where the issuer must communicate that the contract is no longer meant to be reactivated.

Common examples:

- security migration to a new contract after a legal restructuring,
- capitalization events (e.g. merger, split, reverse split) requiring old units to be immobilized,
- issuer decision to discontinue a ledger-based representation,
- DeFi market shutdowns (for example lending pool or AMM pair retirement) where operators need to signal permanent inactivity.

Without a standard signal, integrations cannot distinguish:

- a temporary pause,
- an operational outage,
- a permanent deactivation.

This ERC standardizes that signal.

This ERC is primarily designed for token contracts, but it is not limited to ERC-20 semantics and can be applied to contracts implementing other asset models.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
interface IERCDeactivation is IERC165 {
    /// @notice Emitted when the contract is permanently deactivated.
    /// @param account The address that triggered deactivation.
    event Deactivated(address indexed account);

    /// @notice Error raised when deactivation is attempted after deactivation is already final.
    error AlreadyDeactivated();

    /// @notice Permanently deactivates the contract.
    function deactivateContract() external;

    /// @notice Returns whether the contract has been deactivated.
    function deactivated() external view returns (bool isDeactivated);
}
```

### ERC-165 Support

Implementations MUST implement [ERC-165](./eip-165.md) and MUST return `true` from `supportsInterface` for:

- `0x01ffc9a7` (`IERC165`)
- `0xe9cd80b0` (`IERCDeactivation`)

Implementations MUST return `false` for `supportsInterface(0xffffffff)`.

### Required Behavior

1. **One-way state**
   - `deactivated()` MUST return `false` before successful deactivation and `true` after successful deactivation.
   - Once `deactivated()` becomes `true`, it MUST NOT return to `false` in the active implementation.
   - In upgradeable proxy systems, a future implementation MAY alter behavior. This does not break interface compatibility, but changes permanence assumptions and SHOULD be clearly disclosed to integrators.
   - Implementations behind upgradeable proxies SHOULD NOT present `deactivated()` as an on-chain technical guarantee of irreversible finality unless upgrade authority is effectively removed.

2. **Deactivation call**
   - `deactivateContract()` MUST set the deactivation state to `true`.
   - `deactivateContract()` MUST emit `Deactivated(account)`.
   - `deactivateContract()` MUST revert with `AlreadyDeactivated()` if deactivation has already happened.
   - `deactivateContract()` MUST be access-controlled.

3. **Pause precondition**
   - Implementations using a pause mechanism SHOULD require the contract to be paused before `deactivateContract()` succeeds.
   - If a pause precondition is used and not met, `deactivateContract()` MUST revert.

4. **Post-deactivation operational guarantees**
   - After deactivation, holder-initiated asset movement operations MUST revert. For example:
     - ERC-20: `transfer`, `transferFrom`, `safeTransferFrom` 
     - ERC-721
     - ERC-1155
   - After deactivation, supply-changing operations intended for normal lifecycle management (for example standard `mint` and `burn`) MUST revert.
   - If the implementation includes `unpause`, it MUST revert when `deactivated() == true`.
   - Implementations MAY keep explicitly privileged emergency/regulatory operations (for example forced transfer) available, but MUST document this behavior.
   
5. **Observability**
   - `deactivated()` MUST be a non-reverting view function.
   - Indexers and off-chain systems SHOULD treat `Deactivated` as a terminal lifecycle event.
   - For upgradeable proxy deployments, integrators are RECOMMENDED to adopt a conservative default assumption that once deactivated, the contract remains permanently deactivated, unless governance documentation explicitly states otherwise.

## Rationale

- **Minimalism**: Two functions and one event are sufficient for broad interoperability.
- **Separation of concerns**: This ERC does not mandate any access-control model, pause design, or legal workflow.
- **RWA and DeFi lifecycle signaling**: The standard addresses regulated token lifecycle events and DeFi lifecycle events (such as lending/AMM retirements) with a shared, auditable "no longer active" signal.
- **Compatibility with existing pause modules**: The interface composes naturally with existing pause implementations where deactivation acts as a permanent terminal pause.
- **Deployment-model neutrality**: Both immutable contracts and upgradeable proxies are compatible with this ERC. The interface standardizes signaling, not governance guarantees.

## Backwards Compatibility

This ERC is additive and does not modify existing token standards. Existing wallets and protocols can continue using base token interfaces and optionally integrate this ERC to detect terminal deactivation status.

## Reference Implementation

A reference pattern is:

- store a boolean `isDeactivated`,
- gate `deactivateContract()` behind authorization,
- require paused state (if pause exists),
- set `isDeactivated = true`,
- emit `Deactivated(msg.sender)`,
- reject `unpause` and normal transfer/mint/burn flows when deactivated.

## Security Considerations

- **Authorization risk**: Unauthorized access to `deactivateContract()` creates irreversible denial of service. Use robust access control (multisig, timelock, separation of duties).
- **Proxy nuance**: In upgradeable systems, deactivation may be bypassed by deploying a new implementation that changes logic. If strict permanence is required, implementations should use immutable deployments or disable upgrades (for example by irrevocably renouncing upgrade authority).
- **Integrator default for proxies**: For upgradeable proxy deployments, integrators should apply a conservative trust model and treat deactivation as permanent by default, unless issuer governance documentation explicitly communicates a different policy.
- **Operational risk**: Because deactivation is terminal, operators should use staged procedures (pause first, confirm terms/migration, then deactivate).
- **Integration risk**: Integrators should check `deactivated()` before presenting token actions to users.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
