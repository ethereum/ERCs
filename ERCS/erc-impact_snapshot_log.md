---
eip: XXXX
title: Subject-Linked Impact Snapshot Log
description: Defines append-only subject-linked impact snapshots with correction provenance, methodology versioning, and attestations
author: Chris Turner, David Hay (@david-hay), Reagan Simpson (@krumg111), Collins Musyimi (@Musyimi97)
discussions-to: https://ethereum-magicians.org/t/subject-linked-impact-snapshot-log-candidate-erc/28938
status: Draft
type: Standards Track
category: ERC
created: 2026-07-05
requires: 165
---

## Abstract

This ERC defines an append-only interface for reporting quantitative impact
indicator snapshots against application-defined subjects. Each snapshot records
a signed value, decimal precision, unit, completed measurement period,
methodology commitment and location, reporter, recording time, and correction
provenance.

The core interface supports per-subject storage, per-indicator indexing, exact
period lookup, and fork-free correction chains. Optional interfaces support
append-only endorsement or dispute attestations and future methodology
supersession with active and pending methodology discovery.

This ERC standardizes representation and lifecycle behavior. It does not define
which indicators or methodologies are valid, verify reported measurements,
credential reporters or attestors, prevent overlapping claims, or provide an
impact score.

## Motivation

Impact measurements such as emissions, carbon offsets, renewable energy,
water treatment, employment, beneficiaries, biodiversity area, and diverted
waste are commonly distributed through reports and application-specific data
formats. On-chain systems lack a common interface for associating these values
with a subject, measurement period, unit, and methodology while preserving
later corrections.

A single mutable value cannot distinguish a new reporting period from a
restatement of an earlier measurement. It also erases the prior assertion when
updated. Generic attestations can represent individual claims but do not by
themselves define per-indicator time-series indexing, exact-period uniqueness,
correction chains, or methodology transitions.

This ERC provides:

- subject-linked, period-bounded quantitative snapshots;
- signed values with explicit decimals and units;
- one original snapshot per exact subject, indicator, and period;
- additive, fork-free corrections;
- per-indicator iteration and exact-period current-state lookup;
- required methodology commitments and retrieval references;
- optional append-only endorsement and dispute attestations; and
- optional active and scheduled methodology version discovery.

The interfaces can be deployed independently of any token, registry, identity,
or accounting system.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT",
"SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and
"OPTIONAL" in this document are to be interpreted as described in
[RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Definitions

A **subject** is an application-defined entity identified by `subjectId`.

An **indicator** is an application-defined measured quantity identified by
`indicatorId`.

A **snapshot** is one reported value for an indicator, subject, and measurement
period.

A **measurement period** is the half-open interval `[periodStart, periodEnd)`.

An **original snapshot** is the first snapshot occupying an exact subject,
indicator, and period slot.

A **correction chain** is a linear sequence of snapshots connected by
`correctsIndex` and `correctedByIndex`.

A **terminal snapshot** is a snapshot whose `correctedByIndex` equals zero.

A **methodology** is the documented process used to measure or calculate a
reported value.

An **attestation** is an append-only endorsement or dispute attached to a
specific snapshot.

### Sentinel Value

Implementations MUST use:

```solidity
uint256 constant NO_CORRECTION = type(uint256).max;
```

`correctsIndex == NO_CORRECTION` identifies an original snapshot.
`correctedByIndex == 0` identifies a snapshot with no successor correction.

Index zero is safe as the corrected-by sentinel because every correction index
is greater than the snapshot it corrects and therefore cannot be zero.

### Core Snapshot Interface

A compliant log MUST implement:

```solidity
interface IImpactSnapshotLog {
    struct IndicatorSnapshot {
        bytes32 subjectId;
        bytes32 indicatorId;
        int256 value;
        uint8 decimals;
        bytes32 unit;
        uint64 periodStart;
        uint64 periodEnd;
        bytes32 methodologyHash;
        string methodologyURI;
        address reportedBy;
        uint64 reportedAt;
        uint256 correctsIndex;
        uint256 correctedByIndex;
    }

    event SnapshotRecorded(
        bytes32 indexed subjectId,
        bytes32 indexed indicatorId,
        uint256 indexed snapshotIndex,
        int256 value,
        uint8 decimals,
        bytes32 unit,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 methodologyHash,
        uint256 correctsIndex,
        address reportedBy
    );

    function recordSnapshot(
        bytes32 subjectId,
        bytes32 indicatorId,
        int256 value,
        uint8 decimals,
        bytes32 unit,
        uint64 periodStart,
        uint64 periodEnd,
        bytes32 methodologyHash,
        string calldata methodologyURI,
        uint256 correctsIndex
    ) external returns (uint256 snapshotIndex);

    function getSnapshot(
        bytes32 subjectId,
        uint256 snapshotIndex
    ) external view returns (IndicatorSnapshot memory);

    function snapshotCount(
        bytes32 subjectId
    ) external view returns (uint256);

    function indicatorSnapshotCount(
        bytes32 subjectId,
        bytes32 indicatorId
    ) external view returns (uint256);

    function indicatorSnapshotAt(
        bytes32 subjectId,
        bytes32 indicatorId,
        uint256 ordinal
    ) external view returns (uint256 snapshotIndex);

    function latestIndicatorSnapshot(
        bytes32 subjectId,
        bytes32 indicatorId
    ) external view returns (uint256 snapshotIndex);

    function currentSnapshotForPeriod(
        bytes32 subjectId,
        bytes32 indicatorId,
        uint64 periodStart,
        uint64 periodEnd
    ) external view returns (uint256 snapshotIndex);
}
```

### Value, Decimal, and Unit Semantics

The represented quantity is:

```text
value * 10^(-decimals)
```

`value` is signed because an impact measurement can be negative. This ERC does
not impose a maximum decimal precision below the `uint8` type limit. Consumers
MUST handle the declared precision safely and MUST NOT assume the value is
nonnegative.

`unit` SHOULD be the `keccak256` hash of a documented canonical unit string.
Applications SHOULD use SI or UCUM-compatible representations when available
and MUST document exact case, spelling, pluralization, and conversion rules for
custom or zero-valued unit identifiers.

This ERC does not require a nonzero `subjectId`, `indicatorId`, or `unit`.
Applications requiring stricter namespaces MUST enforce and document them.

### Measurement Periods

`periodStart` is inclusive and `periodEnd` is exclusive.

`recordSnapshot` MUST revert unless:

```text
periodStart < periodEnd <= block.timestamp
```

Only completed measurement periods can be recorded.

An exact period slot is identified by `(subjectId, indicatorId, periodStart,
periodEnd)`. A log MUST accept at most one original snapshot for an exact slot.
Once occupied, revisions to that slot MUST use correction provenance.

Different periods MAY overlap. This ERC does not determine whether overlapping
measurements are additive, duplicative, or methodologically compatible.

### Recording Semantics

Snapshot indices MUST be zero-based and scoped per `subjectId`. The returned
`snapshotIndex` MUST equal the subject's snapshot count before the new snapshot
is appended.

`recordSnapshot` MUST be restricted to authorized reporters. The authorization
mechanism is implementation defined and MUST be documented.

For every accepted snapshot, the log MUST:

- store the supplied snapshot fields;
- set `reportedBy` to `msg.sender`;
- set `reportedAt` to `uint64(block.timestamp)`;
- initialize `correctedByIndex` to zero;
- append the snapshot index to the indicator-specific index;
- make the snapshot discoverable for its exact period; and
- emit `SnapshotRecorded`.

`methodologyHash` MUST NOT be `bytes32(0)`, and `methodologyURI` MUST NOT be
empty.

The methodology hash MUST be `keccak256` of the exact methodology document
bytes under a documented representation. Consumers MUST retrieve the document
and reproduce the commitment before relying on it.

### Correction Semantics

An original snapshot MUST use `correctsIndex == NO_CORRECTION`.

A correction MUST:

- identify an earlier snapshot under the same `subjectId`;
- use the same `indicatorId`, `periodStart`, and `periodEnd` as its target;
- target a snapshot whose `correctedByIndex` is zero; and
- be authorized under the implementation's documented correction policy.

When a correction is accepted, the log MUST set the target snapshot's
`correctedByIndex` to the new snapshot index. No other target field may change.

Each snapshot can be corrected at most once, preventing forks. A correction
snapshot can itself be corrected, producing a linear chain.

The correction policy MUST NOT permit an ordinary reporter to correct another
reporter's snapshot merely because both addresses can report. It MAY authorize
the original reporter, a designated corrector, or an administrator.

A correction MAY change `value`, `decimals`, `unit`, methodology, and reporter,
subject to the active methodology rules of an implementation supporting the
methodology extension.

### Snapshot Queries

`getSnapshot` MUST return the complete stored snapshot and MUST revert when
`snapshotIndex >= snapshotCount(subjectId)`.

`snapshotCount` MUST return the number of snapshots recorded for a subject.

`indicatorSnapshotCount` MUST return the number of snapshots recorded for an
exact subject and indicator, including corrections.

`indicatorSnapshotAt` MUST return the per-subject snapshot index at the
specified zero-based indicator ordinal and MUST revert when the ordinal is
outside the indicator-specific index.

`latestIndicatorSnapshot` MUST return the most recently recorded snapshot
index for the indicator and MUST revert when none exists. It describes
recording order, not the greatest `periodEnd`, and does not necessarily identify
the current value for a particular period.

`currentSnapshotForPeriod` MUST return the terminal snapshot index for the
exact subject, indicator, `periodStart`, and `periodEnd`. It MUST revert when no
snapshot occupies that period slot.

Consumers querying a specific reporting period SHOULD use
`currentSnapshotForPeriod` rather than `latestIndicatorSnapshot`.

### Indicator Identifiers

The following indicator identifiers are defined:

```solidity
bytes32 constant CARBON_OFFSET =
    keccak256("ERC-XXXX:INDICATOR:CARBON_OFFSET");
bytes32 constant CARBON_EMITTED =
    keccak256("ERC-XXXX:INDICATOR:CARBON_EMITTED");
bytes32 constant ENERGY_GENERATED =
    keccak256("ERC-XXXX:INDICATOR:ENERGY_GENERATED");
bytes32 constant ENERGY_SAVED =
    keccak256("ERC-XXXX:INDICATOR:ENERGY_SAVED");
bytes32 constant WATER_TREATED =
    keccak256("ERC-XXXX:INDICATOR:WATER_TREATED");
bytes32 constant JOBS_CREATED =
    keccak256("ERC-XXXX:INDICATOR:JOBS_CREATED");
bytes32 constant BENEFICIARIES =
    keccak256("ERC-XXXX:INDICATOR:BENEFICIARIES");
bytes32 constant BIODIVERSITY_AREA =
    keccak256("ERC-XXXX:INDICATOR:BIODIVERSITY_AREA");
bytes32 constant WASTE_DIVERTED =
    keccak256("ERC-XXXX:INDICATOR:WASTE_DIVERTED");
```

Custom indicators SHOULD use:

```text
keccak256("ERC-XXXX:INDICATOR:<NAMESPACE>:<NAME>:<VERSION>")
```

Applications MUST document indicator definitions, boundaries, calculation
rules, and any mapping to external taxonomies. A generic identifier such as
`keccak256("CUSTOM")` SHOULD NOT be used because it does not provide semantic
separation.

### Unit Identifiers

The following unit identifiers are defined:

```solidity
bytes32 constant UNIT_TCO2E = keccak256("tCO2e");
bytes32 constant UNIT_KWH = keccak256("kWh");
bytes32 constant UNIT_M3 = keccak256("m3");
bytes32 constant UNIT_FTE = keccak256("FTE");
bytes32 constant UNIT_PERSONS = keccak256("persons");
bytes32 constant UNIT_HECTARES = keccak256("hectares");
bytes32 constant UNIT_TONNES = keccak256("tonnes");
```

The defined indicator identifiers do not mandate one unit. Reporters and
consumers MUST inspect the stored unit and methodology rather than inferring a
unit from `indicatorId` alone.

### Attestation Extension

Attestation is OPTIONAL. An implementation supporting it MUST implement:

```solidity
interface IImpactAttestation {
    struct Attestation {
        address attestor;
        bool endorsed;
        bytes32 evidenceHash;
        string evidenceURI;
        uint64 attestedAt;
    }

    event SnapshotAttested(
        bytes32 indexed subjectId,
        uint256 indexed snapshotIndex,
        address indexed attestor,
        bool endorsed,
        bytes32 evidenceHash,
        uint256 attestationIndex
    );

    function attestSnapshot(
        bytes32 subjectId,
        uint256 snapshotIndex,
        bool endorsed,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external returns (uint256 attestationIndex);

    function attestationCount(
        bytes32 subjectId,
        uint256 snapshotIndex
    ) external view returns (uint256);

    function getAttestation(
        bytes32 subjectId,
        uint256 snapshotIndex,
        uint256 attestationIndex
    ) external view returns (Attestation memory);
}
```

`attestSnapshot` MUST reject an unknown snapshot and a zero `evidenceHash`.
`evidenceURI` MAY be empty.

The implementation MUST set `attestor` to `msg.sender`, set `attestedAt` to
`uint64(block.timestamp)`, append the attestation, emit `SnapshotAttested`, and
return its zero-based per-snapshot index.

The reporter address stored on the snapshot MUST NOT attest that snapshot.
This is address-level separation only; it does not establish organizational,
affiliate, financial, or legal independence.

Attestations MUST be immutable and non-deletable. The same attestor MAY submit
multiple attestations for the same snapshot, including a later assessment that
differs from an earlier one. Consumers MUST evaluate the complete history.

Attestations MAY be added to corrected or nonterminal snapshots. Consumers MUST
decide whether an attestation to an earlier snapshot applies to any correction.
This ERC does not carry attestations forward automatically.

Attestor authorization and credentialing are implementation defined and MUST
be documented.

`attestationCount` MUST return the number of attestations for the exact snapshot.
`getAttestation` MUST return the requested record and MUST revert when the
attestation index is outside that snapshot's history.

### Methodology Versioning Extension

Methodology versioning is OPTIONAL. An implementation supporting it MUST
implement:

```solidity
interface IMethodologyVersioning {
    event MethodologySuperseded(
        bytes32 indexed subjectId,
        bytes32 indexed indicatorId,
        bytes32 oldMethodologyHash,
        bytes32 newMethodologyHash,
        uint256 effectiveFromOrdinal
    );

    function supersedeMethodology(
        bytes32 subjectId,
        bytes32 indicatorId,
        bytes32 oldMethodologyHash,
        bytes32 newMethodologyHash,
        string calldata newMethodologyURI,
        uint256 effectiveFromOrdinal
    ) external;

    function activeMethodology(
        bytes32 subjectId,
        bytes32 indicatorId
    ) external view returns (
        bytes32 methodologyHash,
        string memory methodologyURI
    );

    function pendingMethodology(
        bytes32 subjectId,
        bytes32 indicatorId
    ) external view returns (
        bytes32 newMethodologyHash,
        string memory newMethodologyURI,
        uint256 effectiveFromOrdinal,
        bool pending
    );
}
```

### Methodology Initialization and Enforcement

The first snapshot for a subject and indicator MUST initialize its active
methodology to the snapshot's `methodologyHash` and `methodologyURI`.

After initialization, each new snapshot for that subject and indicator MUST use
the methodology hash active at its indicator-specific ordinal.

The snapshot's `methodologyURI` MUST remain nonempty, but this ERC does not
require it to equal the URI returned by `activeMethodology`. Multiple locators
can reference the same committed methodology bytes. Consumers MUST verify the
retrieved bytes against the active hash.

`activeMethodology` MUST return the methodology required for the next snapshot.
Before initialization, it MUST return `bytes32(0)` and an empty URI.

### Methodology Supersession

`supersedeMethodology` MUST be restricted under a documented authorization
policy and MUST revert unless:

- a methodology has already been initialized;
- `oldMethodologyHash` equals the active methodology;
- `newMethodologyHash` is nonzero;
- `newMethodologyURI` is nonempty;
- no future supersession is already pending; and
- `effectiveFromOrdinal` is greater than or equal to the current
  `indicatorSnapshotCount`.

If `effectiveFromOrdinal` equals the current indicator count, the new
methodology becomes active immediately for the next snapshot.

If it is greater than the current count, the supersession is pending. Existing
snapshots and snapshots before the effective ordinal continue to use the old
methodology. The new methodology becomes active when the current indicator
count reaches `effectiveFromOrdinal`.

Every successful supersession MUST emit `MethodologySuperseded`. Existing
snapshot fields MUST NOT change.

Implementations MAY impose a documented maximum future lookahead.

### Pending Methodology Discovery

While a future supersession has not reached its effective ordinal,
`pendingMethodology` MUST return the scheduled hash, URI, ordinal, and
`pending == true`.

When no supersession is scheduled, or once its effective ordinal has been
reached, it MUST return `bytes32(0)`, an empty URI, zero, and `false`.

Once the ordinal has been reached, `activeMethodology` MUST expose the new
methodology even if no state-changing call has yet persisted an internal
transition.

Historical values recalculated under a new methodology MUST be submitted as
corrections. They MUST NOT mutate existing snapshots.

### ERC-165 Detection

Compliant core logs MUST implement [ERC-165](./erc-165.md) and return `true`
for `type(IImpactSnapshotLog).interfaceId`.

Implementations supporting optional extensions MUST also return `true` for the
corresponding `IImpactAttestation` and `IMethodologyVersioning` interface IDs.

ERC-165 indicates interface support only. It does not establish measurement
accuracy, methodology validity, reporter or attestor credentials, evidence
quality, or independence.

## Rationale

### Why Append-Only Snapshots?

Impact data changes through new periods, corrected measurements, and revised
methodologies. Append-only storage preserves each assertion and makes revisions
visible instead of replacing history.

### Why One Original Per Exact Period?

Allowing multiple unrelated originals for the same indicator and exact period
would create competing current values. Requiring later revisions to use
correction provenance provides one resolvable chain.

### Why Permit Overlapping Periods?

Monthly, quarterly, annual, project-phase, and rolling measurements can
legitimately overlap. The interface cannot determine whether an overlap is
valid. Consumers aggregating values must apply methodology-specific rules to
avoid double counting.

### Why Use `int256`?

Measurements can be negative. Net emissions, energy savings relative to a
baseline, or other indicators can move in either direction.

### Why Both Latest and Period-Specific Queries?

The most recently recorded snapshot can concern an old period, such as a late
correction. `latestIndicatorSnapshot` supports monitoring recording activity,
while `currentSnapshotForPeriod` resolves the current value for an exact
period.

### Why Require Methodology Metadata?

A value and unit are insufficient without the process that produced them.
Requiring both a commitment and a retrieval reference makes the declared
methodology independently verifiable when the document remains available.

### Why Methodology Versioning as an Extension?

Some deployments need only immutable per-snapshot methodology references.
Others require a governed active methodology for future reports. Separating the
extension allows the core log to remain usable without prescribing methodology
governance.

### Why Attestation as an Extension?

Not every deployment requires endorsement or dispute records. The optional
interface permits independent assessment histories without making credential
policy part of the core snapshot log.

### Why Not Replace Earlier Attestations?

An attestor's changed view is itself relevant history. Appending the later
assessment preserves both statements and lets consumers apply their own
recency and credential policies.

### Prior Art

[ERC-7512](./erc-7512.md) defines on-chain audit-report representation. This ERC
defines quantitative, period-bounded indicator time series with corrections and
methodology lifecycle semantics.

[ERC-5851](./erc-5851.md) defines on-chain verifiable credentials. Credentials
can support reporter or attestor authorization but do not define this snapshot
model.

Generic attestation systems can represent impact claims through custom schemas.
This ERC defines a dedicated storage and query interface for indicator periods,
correction chains, methodology transitions, and snapshot-specific assessment
histories.

Impact-certificate systems can represent broad claims, evaluations, or funding
relationships. This ERC is narrower: it standardizes subject-linked
quantitative snapshots and their lifecycle rather than ownership of an impact
claim.

Carbon-credit token systems represent issuance, transfer, and retirement of
specific environmental assets. This ERC does not tokenize credits or prevent a
reported measurement from being claimed elsewhere.

## Backwards Compatibility

This ERC introduces new interfaces and does not modify existing token,
registry, credential, attestation, or accounting standards.

An existing application can deploy a companion snapshot log and use its own
application-defined subject namespace. No token contract changes are required
unless the token itself records snapshots.

Implementations can adopt only the core interface or additionally expose either
optional extension. Consumers use ERC-165 to detect supported interfaces.

## Test Cases

Implementations should test at least:

- zero-based per-subject indexing and subject isolation;
- per-indicator counts, ordinals, and latest-recorded lookup;
- completed, zero-length, and future period validation;
- positive, zero, and negative values with varying decimals;
- methodology hash and URI requirements;
- one original per exact period;
- overlapping but nonidentical periods;
- correction bounds, authorization, period matching, and fork prevention;
- multi-step correction chains and exact-period terminal lookup;
- methodology initialization and active-methodology enforcement;
- immediate and future methodology supersession;
- pending methodology hash, URI, ordinal, and activation discovery;
- pending-supersession exclusivity and implementation lookahead limits;
- attestation evidence requirements and empty evidence URIs;
- same-address self-attestation rejection;
- repeated endorsement and dispute histories;
- attestations to current and corrected snapshots;
- unknown snapshot and attestation queries; and
- positive and negative ERC-165 detection for every supported interface.

## Reference Implementation

A Solidity reference implementation, constants library, example integrations,
unit tests, Medusa property tests, deployment scripts, and independent audit are
linked from the official discussion thread.

The reference implementation:

- uses reporter, attestor, and administrator roles;
- allows a reporter to correct its own snapshot and an administrator-reporter
  to correct another reporter's snapshot;
- rejects completed-period duplicates unless correction provenance is used;
- implements all three interfaces;
- blocks same-address self-attestation; and
- limits scheduled methodology supersession to 1,000 future indicator
  ordinals.

Role assignments and the 1,000-ordinal lookahead are reference deployment
choices rather than core interface requirements.

## Security Considerations

### Reporter Trust

The log proves that an authorized address reported a value. It does not verify
the measurement, source data, calculation, unit, period boundaries, or
methodology application. False data remains false when recorded immutably.

### Methodology Integrity and Availability

A methodology commitment is useful only when consumers can obtain the exact
document representation and reproduce its hash. A URI can disappear, change
content, require authorization, or expose sensitive information. Deployments
should use durable storage and document the hashing representation.

### Methodology Governance

An authorized party can supersede a methodology with one that produces more
favorable results. Events and pending-methodology queries make the transition
visible but do not establish its legitimacy. Consumers must evaluate
methodology governance independently.

### Correction Authorization and Chain Length

A weak correction policy can let one reporter supersede another's measurement.
Implementations must document correction authority.

Period lookup traverses correction pointers. Although chains are linear and
acyclic, excessive corrections can make on-chain resolution expensive.

### Attestor Credentials and Independence

Blocking the exact reporter address prevents only direct self-attestation. The
same organization can control multiple addresses, and an attestor role does not
prove professional qualification, financial independence, or legal authority.
Consumers must evaluate credential and conflict policies.

### Conflicting Attestations

The interface permits multiple endorsements and disputes without computing a
consensus result. Counting addresses is not a reliable trust model because
addresses are cheap and credentials can differ. Consumers need an external
attestor-selection and weighting policy.

### Double Counting and Overlapping Claims

Exact-period uniqueness applies only within one subject and indicator slot.
Overlapping periods, related indicators, multiple subjects, and independent
registries can represent the same underlying impact. Consumers must reconcile
boundaries and methodologies before aggregation.

### Privacy

Subjects, values, periods, methodology URIs, and attestation evidence can reveal
commercial, personal, geographic, or site-sensitive information. Public-chain
deployments should use opaque subject identifiers, redacted documents, and
access-controlled evidence distribution where appropriate. Hashing low-entropy
sensitive data without a secret salt does not provide meaningful privacy.

### Unit and Decimal Handling

Consumers that ignore units, decimals, sign, or conversion rules can produce
materially incorrect aggregates. Implementations should use checked arithmetic,
explicit normalization, and methodology-aware conversion.

### Timestamp Dependence

Completed-period validation uses `block.timestamp`, which block producers can
influence within protocol bounds. Applications requiring exact wall-clock
cutoffs must account for that uncertainty.

### Storage Growth

Snapshots and attestations are append-only. Authorization, reporting-frequency
policy, and operational monitoring are necessary to control storage costs and
spam.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
