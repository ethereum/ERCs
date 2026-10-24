---
eip: 99903
title: Agent Default Registry
description: Lender-reported loan defaults of agent identities, countable on chain against trusted reporters
author: Priors contributors (@priors-agents)
discussions-to: https://ethereum-magicians.org/t/erc-tba-agent-default-registry/30026
status: Draft
type: Standards Track
category: ERC
created: 2026-10-20
requires: 165, 721
---

## Abstract

This proposal defines one contract where lenders record the defaults of loans they made to identities of an
[ERC-721](./eip-721.md) identity registry, such as the Identity Registry of [ERC-8004](./eip-8004.md). Each record names
the identity, the owner address the loan recorded, the asset, the principal and the lender's reference to the loan, and
can later be marked cured with the amount recovered, or voided within a short window if it was made by mistake. A lender
that reports from several addresses names one of them its primary, and its records count under that primary. Anyone may
record, and a record counts only for a reader that trusts the primary it is stored under: a contract asks how many open,
cured and still provisional defaults an identity, or an owner address, has according to the lenders it names, at a cost
that grows with that list alone.

## Motivation

A loan that was not repaid is the strongest signal a lender has about a borrower, and today it stays with the lender
that saw it. An agent that defaults with one lender can borrow from the next, and an owner whose agent defaulted can
borrow through another identity. Reputation systems that average scores, or that keep one latest assertion per issuer,
cannot answer the question a lender asks before it lends: how many loans did this identity, or this owner, fail to
repay, according to lenders I trust.

Lenders also need the answer on chain, inside the transaction that opens a line, so the record has to be a contract read
with a bounded cost, not a file to fetch and parse.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT
RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

A registry MUST implement `IAgentDefaultRegistry` and [ERC-165](./eip-165.md), returning `true` for the interface
identifier of `IAgentDefaultRegistry` and for `0x01ffc9a7`.

```solidity
interface IAgentDefaultRegistry {
    struct DefaultRecord {
        address reporter;
        address primary;
        uint256 agentId;
        address owner;
        address asset;
        uint256 principal;
        bytes32 loanRef;
        uint64 recordedAt;
        uint64 curedAt;
        uint64 voidedAt;
        uint256 recovered;
    }

    event DefaultRecorded(uint256 indexed recordId, address indexed reporter, uint256 indexed agentId, address primary, address owner, address asset, uint256 principal, bytes32 loanRef);
    event DefaultCureRecorded(uint256 indexed recordId, address indexed reporter, uint256 recovered);
    event DefaultVoided(uint256 indexed recordId, address indexed by);
    event PrimaryProposed(address indexed reporter, address indexed primary);
    event PrimarySet(address indexed reporter, address indexed primary);

    function identityRegistry() external view returns (address);
    function voidWindow() external view returns (uint64);
    function primaryOf(address reporter) external view returns (address);
    function setPrimary(address primary) external;
    function acceptPrimary(address reporter) external;
    function dropReporter(address reporter) external;
    function recordDefault(uint256 agentId, address owner, address asset, uint256 principal, bytes32 loanRef) external returns (uint256 recordId);
    function recordCure(uint256 recordId, uint256 recovered) external;
    function voidRecord(uint256 recordId) external;
    function getRecord(uint256 recordId) external view returns (DefaultRecord memory);
    function agentDefaults(uint256 agentId, address[] calldata trustedPrimaries) external view returns (uint256 open, uint256 cured, uint256 provisional);
    function ownerDefaults(address owner, address[] calldata trustedPrimaries) external view returns (uint256 open, uint256 cured, uint256 provisional);
    function recordsOfAgent(uint256 agentId, uint256 start, uint256 limit) external view returns (uint256[] memory);
    function recordsOfOwner(address owner, uint256 start, uint256 limit) external view returns (uint256[] memory);
}
```

### Primaries

A lender may report from several addresses (its contracts, a servicer). It names one address its primary, and readers
list it by that primary.

- `primaryOf(reporter)` MUST return the address `reporter`'s new records are stored under: the primary it set and that
  accepted, or `reporter` itself if there is none.
- `setPrimary(primary)` with any other address than the zero address or the caller MUST record a proposal and emit
  `PrimaryProposed`; it MUST NOT change `primaryOf(caller)`. With the zero address or the caller itself, it MUST make
  the caller its own primary at once, drop any proposal, and emit `PrimarySet(caller, caller)`.
- `acceptPrimary(reporter)` MUST revert unless the caller is the address `reporter` last proposed. It MUST then make the
  caller `reporter`'s primary, drop the proposal, and emit `PrimarySet(reporter, caller)`.
- `dropReporter(reporter)` MUST revert unless the caller is `reporter`'s primary. It MUST then make `reporter` its own
  primary again and emit `PrimarySet(reporter, reporter)`.
- A primary is one level: a primary's own primary is not followed.
- Records already written MUST NOT move when a primary changes: each record keeps the primary it was stored under.

### Records

- `identityRegistry()` MUST return the ERC-721 contract the `agentId` values refer to, and MUST NOT change.
- `recordDefault` MUST be callable by any account; the caller is the record's `reporter`, and `primaryOf(caller)` at
  that moment is the record's `primary`. It MUST revert if `owner` is the zero address, if `principal` is zero, if
  `loanRef` is zero, or if a record under the same primary with the same `loanRef` exists and is not voided. It MUST
  store the record with `recordedAt` set to the block timestamp and `curedAt`, `voidedAt` and `recovered` set to zero,
  give it a `recordId` that is not zero and is never reused, emit `DefaultRecorded`, and return the id.
- `owner` MUST be the address the defaulted loan recorded as the identity's owner when the loan was drawn, not the
  current owner. A reporter MUST NOT record any other address. A reader can check it: a lender implementing Agent Credit
  Lines records the owner on each loan when it is drawn, and the identity registry's `Transfer` logs give the owner at
  any block.
- `loanRef` is the reporter's reference to the loan. A reporter SHOULD use
  `keccak256(abi.encode(chainId, lendingContract, loanId))`, so that a loan has the same reference whichever of a
  lender's addresses records it, and readers can find the loan's own logs.
- `asset` is the token lent; `principal` is in its base units.
- `voidWindow()` MUST return the number of seconds after `recordedAt` during which a record can be voided. It MUST NOT
  change, and SHOULD be between one and seven days.
- `recordCure(recordId, recovered)` MUST revert unless called by the record's reporter or its primary, and MUST revert
  if the record does not exist, is cured, or is voided. It MUST set `curedAt` to the block timestamp and `recovered` to
  the amount given, and emit `DefaultCureRecorded`.
- `voidRecord(recordId)` MUST revert unless called by the record's reporter or its primary, and MUST revert if the
  record does not exist, is cured, is voided, or if `recordedAt + voidWindow()` is not after the block timestamp. It
  MUST set `voidedAt` to the block timestamp, make the record's `loanRef` free again under its primary, and emit
  `DefaultVoided`.
- A record MUST NOT change in any other way, and MUST NOT be deleted.
- `getRecord` MUST revert for an id that was never issued.

### Counting

- `agentDefaults(agentId, trustedPrimaries)` MUST return how many records of `agentId` are stored under the listed
  addresses as their `primary`, without voided records, split three ways: `provisional`, those not cured whose
  `recordedAt + voidWindow()` is after the block timestamp; `open`, the other ones not cured; and `cured`.
  `ownerDefaults(owner, trustedPrimaries)` MUST do the same for records whose `owner` is `owner`.
- An address listed more than once MUST be counted once. Records stored under addresses not listed MUST NOT be counted.
- The cost of a count MUST NOT grow with the number of records stored under addresses that are not listed.
  Implementations keep counts per primary for this reason.

### Listing

`recordsOfAgent` and `recordsOfOwner` MUST return record ids in the order they were recorded, starting at position
`start` and returning at most `limit` ids, and an empty list when `start` is at or past the end.

## Rationale

- **Anyone records, readers choose.** A registry that vets lenders needs an owner and becomes a gatekeeper. Letting
  anyone record and making every count take the reader's list of reporters puts trust where it already is: each lender
  decides whose defaults it believes, as readers of [ERC-8004](./eip-8004.md) feedback choose their clients.
- **Counts, not scores.** Lenders weigh defaults differently; a count of open and cured defaults per trusted reporter is
  what any score is computed from, and it cannot be argued over.
- **By identity and by owner.** An identity can change hands, and an owner can hold many identities. A default is a fact
  about both: the identity that borrowed and the address that answered for it when it borrowed.
- **Per-reporter counts.** Since anyone can record, anyone can add thousands of records to an identity. A lender's
  check runs inside the transaction that opens a line, so its cost has to depend on the lender's own list, not on what
  others recorded.
- **Cures, never deletions.** A default that was later recovered is still a default; a reader decides how much a cure
  is worth. A reporter cannot erase a record, so a reader can rely on what it saw.
- **One record per loan per primary.** The loan reference stops a lender from inflating counts by recording the same
  loan twice, from one address or from several, once they share a primary. A registry-wide reference is not an option:
  anyone may record, so a griefer could take a lender's reference first. Two unrelated lenders can still record the
  same loan; a reader lists each lender once, by its primary.
- **The primary is stored with the record.** Resolving it when the record is written means a later link, or a move to
  another primary, never shifts the counts readers already saw, and recording first and linking afterwards cannot get
  around the one-record-per-loan rule. The primary has to accept, or anyone could place its own records under a lender's
  primary; and it can drop an address, so that a compromised reporting key stops writing under its name.
- **Voids inside a short window.** "Defaulted and repaid" is the wrong state for a record that should never have been
  written, and the difference matters once lenders price cured counts. A void is final, keeps the record and its
  history, and frees the loan reference so that the correct record can be written. After the window only a cure is
  possible, so a reporter cannot be paid later to erase a default that readers relied on. While a record can still be
  voided, counts report it apart, as provisional: a reporter could record and void inside the window to dent an
  identity's count while another lender checks it, and the checking lender decides whether to count it.
- **Cures by the lender only.** A cure recorded by the identity's owner would need a signature binding the registry, the
  chain, the record and the amount, and [ERC-1271](./eip-1271.md) for lenders that are contracts, for a call the lender
  can make itself. A record's reporter, or the primary it is stored under, records the cure.

## Backwards Compatibility

No backward compatibility issues found. Lenders whose contracts cannot call the registry record from an address they
control and publish that address as their reporter.

## Test Cases

A conforming registry passes these cases:

- A record by reporter A for identity 6592 and owner O gets id 1 with `primary` A, emits `DefaultRecorded`, and is
  returned whole by `getRecord(1)` and listed by `recordsOfAgent(6592, 0, 10)` and `recordsOfOwner(O, 0, 10)`.
- A recording reverts for a zero owner, a zero principal or a zero loan reference, and for a loan reference already
  recorded under the same primary; an unrelated reporter B may record the same loan reference.
- Once the window has passed, with records by A, B and a third reporter for one identity, `agentDefaults` with `[A]`
  returns one open default, with `[A, B]` two, with `[A, A]` one, and with an empty list none.
- Right after recording, the same record counts as provisional, not open; it becomes open when its window closes.
- A servicer S proposes A as its primary: `primaryOf(S)` stays S until A accepts, and nobody else can accept. Then S's
  record of a loan counts under A, A cannot record the same loan reference again, and listing S counts nothing. A
  record S wrote before the link stays under S, and a later move of S to B moves no record.
- A cure by anyone but the reporter or its primary reverts; the cure moves one count from open to cured in both
  `agentDefaults` and `ownerDefaults`; a second cure reverts.
- A void inside the window removes the record from every count, keeps it listed, and lets its loan reference be recorded
  again; a void after the window, of a cured record, or of a voided one reverts, and so does a cure of a voided record.
- After 200 records by an untrusted reporter, `agentDefaults` with one trusted primary costs the same as before them.
- Pages: with five records, `recordsOfAgent(id, 1, 2)` returns ids 2 and 3, and `recordsOfAgent(id, 5, 10)` returns an
  empty list.

## Reference Implementation

`AgentDefaultRegistry` accompanies this proposal with its tests. It keeps open and cured counts per primary and
identity and per primary and owner, appends record ids to per-identity and per-owner lists, and keeps each primary's
ids per identity and per owner in recording order, so that a count finds the provisional ones by reading back from the
newest until the first record past its window. Its void window is three days.

## Security Considerations

- **False records.** Anyone can record a default about any identity or address. Readers MUST count only reporters they
  trust and SHOULD verify a reporter's records against its loans' own logs before trusting it.
- **Griefing an innocent owner.** A trusted reporter can be wrong or compromised. Readers should treat reporters'
  keys as lenders treat their own, and prefer reporters whose records can be checked against public loan logs.
- **Fresh addresses.** A defaulting owner can create a new address and a new identity. A count of zero means no default
  recorded by the listed reporters, not a vetted borrower.
- **Spam.** Listing functions are paginated because an identity's list can be made arbitrarily long. Counts do not
  depend on those lists, only on the records of the listed primaries still inside their window.
- **A lender's other addresses.** A primary answers for every address it accepted. If one of them is compromised, the
  primary drops it and can void its recent records inside their window; records outside the window stay, and readers
  can see which address wrote each one.
- **Record and void.** A reporter can record a default and void it inside the window to change a count at the moment
  another lender checks it. Counts report such records as provisional, so a reader can leave them out.
- **Privacy.** Records hold only on-chain identifiers and amounts already public in the lender's own logs. Reporters
  MUST NOT put personal data in a loan reference.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
