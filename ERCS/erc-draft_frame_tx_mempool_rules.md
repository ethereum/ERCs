---
title: Frame Transaction Alternative Mempools
description: Alternative mempools framework for EIP-8141 Frame Transactions that extend the public mempool with stake and reputation.
author:
discussions-to: https://ethereum-magicians.org/t/PLACEHOLDER
status: Draft
type: Standards Track
category: ERC
created: 2026-09-21
requires: 1153, 7702, 7819, 7843, 7951, 8037, 8141, 8250
---

## Abstract

[EIP-8141](./eip-8141.md) defines a new [EIP-2718](./eip-2718.md) transaction type and a set of rules such transactions need to follow in the canonical public mempool.
These canonical mempool rules are chosen to be relatively simple and universal in a way that enables a number of high priority use cases.
Other rulesets can exist to serve use cases made impossible by the canonical mempool rules, however without a public mempool such transactions would require a private submission mechanisms.
This document defines a framework for alternative mempools with customized validation rulesets for [EIP-8141](./eip-8141.md) Frame Transactions.
The rulesets define which transactions a node may admit to the mempool, which it rejects, and how it tracks the entities that form a transaction's validation process.

This document also defines the **standard alternative mempool**, a default ruleset for a permissionless and decentralized public Frame Trnansactions mempool that is less restrictive than the canonical one.

## Motivation

A frame transaction replaces a hard-coded signature check with EVM code that runs during a *validation prefix*. Before a mempool node relays such a transaction, it must execute the entire validation prefix code. If the prefix depends on mutable state that anyone can change, a single state change can invalidate many pending transactions at once, and a node that spends resources on those transactions is never paid. This is the *mass invalidation attack*. Mempools must put in place carefully designed sets of rules to bound this threat.

[ERC-4337](./eip-4337.md) relies on rules defined in [ERC-7562](./eip-7562.md) to solve the same problem for `UserOperation`s.
Frame Transactions differ from `UserOperation`s in ways that make defining a shared rule set inconvenient.
This document defines the Frame Transaction specific mempool rules in a way that maintains a full backward compatibility with use cases that existed in ERC-4337, like autonomous [ERC-20](./erc-20.md) Token Paymasters, privacy pool withdrawals and more.

## Specification

### Constants

| Name | Value | Description |
|---|---|---|
| `MAX_VERIFY_GAS_PER_ENTITY` | `100_000` | Maximum execution gas budget for a single unstaked or default-code entity's validation frames. |
| `MAX_VERIFY_GAS_STAKED_ENTITY` | `1_000_000` | Maximum execution gas budget for a single staked entity's validation frames. |
| `MIN_UNSTAKE_DELAY` | `86400` | One day. A withdrawal delay long enough to deter most Sybil attacks. |
| `MIN_STAKE_VALUE` | per-chain | A non-trivial but not excessive amount, roughly the equivalent of USD 1000 in the native token. |
| `SAME_NONCE_KEY_MEMPOOL_COUNT` | `4` | Maximum pending transactions per `(sender, nonce key)` lane ([EIP-8250](./eip-8250.md)). |
| `SAME_SENDER_MEMPOOL_COUNT` | `64` | Maximum pending transactions from one sender, summed across all of its nonce-key lanes. |
| `SAME_UNSTAKED_ENTITY_MEMPOOL_COUNT` | `10` | Base number of pending transactions that may reference the same unstaked sponsoring payer. |
| `THROTTLED_ENTITY_MEMPOOL_COUNT` | `4` | Pending transactions allowed for a throttled entity. |
| `THROTTLED_ENTITY_LIVE_BLOCKS` | `10` | Blocks a transaction referencing a throttled entity may stay in the mempool. |
| `THROTTLED_ENTITY_BLOCK_COUNT` | `4` | Transactions referencing a throttled entity that a node may include in one block it builds. |
| `MIN_INCLUSION_RATE_DENOMINATOR` | `10` | Denominator in the reputation formula. |
| `THROTTLING_SLACK` | `10` | Lets an entity legitimately fail some transactions without being throttled. |
| `BAN_SLACK` | `50` | Lets a throttled entity fail some transactions without being banned. |
| `MAX_TXS_ALLOWED_UNSTAKED_ENTITY` | `10000` | Upper bound on `included` when computing the allowance of an unstaked sponsoring payer. |
| `STAKING_REGISTRY_ADDRESS` | per-chain | Address of the Staking Registry contract (see [Staking Registry Contract](#staking-registry-contract)). |

### Mempool Types

This document relates to three distinct types of mempool rulesets for Frame Transaction mempools:

1. The **canonical public mempool**, as defined by EIP-8141 in the [Mempool](./eip-8141.md#Mempool) section.
2. The **standard alternative mempool**, as defined by this document.
3. The **non-standard alternative mempools**, which are defined by third party mempool operators as defined in [Alternative Mempools](#alternative-mempools) section.

A transaction that violates a canonical public mempool rule MUST NOT be propagated over the public mempool, as EIP-8141 requires. It may only be propagated over the appropriate alternative mempool's own transport if it satisfies its rules. One transaction may be propagated over multiple alternative mempools if it satisfies all of their rules.

### Alternative Mempools

The **standard alternative mempool** defined by this document is not the only possible rule set. Node operators may agree on alternative mempools, rule sets that a node opts into in addition to the standard mempool. Each alternative mempool is identified by its own topic, conventionally the IPFS hash of a document that describes its rules. A transaction that violates a standard rule MUST NOT be propagated in the standard mempool, but may be propagated in any alternative mempool whose rules it satisfies. Reputation counters (`seen` and `included`) should be kept separately for each mempool, so that an entity that is throttled in one mempool is unaffected in another.

### Rule Types

Public transaction mempools are distributed among multiple nodes in a peer-to-peer network, while each node maintains its own view of the mempool and participant reputations at all times. Additionally, certain nodes may choose to act as solo submission channels with custom rules but without a connection to a peer-to-peer network.
Therefore, there are two types of validation rules: **network-wide rules** and **local node rules**.

A violation of any rule by a frame transaction results in the transaction being rejected from submission or dropped from the mempool if necessary, and therefore prevented from being included in future blocks.

A peer-to-peer mempool networks rely on participant reputations to limit the threat of mass transaction invalidation. A **network-wide rule** is a rule whose violation by a transaction damages the reputation of the peer that sent that transaction into the standard mempool. A peer with critically low standing is treated as a **spammer** according to the [Propagation Rules](#propagation-propagation).

A **local rule** depends on a node's own mempool contents and its local tracking of entities' reputations. Different nodes may hold different mempool contents, so no consensus is possible and peers are never penalised for a local rule violation. Local rules are collected in the [Local Rules](#local-rules-local) section, and all other rules are network-wide.

### Definitions

1. **Validation prefix**: the shortest prefix of a transaction's frames whose successful execution sets `payer`, as defined by EIP-8141. All Frames that appear after the **validation prefix** regardless of their type belong to the **execution body** of the Frame Transaction and are largely outside this document's scope.
2. **Validation frame**: a frame in the validation prefix regardless of its mode, type or scope.
3. **Frame Subclasses**: a heuristic classification of a Validation Frame within a Frame Transactgion based on its role and behaviour in the transacion validation process.
   The EIP-8141 mode subclassifications defines the following subclasses: `self_verify`, `only_verify`, `pay`, `expiry_verify` and `deploy`; the `pre_verify` subclass is additionally defined in this document.
4. **Entity**: a smart contract that a Validation Frame executes directly. Entities are defined by their role in a transaction, similarly to Frame Subclasses:
    - The **sender** is `tx.sender`. It runs the `self_verify` or `only_verify` frame.
    - The **payer** is the resolved target of the frame that calls `APPROVE` with a payment scope. It runs the `pay` frame, or the `self_verify` frame if **sender** and **payer** is the same entity.
    - The **factory** is the resolved target of the `deploy` frame.
   Every validation frame is attributed to exactly one entity. An `expiry_verify` frame is attributed to no entity as its code is protocol-defined.
5. **Default-code entity**: an entity whose account has the empty code hash and therefore executes EIP-8141's default code. It has no bytecode to trace, is never staked, and is exempt from the opcode, call and storage rules.
6. **Staked entity**: an entity that has a stake of at least `MIN_STAKE_VALUE` and an unstake delay of at least `MIN_UNSTAKE_DELAY`, as reported by the **Staking Registry** smart contract, and whose stake is not being withdrawn.
7. **Associated storage**: a storage slot of any contract is *associated* with a givne address according to the [Associated Storage Rules](#associated-storage-rules-assoc).
9. **Canonical paymaster**: a contract whose runtime code exactly matches the canonical paymaster implementation defined by EIP-8141.
10. **Admission validation**: the simulation a node performs before it first accepts a transaction.
11. **Revalidation**: a re-simulation of a pending transaction against a newer head or a candidate block, as described in [Replacement, Eviction and Revalidation](#replacement-eviction-and-revalidation-lifecycle).
12. **Spammer**: a peer that attempts to exhaust the mempool network by sending a large number of transactions that were never valid.
13. **Mass invalidation attack**: a series of actions by which a large number of transactions, having passed admission validation and propagated through the mempool network, later become invalid and ineligible for inclusion.

### Execution Model

`VERIFY` frames run in static mode.
The non-static `DEFAULT` mode frames in the validation prefix are allowed for two subclasses:
- The `deploy` frame as defined in EIP-8141
- The `pre_verify` frame

Rules in this document that mention writes, contract creation or value calls consequently take effect only in those frames.

#### The `pre_verify` frame subclass

A `pre_verify` frame is a `DEFAULT`-mode frame whose resolved target is the same as the resolved target of the approving `VERIFY` frame (`self_verify`, `only_verify`, `pay`) that **immediately follows it**. Each approving frame MAY be preceded by at most one `pre_verify` frame.
A `pre_verify` frame is distinguishable from the `deploy` frame as it does not create code in the `tx.sender` address.

The code of an approving `VERIFY` frame that is preceded by a `pre_verify` frame MUST check the **status** of that `pre_verify` frame before it calls `APPROVE`, using the frame status parameter of `FRAMEPARAM`, and MUST NOT call `APPROVE` if that status is not success.

According to EIP-8141, a failed `DEFAULT` mode frame does not invalidate the transaction even if it is reverted in the validation prefix, so without this check the approving frame would approve after the **state writes it depends on had been reverted**. Although mempool nodes reject at admission a transaction whose `pre_verify` frame does not succeed in simulation, smart contracts cannot rely on mempool rules for their security.

### Staking Registry Contract

Stake is kept in a specialized designated contract at `STAKING_REGISTRY_ADDRESS`.

It implements the following interface:

```solidity
interface IStakingRegistry {
    /// Lock `msg.value` as the caller's stake, with the given unstake delay.
    function addStake(uint32 unstakeDelaySec) external payable;

    /// Begin the withdrawal delay. From this point the caller is not considered to be staked.
    function unlockStake() external;

    /// Withdraw the stake after the delay has passed.
    function withdrawStake(address payable withdrawAddress) external;

    /// Return the stake information.
    function getDepositInfo(address account)
        external
        view
        returns (uint256 stake, uint32 unstakeDelaySec, uint64 withdrawTime);
}
```

### Associated Storage Rules (ASSOC)

Several rules below grant an entity broader access to storage that is *associated* with it, rather than only to a contract's own account storage. Associated storage identifies the slots a well-behaved contract is expected to use to track state for a specific address, such as an ERC-20 balance mapping keyed by that address, without requiring the contract to declare in advance which slots those are.

* **[ASSOC-010]** A storage slot of any contract is associated with address `A` if the slot's own value equals `A`.
* **[ASSOC-020]** A storage slot of any contract is associated with address `A` if the slot was computed as `keccak256(A || x) + n`, where `x` is a `bytes32` value and `n` is an integer in the range 0 to 128. This covers the common Solidity mapping and dynamic array layouts keyed or indexed by `A`, together with a fixed run of slots reachable from them.

A node determines storage association by testing the slots a validation frame has actually accessed using specialized simulation and tracing interfaces.

### Validation Prefix and Structure (PREFIX)

* **[PREFIX-010]** The validation prefix MUST match one of the following shapes. A transaction whose prefix does not match any of them MUST be rejected.
    * `[self_verify]`
    * `[deploy, self_verify]`
    * `[only_verify, pay]`
    * `[deploy, only_verify, pay]`

  In every shape, each approving frame (`self_verify`, `only_verify` or `pay`) MAY be immediately preceded by one `pre_verify` frame, as [PREFIX-110] describes. An optional single `expiry_verify` frame is always allowed as the first frame of the validation prefix.
* **[PREFIX-020]** If a `deploy` frame is present it MUST be the first frame of the prefix, not counting a leading `expiry_verify` frame. There is at most one `deploy` frame. The `deploy` frame MUST result in a successful deployment of the `tx.sender` contract.
* **[PREFIX-040]** No frame in the validation prefix may carry `ATOMIC_BATCH_FLAG`.
* **[PREFIX-050]** No `VERIFY` frame may follow the validation prefix.
* **[PREFIX-060]** A transaction MUST be rejected if any validation frame reverts, or a `VERIFY` frame exits without its required `APPROVE`.
* **[PREFIX-080]** A node MUST reject or drop a transaction whose `expiry_verify` deadline is earlier than the node's view of the current block timestamp.
* **[PREFIX-100]** The following types of frames are exempt from alt-mempool rules: frame whose target is a default code account, a canonical paymaster, or the `EXPIRY_VERIFIER` contract. A node MAY evaluate them directly instead of simulating them. It MUST still apply the same **limits** it would apply normally.
* **[PREFIX-110]** The target of a `pre_verify` frame MUST have deployed code.
* **[PREFIX-110]** The `DEFAULT` mode frame in the validation prefix that is neither the `deploy` frame nor a `pre_verify` frame MUST cause the transaction to be rejected. 

### Budgets (BUDGET)

* **[BUDGET-010]** A node MUST track the sum of `limits.execution` **separately per entity**, over that entity's own validation frames. The `pre_verify` frame counts toward the entity of the approving frame it immediately precedes. The intrinsic cost of validating `tx.signatures` counts toward the `tx.sender`.
    For **unstaked entities**, that sum MUST NOT exceed `MAX_VERIFY_GAS_PER_ENTITY`.
    For **staked entities**, that sum MUST NOT exceed `MAX_VERIFY_GAS_STAKED_ENTITY`.

### Signatures (SIGNATURE)

* **[SIGNATURE-010]** Before simulating any frame, a node MUST validate every protocol-validated signature (`SECP256K1`, `P256`) against its own signed message: the transaction's signature hash when `msg` is empty, or the explicit digest `msg` carries otherwise. A transaction with any invalid signature MUST be rejected.

### Opcode Rules (OPCODES)

Every validation frame is bound by the banned opcodes of EIP-8141's [Validation Trace Rules](./eip-8141.md#banned-opcodes), except for the frames [PREFIX-100] exempts. This section lists only the differences.

* **[OPCODES-010]** `BALANCE` (`0x31`) and `SELFBALANCE` (`0x47`) are allowed for a staked entity. They remain banned for every other entity.
* **[OPCODES-020]** `SSTORE` is not banned outright. The [Storage and State Access](#storage-and-state-access-storage) rules decide which frames may write and where.
* **[OPCODES-030]** Any unassigned opcode is blocked.
* **[OPCODES-040]** A revert on "out of gas" is forbidden, because it can leak the gas limit or the call-stack depth.

### Contract Creation (CREATION)

* **[CREATION-010]** `CREATE`, `CREATE2` and `SETDELEGATE` are allowed only inside the `deploy` frame, and only to install code at `tx.sender`. Any one of these opcodes may be executed at most once, and it MUST install code for `tx.sender`.

### Calls and Code Access (CALLING)

* **[CALLING-010]** Using an address that has no deployed or default code is forbidden. 
* **[CALLING-040]** Precompiles that access nothing in the blockchain state or environment are allowed. These include the core precompiles `0x01` to `0x11` and the `P256VERIFY` precompile.

### Storage and State Access (STORAGE)

Storage access by `SLOAD`, `SSTORE`, `TLOAD` and `TSTORE` is restricted as follows. Note that storage writes are possible only in `deploy` and `pre_verify` frames. Transient storage ([EIP-1153](./eip-1153.md)) accessed with `TLOAD` and `TSTORE` is treated exactly like persistent storage accessed with `SLOAD` and `SSTORE`.

* **[STORAGE-000]** Access to storage is always restricted unless allowed by one of the following rules.
* **[STORAGE-010]** Access to `tx.sender`'s own storage is always allowed.
* Access to storage associated with `tx.sender` in an external contract that is not an entity of the transaction is allowed if either:
    * **[STORAGE-021]** the sender's account already exists, meaning the transaction has no `deploy` frame; or
    * **[STORAGE-022]** the transaction has a `deploy` frame and the factory is a staked entity.
* If an entity is staked it is additionally allowed:
    * **[STORAGE-031]** access to its own storage;
    * **[STORAGE-032]** read-only access to any storage in a contract that is not an entity of the transaction.
    * **[STORAGE-033]** write access to slots associated with the entity address in any contract that is not an entity of the transaction;

### Local Rules (LOCAL)

These rules depend on the other transactions in a node's own mempool and have no network propagation effects. A node applies them when it admits a transaction. A transaction that violates one is rejected without any reputation change for the peer that sent it.

* **[LOCAL-010]** A transaction MUST NOT use as its factory or its sponsoring payer an address that is `tx.sender` of another pending transaction in the mempool. A factory or paymaster contract can therefore not also serve as an account.
* **[LOCAL-020]** A transaction MUST NOT use storage associated with its sender, or with a staked entity, in a contract that is `tx.sender` of another pending transaction in the mempool.

### Stake (STAKING)

Note that there are no penalization mechanisms in the alternative mempools protocol and the stake is never slashed. It exists only as a configurable mechanism for sybil attack prevention. The significant lock-up period introduces capital cost of creating new abusive entities.

* **[STAKING-010]** An entity is staked if the Staking Registry reports for it a stake of at least `MIN_STAKE_VALUE` and an unstake delay of at least `MIN_UNSTAKE_DELAY`, and withdrawal has not been initiated.

### Payer Solvency (SOLVENCY)

* **[SOLVENCY-010]** For every payer, including the sender when it pays for itself, a node MUST track `reserved_pending_cost(payer)`, the sum of the maximum costs of every pending transaction in its mempool that names this payer. A node MUST reject a transaction if `available_balance(payer)` is less than its maximum cost, where `available_balance(payer) = balance(payer) - reserved_pending_cost(payer)`.
* **[SOLVENCY-020]** For a canonical paymaster, `available_balance` additionally subtracts `pending_withdrawal_amount(paymaster)`, the amount of any delayed withdrawal currently pending in that paymaster.
* **[SOLVENCY-030]** On admission a node increases `reserved_pending_cost` by the transaction's maximum cost. It decreases it on eviction, replacement, inclusion and removal by reorg. When a replacement changes the payer, the node moves the reservation to the new payer atomically with the replacement.

### Reputation (REPUTATION)

#### Definitions

1. **`seen`**: a per-entity counter of how many times this node received a unique valid transaction that references the entity. It counts transactions received over RPC and over the mempool network. Admitting a replacement for an existing pending transaction is not a new occurrence for this purpose; [REPUTATION-040] governs it instead.
2. **`included`**: a per-entity counter of how many transactions that were previously counted in `seen` for that entity were included in a canonical block. A node determines this from the block's transactions and receipts.
3. **Refresh rate**: every hour, both counters are updated as `value = value * 23 // 24`. The effect is a practical reputation reset after four days of entity inactivity.
4. **`inclusionRate`**: the ratio of `included` to `seen`.

An `OK` staked entity faces no additional limit under the reputation rules. There is no cap on its pending transactions, or on its transactions in a block a node builds. An entity whose transactions are frequently not included loses its reputation, until declines below a certain threshold and gets additional limitations.

#### Calculation

Let `max_seen = seen // MIN_INCLUSION_RATE_DENOMINATOR`. The following conditions partition every entity into exactly one reputation state:

* **BANNED**: `max_seen > included + BAN_SLACK`
* **THROTTLED**: `included + THROTTLING_SLACK < max_seen <= included + BAN_SLACK`
* **OK**: `max_seen <= included + THROTTLING_SLACK`

A new entity starts as `OK`. Reputation is tracked per entity address, not per role. The refresh rate limits an entity's organic climb toward `BANNED`, allowing a relatively small number of invalid transactions per hour without any penalties.

#### General rules

The following rules apply to all staked entities and to unstaked sponsoring payers.

* **[REPUTATION-010]** A `BANNED` address is not allowed into the mempool. Every pending transaction that references it is removed.
* **[REPUTATION-020]** A `THROTTLED` address is limited to `THROTTLED_ENTITY_MEMPOOL_COUNT` entries in the mempool, to `THROTTLED_ENTITY_BLOCK_COUNT` transactions in a block the node builds, and to `THROTTLED_ENTITY_LIVE_BLOCKS` blocks of residency in the mempool.
* **[REPUTATION-040]** Admitting a replacement is not a new occurrence of `seen` for any unchanged entity. If the replacement changes the `payer` or `factory` address in use, the node decrements the old entity's `seen` by 1 and increments the new payer's `seen` by 1, atomically with the replacement.

#### Unstaked entities

* **[REPUTATION-210]** A `THROTTLED` sender is limited to `THROTTLED_ENTITY_MEMPOOL_COUNT` pending transactions in total, regardless of how many nonce keys it uses.
* **[REPUTATION-220]** An unstaked sponsoring payer that is neither `THROTTLED` nor `BANNED` may have at most `opsAllowed` pending transactions in the mempool, where `opsAllowed = SAME_UNSTAKED_ENTITY_MEMPOOL_COUNT + inclusionRate * min(included, MAX_TXS_ALLOWED_UNSTAKED_ENTITY)`. For a new entity this is `SAME_UNSTAKED_ENTITY_MEMPOOL_COUNT`.

#### Blame attribution

The alternative mempool system tracks which entity was the one responsible for a transaction that has been previously admitted to the mempool to become invalid. This is done by detecting the exact `VERIFY` frame in the validation prefix that changes its behaviour and no longer executes the expected `APPROVE` opcode call.

* **[REPUTATION-310]** If a transaction fails revalidation because of the `factory` or the `sender` entities, the sponsoring `payer`'s `seen` is decremented by 1. A `payer` must not lose reputation because of another entity's failure.
* **[REPUTATION-320]** If a staked `factory` is used and the `sender`'s validation frame fails, the failure is attributed to the `factory`, and the `factory`'s reputation is updated accordingly.
* **[REPUTATION-330]** If a staked `sender` is used, its reputation is affected by failures of **all other entities** of the transaction, even if those entities are staked.

### Replacement, Eviction and Revalidation (LIFECYCLE)

* **[LIFECYCLE-010]** A pending transaction is identified by `(sender, nonce)`, where `nonce` is EIP-8250's `(key, sequence)` pair. Two transactions with the same `(sender, key, sequence)` are alternatives, at most one of which can ever be included. Within one `(sender, key)` lane, a node MAY admit a transaction only if its `sequence` is the lane's next **contiguous** `sequence` value. This may be either an observed on-chain account state, or the node already holding the contiguous set of pending transactions for that lane. Forming a nonce gap in the mempool is not allowed. A node MUST keep at most `SAME_NONCE_KEY_MEMPOOL_COUNT` pending transactions per `(sender, key)` lane, and at most `SAME_SENDER_MEMPOOL_COUNT` pending transactions per sender, summed across all of its lanes.
* **[LIFECYCLE-020]** A replacement MUST be valid under every rule in this document. A node SHOULD accept and propagate it only if it increases both `max_fee_per_gas` and `max_priority_fee_per_gas` by at least 10%. A replacement MAY name a different factory or payer contracts.
* **[LIFECYCLE-040]** When a new block is accepted, a node MUST remove the transactions the block includes and update payer reservations. It MUST revalidate every pending transaction that **depends on state the block changed**.

  This includes at least:
    * transactions for the same sender
    * transactions whose **recorded storage dependencies** changed
    * transactions whose payer's balance or code changed
    * transactions that reference an entity whose stake status changed

  A transaction that no longer satisfies the rules MUST be evicted.
  To optimize the revalidation flow, a node should record, for each admitted transaction, the set of state it depended on: the storage slots read, the code, balance and nonce of every address whose value the validation used. It should use this set to select the transactions that requirerevalidation, without the need to re-validate the others.

### Propagation (PROPAGATION)

The wire protocol is out of scope for this document. The following rules apply to any transport that carries transactions between nodes of the standard mempool.

* **[PROPAGATION-010]** A transaction is broadcast with two items: the transaction itself, and the block hash against which it was last validated.
* **[PROPAGATION-020]** A node that receives a transaction from a peer MUST validate it locally before it propagates it.
* **[PROPAGATION-030]** If a received transaction fails a static check, such as an invalid encoding, a value below a minimum, or an outdated block hash, the node drops it and keeps the connection.
* **[PROPAGATION-040]** A node silently drops a transaction whose `(sender, nonce)` was recently included in a block. This is almost certainly a network race. It causes no reputation change.
* **[PROPAGATION-050]** If a received transaction fails against the current block, the node should retry validation against the block named in the transaction's message. If it succeeds, the node silently drops the transaction and keeps the connection. If it fails this is an indicator of a peer propagating a known invalid or incompatible transaction payload. The node should mark the sending peer as a **spammer**, disconnect from it, or block it permanently.

### Acceptance Algorithm

A node applies the rules in this order:

1. Validate the signatures.
2. Determine the validation prefix and check its structure.
3. Resolve each entity's role, address and stake ([STAKING-010]) and check reputation.
4. Simulate the prefix and trace it, applying [OPCODES], [CREATION], [CALLING] and [STORAGE] rules to every validation frame.
5. Check payer solvency and reserve the cost.
6. Check the local rules, the per-sender limitations
7. If the transaction is a replacement, apply the replacement rules.
7. If every check passes, record the dependency set, admit the transaction and propagate it.

## Rationale

### Relationship to the public mempool

EIP-8141's public mempool is deliberately narrow, which is the correct choice for a protocol consensus affecting rules in a decentralized network. However, such a narrow ruleset cannot host a wide range of useful applications of the core Frame Transaction architecture: a shielded pools with Merkle roots as paymasters, registries of authorised signers, or an ERC-20 token paymaster with budgeting code and its own storage. Stake and reputation give a node what the public mempool lacks by design: an economic cost for creating an abusive entity, and a mechanism that throttles an entity once it causes invalidations.

Because the standard mempool extends the public mempool rather than replacing it, the two stay consistent. A wallet author who targets the public mempool needs no knowledge of this document.

### Rationale for per-entity verification gas budgets

A single combined gas budget for the whole validation prefix, as EIP-8141 uses, cannot be raised for a staked entity without also raising it for every unstaked entity in the same transaction, since the rule only sees one sum. The alternative mempool tracks the sum separately per entity instead, so a staked payer, sender or factory can be given `MAX_VERIFY_GAS_STAKED_ENTITY`, a materially higher allowance for more expensive validation logic such as signature aggregation or a Merkle proof check, while every unstaked entity of the transaction remains bound by `MAX_VERIFY_GAS_PER_ENTITY`, exactly as it would be in a transaction with no staked entity at all.

### No cap on state gas

EIP-8141 caps `limits.state` at `MAX_VERIFY_STATE_GAS` across the validation prefix. This document places no cap on state gas. A payer's solvency check already reserves the cost of every frame's declared `limits.state`, so a large budget is paid for, and the prefix structure already limits where state can be written. A `deploy` frame that needs a large state gas budget for a code deposit can declare it without hitting a mempool-specific limit.

### State modifying `pre_verify` frames

ERC-4337 validation functions may write storage, under the same associated-storage and stake rules that govern reads. One common use is a paymaster that pulls ERC-20 tokens from the sender during validation, so that it is reimbursed before it commits to pay. `VERIFY` frames are static, so the same guarantee needs a non-static frame that runs first.

The `pre_verify` subclass marks such a frame, binds it to one approving frame so that each write is attributed to an entity, and allows only one per approving frame. Attribution lets the storage and reputation rules apply to writes exactly as they apply to reads.

### Mitigating the mass invalidation attack

The **mass invalidation attack** can be carried out in any of the three ways listed in its definition. To prevent them, validation code runs in a sandbox. It is isolated from other transactions, from external storage changes, and from environment information such as the block timestamp.

A transaction that fails admission validation and never enters the mempool is not an attack. Nodes are expected to apply ordinary measures against spam, such as throttling by API key, IP address, or peer score. An attack is also not considered economically viable if invalidating `N` transactions costs the attacker `N * X` for a sufficiently large `X`.

## Backwards Compatibility

The rules in this document preserve the ERC-4337 use cases that ERC-7562 made possible, even though neither the `EntryPoint` contract nor a `UserOperation` structures or `handleOps` bundles exist. Each of those use cases depended on a specific relaxation of the mempool's validation rules, and this document keeps the equivalency of restrictions and relaxations with ERC-7562.

A contract written against ERC-7562's rules therefore needs no change in its core validation architecture to adopt Frame Transactions.
The differences are concentrated in the exposed interfaces, where for example `validateUserOp` and `validatePaymasterUserOp` calls are replaced by `self_verify`/`only_verify` and `pay` frames respectively, and `initCode` execution is replaced by the `deploy` frame.

This document introduces no consensus change and requires no change to EIP-8141 or the FOCIL rules of EIP-7805 and similar. It does not modify ERC-4337 or ERC-7562.

## Security Considerations

**Staking Registry.** The stake provisions depend on a registry contract outside the EIP-8141 protocol. Correctness of the deployed Staking Registry contract is critical for the security of the entire alternative mempool system.

**Staked entities can misbehave temporarily.** A staked entity can cause a bounded amount of invalidation before its reputation drops. The bound is `BAN_SLACK * MIN_INCLUSION_RATE_DENOMINATOR / 24` invalid transactions per hour, plus whatever throttling then allows. It is a rate limit, not a guarantee.

**`pre_verify` frames run before approval.** A `pre_verify` frame is called by `ENTRY_POINT`, before any `APPROVE` has happened, so nobody has been authorised yet. The target of a `pre_verify` frame SHOULD check that the transaction's sender, as reported by `TXPARAM`, is the party whose state it is about to change.

**A failed `DEFAULT` frame in the validation prefix does not invalidate the transaction automatically.** Only `VERIFY` failures do, so a `pre_verify` frame that reverts on-chain lets the transaction continue. The approving frame MUST check the `pre_verify` frame's status. A node cannot check the requirement, so a payer that ignores it bears the loss.

**Approval covers all following `SENDER` frames.** `sender_approved` is a single transaction-scoped flag. Once it is set, every `SENDER` frame in the transaction executes as `tx.sender`, not only the frame the approving code inspected. Wallet code that approves execution SHOULD bind its approval to the whole frame list, for example by verifying a signature over the canonical signature hash, which commits to every frame. A signature over an explicit digest that does not commit to the frame list authorises an open-ended set of `SENDER` frames.

**`ARBITRARY` signatures.** The protocol does not validate them, so a transaction that carries one is only as trustworthy as the frame that inspects it.

**Canonical paymaster.** A canonical paymaster is exempt from the trace rules and admitted by code match. This puts a lot of responsibility on the canonicalized code's correctness.

**Default-code payers.** A payer with no code is bounded only by the solvency rules. A sponsor that moves its balance elsewhere between admission and inclusion invalidates every pending transaction it sponsors, up to the balance it appeared to hold. Reservation limits the exposure to the payer's balance at admission time and does not remove it.

**Revalidation load.** A new head can force many revalidations. The lifecycle rules allow a node select only the affected transactions. A node that ignores the filtering of affected transactions would expose itself to a load attack proportional to the size of its mempool.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
