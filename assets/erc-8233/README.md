# ERC-8233 Warden reference implementation

> ⚠️ This implementation was not yet audited. Use it cautiously in production ⚠️

## Overview

The Warden is a smart contract pattern that separates ERC-20 token custody from business logic,
reducing the attack surface of contracts that manage funds. Rather than holding tokens directly,
a business-logic contract (called a **controller**) delegates all token custody to an external
Warden contract. The Warden enforces strict rules about when and how tokens can move, adding
time-based and designation-based protections that limit the damage an attacker can do even
after compromising the controller.

This repository contains a reference implementation of the ERC-8233 Warden standard,
based on an implementation by [Mark Spanbroek](https://github.com/markspanbroek) originally
written for Codex (now [Logos](https://logos.co/) Storage) and later forked into
[Archivist](https://archivist.storage/), where it is
[actively used](https://github.com/durability-labs/archivist-contracts/blob/main/contracts/Vault.sol).

This implementation covers the core [specification](./SPEC.md) and the Lock Extension. For the
Token Streaming extension, see [the original Archivist implementation](https://github.com/durability-labs/archivist-contracts/blob/main/contracts/Vault.sol).
Below is a changelog of the changes that differentiate this reference implementation from the original.

---

## Motivation

Most DeFi contracts hold their own tokens. When a bug or exploit is found in the business
logic, an attacker can often drain funds in a single transaction. The Warden pattern introduces
**defence in depth**: even if a controller is fully compromised, the Warden's invariants ensure
that:

- Tokens cannot be immediately redirected — the time-lock holds balances in place until expiry, after which they can only be withdrawn to their rightful holders.
- Collateral tokens can be permanently committed (designated) to their rightful owner,
  making redirection impossible.
- Account holders can always withdraw directly, bypassing a compromised controller entirely.
- Burning tokens is always available as a last resort to destroy value rather than let an
  attacker capture it.
- Controllers that use upgradability patterns (e.g. UUPS) cannot rug-pull users by upgrading
  their logic to redirect funds - the Warden's rules are enforced independently of the
  controller's implementation. Even if the controller's owner account is compromised and a
  malicious upgrade is pushed, tokens cannot be extracted outside the Warden's constraints.

---

## Concept

### Hierarchy

```
Warden
 └── Controller (a smart contract address)
      └── Fund (identified by a bytes32 FundId chosen by the controller)
           └── Account (identified by AccountId = holder address (20 bytes) | discriminator (12 bytes))
                ├── available balance
                └── designated balance
```

Each controller (i.e. each deployed business-logic contract) has its own isolated namespace
of funds inside the shared Warden. Controllers cannot access each other's funds.

Each fund is a collection of accounts that share a single lifecycle (the time-lock). Funds
are created by the controller choosing a unique `FundId`.

Each account belongs to a fund and tracks:
- **available balance** - tokens that the controller can still redistribute between accounts
- **designated balance** - tokens irreversibly committed to the account holder; cannot be
  transferred away, only burned or withdrawn

---

## Example: Storage Marketplace Usage

The Warden was designed for a decentralised storage marketplace (Archivist/Codex). The
Marketplace contract acts as the controller. The example below illustrates the full use case
including the Token Streaming extension (steps 4–7), which is not part of this implementation
but is available in the [original Archivist implementation](https://github.com/durability-labs/archivist-contracts/blob/main/contracts/Vault.sol).

For each storage request:

1. A `FundId` is derived from the request ID.
2. The fund is locked for the expiry window; the maximum is the full request duration.
3. The client deposits payment tokens into a client account.
4. A self-directed flow (`client → client`) ensures that unspent payment slowly designates
   itself back to the client (so it is returned if fewer than expected hosts fill slots).
5. When a host fills a slot:
   - The host deposits collateral; most of it is immediately **designated** to the host.
   - A **flow** is set from the client account to the host account at the per-second price.
6. If a host misses proofs (slashing):
   - A portion of their designated collateral is burned.
   - A validator reward is transferred to a validator account and immediately designated.
7. If a host is forcibly removed:
   - Their incoming flow is reversed back to the client.
   - Remaining balance is burned.
8. When the request ends:
   - The lock expires; the fund enters the Withdrawing state.
   - Hosts call `freeSlot` → `withdraw` to receive accumulated payment + remaining collateral.
   - The client calls `withdrawFunds` to receive any unspent payment.

## Changelog from Original Implementation (Vault)

- Renamed `Vault` to `Warden`
- Dropped Token Streaming in favour of simplicity
- Renamed `freezeFund` to `sealFund` to avoid confusion with confiscation of funds
