---
eip: TBD
title: Minimal Tipping Interface
description: "A standard interface for contracts to accept pre-approved tip amounts."
author: @nxt3d
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2026-02-10
---

## Abstract

This standard defines a minimal interface for smart contracts to accept optional tips. Contract operators pre-approve specific tip amounts. When a user's payment exceeds the required amount by exactly a pre-approved tip amount, the tip is retained. Payments that do not match a pre-approved tip amount should be rejected.

## Motivation

Many on-chain services charge a base fee or operate for free. Users may wish to voluntarily tip to support the service, unlock perks, or signal appreciation. Without a standard, each contract invents its own tipping mechanism, making it difficult for wallets, frontends, and indexers to present tipping options consistently.

A standard tipping interface solves this by:

- Letting contract operators define exactly which tip amounts are valid, preventing accidental overpayment.
- Emitting a standard event so off-chain systems can uniformly track tips and associate them with perks.
- Keeping the interface minimal so it can be added to any payable contract regardless of its primary function.

This is especially useful for free services (e.g., free NFT mints) where the base cost is zero and tipping is the only way to monetize.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

Compliant contracts MUST implement the following interface:

```solidity
interface IMinimalTipping {
    /// @notice Emitted when a tip amount is enabled or disabled.
    /// @param amount The tip amount in wei.
    /// @param valid  Whether this amount is now accepted (true) or rejected (false).
    event TipUpdated(uint256 amount, bool valid);

    /// @notice Emitted when a tip is received.
    /// @param tipper The address that sent the tip.
    /// @param amount The tip amount in wei.
    event TipReceived(address indexed tipper, uint256 amount);

    /// @notice Enable or disable a specific tip amount.
    /// @param amount The tip amount in wei.
    /// @param valid  true to accept this amount, false to stop accepting it.
    function setTip(uint256 amount, bool valid) external;

    /// @notice Query whether a specific tip amount is currently accepted.
    /// @param amount The tip amount in wei.
    /// @return True if the amount is an accepted tip.
    function tipAmounts(uint256 amount) external view returns (bool);
}
```

### Behaviour

1. When `setTip` is called, the contract MUST emit a `TipUpdated` event with the `amount` and `valid` arguments.

2. When a payable function receives payment that exceeds the required amount, the contract MUST check whether the overpayment matches a valid tip amount (i.e., `tipAmounts[overpayment]` is `true`).

3. If the overpayment matches a valid tip amount, the contract MUST retain the tip and MUST emit a `TipReceived` event. The contract MAY also include the tip amount in any domain-specific event it emits.

4. If the overpayment does not match a valid tip amount, the contract SHOULD reject the transaction (i.e., revert). Implementations MAY instead refund the overpayment, but this is NOT RECOMMENDED as it may mask user error.

5. A tip amount of `0` MUST NOT be set as valid. Calling `setTip(0, true)` SHOULD revert.

6. Multiple tip amounts MAY be valid simultaneously. There is no limit on how many tip amounts can be active.

## Rationale

**Why pre-approved amounts instead of arbitrary tips?** Overpayment is a security risk: without clear rules, a user can accidentally send more than intended and have the excess silently absorbed. Pre-approved amounts bound overpayment to specific, intentional values. They also let operators map specific amounts to specific perks off-chain (e.g., 0.001 ETH = bronze supporter, 0.01 ETH = silver supporter) without on-chain perk logic.

**Why SHOULD reject instead of MUST?** Some contracts already have explicit refund logic for overpayment, and refunding is perfectly acceptable behaviour. Requiring a revert would be a breaking change for those. This ERC recommends *either* rejecting invalid overpayments or refunding them in a clear, auditable way, so that users can easily understand what happened when a non-approved tip amount is sent.

**Why a separate `TipReceived` event?** Domain-specific events (e.g., `AgentMintedWithFee`) may already include a `tip` field, but a dedicated `TipReceived` event allows generic indexing across all compliant contracts regardless of their domain.

## Backwards Compatibility

This ERC introduces no backwards compatibility issues. It is a purely additive interface that can be adopted by any existing or new contract with payable functions.

Contracts that currently refund overpayments can adopt this standard by checking tip validity before deciding whether to refund the overpayment or not. 

## Security Considerations

**Tip amount manipulation**: The contract operator controls which tip amounts are valid. Users SHOULD verify accepted tip amounts on-chain before sending a transaction. Frontends SHOULD read `tipAmounts` to display valid options.

**Reentrancy**: If an implementation refunds invalid overpayments instead of reverting, the refund involves an external call. Such implementations MUST use reentrancy protection (e.g., OpenZeppelin's `ReentrancyGuard`).

**Operator trust**: Users must trust that the operator will not add a tip amount matching common overpayment values to silently capture funds. This is mitigated by the `TipUpdated` event, which makes all changes auditable.

**Front-running**: An operator could front-run a user's transaction by calling `setTip` to enable the user's overpayment amount as a valid tip, capturing funds that would otherwise be refunded or rejected. Implementations CAN mitigate this by, for example, blocking newly added tip amounts for a short period of time, hard-coding an acceptable range of tip values, or using other protection mechanisms.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
