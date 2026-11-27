# Agent Linkability Report: schema and test vectors

- `linkability-report.schema.json`: JSON Schema (draft 2020-12) for a report. It is an aid, not normative: where it
  and the proposal's Specification disagree, the Specification prevails.
- `validate.mjs`: a dependency-free validator (Node.js 18 or later). It implements the schema keywords the schema
  uses, refuses any other keyword, and then checks the rules a schema cannot express: `partial` and
  `partial_reasons` agree with the fields not read, no evidence block is after the report's block, per-address
  entries agree with `agent.owner`, `agent.agentWallet` and `agent.payTo`, entries with address `null` are not read
  (except the unset `agentWallet` entry of `payment_lands_on_owner`), every field with entries has a `payTo` entry
  with address `null` when `agent.payTo` is not read, and `activity_hour_concentration` ends `window_hours` after it
  starts.
- `vectors/valid/`: valid reports, which the validator accepts.
- `vectors/invalid/`: invalid reports, one defect each, which the validator rejects.
- `reference-responses/`: the raw answers of the reference reader the valid vectors were mapped from.

Run:

```sh
node validate.mjs                 # every valid vector passes and every invalid vector fails
node validate.mjs my-report.json  # check one report
```

## How the valid vectors were made

Each valid vector maps one live answer of the reference reader's agent endpoint on chain 4663. The answer's `read` member names the block it was read at and the values its grade was built from.

| Vector | Read at (UTC) | Block |
|---|---|---|
| `agent-20030.json` | 2026-11-21T07:54:05Z | 119724621 |
| `agent-7622.json` | 2026-11-21T07:56:02Z | 119725624 |
| `agent-3000.json` | 2026-11-21T07:57:40Z | 119726456 |
| `agent-9000.json` | 2026-11-21T07:59:18Z | 119727331 |

At each block `owner` (`ownerOf`), `agentWallet` (`getAgentWallet`), `owner_agent_count` (`balanceOf(owner)`) and
the stealth meta-addresses (`stealthMetaAddressOf(address, 1)` on the ERC-6538 registry) were read again with
`eth_call`; all agree with the reference answer, and those calls are the evidence.

Mapping rules:

- `null` in the answer's `read` member is a part not read: it maps to not read with reason `unavailable` (the source
  did not answer or gave no value) or `incomplete` (the history was read in part), which makes the report partial.
  Agent 9000's answer has `pay_to` `null`, so its `payTo` and every `payTo` entry are not read with `unavailable`.
- What the reference reader never reads, for any agent, maps to not read with reason `unsupported`: the direct link
  and stealth meta-address of a `payTo` that is neither the owner nor the `agentWallet`. No valid vector needs it.
- `payers_visible` counts USDG payments into the `payTo` over 30 days, as the reference reader does.
- `shared_payment_address` is read from the reader's index of the registry, comparing `agentWallet` and `payTo`; the
  index lists at most 50 agents, and a full list is marked `lower_bound`.
- `shielded_pool_receipts` uses the reader's own named pool list; a pool counts when it was the first funder of a
  payment address or sent value to the payment wallet. `addresses` is the address whose history was read (the owner
  for agent 9000: its `agentWallet` is unset and its `payTo` not read). A history read in part with no receipt found is `incomplete`.
- The `payment_wallet_leaks` members are parsed from the answer's leak texts; members it does not list are omitted,
  which this proposal reads as not read. `activity_hour_concentration.window_hours` is the length of the hour range
  the answer names (08:00 to 14:00 UTC for agent 9000, so 6).
- `score` copies the reference grade; its method is implementation-defined.
