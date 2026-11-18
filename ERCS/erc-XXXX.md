---
eip: XXXX
title: Onchain Announcements
description: Events and a call wrapper that couple a human-readable disclosure and content URI with the state changes it describes
author: Conner Swenberg (@ilikesymmetry) <conner.swenberg@coinbase.com>, Shaun Martinak <shaun.martinak@coinbase.com>, Daniel Reed <daniel.reed@coinbase.com>, Steve Katzman
discussions-to: https://ethereum-magicians.org/t/erc-onchain-announcements/30428
status: Draft
type: Standards Track
category: ERC
created: 2026-08-31
requires: 165, 7930
---

## Abstract

This standard defines a convention for onchain announcements: a way to couple a human-readable disclosure with the state changes it describes, in a form that indexers can correlate reliably.

An announcement is a bracket. An `Announcement` event opens it, zero or more state-changing calls execute atomically inside it, and an `EndAnnouncement` event closes it. Both events carry a caller-chosen `id` that identifies the announcement for the lifetime of the contract, so every effect emitted inside the bracket can be attributed to its disclosure.

A single entrypoint, `announce`, emits the open event, dispatches the described calls against the same contract in order, and emits the close event. The disclosure and its effects therefore always share one transaction and cannot be separated. A second entrypoint, `updateAnnouncement`, revises an existing announcement: it signals that the announcement's contents changed and can bracket further state changes under the same `id`. Assets can optionally designate other addresses, including on other chains, whose announcements are treated as their own.

## Motivation

Contracts routinely perform operator-driven state changes, such as a token rescaling, a batched issuance, or a parameter update. These changes materially affect holders or users. Today they surface only as low-level effect logs (`Transfer` and custom events) with no attached rationale, no summary, and no link to an offchain disclosure. A consumer must reconstruct intent from raw effects and has no reliable way to tell a deliberately disclosed change from an undisclosed direct call.

An announcement makes intent first-class:

- It emits a summary and a URI alongside the effects, atomically.
- It delimits exactly which effects belong to the announced action.
- Its bracket gives indexers a signal to distinguish a disclosed change from an undisclosed one, so the latter can be flagged (for example, as an emergency override).

Many real-world actions also change over time. A corporate action, for example, is often announced before all of its terms are known, is later corrected or confirmed, and is finally executed onchain days or weeks after the first notice. Consumers need a stable handle for the action across that lifecycle and a signal each time its contents change, without reconciling many unrelated announcements offchain.

The convention is deliberately orthogonal to what the state changes are and to how a contract authorizes them. It reuses a contract's existing mutating functions unchanged and attaches disclosure around them.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Interface

```solidity
interface IAnnouncements {
    /// @notice Opens the bracket of a new announcement.
    ///
    /// @param caller      The account that authorized the announcement.
    /// @param id          Caller-chosen id; identifies the announcement for the lifetime of the contract.
    /// @param description Human-readable summary of the announcement.
    /// @param uri         Offchain location of the full announcement contents; may be empty.
    event Announcement(address indexed caller, string id, string description, string uri);

    /// @notice Opens the bracket of an update to an existing announcement.
    ///
    /// @param caller The account that authorized the update.
    /// @param id     The id of the announcement being updated.
    event AnnouncementUpdated(address indexed caller, string id);

    /// @notice Closes the bracket opened by the `Announcement` or `AnnouncementUpdated` with the same id.
    ///
    /// @param id The id of the bracket being closed.
    event EndAnnouncement(string id);

    /// @notice Posts a new announcement and atomically dispatches each entry in `internalCalls`
    ///         against this contract, in order.
    ///
    /// @param internalCalls ABI-encoded calldata executed in order against this contract; may be empty.
    /// @param id            Caller-chosen id; MUST NOT have been used by a prior announcement.
    /// @param description   Human-readable summary of the announcement.
    /// @param uri           Offchain location of the full announcement contents; may be empty.
    function announce(
        bytes[] calldata internalCalls,
        string calldata id,
        string calldata description,
        string calldata uri
    ) external;

    /// @notice Updates an existing announcement and atomically dispatches each entry in
    ///         `internalCalls` against this contract, in order.
    ///
    /// @param internalCalls ABI-encoded calldata executed in order against this contract; may be empty.
    /// @param id            The id of an existing announcement.
    function updateAnnouncement(bytes[] calldata internalCalls, string calldata id) external;
}
```

### General

- A compliant contract MUST open a bracket by emitting either `Announcement(caller, id, description, uri)` (for a new announcement) or `AnnouncementUpdated(caller, id)` (for an update), and MUST close it by emitting `EndAnnouncement(id)` with the same `id`.
- `caller` MUST be the account that authorized the announcement or update.
- Every state-changing call executed between the opening event and `EndAnnouncement` belongs to that announcement.
- Brackets MUST NOT nest. While a bracket is open, no call inside it may open another bracket.

### `announce`

A call to `announce(internalCalls, id, description, uri)` MUST, in this order:

1. Emit `Announcement(caller, id, description, uri)` before executing any entry in `internalCalls`.
2. Execute each entry of `internalCalls` in array order, against the same contract, as a state-changing call.
3. Emit `EndAnnouncement(id)` after the final entry has executed.

`announce` MUST revert if `id` was consumed by a prior successful `announce`.

### `updateAnnouncement`

A call to `updateAnnouncement(internalCalls, id)` MUST, in this order:

1. Emit `AnnouncementUpdated(caller, id)` before executing any entry in `internalCalls`.
2. Execute each entry of `internalCalls` in array order, against the same contract, as a state-changing call.
3. Emit `EndAnnouncement(id)` after the final entry has executed.

`updateAnnouncement` MUST revert if `id` was not consumed by a prior successful `announce` on the same contract. `updateAnnouncement` does not consume a new `id` and MAY be called any number of times for the same `id`, subject to the implementation's own rules (see Lifecycle).

### Dispatch requirements

The following apply to both `announce` and `updateAnnouncement`:

- **Atomicity.** The entire call MUST be atomic. If any entry in `internalCalls` fails, the call MUST revert; no entry may be partially applied and `EndAnnouncement` MUST NOT be emitted. The specific error surfaced, and whether a failed entry's revert reason is propagated or replaced, is left to the implementation.
- **Pure disclosure.** `internalCalls` MAY be empty. In that case no calls execute and the opening event and `EndAnnouncement` are emitted with nothing between them.
- **No nesting.** No entry in `internalCalls` may re-invoke `announce` or `updateAnnouncement`. An implementation MUST reject such an attempt by reverting the whole call.
- **Self-targeted.** Each entry in `internalCalls` MUST target the announcing contract, not a generic `(target, calldata)` pair. External effects are still reachable: the contract's own methods MAY call out, and those calls run inside the bracket. See Rationale.

### Id uniqueness

- Each `id` MUST be consumed at most once by `announce` for the lifetime of the contract.
- An `id` is consumed only by an `announce` call that succeeds.
- After an `id` is consumed, it can only be referenced again through `updateAnnouncement`.

### Announcement contents (`uri`)

`uri` MAY be empty (a disclosure with no offchain document). When non-empty, it MUST resolve to a document conforming to the Announcement Content Schema below: a strict, machine-readable structure. Free-form or arbitrary documents are non-conforming; a consumer MUST be able to parse any announced `uri` against one schema. Conformance is REQUIRED whenever `uri` is non-empty.

The document MUST be a JSON object encoded in UTF-8 with at least the following structure:

```typescript
type AnnouncementContents = {
  category: string
}
```

- `category` MUST be a non-empty string identifying the kind of announcement (for example, `corporateAction`).
- Each category defines the remaining fields of its documents. Other proposals MAY define category schemas that build on this one.
- A consumer that does not recognize a document's `category` MUST NOT interpret its other fields, and MAY still display the announcement's onchain `description`.

### Lifecycle

An announcement has one identity, its `id`, and one `uri` for its whole life. Its contents can change over that life.

1. **Publication.** `announce` publishes the announcement, fixing its `id`, `description`, and `uri`. Contents MAY be preliminary at this point (for example, terms not yet known or not yet confirmed).
2. **Revision.** When the contents at `uri` change, the publisher MUST call `updateAnnouncement` for the same `id` in or after the transaction that makes the change visible. A publisher MUST NOT change the contents at `uri` without a following `updateAnnouncement`. On each `AnnouncementUpdated`, a consumer MUST treat its cached contents for that `id` as stale and SHOULD fetch `uri` again.
3. **Execution.** State changes that carry out the announced action MAY be bracketed by the original `announce` or by any later `updateAnnouncement` for the same `id`. All of them are attributed to the same announcement.
4. **Conclusion.** This standard defines no onchain terminal state. Whether an announcement is final, cancelled, or withdrawn is part of its contents and is defined by its category. An implementation MAY refuse further updates to an `id` it considers final by reverting `updateAnnouncement`.

Category schemas that describe actions with a lifecycle SHOULD include in each document:

- a monotonically increasing revision number, so that a consumer can order documents and reject an older document served after a newer one;
- whether the contents are complete and whether they are confirmed by the responsible party; and
- whether the announced action is still in effect, has been cancelled, or has been withdrawn.

The `description` emitted in `Announcement` is not changed by updates. Consumers SHOULD prefer summary text from the latest contents, when the category provides it, over the original `description`.

### Announcement references

An asset is the home for discovering announcements about it, but it may not be the only contract that emits them. An asset MAY designate other contracts as announcement references. Announcements emitted by a valid announcement reference SHOULD be treated as if the asset emitted them.

This supports two use cases:

- a service provider that announces on behalf of many asset issuers from one contract; and
- an asset deployed on several chains that keeps a single announcement feed on one home chain.

An asset that supports announcement references MUST implement the following interface:

```solidity
interface IAnnouncementReferences {
    /// @notice Emitted when `delegate` becomes a valid announcement reference.
    ///
    /// @param delegate  ERC-7930 Interoperable Address of the reference contract.
    /// @param extraData Implementation-defined data about the reference; may be empty.
    event AnnouncementReferenceAdded(bytes delegate, bytes extraData);

    /// @notice Emitted when `delegate` stops being a valid announcement reference.
    ///
    /// @param delegate  ERC-7930 Interoperable Address of the reference contract.
    event AnnouncementReferenceRemoved(bytes delegate);

    /// @notice Returns whether `reference` is currently a valid announcement reference.
    ///
    /// @param delegate  ERC-7930 Interoperable Address of the reference contract.
    function isValidAnnouncementReference(bytes calldata delegate) external view returns (bool);
}
```

- `delegate` MUST be encoded as an [ERC-7930](./eip-7930.md) Interoperable Address, so that a reference MAY live on a different chain than the asset.
- A reference contract MUST implement `IAnnouncements`.
- `isValidAnnouncementReference` MUST return `true` for a reference after its `AnnouncementReferenceAdded` and before any later `AnnouncementReferenceRemoved`, and `false` otherwise.
- A consumer SHOULD treat an announcement from a reference as the asset's only if the reference was valid for the asset at the time of the announcement, as reconstructed from `AnnouncementReferenceAdded` and `AnnouncementReferenceRemoved`. For a reference on another chain, "at the time" is judged by timestamp.
- When a reference announces for more than one asset, the contents at `uri` MUST identify the asset or assets the announcement applies to. A consumer MUST NOT attribute an announcement from a shared reference to an asset that its contents do not identify.
- An update (`AnnouncementUpdated`) is attributed to the announcement with the same `id` on the same contract that emitted it.

### Interface detection

A compliant contract MUST implement [ERC-165](./eip-165.md). `supportsInterface(0x4c34fb2a)` MUST return `true`, where `0x4c34fb2a` is the interface id of `IAnnouncements`.

An asset that implements `IAnnouncementReferences` MUST return `true` from `supportsInterface(0x44a2c3d2)`, where `0x44a2c3d2` is the interface id of `IAnnouncementReferences`.

### Caller preservation

`internalCalls` entries are dispatched against the same contract. When those inner mutations enforce their own authorization, the dispatch mechanism SHOULD preserve the original caller, so that authorization observes the announcer rather than the contract's own address. Executing each entry via a self-`delegatecall` (which preserves `msg.sender`) is the RECOMMENDED mechanism; an equivalent that preserves the caller is permitted.

This standard does not otherwise prescribe an authorization model. Whether `announce`, `updateAnnouncement`, the inner mutations, or all of them are access-controlled is left to the implementation. See Security Considerations.

## Rationale

**Why a bracket instead of one event carrying an effect list.** Effects are heterogeneous and are emitted by each inner call's own logic. A bracket lets a contract reuse its existing mutating functions unchanged and still attribute their logs to the announcement, rather than duplicating every effect into a bespoke schema.

**Why the id appears in every event.** Carrying `id` in the opening and closing events lets a consumer pair them and attribute intervening effects without relying on log adjacency, and lets independent tooling reconstruct a bracket from either boundary.

**Why a single entrypoint dispatches the calls.** Routing the disclosure and the effects through one function guarantees they share a transaction and cannot be separated: a disclosure never lands without its effects, and the effects never land without their disclosure.

**Why internal calls rather than generic actions.** Self-targeting, not a generic `(target, calldata)`, for three reasons:

- *Caller preservation.* A self-`delegatecall` carries the announcer's identity, so the contract's own authorization sees the operator. A direct external call cannot: the far contract sees the announcing contract, not the operator.
- *Finite surface.* Announceable effects are exactly the contract's own ABI, which a reviewer can enumerate, not "any function on any contract".
- *No foreign code.* A self-`delegatecall` runs the contract's own code against its own storage; delegatecalling external code would not.

Generality is not lost. The contract's own methods may call out as part of their logic, and those calls run inside the bracket.

**Why one announcement per action, revised in place.** An alternative is to post a new announcement, with a new `id`, each time an action's contents change, and to link the versions through a shared identifier inside the contents. That forces every consumer to fetch and index offchain contents just to learn that several announcements describe the same action. Keeping one `id` for the action's whole life lets a consumer follow it from onchain data alone, and lets a later update bracket the state changes that execute the action under the same handle as the first notice.

**Why a separate update function instead of re-announcing an id.** Allowing `announce` to reuse an `id` would let an operational mistake, such as a retried job or a duplicated identifier, silently overwrite an unrelated announcement. Requiring an explicit `updateAnnouncement`, which only accepts an existing `id`, makes revision a deliberate act and keeps `announce` strictly for new announcements.

**Why a distinct `AnnouncementUpdated` event.** Reusing `Announcement` for updates would make the first publication indistinguishable from a revision without contract state. A distinct event lets an indexer tell them apart from logs alone, and it is lighter because it does not repeat `description` and `uri`, which do not change.

**Why lifecycle states live in the contents.** The states an announcement passes through (preliminary, confirmed, cancelled, withdrawn, and so on) differ by domain and already have established vocabularies in some domains. Defining them onchain would either be too narrow for some categories or too vague to be useful. This standard therefore provides the onchain signal that contents changed, and leaves their meaning to category schemas. Implementations that need onchain finality can refuse updates to a final `id`.

**Why authorization-agnostic.** The pattern is orthogonal to any particular access-control model. Its only interaction with authorization is caller preservation, which is a recommendation so that contracts that gate inner mutations can keep those checks meaningful.

**Why no id-status getter.** Whether an `id` has been consumed can be fully reconstructed from `Announcement` logs. Requiring a getter would add cost without serving any consumer that the logs do not already serve.

**Why `description` and `uri` are separate.** `description` is a cheap onchain summary suitable for direct display; `uri` points to the full, possibly large, contents held offchain. Splitting them keeps the onchain footprint small while preserving a link to the complete record.

**Why a strict content schema with a `category`.** A consumer that encounters an arbitrary `uri` must know how to parse it. A required `category` field gives every document a common entry point, and lets each domain define its own fields without this standard enumerating them.

**Why empty `internalCalls` is first-class.** Some disclosures carry no onchain effect (a notice, a statement of record, a correction). Allowing an empty batch makes a pure disclosure or a pure revision a normal announcement rather than a special case.

**Why announcement references use Interoperable Addresses.** A reference may live on another chain, for example a home-chain feed for a multichain asset. ERC-7930 gives a compact binary encoding of an address together with its chain, so one interface covers both same-chain service providers and cross-chain feeds.

**Related work.** [ERC-1129](./eip-1129.md) proposed a board of free-text announcements for a DApp. This standard instead couples a structured disclosure with the state changes it describes and gives each announcement a stable identity across revisions.

## Backwards Compatibility

This standard is purely additive: three new events and two new functions, plus an optional interface for announcement references. It introduces no changes to existing behavior and conflicts with no prior standard. Existing effect events (such as `Transfer`) are unchanged and simply fall inside a bracket when emitted by an inner call.

## Reference Implementation

A minimal, authorization-agnostic sketch. Access control on `announce` and `updateAnnouncement` is omitted for brevity and is discussed under Security Considerations.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

abstract contract OnchainAnnouncements {
    event Announcement(address indexed caller, string id, string description, string uri);
    event AnnouncementUpdated(address indexed caller, string id);
    event EndAnnouncement(string id);

    error AnnouncementIdAlreadyUsed(string id);
    error AnnouncementNotFound(string id);
    error AnnouncementInProgress();
    error InternalCallMalformed(bytes call);
    error InternalCallFailed(bytes call);

    mapping(bytes32 => bool) private _usedId;
    bool private _inProgress;

    function announce(
        bytes[] calldata internalCalls,
        string calldata id,
        string calldata description,
        string calldata uri
    ) external virtual {
        // Implementations SHOULD gate this call; see Security Considerations.
        if (_inProgress) revert AnnouncementInProgress();
        bytes32 key = keccak256(bytes(id));
        if (_usedId[key]) revert AnnouncementIdAlreadyUsed(id);
        _usedId[key] = true;

        _inProgress = true;
        emit Announcement(msg.sender, id, description, uri);
        _dispatch(internalCalls);
        emit EndAnnouncement(id);
        _inProgress = false;
    }

    function updateAnnouncement(bytes[] calldata internalCalls, string calldata id) external virtual {
        // Implementations SHOULD gate this call; see Security Considerations.
        if (_inProgress) revert AnnouncementInProgress();
        if (!_usedId[keccak256(bytes(id))]) revert AnnouncementNotFound(id);

        _inProgress = true;
        emit AnnouncementUpdated(msg.sender, id);
        _dispatch(internalCalls);
        emit EndAnnouncement(id);
        _inProgress = false;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x4c34fb2a // IAnnouncements
            || interfaceId == 0x01ffc9a7; // ERC-165
    }

    function _dispatch(bytes[] calldata internalCalls) private {
        for (uint256 i; i < internalCalls.length; ++i) {
            bytes calldata c = internalCalls[i];
            if (c.length < 4) revert InternalCallMalformed(c);
            // Self-delegatecall preserves msg.sender.
            (bool ok,) = address(this).delegatecall(c);
            if (!ok) revert InternalCallFailed(c);
        }
    }
}
```

## Security Considerations

**An announcement is a claim, not a proof.** `description` and the contents at `uri` are supplied by the caller and are not verified onchain. A consumer must not trust them beyond the effects actually executed inside the bracket.

**Undisclosed effects.** A consumer should treat state changes that occur outside any bracket as undisclosed direct calls and may flag them (for example, as emergency overrides). This signal is only as strong as the contract's discipline in routing disclosed changes through `announce` and `updateAnnouncement`.

**Arbitrary self-dispatch.** `internalCalls` is arbitrary calldata executed against the contract itself, typically with the caller preserved. Any account able to call `announce` or `updateAnnouncement` can therefore invoke any inner mutation the contract exposes, as the announcer. Access control on both functions is consequently critical: implementations should gate them and must ensure that self-dispatch cannot reach functions or storage the caller is not entitled to reach. Implementations must guard against re-entering either function (nesting).

**Mutable contents.** The contents at `uri` are expected to change over an announcement's life, and nothing onchain binds a given `AnnouncementUpdated` to particular contents. A publisher could change contents without emitting an update, serve different contents to different consumers, or let `uri` stop resolving. Consumers should keep a copy of each version of the contents they act on, and category schemas should carry a revision number so that consumers can detect contents that changed without a revision or that went backwards. Content-addressed URIs cannot be used for announcements that are revised, because `uri` does not change.

**Revisions after users act.** An update can change the terms of an announcement after a user acted on an earlier version. Consumers should surface material changes to users and should not silently replace terms that a user relied on. Implementations that need finality can refuse updates to final announcements.

**Missed updates.** A consumer that misses an `AnnouncementUpdated` event may act on stale contents, including contents later marked cancelled or withdrawn. Consumers should process all announcement events of the asset and its references, not only the most recent ones.

**Announcement references.** A valid reference can make announcements that consumers attribute to the asset, so compromising a reference is equivalent to compromising the asset's announcement authority. Assets should restrict who can add references and should remove a compromised reference promptly. For references on other chains, consumers depend on reading that chain correctly and on the asset's add and remove events, and should account for differences in finality between chains. A shared reference that serves many assets could name the wrong asset in its contents; consumers must check the asset identification required by this standard.

**Id griefing.** If `id` selection is unauthorized, an attacker can consume ids to interfere with an issuer's naming scheme, or update announcements they did not make. Gating `announce` and `updateAnnouncement` mitigates this.

**Unbounded batches.** A large `internalCalls` array can exceed the block gas limit. Implementations and callers should bound batch size.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
