---
eip: XXXX
title: Subject-Linked NAV Snapshot Oracle
description: Defines subject-linked NAV streams with provider attribution, corrections, invalidation, staleness, and aggregation
author: Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)
discussions-to: https://ethereum-magicians.org/t/subject-linked-nav-snapshot-oracle-candidate-erc/28939
status: Draft
type: Standards Track
category: ERC
created: 2026-07-05
requires: 165
---

## Abstract

This ERC defines an interface for publishing and querying subject-linked Net
Asset Value (NAV) snapshots. Each stream is keyed by `(subjectId, currency)` and
has one configured NAV basis. Snapshots include signed NAV, decimal precision,
valuation and publication timestamps, provider attribution, methodology
references, and correction provenance.

The core interface supports raw and staleness-aware latest-value queries,
provider-specific history, correction-chain resolution, and administrative
invalidation that preserves records while excluding invalid snapshots from
current-value queries. An optional aggregation interface defines deterministic
lower-median aggregation across provider submissions sharing a valuation
timestamp.

This ERC standardizes publication and query semantics. It does not calculate
NAV, credential providers, verify methodologies, establish asset backing, or
guarantee that NAV is an executable market or redemption price.

## Motivation

Periodic valuations for funds, private credit, real estate, infrastructure,
commodities, and other illiquid or administratively priced assets differ from
continuous exchange prices. Consumers need to know what the value represents,
when the underlying valuation was measured, when it was published, who supplied
it, and whether it is too old for the intended use.

Existing price and quote interfaces do not necessarily preserve valuation
history, provider identity, methodology references, restatement provenance, or
separate publication-age and valuation-age checks. Bespoke NAV contracts also
use incompatible stream keys and latest-value semantics.

This ERC provides:

- independent `(subjectId, currency)` NAV streams;
- stream-level basis configuration preventing provider disagreement over
  per-unit, per-share, or total interpretation;
- provider-attributed historical snapshots;
- one original provider submission per valuation timestamp;
- fork-free corrections and current-chain helpers;
- administrative invalidation for compromised or disputed terminal snapshots;
- separate publication and valuation staleness signals; and
- optional deterministic aggregation with quorum and deviation reporting.

The interface can serve vaults, settlement systems, reporting applications, and
other consumers while leaving valuation policy and provider governance to each
deployment.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Definitions

A **stream** is the namespace identified by `(subjectId, currency)`.

A **NAV basis** states whether NAV represents one underlying unit, one share or
token, or the total value of the subject.

A **provider** is the address recorded as publishing a snapshot.

A **valuation timestamp** is the asserted as-of time of the valuation.

A **publication timestamp** is the block timestamp at which the snapshot was
recorded.

A **terminal snapshot** is a snapshot whose `correctedByIndex` equals
`NO_CORRECTED_BY`.

A **current snapshot** is a terminal snapshot that has not been invalidated.

A **publication heartbeat** is the maximum accepted time since publication.

A **maximum valuation age** is the maximum accepted time since the valuation
timestamp.

### Sentinel Values

Implementations MUST use:

```solidity
uint256 constant NO_CORRECTION = type(uint256).max;
uint256 constant NO_CORRECTED_BY = 0;
```

`NO_CORRECTION` identifies an original snapshot. `NO_CORRECTED_BY` identifies a
snapshot with no successor correction.

Index zero is safe as the corrected-by sentinel because a correction index is
always greater than its target and therefore cannot be zero.

### Core Interface

A compliant oracle MUST implement:

```solidity
interface INAVSnapshotOracle {
    struct NAVSnapshot {
        bytes32 subjectId;
        bytes32 currency;
        bytes32 navBasis;
        int256 nav;
        uint8 decimals;
        uint64 valuationTimestamp;
        uint64 publishedAt;
        address provider;
        bytes32 methodologyHash;
        string methodologyURI;
        uint256 correctsIndex;
        uint256 correctedByIndex;
    }

    event NAVPublished(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        address indexed provider,
        uint256 snapshotIndex,
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        uint256 correctsIndex
    );

    event StalenessConfigUpdated(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        uint64 heartbeat,
        uint64 maxValuationAge
    );

    event NAVBasisConfigured(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        bytes32 navBasis
    );

    event NAVSnapshotInvalidated(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        address indexed provider,
        uint256 snapshotIndex,
        address invalidatedBy,
        bytes32 reasonHash
    );

    function publishNAV(
        bytes32 subjectId,
        bytes32 currency,
        bytes32 navBasis,
        int256 nav,
        uint8 decimals,
        uint64 valuationTimestamp,
        bytes32 methodologyHash,
        string calldata methodologyURI,
        uint256 correctsIndex
    ) external returns (uint256 snapshotIndex);

    function setNAVBasis(
        bytes32 subjectId,
        bytes32 currency,
        bytes32 navBasis
    ) external;

    function invalidateSnapshot(
        bytes32 subjectId,
        bytes32 currency,
        uint256 snapshotIndex,
        bytes32 reasonHash
    ) external;

    function isSnapshotInvalidated(
        bytes32 subjectId,
        bytes32 currency,
        uint256 snapshotIndex
    ) external view returns (bool);

    function setStalenessConfig(
        bytes32 subjectId,
        bytes32 currency,
        uint64 heartbeat,
        uint64 maxValuationAge
    ) external;

    function streamNAVBasis(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (bytes32 navBasis);

    function latestNAV(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        uint64 publishedAt,
        address provider
    );

    function latestNAVStatus(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        uint64 publishedAt,
        address provider,
        bool isPublishStale,
        bool isValuationStale
    );

    function getSnapshot(
        bytes32 subjectId,
        bytes32 currency,
        uint256 snapshotIndex
    ) external view returns (NAVSnapshot memory);

    function currentSnapshotIndex(
        bytes32 subjectId,
        bytes32 currency,
        uint256 snapshotIndex
    ) external view returns (uint256);

    function isSnapshotCurrent(
        bytes32 subjectId,
        bytes32 currency,
        uint256 snapshotIndex
    ) external view returns (bool);

    function snapshotCount(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (uint256);

    function latestNAVByProvider(
        bytes32 subjectId,
        bytes32 currency,
        address provider
    ) external view returns (NAVSnapshot memory);

    function providerSnapshotCount(
        bytes32 subjectId,
        bytes32 currency,
        address provider
    ) external view returns (uint256);

    function providerSnapshotAt(
        bytes32 subjectId,
        bytes32 currency,
        address provider,
        uint256 ordinal
    ) external view returns (uint256 snapshotIndex);

    function heartbeat(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (uint64);

    function maxValuationAge(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (uint64);
}
```

### Stream Scope

Snapshot indices MUST be zero-based and scoped independently to each
`(subjectId, currency)` stream.

This ERC does not require nonzero `subjectId` or `currency` values.
Applications requiring stricter namespaces MUST enforce and document them.

### NAV Basis

The following basis identifiers are defined:

```solidity
bytes32 constant PER_UNIT =
    keccak256("ERC-XXXX:NAV_BASIS:PER_UNIT");
bytes32 constant PER_SHARE =
    keccak256("ERC-XXXX:NAV_BASIS:PER_SHARE");
bytes32 constant TOTAL =
    keccak256("ERC-XXXX:NAV_BASIS:TOTAL");
```

`PER_UNIT` represents one unit of the underlying asset. `PER_SHARE` represents
one share or token in a fund or pool. `TOTAL` represents the total NAV of the
subject.

An authorized configurer MUST call `setNAVBasis` before the first publication
to a stream. The function MUST:

- accept only `PER_UNIT`, `PER_SHARE`, or `TOTAL`;
- reject a stream that already contains snapshots;
- reject a stream whose basis was already configured;
- store the basis permanently; and
- emit `NAVBasisConfigured`.

`streamNAVBasis` MUST return the configured basis or `bytes32(0)` for an
unconfigured stream.

`publishNAV` MUST reject an unconfigured stream and any supplied basis that
does not equal its configured basis.

Provider-selected basis changes are prohibited. Stream-level configuration
prevents incompatible submissions from disabling aggregation at a shared
valuation timestamp.

### NAV and Decimal Semantics

The represented NAV is:

```text
nav * 10^(-decimals)
```

`nav` is signed because liabilities can exceed assets. Consumers MUST handle
negative and zero values explicitly.

`publishNAV` MUST reject:

- `decimals > 18`;
- `nav == type(int256).min`; and
- a magnitude greater than:

```solidity
uint256(type(int256).max) / (10 ** uint256(18 - decimals))
```

This bound ensures that a conforming aggregation implementation can safely
normalize every accepted value to 18 decimal places.

### Currency Identifiers

The following fiat currency identifiers are defined:

```solidity
bytes32 constant USD = keccak256("ERC-XXXX:CURRENCY:USD");
bytes32 constant EUR = keccak256("ERC-XXXX:CURRENCY:EUR");
bytes32 constant GBP = keccak256("ERC-XXXX:CURRENCY:GBP");
bytes32 constant KES = keccak256("ERC-XXXX:CURRENCY:KES");
bytes32 constant ZMW = keccak256("ERC-XXXX:CURRENCY:ZMW");
```

Additional ISO 4217 currencies SHOULD use:

```text
keccak256("ERC-XXXX:CURRENCY:<CODE>")
```

Token-denominated streams SHOULD derive currency as:

```solidity
keccak256(
    abi.encodePacked(
        "ERC-XXXX:CURRENCY:TOKEN",
        chainId,
        tokenAddress
    )
)
```

Including both chain ID and token address prevents equal addresses on different
chains from sharing a currency identifier.

Other denominations SHOULD use an application-documented, domain-separated
identifier and MUST NOT reuse an ISO code unless the denomination is that fiat
currency.

### Publication Semantics

`publishNAV` MUST be restricted to authorized providers. Provider authorization
is implementation defined and MUST be documented.

For every accepted snapshot, the oracle MUST:

- set `provider` to `msg.sender`;
- set `publishedAt` to `uint64(block.timestamp)`;
- initialize `correctedByIndex` to `NO_CORRECTED_BY`;
- append the snapshot to the stream and provider history;
- update current-value and provider/timestamp indexes;
- emit `NAVPublished`; and
- return the new stream-scoped index.

`valuationTimestamp` MUST NOT be greater than `block.timestamp`.
`methodologyHash` MUST NOT be `bytes32(0)`.

`methodologyURI` MAY be empty only when the deployment documents how consumers
retrieve the exact methodology representation out of band. The hash derivation
MUST be documented. It MAY commit to raw document bytes or a deterministic
document-bundle commitment.

The oracle MUST reject the call if `block.timestamp` cannot be represented as
`uint64`.

### Provider and Valuation Uniqueness

A provider MAY publish at most one current original snapshot for an exact
stream and `valuationTimestamp`.

If that provider/timestamp slot is occupied, a revision MUST use correction
provenance. Other providers MAY publish independent originals for the same
stream and valuation timestamp.

### Correction Semantics

An original snapshot MUST use `correctsIndex == NO_CORRECTION`.

A correction MUST:

- identify an earlier snapshot in the same stream;
- target a terminal, non-invalidated snapshot;
- be published by the same provider as the target;
- use the same `valuationTimestamp` and `navBasis` as the target; and
- target the provider's current snapshot for that valuation timestamp.

When accepted, the target's `correctedByIndex` MUST be set to the new snapshot
index. No other target field may change.

Before invalidation, each snapshot can have at most one successor correction.
A correction can itself be corrected, creating a linear current chain. A
correction MAY change NAV, decimals, methodology, and methodology URI.

### Invalidation

`invalidateSnapshot` MUST be restricted under a documented administrative or
governance policy. It MUST reject a zero `reasonHash`, unknown snapshot,
nonterminal snapshot, or already invalidated snapshot.

On success, the oracle MUST:

- preserve the invalidated snapshot record;
- permanently mark it invalidated;
- exclude it from latest-value, provider-latest, current-chain, quorum,
  aggregation, and deviation calculations;
- recompute affected latest and quorum pointers; and
- emit `NAVSnapshotInvalidated`.

If an original snapshot is invalidated, its provider/timestamp slot MUST become
available for a replacement original.

If a correction is invalidated, its direct predecessor MUST become terminal
again and the provider/timestamp slot MUST point to that predecessor. The
provider can then publish a replacement correction.

In a longer correction chain, invalidating the terminal restores only its
direct predecessor. Administrators MAY unwind additional snapshots by
invalidating each newly restored terminal in turn.

Invalidation does not erase `correctsIndex` history. Replacement corrections
can create multiple historical records that reference the same predecessor,
but only one non-invalidated branch can be current. Consumers reconstructing
history MUST account for `NAVSnapshotInvalidated` events.

An invalidated snapshot MUST NOT be corrected or restored.

`isSnapshotInvalidated` MUST revert for an unknown index and otherwise return
the permanent invalidation state.

### Current-Chain Queries

`currentSnapshotIndex` MUST revert for an unknown index. It MUST follow
`correctedByIndex` to a terminal snapshot and return that index only if the
terminal is not invalidated. It MUST revert when no current terminal remains.

`isSnapshotCurrent` MUST revert for an unknown index and otherwise return
`true` only when the snapshot is terminal and not invalidated.

### Latest NAV Queries

`latestNAV` MUST return the current snapshot with the greatest
`valuationTimestamp`, regardless of staleness. When multiple current snapshots
share that valuation timestamp, it MUST return the most recently published one;
if publication timestamps are equal, the greater snapshot index wins.

A late correction to an older valuation timestamp MUST NOT replace a current
snapshot with a later valuation timestamp as the stream's latest NAV.

`latestNAV` MUST revert when no current snapshot exists.

`latestNAVByProvider` MUST apply the same valuation and publication ordering to
that provider's current snapshots and MUST revert when the provider has no
current snapshot.

### Historical Queries

`getSnapshot` MUST return the preserved record for any valid index, including a
corrected or invalidated snapshot, and MUST revert for an unknown index.

`snapshotCount` MUST include every published snapshot, including corrections
and invalidated records.

`providerSnapshotCount` and `providerSnapshotAt` MUST expose the provider's
complete publication history, including corrected and invalidated snapshots.
`providerSnapshotAt` MUST revert for an out-of-range ordinal.

### Staleness Configuration

An authorized configurer MUST be able to set a nonzero publication `heartbeat`
and nonzero `maxValuationAge` independently for each stream. Successful changes
MUST emit `StalenessConfigUpdated`.

`heartbeat` and `maxValuationAge` MUST return zero while the corresponding
value is unconfigured.

Configuration authorization is implementation defined and MUST be documented.

### Staleness Semantics

`latestNAVStatus` MUST return the same snapshot selected by `latestNAV` plus two
independent flags:

```text
isPublishStale = block.timestamp > publishedAt + heartbeat
isValuationStale =
    block.timestamp > valuationTimestamp + maxValuationAge
```

A value is not stale exactly at its threshold boundary.

`latestNAVStatus` MUST revert when either staleness threshold is unconfigured or
when no current snapshot exists. It MUST NOT mutate state or emit events.

Consumers MUST evaluate both flags. Recent publication of an old valuation can
be publication-fresh but valuation-stale.

### Aggregation Extension

Aggregation is OPTIONAL. An implementation supporting it MUST implement:

```solidity
interface INAVAggregation {
    event NAVDeviationDetected(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        uint64 valuationTimestamp,
        int256 minNav,
        int256 maxNav,
        uint256 deviationBps
    );

    event AggregationConfigUpdated(
        bytes32 indexed subjectId,
        bytes32 indexed currency,
        uint256 quorum,
        uint256 deviationThresholdBps
    );

    function setAggregationConfig(
        bytes32 subjectId,
        bytes32 currency,
        uint256 quorum,
        uint256 deviationThresholdBps
    ) external;

    function aggregatedNAV(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        uint256 providerCount,
        bool isPublishStale,
        bool isValuationStale
    );

    function providerSubmissionCount(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (uint256);

    function providerSubmissionAt(
        bytes32 subjectId,
        bytes32 currency,
        uint256 index
    ) external view returns (
        uint256 snapshotIndex,
        address provider,
        int256 nav,
        uint8 decimals,
        bytes32 navBasis,
        uint64 valuationTimestamp,
        uint64 publishedAt
    );

    function latestAggregationTimestamp(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (uint64);

    function quorum(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (uint256);

    function deviationThreshold(
        bytes32 subjectId,
        bytes32 currency
    ) external view returns (uint256);
}
```

### Aggregation Configuration

`setAggregationConfig` MUST be restricted to authorized configurers. It MUST
reject a zero quorum and a deviation threshold greater than 10,000 basis
points. Implementations MAY impose a documented maximum provider count and MUST
reject a quorum above that maximum.

Successful configuration MUST emit `AggregationConfigUpdated` and MUST account
for historical timestamps that already satisfy the new quorum.

`quorum` and `deviationThreshold` MUST return zero while unconfigured.

### Eligible Provider Submissions

For one valuation timestamp, at most one submission per provider is eligible.
That submission is the provider's current snapshot for the timestamp.
Corrected, invalidated, and detached historical snapshots MUST be excluded.

A valuation timestamp is aggregation-eligible when its number of eligible
providers is at least the configured quorum.

The latest aggregation timestamp MUST be the greatest eligible valuation
timestamp, not the timestamp of the most recent publication.

`latestAggregationTimestamp`, `providerSubmissionCount`,
`providerSubmissionAt`, and `aggregatedNAV` MUST revert when quorum is
unconfigured or no valuation timestamp meets quorum.

`providerSubmissionCount` MUST return the eligible provider count at the latest
aggregation timestamp.

`providerSubmissionAt` MUST return eligible submissions in provider first-seen
order for that timestamp and MUST revert when `index` is outside the eligible
set.

### Median Aggregation

`aggregatedNAV` MUST normalize all eligible values to the greatest submitted
decimal precision:

```text
normalizedNav = nav * 10^(maxDecimals - decimals)
```

It MUST sort normalized values in ascending order and return:

```text
values[(providerCount - 1) / 2]
```

This selects the lower median for an even provider count.

The returned basis MUST equal the configured stream basis. The returned
valuation timestamp MUST equal the latest aggregation timestamp. The returned
provider count MUST equal the number of eligible submissions.

For aggregate publication staleness, `publishedAt` MUST be treated as the
greatest publication timestamp among eligible submissions. Aggregate valuation
staleness uses the shared valuation timestamp.

`aggregatedNAV` MUST revert until both staleness thresholds are configured.

### Deviation Detection

After a successful publication at a valuation timestamp that meets quorum, the
non-view publication path MUST calculate:

```text
spread = maxNav - minNav
deviationBps = spread * 10_000 / abs(medianNav)
```

The calculation MUST account safely for signed values. If the spread is zero,
deviation is zero. If the median is zero while spread is nonzero, or if the
calculation would overflow, deviation MUST saturate at `type(uint256).max`.

When `deviationBps > deviationThresholdBps`, the oracle MUST emit
`NAVDeviationDetected` from the publication transaction. Equality does not
trigger the event.

Deviation events are alerts. They do not invalidate submissions or prevent
aggregation.

### ERC-165 Detection

Compliant core oracles MUST implement [ERC-165](./erc-165.md) and return `true`
for `type(INAVSnapshotOracle).interfaceId`.

Implementations supporting aggregation MUST also return `true` for
`type(INAVAggregation).interfaceId`.

ERC-165 indicates interface support only. It does not establish provider
credentials, NAV accuracy, methodology validity, liquidity, redemption rights,
or use of the oracle by a consuming contract.

## Rationale

### Why Key Streams by Subject and Currency?

A subject can be valued in multiple denominations. Treating each pair as an
independent stream removes ambiguity and permits separate history, staleness,
and aggregation configuration.

### Why Configure NAV Basis at Stream Level?

Per-unit, per-share, and total NAV differ materially. If providers can choose
basis independently, one mismatched submission can make a quorum set
incomparable or unavailable. Immutable stream-level basis configuration rejects
the mismatch before it enters the stream.

### Why Separate Valuation and Publication Timestamps?

A value can be published recently while describing an old valuation. Consumers
need both times to assess operational feed health and economic recency.

### Why Signed NAV?

Liabilities can exceed assets. A signed representation avoids silently
excluding insolvent or leveraged subjects, while consumers remain responsible
for handling nonpositive values safely.

### Why Corrections?

Valuations can be restated after administrator error, late information, audit
adjustments, or model changes. Correction links preserve the earlier assertion
and identify its successor.

### Why Administrative Invalidation?

Correction requires the original provider. If that provider is compromised,
revoked, or unavailable, a poisoned terminal snapshot could otherwise remain
current and continue to satisfy quorum. Invalidation excludes it without
deleting history and allows a valid replacement.

### Why Latest by Valuation Time?

A late correction for an older valuation should not displace a more recent
valuation as the stream's raw latest value. Period recency and publication
recency answer different questions.

### Why Lower-Median Aggregation?

Median aggregation resists a minority of extreme submissions. Selecting the
lower median for even sets makes the result deterministic without introducing
rounding between two signed values.

### Why Dual Staleness?

Publication heartbeat detects a feed that stopped updating. Maximum valuation
age detects publication of economically old data. Either condition can matter
independently.

### Prior Art

[ERC-7726](./erc-7726.md) defines a common quote interface returning the amount
of one asset in another asset's terms. This ERC defines historical NAV
snapshots with valuation timestamps, providers, methodology, corrections,
invalidation, and staleness metadata.

[ERC-4626](./erc-4626.md) defines tokenized vault accounting and conversion
functions. This ERC can provide an external valuation input but does not define
vault accounting, deposits, withdrawals, or redemption guarantees.

[ERC-7540](./erc-7540.md) extends ERC-4626 for asynchronous requests, and
[ERC-7575](./erc-7575.md) supports multi-asset vaults. Both may consume NAV but
do not define this provider-attributed snapshot lifecycle.

General market-price feeds often use heartbeat and deviation mechanisms for
liquid assets. This ERC applies separate publication and valuation age to
periodic NAV and exposes methodology and correction history.

## Backwards Compatibility

This ERC introduces new interfaces and does not modify existing token, vault,
oracle, or accounting standards.

Existing systems can deploy a companion oracle and map their asset or fund
identifier to `subjectId`. Integration is optional.

Vault integrations should not call `latestNAVStatus` or `aggregatedNAV` from
critical conversion paths unless configuration is guaranteed. These functions
revert when staleness configuration is absent. Adapters can validate and cache
an accepted NAV for non-reverting preview or conversion surfaces.

## Test Cases

Implementations should test at least:

- stream isolation by subject and currency;
- one-time known-basis configuration and publication-before-configuration
  rejection;
- rejection of provider basis mismatch;
- signed NAV, decimal, magnitude, and future-valuation bounds;
- methodology hash requirements and documented empty-URI behavior;
- provider/timestamp original uniqueness;
- correction provider, timestamp, basis, terminal, and latest-slot guards;
- correction-of-correction chains and current-state helpers;
- latest selection by valuation timestamp rather than publication order;
- provider history including corrected and invalidated records;
- publication and valuation staleness before, at, and after each boundary;
- staleness-aware query rejection while unconfigured;
- original and correction invalidation;
- predecessor restoration and replacement publication after invalidation;
- latest-provider, latest-stream, and quorum recomputation after invalidation;
- aggregation configuration and historical quorum discovery;
- provider caps and quorum limits;
- decimal normalization and lower-median selection;
- latest eligible valuation-timestamp selection;
- provider submission pagination and ordering;
- corrected and invalidated submission exclusion;
- deviation threshold, zero-median, and overflow saturation behavior;
- fiat and token currency derivation; and
- positive and negative ERC-165 detection.

## Reference Implementation

A Solidity reference implementation, constants library, unit tests, Medusa
property tests, deployment configuration, and independent audit are linked from
the official discussion thread.

The reference implementation:

- uses provider, configurer, and administrator roles;
- supports all core and aggregation functions in one contract;
- caps providers per valuation timestamp at 64;
- uses deterministic lower-median aggregation;
- emits deviation alerts from `publishNAV`; and
- recomputes affected indexes after administrative invalidation.

Role assignments and the provider cap are reference deployment choices. The
stream basis, correction, invalidation, staleness, and deterministic aggregation
semantics are requirements of this ERC.

## Security Considerations

### NAV Is Not an Executable Price

NAV is an accounting or valuation assertion. A token can trade above or below
NAV, and redemption can be gated, delayed, limited, or unavailable. Consumers
must not treat NAV as a liquid market price without separately validating
liquidity and redemption assumptions.

### Provider and Configurer Trust

A provider can publish fabricated or mistaken values and methodologies. A
configurer can choose unsafe staleness or quorum settings. Implementations must
document authorization, governance, upgrade, and key-management policies.

Revoking a provider role does not invalidate its existing snapshots. An
authorized invalidator must separately invalidate any snapshot that should no
longer participate in current queries.

### Methodology Verification

A methodology hash is useful only when consumers can obtain the committed
document representation and reproduce the hash. An empty or unavailable URI
can make independent verification impossible unless an out-of-band retrieval
process is documented.

### Staleness Enforcement

Staleness flags protect only consumers that check them. `latestNAV` deliberately
returns raw data without a staleness decision. Pricing and settlement paths
should use validated status or a controlled adapter.

### Negative and Zero NAV

Consuming contracts that assume positive NAV can underflow, divide by zero, or
misprice assets. They must define explicit behavior for zero and negative
values.

### Provider Collusion and Correlated Error

Median and quorum reduce single-provider influence but do not prevent collusion,
shared data-source failures, or common methodology errors. Address count does
not prove provider independence.

### Invalidation Authority and Cost

Invalidation can remove legitimate data and change latest or aggregate values.
The authority should be strongly controlled and every reason commitment should
be independently reviewable.

Recomputing latest and quorum pointers can require work proportional to stream
history. Production implementations with long histories should use bounded or
checkpointed indexing while preserving the specified results.

### Correction and Invalidation Interpretation

Invalidation can detach a historical correction and permit a replacement branch.
Consumers must combine correction pointers with invalidation state and events;
following `correctsIndex` alone does not identify the current branch.

### Front-Running Valuation Updates

Material NAV changes visible before inclusion can enable transactions against
an older accepted value. Deployments should consider private submission,
commit-reveal publication, settlement pauses, or delayed activation when the
economic risk justifies the complexity.

### Timestamp Dependence

Valuation timestamps are provider assertions, and staleness uses
`block.timestamp`. Block producers can influence timestamps within protocol
bounds. Consumers must account for this uncertainty.

### Decimal Normalization

Aggregation multiplies lower-precision signed values. Implementations must
enforce the numeric bounds in this ERC before normalization and use checked
arithmetic.

### Privacy and Commercial Sensitivity

Methodology URIs, valuation timing, and provider behavior can reveal sensitive
fund or asset information. Deployments should avoid publishing confidential
documents or predictable private references on public chains.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
