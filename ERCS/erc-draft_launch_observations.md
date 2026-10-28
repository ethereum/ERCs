---
title: Launch Observations
description: Block-pinned facts an independent detector records about a token launch, keyed to ERC-8376 launch ids
author: Toll (@soli0x)
discussions-to: https://ethereum-magicians.org/t/pre-erc-launch-observations-the-check-an-agent-reads-before-it-buys-a-token/30112
status: Draft
type: Standards Track
category: ERC
created: 2026-10-27
requires: 165, 721, 8004, 8376
---

## Abstract

This proposal defines a registry in which any address, acting as a detector, records what it observed about a token
launch at a given block. An observation is keyed to the launch's [ERC-8376](./eip-8376.md) `launchId` when an ERC-8376
directory lists the launch, and otherwise to the chain id and token address. It carries a small set of typed findings,
such as the share of supply bought in the block of the first trade (the first-block share), the share bought by
early buyers, the creator's prior launches,
the share held by wallets linked through funding, and whether a product was found behind the token, together with
any of the base signals ERC-8376 defines, measured up to the observed block; a tally of how the detector reads its findings; the block the findings hold at;
and the hash and URI of the detector's full report. Observations are never edited or removed. A detector records a
newer observation to supersede its own earlier one, and both stay readable. A detector MAY link an
[ERC-8004](./eip-8004.md) identity. Together with the facts a launchpad declares at launch, observations let anyone
compare what was declared with what independent detectors saw, detector by detector. An agent, or a guard around it,
reads a trusted detector's latest typed finding for a token in one call before it buys.

## Motivation

A launch has two sides that a buyer, a wallet, a lender or an agent needs to compare: what the launchpad and the creator
say, and what the chain shows. The declared side is being standardized separately (the Token Launch Declarations
proposal, a separate draft, records the creator, allocations, liquidity locks and fee recipients a launchpad declares).
Its stated purpose is that "detectors, wallets and lenders can compare what a launchpad declared with what they
observe". Nothing standardizes the observed side.

Today every detector publishes through its own interface and its own vocabulary. Three problems follow:

1. **No common shape.** A wallet that wants to show "34% of supply was bought in the first trade block" must integrate each
   detector separately, and two detectors measuring the same thing cannot be compared because nothing says they
   measured the same thing.
2. **No block.** A figure such as "the creator holds 12%" is true at one block and false a few blocks later. Without the
   block it was read at, a reader cannot reproduce it, and a detector cannot be shown wrong.
3. **No history.** Off-chain results are replaced in place. A reader cannot see what a detector said before the
   outcome was known, which is the only way to judge whether its findings mean anything.

ERC-8376 defines a registry of bonded abuse reports, each scoring one abuse pattern from 0 to 100. That fits a party
prepared to stake a bond on a claim of abuse. Most useful readings of a launch are not claims of abuse: the share bought
by early buyers, how many launches the creator made before, whether a product exists behind the token. Many detectors
can state such facts and stand behind the block they read them at, without asserting a pattern or posting a bond. This
proposal is that layer: append-only facts without a bond or a score, at a block, keyed so that they line up with ERC-8376
launches and with declarations.

Readers it serves:

- **Agents and the guards around them** read a trusted detector's latest typed findings for a token in one call,
  before or inside the transaction that buys it, and refuse a stale or missing reading.
- **Detectors** read each other's observations to corroborate or dispute a figure at a named block.
- **Wallets** show findings from the detectors their user chose, next to what was declared.
- **Lenders and contracts** read the latest observation of a trusted detector inside the transaction that acts on it.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

An observations registry MUST implement `ILaunchObservations` and [ERC-165](./eip-165.md), returning `true` for the
interface identifier of `ILaunchObservations`, `0x526791dc`, and for `0x01ffc9a7`.

```solidity
interface ILaunchObservations {
    enum KeyKind { None, Erc8376, Token }

    enum Lean { None, Clear, Careful, Against }

    struct Tally {
        uint16 against;
        uint16 careful;
        uint16 clear;
    }

    struct Finding {
        bytes32 kind;
        uint256 value;
        uint64 param;
        Lean lean;
    }

    struct ObservationInput {
        KeyKind kind;
        bytes32 launchId;
        uint256 chainId;
        address token;
        uint64 observedBlock;
        bytes32 observedBlockHash;
        Tally tally;
        bytes32 reportHash;
        string reportURI;
        bytes32 evidenceRoot;
    }

    struct Observation {
        bytes32 launchKey;
        uint256 chainId;
        address token;
        KeyKind kind;
        uint64 observedBlock;
        address detector;
        uint64 recordedAt;
        address identityRegistry;
        Tally tally;
        uint256 agentId;
        uint256 supersedes;
        bytes32 reportHash;
        bytes32 evidenceRoot;
        string reportURI;
    }

    event ObservationRecorded(uint256 indexed observationId, bytes32 indexed launchKey, address indexed detector, KeyKind kind, uint256 chainId, address token, uint64 observedBlock, bytes32 observedBlockHash, uint256 supersedes, Tally tally, bytes32 reportHash, string reportURI, bytes32 evidenceRoot);
    event FindingObserved(uint256 indexed observationId, bytes32 indexed kind, uint256 value, uint64 param, Lean lean);
    event DetectorIdentitySet(address indexed detector, address indexed identityRegistry, uint256 indexed agentId);

    function launchDirectory() external view returns (address);
    function tokenKey(uint256 chainId, address token) external pure returns (bytes32);
    function recordObservation(ObservationInput calldata input, Finding[] calldata findings) external returns (uint256 observationId, bytes32 launchKey);
    function setDetectorIdentity(address identityRegistry, uint256 agentId) external;
    function detectorIdentity(address detector) external view returns (address identityRegistry, uint256 agentId);
    function getObservation(uint256 observationId) external view returns (Observation memory observation, Finding[] memory findings);
    function latestOf(bytes32 launchKey, address detector) external view returns (uint256 observationId);
    function latestByToken(uint256 chainId, address token, address detector) external view returns (uint256 observationId);
    function latestFinding(uint256 chainId, address token, address detector, bytes32 kind, uint64 param) external view returns (uint256 observationId, uint64 observedBlock, uint64 recordedAt, uint256 value, Lean lean);
    function latestFindingFrom(uint256 chainId, address token, address[] calldata detectors, bytes32 kind, uint64 param) external view returns (address detector, uint256 observationId, uint64 observedBlock, uint64 recordedAt, uint256 value, Lean lean);
    function observationsOf(bytes32 launchKey, uint256 start, uint256 limit) external view returns (uint256[] memory);
    function observationsBy(bytes32 launchKey, address detector, uint256 start, uint256 limit) external view returns (uint256[] memory);
    function detectorsOf(bytes32 launchKey, uint256 start, uint256 limit) external view returns (address[] memory);
}
```

### Terms

- A **detector** is any address that records an observation. It is the caller of `recordObservation`.
- The **directory** is the ERC-8376 `ILaunchDirectory` whose address `launchDirectory()` returns, or the zero address
  when the registry serves no directory. `launchDirectory()` MUST NOT change.
- A **launch key** is the `bytes32` under which observations of one launch are grouped.
- An **observation** is one record by one detector about one launch key at one observed block.
- A **finding** is one typed fact inside an observation.
- The **observed block** is the block number, on the chain the launch is on, at which every finding of the observation
  holds. The **observed block hash** is the hash of that block as the detector read it.
- A chain's **block number** is the number its own blocks carry, the number its nodes return for `eth_blockNumber`.
  Every block number in this proposal, observed or current, is in that domain. On most chains it is `block.number`. On
  an Arbitrum chain, such as Robinhood Chain, `block.number` inside the EVM returns a block number of the parent chain
  and `blockhash` does not return the chain's own block hashes; the chain's block number is
  `ArbSys(address(100)).arbBlockNumber()`.
- The **creator** is, for a launch the directory lists, the directory's `deployerOf(launchId)`; otherwise the party the
  detector attributes the launch to, as stated in its report.

### Launch keys

An observation has one of two kinds of launch key.

- **ERC-8376 keys** (`KeyKind.Erc8376`). For a launch the directory lists, the launch key is its `launchId`. The
  registry MUST read the token from the directory's `tokenOf(launchId)` and MUST revert if it is the zero address, if
  the directory is the zero address, or if the input's `chainId` or `token` is not zero. The recorded `chainId` is
  `block.chainid`, since an ERC-8376 directory records only its own chain's launches.
- **Token keys** (`KeyKind.Token`). For any other launch, the launch key is derived as below from the chain the token
  is on and its address. The registry MUST revert if `chainId` or `token` is zero, or if `launchId` is not zero.
  `tokenKey(chainId, token)` MUST return this value.

```
launchKey    = keccak256(abi.encode(TOKEN_SCOPED, chainId, token))
TOKEN_SCOPED = keccak256("erc.launch-observations.token-scoped")
```

A detector SHOULD observe a launch the directory lists under its `launchId`. A token key groups every launch of a token
on a chain, including relaunches, and its observations describe the token at the observed block, whichever launch
produced it. `KeyKind.None` is the kind of an observation that does not exist; recording with it MUST revert.

The chain in a token key is the chain the token is on, which need not be the chain of the registry: a registry on one
chain MAY hold observations of launches on another.

### Recording

`recordObservation(input, findings)` records one observation and returns its identifier and launch key.

- It MUST NOT restrict its caller. Any address MAY act as a detector.
- It MUST resolve the launch key as above.
- It MUST revert if `observedBlock` is zero, or if the launch is on the registry's chain and `observedBlock` is not
  lower than the chain's current block number.
- When the launch is on the registry's chain, it MUST revert if `observedBlockHash` is zero, and if
  `observedBlockHash` differs from the hash of block `observedBlock` where the registry can read that hash on chain:
  from the [EIP-2935](./eip-2935.md) history contract at `0x0000F90827F1C53a10cb7A02335B175320002935` when it has
  code and returns a hash for the block (it holds the last 8191 blocks), and otherwise, on a chain where `blockhash`
  takes the chain's own block numbers, from `blockhash(observedBlock)` when the block is at most 256 blocks old. A
  hash the registry cannot read is not checked. When the launch is on another chain, `observedBlockHash` SHOULD be the
  hash of the observed block on that chain and MAY be zero, meaning not given; the registry does not check it.
- It MUST revert if `reportHash` is zero, if `reportURI` is empty, or if `reportURI` is longer than 512 bytes.
- It MUST revert if `findings` holds more than 32 entries, if two findings share both `kind` and `param`, or if a
  finding is invalid as defined under [Findings](#findings).
- It MUST revert if `tally.against`, `tally.careful` or `tally.clear` is lower than the number of findings with lean
  `Against`, `Careful` or `Clear` respectively.
- When the caller has recorded under the same launch key before, it MUST revert if `observedBlock` is lower than the
  observed block of the caller's latest observation of that key, and MUST set `supersedes` to that observation's
  identifier. Otherwise `supersedes` is zero.
- It MUST assign an identifier one greater than the last one assigned, starting at 1, and MUST record the caller as
  `detector` and the block timestamp as `recordedAt`.
- It MUST recheck the caller's linked identity as `setDetectorIdentity` checks it, and record it as `identityRegistry`
  and `agentId` only if the caller still holds it. Otherwise it MUST record both as zero, and MUST NOT revert for it.
- It MUST emit `ObservationRecorded`, carrying `observedBlockHash` as given, then `FindingObserved` once per finding
  in the order given. `observedBlockHash` is emitted only; it is not part of the stored `Observation`.

### Findings

A finding states that a quantity, identified by `kind` and qualified by `param`, had `value` at the observed block.
`lean` is the detector's reading of that one finding for a prospective buyer: `Against` (it weighs against buying),
`Careful` (it calls for care), `Clear` (the detector looked and found nothing adverse), or `None` (no reading). A lean is
the detector's reading of one fact. It is not a determination about the launch.

Where a detector could not establish a value, it MUST report `type(uint256).max` (**not read**) and MUST NOT report zero.
Zero asserts that the quantity was measured and was zero.

Kinds are `bytes32` identifiers derived from namespaced strings, as ERC-8376 derives pattern identifiers. The `erc.`
prefix is reserved for kinds defined in an ERC. This proposal defines the core kinds below; the registry MUST revert on
a core finding whose `param` or `value` is outside the domain given. Shares are in basis points of the token's total
supply, from 0 to 10000.

| Kind | Derivation | `param` | `value` |
| --- | --- | --- | --- |
| First-block share | `keccak256("erc.launch-observations.first-block-share")` | 0 | Share of total supply acquired in the block of the token's first trade, by accounts other than the pool and the venue. |
| Early-buyer share | `keccak256("erc.launch-observations.early-buyer-share")` | N, seconds, not zero | Share of total supply acquired in the first N seconds after the first trade, by accounts other than the pool and the venue. |
| Creator prior launches | `keccak256("erc.launch-observations.creator-prior-launches")` | 0 | Number of tokens launched by the creator before this launch, on the same chain. |
| Funding-linked share | `keccak256("erc.launch-observations.funding-linked-share")` | H, hops, not zero | Share of total supply held at the observed block by accounts that share a funding source, within H transfers of native currency, with the creator or with another holder in the set. |
| Product label | `keccak256("erc.launch-observations.product-label")` | 0 | Whether the detector found a working product behind the token, checking each claim the project makes against the chain and its public interfaces: 1 found, 2 partly found, 3 not found, or not read. |

For the creator prior launches, a detector that could establish only a lower bound, because its scan of the creator's
history stopped before the observed block, MUST report not read, and MAY give the bound in its report. For the product
label, the detector's report MUST list each claim it checked and what it found.

The first-block and early-buyer shares are fixed once their window has passed, so they hold at every later block. Every
other finding MUST be read at the observed block itself. A detector that reads the parts of a check at different
blocks MUST record as `observedBlock` the block at which it read the quantities that can still change, and MUST NOT
record a finding it did not read at that block.

#### ERC-8376 signals

A detector MAY record any base signal of the ERC-8376 signal vector as a finding. Its kind is derived from the
signal's field name, `param` is 0, and `value` is the signal as ERC-8376 defines it, with the observation window
ending at the observed block instead of at `windowEnd`:

```
kind = keccak256(bytes.concat("erc.launch-observations.signal.", bytes(fieldName)))
```

so that, for example, the kind of `deployerSellRatio` is `keccak256("erc.launch-observations.signal.deployerSellRatio")`.
The registry MUST revert on such a finding whose `param` is not zero or whose `value` is outside the signal's domain:
at most 10000 for the signals ERC-8376 gives in basis points, at most `type(uint32).max - 1` seconds for
`lpLockRemaining`, at most `0xff` for the `privilegedPowers` bitmask, and at most `type(uint16).max - 1` for
`priorUpheldClaims`. ERC-8376's own unavailability sentinels are not values here: a signal that was not established is
reported as not read, `type(uint256).max`, as every other finding is. The rules ERC-8376 sets for measuring a signal,
such as selecting the pool that holds the most of the paired asset, measuring liquidity in the paired asset and
reporting a lock as unavailable once liquidity was demonstrably removed, apply unchanged.

A detector SHOULD record a quantity that ERC-8376 defines under its signal kind rather than under a kind of its own,
so that readers of both proposals read one definition. Liquidity in particular is read through the `lpLockedShare` and
`lpLockRemaining` signals, not through a finding of this proposal.

A detector MAY report kinds outside the core set, derived from a namespaced string under a prefix it controls, such as a
domain it owns, and MUST NOT use the `erc.` prefix for them. The registry stores them without checking `param` or
`value`, except that `kind` MUST NOT be zero. A reader MUST treat a kind it does not recognize as informational.

### Tally

`tally` counts the detector's readings over every finding in its full report, typed or not: how many weigh against,
call for care, or are clear. It is how the detector summarizes the observation, and like a lean it is a reading of
facts, not a determination about the launch. It MUST be at least the counts of the typed findings with each lean, as
required above, and MAY be higher where the report holds findings that have no typed kind.

### Report

`reportURI` locates the detector's full report, and `reportHash` MUST be the `keccak256` of the exact bytes served at
it. A detector SHOULD serve the report from content-addressed storage. The report SHOULD be a JSON object with at least:

- `launchKey`, `kind`, `chainId`, `token`, `observedBlock` and `observedBlockHash`, as recorded;
- `findings`: every finding, typed or not, each with its kind or name, `param`, `value`, `lean` and a one-line
  description of how it was read;
- `tally`: the three counts;
- `creator`: the address the detector attributes the launch to, and how;
- `method`: the detector's method version.

The report MAY also carry `detail`, the URL of a fuller report, which MAY require payment. `reportHash` does not cover
it, so the report it hashes stays readable without payment.

`evidenceRoot` is OPTIONAL and zero when absent. Where present, it MUST be a root over evidence leaves built as ERC-8376
specifies for its `evidenceRoot`, so that a third party can check a finding against the transactions it was read from.

### Immutability and superseding

- An observation, and every finding recorded with it, MUST NOT be changed or removed. The registry MUST NOT expose any
  function that changes or removes one.
- A detector that wants to correct or update an observation records a new one. The new observation names the earlier
  one in `supersedes`, and becomes the detector's latest for that launch key. The earlier one stays readable through
  `getObservation` and `observationsBy`.
- A detector's observed blocks for one launch key never decrease. A correction of a reading at the same block records
  the same `observedBlock` again.
- An observation supersedes only the same detector's earlier observation of the same launch key. No detector can
  supersede another's.

### Detector identity

A detector MAY link an ERC-8004 identity, or another [ERC-721](./eip-721.md) identity, with
`setDetectorIdentity(identityRegistry, agentId)`.

- When `identityRegistry` is the zero address, the call MUST revert unless `agentId` is zero, and it removes the link.
- Otherwise it MUST revert unless `identityRegistry` has code and the caller is its `ownerOf(agentId)`, or its
  `getAgentWallet(agentId)` where the registry provides that function.
- It MUST emit `DetectorIdentitySet`. `detectorIdentity(detector)` MUST return the current link.

The link held when an observation is recorded is copied into it, if the detector still holds the identity then, so a
later change does not alter what an earlier observation records. A reader that trusts a detector by its `agentId`
SHOULD recheck, when it reads, that the identity is still owned by the detector or names it as agent wallet. Through the linked identity, readers can find the detector's ERC-8004 registration file and its
reputation, and can give feedback on the detector's observations in the ERC-8004 reputation registry.

A detector that links an ERC-8004 identity SHOULD list each registry it records to in its registration file, as a
service named `launch-observations` whose endpoint is the registry's CAIP-10 address (`eip155:<chainId>:<address>`).
A reader that acted on a detector's observation MAY give feedback to the detector's `agentId` in the ERC-8004
reputation registry with `tag1` `launch-observations` and `tag2` the finding kind it relied on, and a `feedbackURI`
naming the registry and the `observationId`.

### Reading

- `getObservation(observationId)` MUST return the observation and its findings in the order recorded. For an identifier
  with no observation it MUST return an observation whose kind is `KeyKind.None` and whose other fields are zero, and no
  findings. It MUST NOT revert.
- `latestOf(launchKey, detector)` MUST return the identifier of the detector's latest observation of the key, or zero.
- `latestByToken(chainId, token, detector)` MUST return the identifier of the detector's observation, under either key
  kind, of `token` on chain `chainId` with the highest observed block (on a tie, the one recorded last), or zero. For
  an ERC-8376 key, the chain is the registry's chain and the token is the one read from the directory.
- `latestFinding(chainId, token, detector, kind, param)` MUST return, for the observation `latestByToken` returns, its
  identifier, observed block and `recordedAt`, and the `value` and `lean` of its finding with that `kind` and `param`.
  When there is no such observation, the identifier, observed block and `recordedAt` MUST be zero. When there is no
  such observation or no such finding, `value` MUST be not read (`type(uint256).max`) and `lean` MUST be `None`, so
  that a missing reading never reads as a measured zero. It MUST NOT revert.
- `latestFindingFrom(chainId, token, detectors, kind, param)` MUST try the detectors in the order given and return the
  first one whose `latestFinding` for `kind` and `param` has a value other than not read, with that detector and the
  results `latestFinding` gives for it. When no detector in the list has one, it MUST return the zero address, zero
  identifier, observed block and `recordedAt`, not read and `None`. It MUST NOT revert. Its gas grows linearly with
  the length of the list, so a reader SHOULD pass only the few detectors it trusts, in order of preference.
- `observationsOf(launchKey, start, limit)` MUST return the identifiers of every observation of the key, by any
  detector, in the order recorded. `observationsBy(launchKey, detector, start, limit)` MUST do the same for one
  detector's observations of the key. `detectorsOf(launchKey, start, limit)` MUST return each detector that recorded
  under the key once, in the order of its first observation.
- Each list MUST start at position `start`, return at most `limit` entries, and return an empty list when `start` is at
  or past its end.

A reader acting on an observation SHOULD refuse one whose observed block is more than a bound of its own choosing
below the current block number of the launch's chain. The first-block and early-buyer shares do not change after their
window; every other kind can. For an observation of another chain, the reader SHOULD bound `recordedAt` instead. The
registry sets no bound: how fresh a reading must be depends on what the reader is about to do.

### Arbitrum chains

On an Arbitrum chain, `block.number` and `blockhash` inside the EVM refer to the parent chain, while observed blocks
are the chain's own. A registry deployed there MUST take the current block number from
`ArbSys(address(100)).arbBlockNumber()` and MUST NOT compare an observed block with `block.number` or check its hash
with `blockhash`; it checks the hash through the EIP-2935 history contract where the chain deploys it. A reader or
guard on an Arbitrum chain MUST take its current block number from the same source when it bounds the age of an
observation, since `block.number` there is smaller than every observed block and the difference underflows or
compares numbers of two chains. A registry or reader that runs on several chains MAY use ArbSys when code exists at
`address(100)` and the call succeeds, and `block.number` otherwise, as the reference implementation does.

### Deployment

A registry MUST be permissionless, immutable and without an owner. It MUST NOT refuse an observation that meets the
requirements above, since a registry able to refuse observations could suppress the ones its operator dislikes. Any
address MAY deploy a registry. A reader MUST obtain the registry's address from a source independent of the launch it
is examining.

A registry SHOULD be deployed through the [EIP-7997](./eip-7997.md) factory where that factory is present on the chain,
with its salt and init-code hash published, so that a reader can derive its address and check its code without
trusting the deployer.

### Relation to ERC-8376 and to declarations

This section is informative.

- An observation is not an ERC-8376 report. It carries no score, names no abuse pattern and posts no bond, and an
  ERC-8376 consumer MUST NOT treat it as a report. A detector that is also an ERC-8376 detector MAY derive inputs for
  its `observe` call from its own observations, and MAY cite an observation's report in its `evidenceURI`.
- First-block and early-buyer shares are measured without regard to funding, so they differ from ERC-8376's
  `sniperConcentration`, which counts only buyers linked to the deployer. The funding-linked share is the measurement
  ERC-8376 needs for `insiderAllocationShare` and `deployerSupplyShare`, without its window. A detector that measures
  those signals as ERC-8376 defines them records them under their signal kinds.
- Against declarations: a declared allocation is compared with the funding-linked share at a block; a declared
  liquidity lock is compared with the `lpLockedShare` and `lpLockRemaining` signals at a block after the lock was
  declared; a declared creator is compared with the creator the detector attributes the launch to. For a launch the
  directory lists, both sides use the same `launchId`. A launch the directory does not list is declared under a
  venue-scoped identifier, which includes the venue and so cannot equal a token key: a reader joins the two through
  the token, reading the declarations of the observation's `token` with `declarationIdsOf`.

### Use before a trade

This section is informative.

A contract that buys on behalf of a user or an agent, such as a guard, a wallet module or an agent router, can check a
trusted detector's latest reading of the token inside the same transaction, before the swap. The thresholds and the
age bound below are the integrator's, not this proposal's.

```solidity
// Inside a guard, wallet module or agent router, before the swap.
// The chain's own block number: ArbSys on an Arbitrum chain, block.number elsewhere.
uint256 current = ON_ARBITRUM ? IArbSys(address(100)).arbBlockNumber() : block.number;
(uint256 id, uint64 at,, uint256 linked,) = obs.latestFinding(block.chainid, token, DETECTOR, FUNDING_LINKED_SHARE, 2);
require(id != 0 && at <= current && current - at <= MAX_AGE, "no fresh observation");
require(linked != type(uint256).max && linked <= 1500, "funding-linked share");
(,,, uint256 first,) = obs.latestFinding(block.chainid, token, DETECTOR, FIRST_BLOCK_SHARE, 0);
require(first != type(uint256).max && first <= 2000, "first-block share");
```

A missing observation and a missing finding both come back as not read, so the guard refuses them rather than passing
them as clean. A guard that trusts several detectors can read them in order of preference with `latestFindingFrom`
and check which detector answered. An off-chain agent makes the same reads with `eth_call` and follows `reportURI`
for the detail.

## Rationale

- **Facts, not verdicts.** A finding is a quantity at a block, which a third party can recompute. A verdict is not, and
  two detectors' verdicts cannot be compared. The lean and the tally carry the detector's reading without turning it
  into a claim about the launch, and keep the reading separate from the fact so that a reader can ignore one and keep
  the other.
- **Append-only.** An observation is worth reading because it cannot be withdrawn once the outcome is known. A detector
  able to edit could rewrite a reading that turned out wrong, and nobody could measure its record. Corrections are new
  observations that point at the old one.
- **Block-pinned.** Launch state changes block by block. Pinning every finding to one block makes it reproducible, makes
  a wrong finding demonstrably wrong, and lets a reader see whether an observation came before or after an event. The
  observed block is stated by the detector because the registry may sit on another chain; on its own chain the
  registry rejects a block that does not exist yet.
- **The block hash is emitted, not stored.** A block number alone does not say which block a detector read if that
  block was reorganized out. The hash names it at the cost of one word of calldata and log data. It is checked on chain
  where the registry can read the block's hash, through EIP-2935 or `blockhash`, and otherwise left to readers, who
  can compare it with the canonical chain at no cost to the registry; storing it would add a storage write to every
  record for a value contracts can read back only for a bounded window.
- **The chain's own block numbers.** Observed blocks are what a detector's node reports, so the registry compares them
  with the same number. On an Arbitrum chain `block.number` is the parent chain's and would reject every same-chain
  observation, so the registry reads ArbSys there.
- **Identity rechecked at record time.** A link set once would let a detector keep showing an `agentId` it sold or
  lost. Checking it at each record costs one or two static calls and keeps the copied identity true when it is made;
  recording zero rather than reverting keeps a detector's observations flowing while its link is fixed.
- **An ordered list of detectors.** A guard that trusts more than one detector wants the first that has read the
  finding, without one call per detector. `latestFindingFrom` returns which detector answered, so the guard keeps
  control of whom it trusts; it does not merge or count readings.
- **Observed blocks do not go backwards.** Without this, a detector could record an observation of an earlier block
  after a later one and make "latest" mean something other than "most recent state".
- **A typed core and an off-chain report.** Contracts and wallets need a few comparable numbers they can read without
  parsing. Everything else a detector checks, and how, belongs in a report that changes shape with its methods. The hash
  binds the report to the record, and the optional evidence root reuses ERC-8376's leaf format instead of inventing one.
- **Five core kinds, and ERC-8376's signals by name.** ERC-8376 already defines twelve signals with their units and
  measuring rules. Defining them again would give readers two definitions of one quantity, so an observation records
  them under kinds derived from their ERC-8376 field names. The five core kinds are the readings ERC-8376 does not
  define: what was bought in the first trade block and the first seconds by anyone, the creator's earlier launches, the share
  held by wallets that share a funding source, and whether a product stands behind the claims a project makes. New
  kinds are namespaced, as ERC-8376 patterns are, so the set grows without a central registry.
- **A registry of its own, not a general attestation service.** A general attestation registry, such as the Ethereum
  Attestation Service or the ERC-8004 validation registry, stores a payload under a schema and a subject. It does not
  check that a share is at most 10000, that "not read" is never written as zero, that a detector's observed blocks do
  not go backwards, or that an ERC-8376 key names a listed launch, and it cannot answer "this detector's latest
  observation of this launch" in one read. Those rules are what make two detectors' readings comparable and a
  contract's read of one safe, so they belong in the registry.
- **ERC-8004 reputation, not validation.** The ERC-8004 validation registry is not used for observations. Its subject
  is an agent's work, not a token; a request must come from the validated agent's owner or operator, which would add
  a transaction before every trade; and its response is a score from 0 to 100. It is also not deployed everywhere the
  identity and reputation registries are: on Robinhood Chain only those two are deployed. The links this proposal
  uses, a service entry in the registration file and reputation feedback tagged with the kind relied on, exist
  wherever ERC-8004 identity and reputation do. Where an agent wants a validation record, the detector MAY answer its
  request with `validationResponse(requestHash, response, responseURI, responseHash, tag)`, with `responseURI` the
  observation's `reportURI`, `responseHash` its `reportHash`, `tag` `launch-observations:<observationId>`, and
  `response` the percentage of core kinds it read, which measures coverage, not safety.
- **One call by token.** An agent holds a token address, not a launch key. `latestByToken` and `latestFinding` find a
  trusted detector's newest reading of the token under either key kind without a directory lookup and without copying
  the report URI and every finding, so a guard can afford the read inside a trade. They return not read for anything
  missing, which makes absence fail closed.
- **The reader sets the age.** A registry-wide limit on how old an observation may be would be a policy, and the right
  bound differs between a guard on a trade and a lender's daily check. The reader states its own bound.
- **Keyed like declarations.** Using the ERC-8376 `launchId`, and reading the token from the directory as the
  declarations proposal reads the creator, means declared and observed facts about a listed launch meet under one
  identifier. The token key covers the many launches no directory lists, and its domain tag keeps it from matching a
  `launchId` or a venue-scoped declaration identifier.
- **No bond.** A bond answers for a claim of abuse. Requiring one for facts would keep most detectors out, and the
  facts are checkable at their block without one. Readers decide which detectors to trust, by identity and by record.
- **Optional identity, copied at record time.** An ERC-8004 identity lets a reader find a detector's reputation and
  registration file. Copying the link into each observation keeps the record of who stood behind it when it was made.
- **"Not read" is not zero.** As in ERC-8376, a missing measurement reported as zero would read as a clean measurement.
- **Bounds and pages.** At most 32 findings and a 512-byte URI keep a record's cost bounded. Every list can be made long
  by anyone, so every list is paged, and `latestOf`, `latestByToken` and `latestFinding` answer in one read for a
  reader that knows which detector it trusts.

## Backwards Compatibility

No backward compatibility issues found. This proposal changes nothing in ERC-8376. A registry can serve no directory, in
which case it records token keys only.

## Test Cases

A conforming registry, next to an ERC-8376 directory that lists one launch, passes these cases:

- A detector records an observation under a token key with five core findings and an ERC-8376 signal. `getObservation` returns every field
  and finding as given, `latestOf` returns it, and `detectorsOf` lists the detector once.
- Under an ERC-8376 key, the registry records the token the directory names and the registry's chain id. An unlisted
  `launchId`, a non-zero input `chainId` or `token`, or a registry without a directory reverts.
- A token key with a zero chain id, a zero token or a non-zero `launchId` reverts, as does `KeyKind.None`.
- No function changes or removes an observation; a second detector's observation leaves the first unchanged.
- A detector's second observation of a key supersedes its first: `supersedes` names the first, `latestOf` returns the
  second, the first and its findings stay readable, and `observationsBy` lists both, oldest first. Another detector's
  observations are unaffected.
- An observation at the same observed block as the detector's latest is accepted; one at an earlier block reverts.
- `ObservationRecorded` is emitted, then one `FindingObserved` per finding, in order.
- 32 findings are accepted and 33 revert. A 512-byte URI is accepted; 513 bytes, an empty URI and a zero report hash
  revert.
- A share above 10000, an early-buyer share with N zero, a product label of 0 or 4, and a zero kind revert. "Not read"
  is accepted for a share and for the product label. Two findings with the same kind and `param` revert; the same kind
  with another `param` is accepted.
- An ERC-8376 signal in basis points is accepted at 10000 and reverts at 10001 or with a non-zero `param`;
  `lpLockRemaining` reverts at `type(uint32).max`; `privilegedPowers` accepts 0 and reverts at `0x100`; "not read" is
  accepted for each.
- A tally lower than the leans of the typed findings reverts.
- On the registry's own chain, an observed block of zero or of the current block reverts; on another chain a block
  number above the current one is accepted.
- On the registry's own chain, without an EIP-2935 history contract, a wrong observed block hash reverts for a block up
  to 256 blocks old, including exactly 256, and is accepted unchecked for a block 257 blocks old; a zero hash reverts,
  as it does under an ERC-8376 key. On another chain a zero hash and an arbitrary hash are accepted.
  `ObservationRecorded` carries the hash given. With a history contract, a wrong hash for a block 1000 old reverts.
- With ArbSys at `address(100)` returning a block number far above `block.number`, a same-chain observation at an
  earlier ArbSys block is accepted, and one at or above the ArbSys block reverts. With an EIP-2935 history contract a
  wrong hash reverts, at 100 blocks old and at exactly 8191; a block 8192 old, or one the history has no hash for, is
  accepted unchecked, and `blockhash` is not used.
- After the detector's identity is transferred away, its next observation records zero `identityRegistry` and
  `agentId`; once the identity names the detector as agent wallet again, the link is recorded again.
- `latestFindingFrom` returns not read and the zero address when no listed detector has observed the token; skips a
  detector without an observation and one whose finding is not read; returns the first listed detector with a value
  even when a later one observed a later block; and returns not read for a kind nobody holds, an empty list, and
  another chain.
- With five observations of a key, `observationsOf(key, 1, 2)` returns the second and third, a start at 5 returns an
  empty list, and a limit of `type(uint256).max` returns the rest.
- The owner of an identity and its agent wallet can link it; another address, a registry without code, and a zero
  registry with a non-zero id cannot; a registry without `getAgentWallet` is read through `ownerOf`. An observation keeps
  the identity it was recorded under after the detector removes its link.
- `latestByToken` finds a detector's observations of a token under both key kinds: a higher observed block under the
  other key becomes the latest, a lower one does not, a tie goes to the one recorded last, and another detector or
  another chain returns zero.
- `latestFinding` returns the identifier, observed block, `recordedAt`, value and lean of the finding asked for. With
  no observation it returns zeros, not read and `None`; for a kind or `param` the observation does not hold it returns
  the identifier and block with not read and `None`; a measured zero stays zero.
- `supportsInterface` returns `true` for `0x526791dc` and `0x01ffc9a7`, and `false` for `0xffffffff`.

## Reference Implementation

A reference implementation, `LaunchObservations`, and its tests are in
[`assets/erc-draft_launch_observations`](../assets/eip-draft_launch_observations/contracts/LaunchObservations.sol). It
stores each observation and its findings, keeps per-key, per-detector and per-key detector lists, and validates the core
kinds and ERC-8376 signals. The tests run under Foundry with mocks of an ERC-8376 directory and of ERC-8004 and plain
ERC-721 identity registries, and need no external library.

## Security Considerations

- **Anyone can be a detector.** Recording is permissionless, so any address can record observations of any launch,
  with any figures. Readers MUST choose the detectors they trust and SHOULD read those detectors' observations with
  `latestOf`, `latestByToken` or `latestFinding`, and MUST NOT count observations or detectors as evidence. A thousand addresses agreeing may be one party.
- **Spam.** Lists by key can be made arbitrarily long. A reader SHOULD read pages of a size it can afford and SHOULD
  NOT assume a first page is the whole list. A trusted detector's latest observation stays readable in one call however
  long the lists grow.
- **A detector can be wrong.** An observation proves only that the detector recorded it. Its figures are facts at a
  block, as the detector read them, not a judgment that a launch is sound or fraudulent, and a reader MUST NOT present
  them as one. Readers SHOULD prefer detectors that publish evidence roots and reproducible reports, and that have a
  record of observations recorded before outcomes were known.
- **Absence.** A launch with no observation, or a finding reported as not read, says nothing about the launch. It
  SHOULD be presented as unknown, never as clear, and a contract acting on it SHOULD refuse it.
- **Staleness.** Most findings can change after their observed block. A reader that acts on an old observation acts
  on old facts; it SHOULD bound the age as described under [Reading](#reading).
- **Front-running.** An observation is visible in the mempool before it is mined. A copier can record the same figures
  first under its own address; this gains it nothing with readers who trust by detector identity, and `recordedAt`
  shows who recorded first. A creator watching the mempool can act on an adverse observation before it lands, so the
  observed block, not the time of recording, says when the facts held. Detectors SHOULD NOT rely on an observation
  staying private before it is mined.
- **Reorganizations and finality.** Finality is the main rule: a detector SHOULD observe only finalized blocks. On an
  Arbitrum Orbit chain, such as Robinhood Chain, a block is final once the batch that holds it is final on the parent
  chain, which is what the node's `finalized` block tag returns. The registry cannot enforce this, since it can read a
  block's hash only for a bounded window: the last 256 blocks through `blockhash`, which on an Arbitrum chain does not
  return the chain's own hashes at all, or the last 8191 blocks through the EIP-2935 history contract on chains that
  deploy it, which gives a longer window. So each observation emits the hash of its observed block: a reader or indexer
  SHOULD compare it with the canonical block at that number and treat an observation whose hash differs, or is not
  given, as unsupported for that block. Where a detector observed a block later reorganized out, it SHOULD record a
  correction at a final block; the earlier observation stays, and readers see both.
- **Other chains.** When the launch is on another chain, the registry cannot check that the observed block exists or
  what it held. The report and evidence root are the only means of checking such an observation.
- **Report availability.** The hash binds the report, but the URI can stop resolving. Detectors SHOULD use
  content-addressed storage, and readers SHOULD treat an observation whose report cannot be fetched or does not match
  its hash as unsupported.
- **Identities change hands.** An ERC-8004 identity can be transferred. An observation records the identity linked when
  it was recorded, and only if the detector still held it then; whether a later owner answers for it is the reader's
  decision. A reader that trusts an `agentId` SHOULD recheck the link when it reads, since a detector can lose the
  identity after recording.
- **Leans and tallies are readings.** Two detectors can read the same fact differently. Contracts that act
  automatically SHOULD act on typed values against thresholds they choose, not on another party's lean or tally.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
