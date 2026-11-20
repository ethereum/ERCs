---
eip: TBD
title: Evaluated Work Records
description: A profile of the ERC-8004 Reputation Registry for escrowed agent work, rebuilt from the escrow's own logs through verdict and payout
author: Kuro Sato (@kurokawasato)
discussions-to: https://ethereum-magicians.org/t/draft-erc-evaluated-work-records/30447
status: Draft
type: Standards Track
category: ERC
created: 2026-11-16
requires: 20, 55, 8004, 8217
---

## Abstract

This proposal is a profile of the [ERC-8004](./eip-8004.md) Reputation Registry for paid work that an escrow settled on
an evaluator's verdict. It adds no core contract. For each settled task, a writer posts one `giveFeedback` entry tagged
`work.outcome` about the agent that did the work: 100 when the work was accepted and paid, 0 when it was rejected, or
when the worker took the task on chain and never delivered.

The entry carries its evidence, the record, as a `data:` URI. The record names every log the escrow emitted for the
task, from funding through delivery, each verdict and each challenge (a dispute or an appeal), to the payment or the
refund. A reader that holds the escrow's descriptor and an RPC endpoint can rebuild the record, derive the outcome, and
check that the escrow paid the worker who delivered, in full, and only after a final verdict that accepted the work.

Any escrow that logs these steps, with the task id as each event's first indexed parameter, is a source as deployed,
such as [ERC-8183](./eip-8183.md) job contracts.

## Motivation

An ERC-8004 feedback entry can name a task. Nothing ties its value to work that was paid for, to the party that judged
the work, or to what happened when someone contested the judgment. An opinion costs nothing to post.

Work settled through an escrow leaves harder evidence. A client locked funds, a worker delivered, an evaluator decided,
and the escrow paid or refunded. Each step is a log. ERC-8183 standardizes one such escrow with a single evaluator and
recommends turning job outcomes into ERC-8004 signals, but leaves the mapping to each implementation. Other escrows add
disputes and appeals, so the first verdict is not always the one that settles the task. Each escrow reports outcomes in
its own way, if at all, and a record earned at one marketplace is invisible at the next.

The readers are agents choosing whom to hire, lenders sizing credit on work an agent was paid for, bond contracts that
release on accepted delivery, and marketplaces ranking workers. They need the same few facts from every escrow: whether
the work was accepted, after which challenges, and whether the money followed the verdict.

Goals:

1. **No new core contract.** It works with the deployed ERC-8004 registries and with escrows as they are deployed.
2. **Checkable.** Every step in a record is a log, and every amount a transfer, that a reader holding the source's
   descriptor can fetch and check.
3. **Payment follows acceptance.** A record of accepted work shows delivery, then a final verdict that accepted it, then
   the full payment to the worker who delivered.
4. **Contested outcomes are explicit.** Every verdict and challenge is in the record, and the last verdict decides.
5. **No zero without a worker act.** A task the evaluator never decided, or one the worker never touched on chain,
   does not count against the worker.
6. **Readable on chain.** The registry stores the value and tags, so a contract can read an agent's acceptance rate over
   the writers it trusts.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This profile uses the Reputation Registry's `giveFeedback`, `readFeedback`, `getSummary`, `getLastIndex` and
`NewFeedback`, and the Identity Registry's `ownerOf`, `getAgentWallet`, `getMetadata` and `setMetadata`, as ERC-8004
defines them.

### Terms

- **Source:** a contract that holds a client's payment for a task and releases it to the worker or returns it to the
  client. A source is identified by (`chainId`, `contract`).
- **Descriptor:** the JSON object that says which of a source's events are which steps (see Sources).
- **Task:** one unit of paid work at a source, with an id unique within that source.
- **Worker:** the party the source names for the task, as an address or a `bytes32` id; [Outcomes](#outcomes) says
  which one a task has.
- **Verdict:** a decision on whether delivered work is accepted. An evaluation is a verdict, and so is a ruling on a
  dispute or an appeal.
- **Challenge:** an act that asks for a new verdict on the latest one, such as a dispute or an appeal. Until a later
  verdict arrives, the challenged verdict stands.
- **Writer:** the address that posts entries (the entry's `clientAddress`).
- **Record:** the JSON document an entry carries, describing one settled task (see [Record](#record)).
- **Record bytes:** the record's canonical encoding, the bytes `feedbackHash` commits to.
- **Head fields:** every field of a record except `work`.
- **Source time:** the timestamps of the source chain's blocks.
- **Finalized head:** the source chain's latest final block, read as the descriptor's `finality` says.
- **Takes an entry:** said of a settled, consistent task whose outcome is `accepted`, `rejected` or `undelivered`.
- **Due:** a settled task whose terminal block is final is due once the later of the finalized head's timestamp and the
  timestamp of the registries' chain's latest block is at least 72 hours past the timestamp of the terminal block. The
  registries' chain keeps the clock running when the source chain produces no blocks.

### Steps

A source's logs map to seven kinds of step. `paid` and `refunded` are terminal.

| step | meaning | required fields | optional fields |
| --- | --- | --- | --- |
| `funded` | the client's payment is held for the task | `task`, `client`, `amount` | `brief` |
| `assigned` | a worker is hired, or takes the task | `task`, `worker` | |
| `delivered` | the worker submits the work | `task`, `worker` | `result` |
| `verdict` | the work is accepted or not | `task`, `accepted` | `ref`, `evaluator` |
| `challenge` | a party reopens the latest verdict | `task` | `by`, `bond` |
| `paid` | the source releases the payment | `task`, `to`, `amount` | `worker`, `fee` |
| `refunded` | the source returns the payment | `task`, `to`, `amount` | |

| field | type | meaning |
| --- | --- | --- |
| `task` | `uint256` | the task id |
| `client`, `to`, `by`, `evaluator` | `address` | the account named |
| `worker` | `address` or `bytes32` | the worker. An address is compared in its 32-byte left-padded form |
| `amount`, `fee`, `bond` | `uint8` to `uint256` | base units of the source's asset |
| `brief`, `result`, `ref` | `bytes32`, or `uint8` to `uint256` | commitments to the task's terms, to the work, and to the verdict's evidence |
| `accepted` | `bool`, or a literal | whether the verdict accepts the work |

### Sources

A descriptor for an ERC-8183 contract with the events of that proposal's reference implementation:

```json
{
  "chainId": 8453,
  "contract": "0x…",
  "asset": "eip155:8453/erc20:0x…",
  "fromBlock": 0,
  "finality": "finalized",
  "events": [
    { "step": "assigned", "event": "JobCreated(uint256 indexed jobId, address indexed client, address indexed provider, address evaluator, uint256 expiredAt, address hook)",
      "fields": { "task": "jobId", "worker": "provider" } },
    { "step": "assigned", "event": "ProviderSet(uint256 indexed jobId, address indexed provider)",
      "fields": { "task": "jobId", "worker": "provider" } },
    { "step": "funded", "event": "JobFunded(uint256 indexed jobId, address indexed client, uint256 amount)",
      "fields": { "task": "jobId", "client": "client", "amount": "amount" } },
    { "step": "delivered", "event": "JobSubmitted(uint256 indexed jobId, address indexed provider, bytes32 deliverable)",
      "fields": { "task": "jobId", "worker": "provider", "result": "deliverable" }, "actor": "worker" },
    { "step": "verdict", "event": "JobCompleted(uint256 indexed jobId, address indexed evaluator, bytes32 reason)",
      "fields": { "task": "jobId", "accepted": true, "ref": "reason", "evaluator": "evaluator" } },
    { "step": "verdict", "event": "JobRejected(uint256 indexed jobId, address indexed rejector, bytes32 reason)",
      "fields": { "task": "jobId", "accepted": false, "ref": "reason", "evaluator": "rejector" } },
    { "step": "paid", "event": "PaymentReleased(uint256 indexed jobId, address indexed provider, uint256 amount)",
      "fields": { "task": "jobId", "worker": "provider", "to": "provider", "amount": "amount" } },
    { "step": "refunded", "event": "Refunded(uint256 indexed jobId, address indexed client, uint256 amount)",
      "fields": { "task": "jobId", "to": "client", "amount": "amount" } }
  ]
}
```

`PaymentReleased` reports the amount after fees and no event reports the platform fee, so a job of such a contract that
charged a fee does not meet the amount rule in [Outcomes](#outcomes) and gets no entry.

A descriptor:

- MUST have exactly the fields `chainId`, `contract`, `asset`, `fromBlock`, `finality` and `events`;
- MUST give `contract` as an [ERC-55](./eip-55.md) checksummed address;
- MUST give `asset`, the [ERC-20](./eip-20.md) token the source holds, as the CAIP-19 id
  `eip155:<chainId>/erc20:<address>`, with the source's `chainId` and an ERC-55 checksummed address;
- MUST give `fromBlock`, the block the source was deployed in;
- MUST give `finality`: the string `"finalized"` when the source chain's nodes answer the `finalized` block tag, or a
  positive integer N, a confirmation depth, for a chain without it. With N, the finalized head is the block N below the
  latest block;
- MUST list in `events` every event the source emits for any of the seven steps, and at least one event each for
  `funded`, `delivered`, `verdict`, `paid` and `refunded`.

Each item of `events` has `step`, `event` and `fields`, and MAY have `actor` and `feeIncluded`:

- `event` MUST be `Name(type [indexed] name, ...)`: parameters separated by a comma and one space, each a canonical
  ABI type name (`uint256`; the alias `uint` does not qualify), the word `indexed` when the parameter is indexed, and a parameter name. Types
  are elementary types or their dynamic arrays (`T[]`); static arrays (`T[k]`) and tuples MUST NOT appear. An event MUST
  have at most three indexed parameters and MUST NOT be anonymous. An enum parameter is written `uint8`.
- The event's topic, `keccak256` of the signature without parameter names and without `indexed`, MUST appear at most
  once in `events`, so each log is exactly one step.
- `fields` MUST map each required field of the step, and MAY map its optional fields, to a parameter of the event whose
  type the field table allows. `task` MUST name the event's first indexed parameter, which MUST be a `uint256`.
  `accepted` MAY instead be the JSON literal `true` or `false`, for an event that is itself the verdict.
- `actor`, when present, MUST be `"worker"`. It marks an event whose transaction the worker sends.
- `feeIncluded`, when present, MUST be a boolean on a `paid` event that maps `fee`. It is `true` when `amount` includes
  `fee`. The worker receives `amount` minus `fee` when it is `true`, and `amount` otherwise.

A reader MUST hold the descriptor of each source it reads, keyed by (`chainId`, `contract`), from a party it trusts: its
own copy, or one the source's deployer publishes. Two descriptors are the same when their canonical encodings, as in
[Record](#record), are the same bytes. A reader MUST reject a record whose descriptor differs from the one it holds.

A new source SHOULD emit events of at least these shapes:

```solidity
event TaskFunded(uint256 indexed task, address indexed client, uint256 amount, bytes32 brief);
event WorkerAssigned(uint256 indexed task, bytes32 indexed worker);
event WorkDelivered(uint256 indexed task, bytes32 indexed worker, bytes32 result);
event Verdict(uint256 indexed task, address indexed evaluator, bool accepted, bytes32 ref);
event Challenged(uint256 indexed task, address indexed by, uint256 bond);
event TaskPaid(uint256 indexed task, bytes32 indexed worker, address indexed to, uint256 amount, uint256 fee);
event TaskRefunded(uint256 indexed task, address indexed to, uint256 amount);
```

### Outcomes

The steps of a task are the logs the source emitted from the descriptor's `fromBlock` onward, of declared events whose
`task` parameter equals the task id. They are ordered by block number and log index, and run to the end of the
transaction that holds the first terminal step. A step from an event marked `actor: "worker"` also has a sender: the
`from` of its transaction.

The worker of a task is the worker of its first `delivered` step or, without one, of its latest `assigned` step that
names a non-zero worker. A worker act is a step, other than `delivered`, whose sender, left-padded to 32 bytes, equals
the worker.

A task's outcome is the first of these that applies:

1. No terminal step: `unsettled`.
2. No `delivered` step and no `assigned` step that names a non-zero worker: `no worker`.
3. No `delivered` step: `undelivered` when the task has a worker act, `unstarted` otherwise.
4. No `verdict` step after the last `delivered` step: `unevaluated`.
5. The last `verdict` step after the last `delivered` step accepts: `accepted`. Otherwise: `rejected`. A challenge with
   no later verdict leaves the challenged verdict standing.

A task is consistent when all of these hold:

- it has exactly one `funded` step, before any `delivered` step;
- the transaction that holds the first terminal step holds no other terminal step;
- an `accepted` task's terminal step is `paid`, and the terminal step of every other outcome is `refunded`;
- the terminal step settles the funded amount: for `paid`, `amount` when the event's `feeIncluded` is `true`, and
  `amount` plus `fee` (zero when not mapped) otherwise; for `refunded`, `amount`;
- every `delivered` step, and the `paid` step where it maps `worker`, names the task's worker;
- every `challenge` step comes after a `verdict` step;
- every log the source emitted whose topic 0 is a declared event's and whose topic 1 is the task id decodes under that
  event: it has one topic more than the event's indexed parameters, and each word fits its parameter's type. Events that
  differ only in which parameters are indexed share topic 0, so a log of the other shape makes the task inconsistent;
- the source emitted no declared log for the task after the transaction that holds its terminal step and at or before
  the time of the entry's block. A log later than the entry is not held against it.

### Entries

A writer MUST post each entry with `giveFeedback(agentId, value, valueDecimals, tag1, tag2, endpoint, feedbackURI,
feedbackHash)` and these values:

| outcome | `tag1` | `tag2` | `value` |
| --- | --- | --- | --- |
| `accepted` | `work.outcome` | `accepted` | 100 |
| `rejected` | `work.outcome` | `rejected` | 0 |
| `undelivered` | `work.outcome` | `undelivered` | 0 |

- `valueDecimals` MUST be 0.
- `endpoint` MAY be empty, or name a page about the task. It is not evidence.
- When the record bytes are at most 8,192 bytes, `feedbackURI` MUST be exactly `data:application/json;base64,`
  followed by their base64 (RFC 4648 standard alphabet, padded, no other character). Longer record bytes MAY be served
  at an `https://` or `ipfs://` URI instead. Either way, `feedbackHash` MUST be `keccak256` of the record bytes.
- A writer MUST NOT post an entry for a task that does not take one.
- The record's `createdAt` MUST NOT precede the timestamp of the block that holds the task's terminal step, and MUST
  NOT follow the timestamp of the block that holds the entry.

### Record

A record holds ERC-8004's off-chain feedback fields and one object, `work`. The record of BrainChain mainnet task 50,
with its entry on Robinhood Chain (chain id 4663), is
[`example-record.json`](../assets/eip-draft_evaluated_work_records/example-record.json). Abbreviated below; the record
bytes are canonical:

```json
{
  "agentRegistry": "eip155:4663:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432",
  "agentId": 20424,
  "clientAddress": "eip155:4663:0x97D558417c3D61f1074422AD843e1Db1E565b952",
  "createdAt": "2026-11-16T12:00:00Z",
  "value": 100, "valueDecimals": 0,
  "tag1": "work.outcome", "tag2": "accepted",
  "work": {
    "v": "work-record/v1",
    "source": { "…": "the descriptor" },
    "task": "50",
    "worker": "0x5f1c28741ee74be2a828fd337283ca47e477a0cd56bf5ad31c61e1ce3ce1d22f",
    "outcome": "accepted",
    "steps": [
      { "step": "funded", "block": 2451, "tx": "0x749d…d5ef", "log": 2, "client": "0x97D5…b952", "amount": "1000000", "brief": "0x5ba7…a9a9" },
      { "…": "assigned, delivered and verdict" },
      { "step": "paid", "block": 2471, "tx": "0xdca6…8abf", "log": 3, "worker": "0x5f1c…d22f", "to": "0xFB9C…f84D", "amount": "1000000", "fee": "30000" }
    ]
  }
}
```

A record MUST have exactly these fields:

| field | JSON type | encoding | presence |
| --- | --- | --- | --- |
| `agentRegistry` | string | CAIP-10 `eip155:<chainId>:<address>` of the Identity Registry | always |
| `agentId` | number | the agent id, at most 2^53 - 1 | always |
| `clientAddress` | string | CAIP-10 of the writer, on the same chain as `agentRegistry` | always |
| `createdAt` | string | RFC 3339 in UTC to the second, exactly `YYYY-MM-DDThh:mm:ssZ` | always |
| `value` | number | 100 or 0, as [Entries](#entries) gives | always |
| `valueDecimals` | number | 0 | always |
| `tag1` | string | `work.outcome` | always |
| `tag2` | string | the outcome | always |
| `work.v` | string | `work-record/v1` | always |
| `work.source` | object | the source's descriptor | always |
| `work.task` | string | the task id, decimal | always |
| `work.worker` | string | the task's worker, 32 bytes | always |
| `work.outcome` | string | `accepted`, `rejected` or `undelivered` | always |
| `work.steps` | array | every step of the task, in order | always |
| `step` | string | the step's kind | every step |
| `block`, `log` | number | the log's block number and its index in the block | every step |
| `tx` | string | the log's transaction hash, 32 bytes | every step |
| `client`, `to`, `by`, `evaluator` | string | address | when the step's event maps the field |
| `amount`, `fee`, `bond` | string | decimal, base units | when the step's event maps the field |
| `worker`, `brief`, `result`, `ref` | string | the parameter's 32-byte ABI word: a `uintN` or an `address` left-padded with zeros | when the step's event maps the field |
| `accepted` | boolean | | when the step's event maps the field |
| `sender` | string | address, the `from` of the step's transaction | when the step's event is marked `actor: "worker"` |

A step MUST carry every field its event maps, `accepted` included when the descriptor maps it to a literal, and no
other field. ERC-8004's other optional feedback fields, such as `endpoint`, `mcp`, `a2a`, `oasf` and `proofOfPayment`,
MUST NOT appear: the entry itself carries `endpoint`.

- The head fields MUST equal the entry's. `agentId`, `value` and `valueDecimals` are JSON numbers, as ERC-8004's
  off-chain feedback file writes them; an agent id above 2^53 - 1 cannot be written under this profile.

The record bytes MUST meet all of these:

- UTF-8 without a byte order mark, holding JSON in the canonical form of RFC 8785 (JCS): object keys sorted, no
  whitespace;
- JSON numbers are integers from 0 to 2^53 - 1, and decimal strings have no leading zeros;
- every address, alone or inside a CAIP id, is the 20-byte address in ERC-55 checksummed form. A 32-byte value
  (`tx`, `worker`, `brief`, `result`, `ref`) is `0x` followed by 64 lowercase hex digits, and an address worker
  appears only in that 32-byte form.

### Worker binding

A worker's identity at a source often differs from its agent's owner and `agentWallet`. An agent MAY declare its
workers in ERC-8004 on-chain metadata under the key `work.workers`:

```solidity
struct WorkerRef {
    uint256 chainId;
    address source;
    bytes32 worker; // an address worker, left-padded
}
// metadataValue = abi.encode(WorkerRef[])
```

A record's binding, read on the registries' chain at the entry's block, is one of:

- `declared` when the agent's `work.workers` lists the source and the worker;
- `wallet` when an event marked `actor: "worker"` types its `worker` as an `address`, and the worker equals
  `ownerOf(agentId)` or `getAgentWallet(agentId)`;
- `writer` otherwise.

The Identity Registry's `MetadataSet` logs carry each value, so a reader needs no archive state to read `work.workers`
at an entry's block.

A record is **bound** when its binding is `declared` or `wallet`. An entry is **checked** when it passes every reader
check below and its record is bound.

- A writer MUST bind each task to one agent and MUST NOT post the task for any other agent. ERC-8004 already refuses
  entries from the agent's owner and its approved operators.
- Transferring an agent does not change the binding of entries posted before the transfer. Those entries stay in the
  epoch they were posted in (see Epochs). The new owner MAY replace `work.workers`.
- A writer that changes its key SHOULD list its keys, oldest first, as `abi.encode(address[])` under the metadata key
  `work.writers` of an ERC-8004 agent it controls. A reader MAY then treat the listed keys as one writer.

### Epochs

An agent's **epoch** is its controller together with its declared build:

- the **controller** is `ownerOf(agentId)`, or, when the owner is a binding adapter the reader trusts (such as an
  [ERC-8217](./eip-8217.md) adapter), the holder of the token the agent is bound to;
- the **build** is the agent's ERC-8004 on-chain metadata under the key `work.build`, a UTF-8 label its owner sets for
  the code and model the agent runs. An agent that sets none has the empty build.

```solidity
// build is the metadata value as a string
bytes32 epoch = keccak256(abi.encode(block.chainid, identityRegistry, agentId, controller, build));
```

An entry belongs to the epoch in force at its block. The registry's `Transfer` and `MetadataSet` logs, and the
adapter's binding logs, carry every change, so a reader needs no archive state to place an entry.

A reader:

- SHOULD report the epoch of each entry, and the agent's current epoch;
- SHOULD present and weigh only the entries of the current epoch as the agent's record, and MAY show earlier epochs
  apart from it;
- SHOULD NOT carry entries from an earlier epoch into a later one: a sale or a new build starts the record again;
- SHOULD treat an epoch that recurs, an agent returning to the same controller with the same build, as the same epoch.

A writer needs to do nothing for epochs: they are read, not written.

### Writers

A writer:

- MUST post at most one entry per task;
- MUST post only after the terminal step is final; an entry over steps that later disappear fails every reader and
  cannot be withdrawn;
- MUST build the record from final logs only;
- once it has posted an entry for a worker of an agent at a source, MUST post an entry for every later task of that
  worker at that source that takes an entry, before the task is due;
- MUST NOT revoke an entry.

### Readers

A reader:

- MUST check each entry's record bytes: the URI, that `feedbackHash` is `keccak256` of them, the encoding, every field
  of this profile, and that the head fields equal the entry's. Record bytes of 8,192 or fewer fail when they are not
  carried as a `data:` URI;
- MUST read a writer's entries from the registry's `NewFeedback` logs, or from an index whose entries it then reads
  from their transaction receipts, and MUST check that the writer's `feedbackIndex` values for the agent run from 1 to
  `getLastIndex(agentId, writer)` with none missing, reading `getLastIndex` at the same block as the logs;
- MUST treat an entry that `readFeedback` reports as revoked as missing;
- MUST read each source on the chain its descriptor names;
- MUST rebuild the task's steps from the source's logs, from the descriptor's `fromBlock`, and check that they equal the
  record's steps, each `sender` included. A reader MUST NOT start the scan at a block the record supplies;
- MUST derive the outcome, and fail an entry whose outcome, tags or value disagree with the steps, whose task is not
  consistent, or whose `createdAt` precedes the terminal step or follows the entry;
- MUST check the money: in the `funded` transaction, a transfer of the funded `amount` of the asset from `client` to the
  source; in the `paid` transaction, a transfer of what the worker receives from the source to `to`; in the `refunded`
  transaction, a transfer of `amount` from the source to `to`. Each `Transfer` log backs at most one step: the reader
  matches the transfers of every declared step in the transaction, of any task, to distinct logs, and fails the entry
  when any of them is left without one;
- MUST NOT count an entry whose `funded` step's `client` is the agent's owner or `agentWallet` at the entry's block, and
  SHOULD apply its own rule to clients that the worker, the agent's owner or its `agentWallet` funded before the task.
  The `client` is the account the bounty came from;
- MUST report each record's binding, and MUST NOT present an entry that is not bound as checked;
- MUST treat two entries from one writer for one task as a failure of that writer, even when they are about different
  agents;
- MUST read the writer's `work.outcome` entries about every agent, with one log query on the indexed `clientAddress`
  and `tag1` topics, and fail an entry whose task the writer also posted for another agent. A reader of one agent finds
  such entries no other way;
- MUST count each (`chainId`, `contract`, task) at most once when it combines entries of several writers or agents;
- when it rebuilds an agent's history, MUST find the tasks of every worker the writer has used for the agent at each
  source, settled since the writer's first entry for that worker. A due task that takes an entry and has no unrevoked
  entry from the writer is a failure of that writer for that agent;
- MUST choose which writers and which sources it trusts. Anyone can deploy an escrow and write records about tasks it
  paid to itself.

When a reader reports an agent's record, its counts are the numbers of checked entries for each outcome, per writer,
after duplicates are removed.

### Reading on chain

For the writers it trusts, a contract can call `getSummary(agentId, writers, "work.outcome", "")`: the count is the
number of entries and the summary value is the share accepted, in percent, as the registry averages. With `tag2` set to
`accepted`, the count is the number of accepted tasks. A contract cannot check records or bindings, so it relies on
the writers it names.

## Rationale

- **A profile of the existing registry.** Every ERC-8004 deployment and every indexer of `NewFeedback` already sees
  these entries. Work outcomes sit next to the agent's other reputation, and `tag1` is indexed, so one log filter finds
  them.
- **Declared events instead of a new escrow interface.** Escrows already exist with different event names. A new
  interface would leave every deployed escrow out. A descriptor says which logs mean what, so one reader decodes any
  source, and the event shapes above give new escrows a default.
- **Pinned descriptors.** If each record could bring its own descriptor, a writer could leave out the event that would
  change an outcome. The reader holds the descriptor instead, from its own reading of the contract or from the
  deployer, and scans from the deployment block it names. An upgradeable source that changes its events needs a new
  descriptor, which readers adopt deliberately.
- **One entry per task.** Paid tasks are fewer and larger than micropayments, and each one carries evidence a reader
  wants to see on its own: who judged it and whether it was contested. Per-task entries also give contracts an
  acceptance rate through `getSummary`.
- **Verdicts and challenges as one sequence.** One rule, that the last verdict after the last delivery decides, covers a
  single evaluator, a dispute with a ruling, an appeal with a second ruling, further rounds in an outside court, and
  work delivered again after a rejection. The profile names no procedure.
- **No forced zeros.** A source can name a worker who never agreed to the task. A refund then says nothing about that
  worker, so a zero needs an act the worker sent on chain, such as taking the task. A worker whose delivered work was
  never judged did not fail either. ERC-8183 suggests a neutral or negative signal for an expired job depending on
  policy; under this profile an expired ERC-8183 job gets no entry, because its events record no act by the provider
  before delivery.
- **Payment checked against the verdict.** The consistency rules and the transfer checks make an `accepted` entry mean
  that the funded amount moved after the verdict, in full, to the worker and the fee recipient.
- **The Reputation Registry rather than the Validation Registry.** The agent's owner makes a validation request, before
  any outcome, and the response is a score with no tie to payment. An escrow's outcome exists only at settlement, and
  the party that commissions the evaluation is the client. An evaluator can still post its verdict as a validation
  response and expose it through `ref`.
- **`data:` URIs and canonical JSON.** The evidence sits in the entry's calldata, so it cannot change and needs no
  server. One canonical form gives each record one reading. The same `data:` form, canonical JSON, `keccak256` commitment
  and 8,192-byte cap appear in the open drafts numbered 8466 (Agent Credit History) and 8458 (Agent Income Statements).
- **Binding through agent metadata.** A worker's id at an escrow can be a hash, and the escrow can be on another chain
  than the registry. Metadata set by the agent's owner is the agent's own statement of which workers are its own, and
  readers see which records rest on it and which rest on the writer's word.
- **An unanswered challenge.** When a dispute or an appeal gets no ruling before settlement, the challenged verdict
  stands. Sources settle that way: BrainChain's `TaskBoard` pays or refunds on the standing verdict when a ruling window
  lapses, and the consistency rules tie the outcome to that money. Calling the task `unevaluated` would drop a
  settlement the source made on a verdict.
- **One worker and one terminal step per task.** Several workers, milestones and partial payments go to a later version
  of the record.
- **Epochs.** Without them a record is an asset that can be sold: a buyer acquires an agent with a long history and
  works under it. A new model behind the same agent is another worker for the same reason. Keying the record on the
  controller and the declared build ends both, and needs no new contract. A build is only what the owner declares; a
  reader that needs more MAY require the build to name an attested measurement, which this profile does not define.

### Open questions

1. **An on-chain view for sources.** A function such as `workOutcome(uint256 task)` would let a contract check one
   task's outcome without reading a record. Should this profile define it for new sources?
2. **Payers behind the client.** Some escrows are funded by an operator on behalf of an agent that paid it off chain.
   Should a record name that payer when a signed receipt ties the payment to the task?
3. **A build that survives a sale.** An agent whose build is an attested measurement (a TEE's) runs the same code under
   any owner. Should its record carry across a sale when the measurement is unchanged?

## Backwards Compatibility

The profile adds tags, two metadata keys and a record format. It changes nothing in ERC-8004, and readers that do not
know the tags ignore them. Contracts whose events carry the task id as their first indexed parameter, such as ERC-8183
job contracts, are sources as deployed. Entries a writer posted under other tags before adopting this profile are not part of it.

## Test Cases

The reference source runs on BrainChain mainnet (chain id 274663, `0x44b8464342Bbfb9B565FAE494DfDefa37D33A211`). The
same release runs on BrainChain testnet (chain id 274630, `0x7A7cC5D35A642CCc268C7B263fF800bc7eBD52A4`). Each case below
is rebuilt from public logs. The [test vectors](../assets/eip-draft_evaluated_work_records/vectors.json) hold every log
of each task, the record a writer builds from it, and eight cases a reader fails:

| chain | task | steps | outcome | entry |
| --- | --- | --- | --- | --- |
| mainnet | 50 | funded, assigned, delivered, verdict (accepts), paid | `accepted` | `accepted`, 100 |
| mainnet | 51 | funded, assigned, delivered, verdict (rejects), refunded | `rejected` | `rejected`, 0 |
| mainnet | 54 | funded, assigned, refunded | `unstarted` | none |
| mainnet | 9 | funded, assigned, delivered, refunded | `unevaluated` | none |
| mainnet | 10 | funded, refunded | no worker | none |
| testnet | 3 | funded, assigned, delivered, verdict (rejects), challenge, verdict (accepts), paid | `accepted` | `accepted`, 100 |
| testnet | 84 | funded, assigned, delivered, verdict (rejects), challenge, verdict (rejects), challenge, verdict (rejects), refunded | `rejected` | `rejected`, 0 |
| testnet | 1 | funded, assigned, delivered, verdict (accepts), challenge, verdict (accepts), challenge, verdict (accepts), paid | `accepted` | `accepted`, 100 |

In mainnet task 54, BrainChain's `TaskBoard` hired a worker that never delivered. The board sent the hire, so the task
has no worker act and is `unstarted`. In testnet task 3, a ruling on a dispute reversed a rejecting evaluation, and the board paid.
In task 84, a staked worker's work was rejected; the worker disputed, lost the ruling, appealed and lost again, and the
board refunded.

Every task in the vectors was posted, evaluated and recorded by BrainChain itself, and the writer key in the mainnet
vectors, `0x97D558417c3D61f1074422AD843e1Db1E565b952`, is also the client of mainnet task 50. Disputes and appeals have
happened only on BrainChain testnet so far.

The record of BrainChain mainnet task 50 for agent 20424, written by that key with `createdAt`
`2026-11-16T12:00:00Z`, is `example-record.json`; the payout it follows is in block 2471, at `2026-11-15T14:15:28Z`.
Its record bytes are 3,622 bytes long, and their `feedbackHash` is
`0x362bfa0b49ac22cabe8566773da906e0ca8b7cf1b0fe8960df2657e697b1259a`.

A conforming reader fails each of these: the record of task 50 with its `verdict` step removed; the same record
relabeled `rejected`; the same record with a descriptor other than the pinned one; the same record behind a byte order
mark; the task's logs with the payment replaced by a refund; the task's logs with the paid amount short of the funded
amount; a second entry for task 50 from the same writer; and a record of task 50 dated before its payout.

## Reference Implementation

The first source is BrainChain's `TaskBoard`, release 3.5.0, at `0x44b8464342Bbfb9B565FAE494DfDefa37D33A211` on
BrainChain mainnet (chain id 274663). As its deployer, BrainChain publishes its descriptors for
[mainnet](../assets/eip-draft_evaluated_work_records/sources/brainchain-mainnet.json) and
[testnet](../assets/eip-draft_evaluated_work_records/sources/brainchain-testnet.json).

Reference code runs on Node.js 18 or later, with no dependencies, and reads public JSON-RPC endpoints only:

- [`work-records.mjs`](../assets/eip-draft_evaluated_work_records/work-records.mjs): descriptors, steps, outcomes,
  consistency, records and the reader's rules, with no network access;
- [`cli.mjs`](../assets/eip-draft_evaluated_work_records/cli.mjs): the writer (`build`), which prints the record and the
  `giveFeedback` calldata and sends nothing, and the reader (`check` for one record, `entries` for every entry one
  writer posted about one agent, with transfers, binding, revocations and coverage);
- [`example-record.json`](../assets/eip-draft_evaluated_work_records/example-record.json): a complete record;
- [`vectors.json`](../assets/eip-draft_evaluated_work_records/vectors.json) and
  [`test.mjs`](../assets/eip-draft_evaluated_work_records/test.mjs): the test vectors and the offline tests;
- [`README.md`](../assets/eip-draft_evaluated_work_records/README.md): how to run them, including a reader run against
  a fork of Robinhood Chain.

## Security Considerations

- **Self-dealing.** A client and a worker under one control can fund tasks, accept them and pay themselves. Every check
  passes, because it all happened. A record shows the client, the amounts, the fee and, where the source maps it, the
  evaluator. Readers do not count a task the agent's owner or `agentWallet` funded, and SHOULD weigh records by the fees
  paid to parties outside the worker's control, by the number of distinct clients, by whether the worker or the agent's
  owner funded a client before its task, and by whether the evaluator is independent of both client and worker. ERC-8183 allows the client to be the
  evaluator, and a reader sees this only when the descriptor maps `evaluator`.
- **Wrong verdicts.** A record shows what was decided, not that the decision was right. Challenge steps show whether a
  verdict could be contested and whether it was.
- **Forced zeros.** A source names its workers; a worker does not consent to being named. Without the worker-act rule,
  anyone could hire an agent's worker on an escrow of their own, let the task lapse and have a writer post a zero. With
  it, a zero for an undelivered task needs a transaction the worker sent.
- **A lying writer.** False fields fail against the logs, a dropped step fails the rebuild, a descriptor of the writer's
  choosing fails against the one the reader holds, and an entry for an inconsistent task fails the consistency check. A
  writer that stops writing about a worker after a rejection leaves a gap that a rebuilding reader finds. A writer can
  still choose never to write about a worker, and can write about a source it controls; which writers and sources count
  is the reader's decision.
- **A lying source.** Logs show what a contract emitted. The transfer checks tie each step that moves money to its own
  transfer of the asset, so one transfer cannot stand for two tasks settled in one transaction. Before pinning a descriptor, a reader SHOULD match the source's bytecode to published source.
- **Binding.** `declared` is the agent's own statement, `wallet` checks an address the agent controls, and `writer` is
  the writer's word. An agent can declare a worker it does not control; the writer still chooses whom it writes about.
- **Finality and late logs.** Writers post only over final steps, since an entry cannot be withdrawn. Readers judge an
  entry against the logs up to its time, so a source that emits a stray log after the entry cannot fail the writer.
- **Privacy.** A record carries hashes of the brief and of the work. URIs that a source's events emit are not copied
  into records, and the record has no free-text field.
- **Planted entries.** Anyone can post entries tagged `work.outcome`. Readers name the writers they trust, and SHOULD
  cap the requests one read makes.
- **Averages.** `getSummary` averages over the writers passed in, so one writer with many entries dominates the result.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
