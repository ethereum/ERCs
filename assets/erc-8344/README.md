# Relational Agent Registry — Reference Implementation

Reference implementation and test suite for the Relational Agent Registry ERC, where an agent is defined as a relationship (edge or hyperedge) among two or more humans rather than a standalone node.

## Layout

- `contracts/IRelationalAgentRegistry.sol` — the standard interface.
- `contracts/RelationalAgentRegistry.sol` — reference implementation: relationship/agent identity, unanimous propose/accept lifecycle, pause/resume with re-consent, leave/dissolve with generation lineage, append-only Shared Record Corpus with per-member co-signing, and all-keys-grant / single-key-revoke delegation.
- `test/RelationalAgentRegistry.t.sol` — Foundry tests, including the exact test vectors from the ERC's Test Cases section.

## Run

```sh
forge install foundry-rs/forge-std
forge test -vv
```

## Demo walkthrough (what the tests exercise)

1. A proposes an agent for `{A, B, C}`; B and C accept; the agent activates (unanimous consent).
2. A appends a meeting-note record (content hash + URI); B and C co-sign it (fully co-signed evidence).
3. All three members confirm a scoped, expiring delegation to an operator key; the operator appends a chat-history record on the relationship's behalf; any single member can revoke.
4. C leaves; the agent dissolves with its record log sealed but readable; `{A, B, C}` recreates a next-generation agent that links its predecessor automatically.
