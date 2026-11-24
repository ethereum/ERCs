# Evaluated Work Records: reference code

A writer, a reader and test vectors for the profile. Node.js 18 or later (tested on 18.20 and 24.14), no dependencies,
no keys: the code reads public JSON-RPC endpoints and never sends a transaction. `node cli.mjs <command> --help` lists
each command's flags; flags take `--flag value` or `--flag=value`.

| File | What it is |
| --- | --- |
| `work-records.mjs` | The profile's rules, offline: Keccak-256, ERC-55, canonical JSON, descriptor rules, steps, outcomes, consistency, record files, reader rules, `giveFeedback` calldata |
| `cli.mjs` | The writer (`build`), the reader (`check`, `entries`) and the vector runner (`vectors`) |
| `sources/` | The descriptors BrainChain publishes for its `TaskBoard` 3.5.0 on mainnet (chain id 274663) and testnet (chain id 274630) |
| `example-record.json` | The record of BrainChain mainnet task 50, as the record bytes a writer posts |
| `vectors.json` | Eight tasks read from those chains, with their logs and expected records, and nine cases a reader must fail |
| `test.mjs` | Offline tests over the vectors, the rules the vectors do not reach, and the CLI's exit codes |

Exit codes: 0 every check passed, 1 a check failed or an error, 2 usage, 3 nothing to post.

```sh
node --test test.mjs
node cli.mjs vectors --verify 274663=https://rpc.usebrainchain.com --verify 274630=https://rpc.testnet.usebrainchain.com
```

## Writing a record

`build` reads the task's logs up to the source's finalized block and prints the record, its hash and the
`giveFeedback` calldata. `--calldata` prints the calldata alone, and `--out <path>` also writes the record bytes to a
file for `check --file`. Posting the entry is left to the caller. A task that takes no entry, such as mainnet task 54
(`unstarted`), exits 3 with the reason. Mainnet task 9, delivered and never graded, builds a `work.lapsed` entry with
`tag2` `delivered`.

```sh
node cli.mjs build --rpc https://rpc.usebrainchain.com --descriptor sources/brainchain-mainnet.json --task 50 \
  --registry eip155:4663:0x8004A169FB4a3325136EB29fA0ceB6D2e539a432 --agent 20424 \
  --writer 0x97D558417c3D61f1074422AD843e1Db1E565b952 --out record.json
```

A record of mainnet task 50 is 3,622 bytes, and its `giveFeedback` costs about 250,000 gas on Robinhood Chain.

## Checking a record

```sh
node cli.mjs check --rpc https://rpc.usebrainchain.com --descriptor sources/brainchain-mainnet.json \
  --file example-record.json
```

`--file record.json` checks the record `build --out` wrote the same way.

```text
ok      task 50 at 0x44b8464342Bbfb9B565FAE494DfDefa37D33A211 (accepted)
        feedbackHash 0x362bfa0b49ac22cabe8566773da906e0ca8b7cf1b0fe8960df2657e697b1259a
        agent 20424 and the binding are checked only against an entry, by the entries command
```

Change the paid amount in a copy of the record and the same command prints
`FAIL    task 50 at 0x44b8464342Bbfb9B565FAE494DfDefa37D33A211: step 5 paid.amount: record 970000, chain 1000000` and
exits 1.

## Reading entries

`entries` reads every entry one writer posted about one agent. `--from-block` is where it starts scanning the
Reputation Registry's logs: the registry's deployment block on its chain. On Robinhood Chain the registry's first log is
in block 12058837, so that block covers every entry.

```sh
node cli.mjs entries --registry-rpc https://rpc.mainnet.chain.robinhood.com \
  --reputation eip155:4663:0x8004BAa17C55a88189AE136b182e5fdA19dE9b63 --agent 20424 \
  --writer 0x97D558417c3D61f1074422AD843e1Db1E565b952 --from-block 12058837 \
  --rpc 274663=https://rpc.usebrainchain.com --descriptor sources/brainchain-mainnet.json
```

No entries under this profile's tags exist on Robinhood Chain yet, so today this prints the line below on standard
output and the reason on standard error, and exits 1. N counts BrainChain's earlier entries for agent 20424, under its
own tags, and grows as entries are added.

```text
N entries, 0 under work.outcome or work.lapsed, 0 unbound
no work.outcome or work.lapsed entries from 0x97D558417c3D61f1074422AD843e1Db1E565b952 about agent 20424
```

Entries that are only `unbound` pass and keep the exit at 0; the summary says that they rest on the writer's word.

To see the reader work, post entries on a local fork. This needs Foundry's `anvil` and `cast` (the run below used anvil
1.8.1); every transaction stays on the fork, and each `cast send` prints its receipt.

```sh
A=http://127.0.0.1:8547
R=0x8004BAa17C55a88189AE136b182e5fdA19dE9b63   # Reputation Registry, Robinhood Chain
I=0x8004A169FB4a3325136EB29fA0ceB6D2e539a432   # Identity Registry
W=0x97D558417c3D61f1074422AD843e1Db1E565b952   # BrainChain's writer key
OWNER=0x70C665780E43BA1496a4E691e408F24844dB58eC   # owner of agents 20424 to 20428
anvil --fork-url https://rpc.mainnet.chain.robinhood.com --port 8547 --silent &
until cast chain-id --rpc-url $A >/dev/null 2>&1; do sleep 1; done
for a in $W $OWNER; do cast rpc anvil_impersonateAccount $a --rpc-url $A; cast rpc anvil_setBalance $a 0x8AC7230489E80000 --rpc-url $A; done

# Agent 20424 declares the worker BrainChain hires it as (the board's model id).
BOARD=44b8464342bbfb9b565fae494dfdefa37d33a211
MODEL=5f1c28741ee74be2a828fd337283ca47e477a0cd56bf5ad31c61e1ce3ce1d22f
WORKERS=0x$(printf '%064x%064x%064x' 32 1 274663)000000000000000000000000$BOARD$MODEL
cast send --unlocked --from $OWNER $I "setMetadata(uint256,string,bytes)" 20424 work.workers $WORKERS --rpc-url $A

for t in 50 51 9; do
  CD=$(node cli.mjs build --rpc https://rpc.usebrainchain.com --descriptor sources/brainchain-mainnet.json --task $t \
    --registry eip155:4663:$I --agent 20424 --writer $W --calldata) || continue
  cast send --unlocked --from $W $R "$CD" --rpc-url $A
done

node cli.mjs entries --registry-rpc $A --reputation eip155:4663:$R --agent 20424 --writer $W --from-block 12058837 \
  --rpc 274663=https://rpc.usebrainchain.com --descriptor sources/brainchain-mainnet.json --rebuild
```

The reader's output has this shape (`cast rpc` also prints `null` for each impersonation call):

```text
ok      entry <n> (task 50), accepted, binding declared
ok      entry <n+1> (task 51), rejected, binding declared
ok      entry <n+2> (task 9), lapsed after delivery, binding declared
FAIL    task <t> at 0x44b8464342Bbfb9B565FAE494DfDefa37D33A211 (accepted): no entry from the writer, <h> h <m> min past the terminal step
wait    task <t> at 0x44b8464342Bbfb9B565FAE494DfDefa37D33A211 (rejected): terminal step <h> h <m> min ago; the entry is due in <h> h <m> min
<N> entries, 3 under work.outcome or work.lapsed, 0 unbound
<F> checks failed
```

With `--rebuild`, coverage starts at the writer's earliest entry for the worker, task 9's settlement here. Every later
task of that worker that takes an entry and has none prints `wait` until it is due, then `FAIL`, so this run, which
posts three entries, exits 1. Each wait is measured from the later of the source's finalized head and the fork's latest
block. Without `--rebuild` the three entries pass and the run exits 0.

Without the `work.workers` declaration the three entries read `unbound`. A revoked entry prints a `FAIL` line that says it
was revoked, and its task counts as having no entry. Without `--descriptor` every record fails, since the reader holds no descriptor for the
source. If the writer also posted task 50 for another agent, the entry for task 50 fails with
`the writer also posted task 50 for agent …`.

## Notes on the BrainChain source

- The deployed bytecode at `0x44b8464342Bbfb9B565FAE494DfDefa37D33A211` matches `src/TaskBoard.sol` at tag `v3.5.0`
  of the `usebrainchain/brainchain` repository, compiled with solc 0.8.24 and 200 optimizer runs.
- `Ruled` and `AppealRuled` report in their `paid` parameter the decision that settles the task: a ruling below the board's confidence
  threshold leaves the standing verdict in place, and `paid` repeats it.
- `BountyPaid` reports the full bounty and the fee taken from it, hence `"feeIncluded": true`.
- The board's events carry no act by the worker before delivery, so no BrainChain task lapses after `assigned`: a hire
  the worker never delivered on is `unstarted` and takes no entry. A delivery the board never graded, as in mainnet task
  9, lapses after `delivered`.
- The board marks no event `actor: "worker"` and its descriptor names no `vault`: the board holds every bounty itself.
- Robinhood Chain's public endpoint keeps no state older than about 10,000 blocks, so the reader reads `work.workers`
  from the Identity Registry's `MetadataSet` logs rather than from `getMetadata` at the entry's block.
