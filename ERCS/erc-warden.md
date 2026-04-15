---
eip: XXXX
title: Warden - Secure Token Custody Contract 
description: A standard interface for controller-scoped ERC-20 token custody with time-locked funds and account designation.
author: Adam Uhlir <adam@uhlir.dev>, Mark Spanbroek <mark@spanbroek.net>, Eric Mastro (@emizzle)
discussions-to: https://ethereum-magicians.org/t/erc-warden-contract-secure-token-custody/28252
status: Draft
type: Standards Track
category: ERC
created: 2026-04-15
requires: 20
---

## Abstract

This proposal defines a standard interface for a **Warden** - a smart contract that holds ERC-20 tokens on behalf of other smart contracts (called *controllers*). Controllers instruct the Warden to move tokens between internal accounts; they never hold tokens themselves. The Warden organises accounts into *funds* that carry a time-lock lifecycle. Tokens can be irreversibly committed to an account holder (*designation*) or destroyed (*burning*). The lock invariant is enforced at every state-changing operation.

## Motivation

Most DeFi contracts hold their own ERC-20 token balances. When a bug or exploit is found in the business logic, an attacker can often drain the entire balance in a single transaction. The Warden pattern introduces **defence in depth**: the token custody contract enforces invariants that constrain what even a fully compromised controller can do.

A second, often overlooked threat is the controller itself. Many production contracts use upgradability patterns such as UUPS or transparent proxies. This means the contract owner can push a new implementation at any time - intentionally or after their owner account is compromised - that redirects all held tokens. Because the Warden holds the tokens and enforces its own rules independently of the controller's logic, no controller upgrade can circumvent them.

Concretely, the Warden addresses these threat scenarios:

- **Redirecting funds** - A time-lock prevents an attacker from withdrawing tokens immediately; by the time the lock expires, the balances are fixed in place.
- **Stealing collateral** - Designation makes tokens permanently committed to their rightful holder; no controller operation can transfer them away.
- **Blocking withdrawals** - Account holders can call `withdrawByRecipient` directly, bypassing the controller entirely.
- **Upgradability rug-pull** - If the controller uses an upgradability pattern, a malicious or compromised owner cannot push an upgrade that steals funds; the Warden's constraints apply regardless of the controller's implementation.

## Specification

The keywords "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

| Term | Definition |
|------|-----------|
| **Warden** | The custody contract defined by this standard. Holds ERC-20 tokens on behalf of controllers and enforces all invariants. |
| **Controller** | A smart contract that instructs the Warden to move tokens. Identified by its address (`msg.sender`). Each controller has an isolated namespace of funds and cannot access another controller's funds. |
| **Fund** | A top-level grouping of accounts owned by one controller. Carries a time-lock lifecycle and a unique `FundId` chosen by the controller. |
| **Account** | A subdivision of a fund belonging to one holder. Tracks an available balance and a designated balance separately. Identified by an `AccountId`. |
| **Holder** | The address that is entitled to withdraw the tokens in an account. Encoded in the high-order 20 bytes of the `AccountId`. |
| **Discriminator** | A 12-byte value packed into the low-order bytes of an `AccountId`. Allows one holder address to own multiple independent accounts within the same fund. |
| **Available balance** | The portion of an account's balance that the controller can still transfer to other accounts or designate. |
| **Designated balance** | The portion of an account's balance that has been irreversibly committed to the holder. Cannot be transferred to any other account; can only be burned or withdrawn by the holder. |
| **Designation** | The act of moving tokens from available to designated. Irreversible within the lifetime of a fund. |
| **Burning** | Permanently destroying tokens by sending them to address `0x000000000000000000000000000000000000dEaD` or using the `burn()` function of the used ERC-20 token. |
| **Lock** | The time-window during which the controller may operate on a fund. Defined by `lockExpiry` — the timestamp at which the fund transitions to `Withdrawing`. |
| **Seal** | A controller-initiated transition that closes a fund to all further operations before the lock expires naturally. The fund remains sealed until `lockExpiry`, then transitions to Withdrawing. |

### Types

For better readability this specification introduces the following alias types:

| Type | Underlying | Description |
|------|-----------|-------------|
| `FundId` | `bytes32` | Identifies a fund within a controller's namespace. Chosen by the controller. |
| `AccountId` | `bytes32` | Identifies an account. Encodes a 20-byte holder address (high bits) and a 12-byte discriminator (low bits). |
| `Timestamp` | `uint40` | A Unix timestamp in seconds. Used for lock expiry values. |

A compliant Warden MUST use these types (or their underlying equivalents) in its interface.

### Fund state machine

A compliant Warden MUST implement the following fund states:

```solidity
enum FundStatus {
  Inactive,     // No lock set; no tokens held.
  Locked,       // Time-lock is active; controller operations are permitted.
  Sealed,       // Seal account balances - no further transfers or any other changes until the fund unlocks.
  Withdrawing   // Lock has expired; withdrawals are permitted.
}
```

A fund progresses through states according to the following state machine:

```
Inactive ──lock()──► Locked ──lockExpiry passes──► Withdrawing
                       │
                   sealFund()
                       │
                       ▼
                     Sealed ──lockExpiry passes──► Withdrawing
```

A fund MUST begin in the `Inactive` state. The `Inactive` state means no lock has ever been set on that `(controller, fundId)` pair. Once a lock has been set, the `(controller, fundId)` pair MUST NOT transition back to `Inactive`, even if all account balances are zero. Reuse of a `FundId` by the same controller is therefore impossible after locking.

### Controller Identity

The Warden uses `msg.sender` as the controller address for all fund-scoped operations. Each controller has an isolated namespace of funds; one controller cannot access another controller's funds.

### Account Identity

An `AccountId` MUST pack the holder address into the 20 high-order bytes and the discriminator into the 12 low-order bytes:

```
AccountId = bytes32(bytes20(holder)) | bytes32(uint256(uint96(discriminator)))
```

The holder address embedded in the `AccountId` is the only address to which tokens can be withdrawn from that account. The discriminator allows a single address to hold multiple independent accounts within the same fund.

### Smart contract deployment and maintenance

A Warden implementation MUST NOT utilize upgradeability patterns like UUPS or transparent proxies. If the Warden deployer requires operational control, they MAY support pausing by an owner or governance contract. If pausing is implemented:

- All controller operations (`lock`, `deposit`, `transfer`, `designate`, `burnDesignated`, `burnAccount`, `sealFund`, `withdraw`) SHOULD be blocked when paused.
- `withdrawByRecipient` MUST remain callable when paused. Account holders must always be able to recover their tokens.

### Operations

#### `lock`

```solidity
function lock(FundId fundId, Timestamp expiry) external;
```

Activates a fund by setting its time-lock.

- MUST revert with `WardenFundAlreadyLocked` if the fund is not in `Inactive` state.
- On success: the fund transitions to `Locked`.

#### `deposit`

```solidity
function deposit(FundId fundId, AccountId accountId, uint128 amount) external;
```

Moves ERC-20 tokens from `msg.sender` into the Warden and credits the account's *available* balance.

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- MUST transfer `amount` of the Warden's ERC-20 token from `msg.sender` to the Warden contract using `safeTransferFrom`. MUST revert if the transfer fails.
- On success: `account.balance.available += amount`.

#### `transfer`

```solidity
function transfer(FundId fundId, AccountId from, AccountId to, uint128 amount) external;
```

Moves available tokens between two accounts within the same fund. Only *available* tokens (not designated) can be transferred.

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- MUST revert with `WardenInsufficientBalance` if `amount > from.balance.available`.
- After the solvency check passes: `from.balance.available -= amount`, `to.balance.available += amount`.

#### `designate`

```solidity
function designate(FundId fundId, AccountId accountId, uint128 amount) external;
```

Irreversibly commits available tokens to the account holder. Once designated, tokens cannot be transferred to any other account.

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- MUST revert with `WardenInsufficientBalance` if `amount > account.balance.available`.
- On success: `account.balance.available -= amount`, `account.balance.designated += amount`.

#### `burnDesignated`

```solidity
function burnDesignated(FundId fundId, AccountId accountId, uint128 amount) external;
```

Destroys a specified quantity of designated tokens from an account (penalty/slashing).

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- MUST revert with `WardenInsufficientBalance` if `amount > account.balance.designated`.
- On success: `account.balance.designated -= amount`. The `amount` of tokens MUST be transferred to address `0x000000000000000000000000000000000000dEaD` or burned using the `burn()` function of the ERC-20 token, if it supports it.

#### `burnAccount`

```solidity
function burnAccount(FundId fundId, AccountId accountId) external;
```

Destroys the entire balance (available + designated) of an account.

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- On success: deletes the account record and transfers `available + designated` tokens to address `0x000000000000000000000000000000000000dEaD` or burned using the `burn()` function of the ERC-20 token, if it supports it.

#### `sealFund`

```solidity
function sealFund(FundId fundId) external;
```

Seals account balances - no further transfers, designations, deposits, or burns are permitted until the lock expires and withdrawals begin.

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- On success: the fund enters `Sealed` state.

#### `withdraw`

```solidity
function withdraw(FundId fundId, AccountId accountId) external;
```

Called by the controller to send an account's full balance to its holder.

- MUST revert with `WardenFundNotUnlocked` if the fund is not in `Withdrawing` state.
- MUST compute `total = account.balance.available + account.balance.designated`.
- MUST delete the account record before transferring (so a second `withdraw` call for the same account transfers zero tokens).
- MUST transfer `total` of the ERC-20 token to the holder address extracted from `accountId`.

#### `withdrawByRecipient`

```solidity
function withdrawByRecipient(
    address controller,
    FundId fundId,
    AccountId accountId
) external;
```

Called directly by the account holder, bypassing the controller. This is a critical safety escape hatch.

- MUST revert with `WardenOnlyAccountHolder` if `msg.sender` is not equal to the holder address encoded in `accountId`.
- Otherwise identical to `withdraw`, using the provided `controller` to scope the fund lookup.

This function MUST NOT be subject to the pause mechanism (if any), so that account holders can always recover their tokens even when the Warden is paused.

### Query Functions

A compliant Warden MUST expose the following view functions. For fund-scoped queries, `msg.sender` determines the controller namespace:

```solidity
function getToken() external view returns (IERC20);
```
Returns the ERC-20 token that this Warden holds custody of.

```solidity
function getBalance(FundId fundId, AccountId accountId) external view returns (uint128);
```
Returns the total token balance of an account (`available + designated`). Returns 0 for `Inactive` funds.

```solidity
function getDesignatedBalance(FundId fundId, AccountId accountId) external view returns (uint128);
```
Returns only the designated portion of the balance. Returns 0 for `Inactive` funds.

```solidity
function getFundStatus(FundId fundId) external view returns (FundStatus);
```
Returns the current state of a fund.

```solidity
function getLockExpiry(FundId fundId) external view returns (Timestamp);
```
Returns the `lockExpiry` timestamp of the fund.

### Invariants

The core specification defines no invariants beyond the fund state machine transition rules. Each operation enforces its preconditions via the status checks described above. Extensions may introduce additional invariants; see the relevant extension sections.

### Errors

| Error | Condition |
|-------|-----------|
| `WardenFundAlreadyLocked` | `lock` called on a fund that is not `Inactive` |
| `WardenFundNotLocked` | A controller operation requiring `Locked` state was called on a fund that is not `Locked` |
| `WardenFundNotUnlocked` | `withdraw` called on a fund that is not `Withdrawing` |
| `WardenInsufficientBalance` | An operation would exceed the available or designated balance |
| `WardenOnlyAccountHolder` | `withdrawByRecipient` called by an address that is not the account holder |

### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IERC-XXXX Secure Token Custody Warden
interface IWarden {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    type FundId is bytes32;

    // AccountId encodes: bytes20(holder) || bytes12(discriminator)
    type AccountId is bytes32;

    type Timestamp is uint40;

    enum FundStatus {
        Inactive,
        Locked,
        Sealed,
        Withdrawing
    }

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error WardenFundAlreadyLocked();
    error WardenFundNotLocked();
    error WardenFundNotUnlocked();
    error WardenInsufficientBalance();
    error WardenOnlyAccountHolder();

    // -------------------------------------------------------------------------
    // Query functions (msg.sender is the controller)
    // -------------------------------------------------------------------------

    function getToken() external view returns (IERC20);

    function getBalance(FundId fundId, AccountId accountId)
        external view returns (uint128);

    function getDesignatedBalance(FundId fundId, AccountId accountId)
        external view returns (uint128);

    function getFundStatus(FundId fundId) external view returns (FundStatus);

    function getLockExpiry(FundId fundId) external view returns (Timestamp);

    // -------------------------------------------------------------------------
    // Fund lifecycle (msg.sender is the controller)
    // -------------------------------------------------------------------------

    function lock(FundId fundId, Timestamp expiry) external;

    function sealFund(FundId fundId) external;

    // -------------------------------------------------------------------------
    // Token operations (msg.sender is the controller; fund must be Locked)
    // -------------------------------------------------------------------------

    function deposit(FundId fundId, AccountId accountId, uint128 amount) external;

    function transfer(
        FundId fundId,
        AccountId from,
        AccountId to,
        uint128 amount
    ) external;

    function designate(
        FundId fundId,
        AccountId accountId,
        uint128 amount
    ) external;

    function burnDesignated(
        FundId fundId,
        AccountId accountId,
        uint128 amount
    ) external;

    function burnAccount(FundId fundId, AccountId accountId) external;

    // -------------------------------------------------------------------------
    // Withdrawal (fund must be Withdrawing)
    // -------------------------------------------------------------------------

    /// @notice Called by the controller to withdraw on behalf of an account holder.
    function withdraw(FundId fundId, AccountId accountId) external;

    /// @notice Called directly by the account holder; bypasses the controller.
    ///         MUST remain callable even when the Warden is paused.
    function withdrawByRecipient(
        address controller,
        FundId fundId,
        AccountId accountId
    ) external;
}
```

## Rationale

### Controller-as-caller identity

Using `msg.sender` as the controller address removes the need for explicit access control lists inside the Warden. A controller can only access funds it created. This keeps the interface minimal and avoids a separate registration step.

### `FundId` chosen by the controller

Controllers typically derive `FundId` from a domain object. This allows deterministic lookup without requiring the Warden to issue IDs, and it means the controller can lock a fund in the same transaction that creates the domain object.

### No `FundId` reuse

Once a `(controller, fundId)` pair has been locked, re-locking the same pair is rejected. This ensures that account state from a previous lifecycle of the fund cannot bleed into a new one.

### Burn address `0x000...dEaD` instead of `address(0)`

Some ERC-20 implementations revert on `transfer` to `address(0)`. Using `0xdEaD` avoids this while making burned tokens visibly auditable on-chain.

### `withdrawByRecipient` not pausable

The ability for account holders to withdraw directly is the ultimate safety guarantee. If the Warden owner or governance is also compromised, pausing the Warden must not be able to trap account holders' funds. A paused Warden that blocks all withdrawals would be indistinguishable from a compromised one.

### No events

This specification does not mandate events in order to keep the interface minimal. Implementations SHOULD emit events for off-chain indexing, but the exact event signatures are left to the implementer to avoid over-constraining the ABI.

### Controller access restriction

It is RECOMMENDED that Warden deployments restrict which addresses may act as controllers — for example, by allowlisting only the deployer's own contracts. An unrestricted Warden accepts any `msg.sender` as a controller, which means third parties could use it to custody their users' funds.

This matters most when the Warden has an owner or pausing mechanism. An owner who can pause the Warden gains effective control over every fund stored in it, regardless of which controller created the fund. If third-party funds are stored in a Warden that the deployer can pause, the deployer may be considered a custodian of those funds in some jurisdictions, with the associated regulatory and legal liability. Restricting the controller set to contracts the deployer controls keeps the deployer's custodial exposure limited to their own application.

## Extensions

This section describes optional extensions that implementations MAY support. Extensions MUST NOT break compliance with the core specification; a Warden that does not implement an extension remains fully compliant.

### Lock Extension (`extendLock`)

By default, a fund's lock expiry is fixed at the time `lock` is called. This extension allows the controller to push the expiry forward after locking, up to a ceiling (`lockMaximum`) established at lock time. This is useful when the duration of a deal or agreement may need to be extended without creating a new fund. Sealing a fund terminates the ability to extend its lock: `extendLock` requires `Locked` state and MUST revert on a `Sealed` fund.

#### Changes to `lock`

When this extension is supported, `lock` accepts an additional `maximum` parameter:

```solidity
function lock(FundId fundId, Timestamp expiry, Timestamp maximum) external;
```

- MUST revert with `WardenInvalidExpiry` if `expiry > maximum`.
- On success: sets `fund.lockExpiry = expiry` and `fund.lockMaximum = maximum`.

The `maximum` is fixed at lock creation time and MUST NOT be modified thereafter.

#### New operation

```solidity
function extendLock(FundId fundId, Timestamp expiry) external;
```

Pushes the lock expiry forward.

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- MUST revert with `WardenInvalidExpiry` if `expiry < fund.lockExpiry` (cannot move expiry backward).
- MUST revert with `WardenInvalidExpiry` if `expiry > fund.lockMaximum`.
- On success: sets `fund.lockExpiry = expiry`.

#### New invariant

```
fund.lockExpiry ≤ fund.lockMaximum
```

The lock expiry can never exceed the maximum established at `lock` time. Checked on `lock` and `extendLock`.

#### New error

| Error | Condition |
|-------|-----------|
| `WardenInvalidExpiry` | `lock` or `extendLock` called with an `expiry` outside the valid range |

#### Interaction with the Token Streaming extension

When both extensions are active, the solvency invariant uses `lockMaximum` as the upper time bound (rather than `lockExpiry`), ensuring that a streaming account holds enough available balance to cover outgoing flows even if `extendLock` is called later.

### Token Streaming (`flow`)

The streaming extension allows a controller to establish a **continuous per-second token transfer** between two accounts within the same fund. Rather than executing a transfer at every block, accumulated amounts are computed lazily on-demand whenever state changes, keeping gas costs proportional to operations rather than time elapsed.

Tokens flowing *into* an account become **designated** immediately on arrival — they cannot be redirected to any other account.

#### New type

```solidity
type TokensPerSecond is uint96;
```

#### New operations

```solidity
function flow(
    FundId fundId,
    AccountId from,
    AccountId to,
    TokensPerSecond rate
) external;
```

Establishes or updates a continuous token stream from `from` to `to` at `rate` tokens per second. Setting `rate` to zero cancels an existing stream.

- MUST revert with `WardenFundNotLocked` if the fund is not in `Locked` state.
- MUST enforce the **solvency invariant** (see below) on the sending account after updating the rate. MUST revert if the invariant would be violated.
- Accumulated flow since the last update MUST be settled before applying the new rate: the elapsed amount is deducted from `from.balance.available` and added to `to.balance.designated`.

#### New invariants

Two additional invariants apply when the streaming extension is active.

**Solvency invariant** — the sending account must hold enough available balance to cover all outgoing flow from now until the latest possible expiry:

```
flow.rate × (lockBound − now) ≤ account.balance.available
```

where `lockBound` is `fund.lockMaximum` if the Lock Extension is also implemented, or `fund.lockExpiry` otherwise. This is checked at the time `flow` is called and guarantees the stream is fully funded for the entire remaining lock duration.

**Flow conservation invariant** — for every fund, total incoming flow rate across all accounts equals total outgoing flow rate:

```
Σ incoming rates = Σ outgoing rates  (per fund)
```

This invariant is maintained naturally because each `flow` call sets one outgoing stream from one account to one other account within the same fund.

#### Interaction with `sealFund`

When this extension is active, the Warden MUST record the sealing timestamp on `sealFund` (`sealedAt = block.timestamp`). All flow calculations use `fund.sealedAt` as the cut-off timestamp instead of `lockExpiry`. No further accumulation occurs after sealing.

#### Interaction with `burnAccount`

`burnAccount` MUST revert if the account has any active incoming or outgoing flows. The controller must set those flows to zero before burning the account.

#### Security considerations

**Solvency at setup time, not at withdrawal time.** The solvency invariant is enforced when `flow` is called, not continuously. If additional transfers out of the sending account are made after a flow is established, the invariant must be re-checked; implementations SHOULD enforce it on every operation that reduces `available` balance on an account with outgoing flows.

**Re-entrancy during settlement.** Lazy settlement computes and applies accumulated amounts at the start of each state-changing operation. Implementations MUST apply settlement before performing any ERC-20 transfer to prevent re-entrancy from observing an unsettled state.

### Warden Discovery (`getWarden`)

Unlike the extensions above (which are implemented by the Warden contract), this convention applies to **controller contracts** that use a Warden as their custody backend.

A controller MAY expose the Warden address through the following view function:

```solidity
function getWarden() external view returns (IWarden);
```

This allows off-chain tools, indexers, and other on-chain contracts to discover which Warden instance a controller is backed by without inspecting deployment scripts or contract storage directly.

## Reference Implementation

A reference implementation is provided at https://github.com/auHau/erc-warden

## Security Considerations

### Re-entrancy

`deposit` uses `safeTransferFrom`, and `withdraw`/`burnDesignated`/`burnAccount` use `safeTransfer`. Implementations MUST delete or zero out account state before calling `safeTransfer` to prevent re-entrancy from inflating balances. The reference implementation deletes the account record before transferring in `withdraw` and `burnAccount`.

### Integer arithmetic

All balance arithmetic uses `uint128`. Implementations MUST ensure that `balance.available + balance.designated` cannot overflow when computing a withdrawal amount.

### Fund namespace isolation

Because `msg.sender` determines the controller namespace, a Warden that is itself a controller (e.g. a proxy or aggregator) creates a shared namespace for all callers of that contract. Implementers of controller contracts MUST ensure that distinct callers cannot affect each other's funds through the shared controller address.

### Withdrawal completeness

`withdraw` and `withdrawByRecipient` both delete the account record after computing the payout. A second withdrawal call for the same account returns zero. Controllers SHOULD NOT assume that a zero withdrawal means an error; it may indicate a previously withdrawn or empty account.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
