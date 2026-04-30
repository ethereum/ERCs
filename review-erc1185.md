# Review: ERC-1185 — Storage of DNS Records in ENS

**Date:** 2026-04-30
**Status under review:** Review
**File:** `ERCS/erc-1185.md`

## Summary

ERC-1185 defines a DNS resolver profile for ENS. The proposal is conceptually sound and is well-aligned with ERC-137 resolver patterns, but the **specification is incomplete relative to the reference implementation**, lacks **RFC 2119 normative language**, and underspecifies **events**, **`setZonehash`/`zonehash`**, and **error/return semantics**. The Security Considerations section is too thin given the complexity of DNS wire format parsing on-chain. Several blockers should be addressed before moving to Final.

---

## Blockers

### 1. Spec/implementation mismatch on `dnsRecords` vs `dnsRecord`

- **L52** spec defines `dnsRecords(bytes32 node, bytes32 name, uint16 resource)`.
- **L188** reference implementation declares `dnsRecord(...)` (singular).

These names disagree. Function selectors `0x2461e851` (spec) and the actual selector of `dnsRecord(bytes32,bytes32,uint16)` will not match. Pick one and make spec + implementation consistent. The event/storage layout suggests that **multiple** values are concatenated wire-format records, so `dnsRecords` (plural) reads better.

### 2. `setZonehash` and `zonehash` are in the implementation but not in the Specification

- **L216–229** the reference implementation exposes `setZonehash(bytes32,bytes)`, `zonehash(bytes32) view returns (bytes)`, and an interface ID `DNS_ZONE_INTERFACE_ID = 0x5c47637c`.
- **L30** spec states "two functions to set DNS information and two functions to query DNS information" — but the implementation has four setters/queries plus a zonehash pair.

The Specification section must describe `setZonehash`/`zonehash`, their selectors, the relationship to ERC-1577 contenthash format, and the second interface ID. Otherwise interoperability across resolvers is unguaranteed.

### 3. Events are unspecified

The reference implementation emits `DNSRecordChanged`, `DNSRecordDeleted`, `DNSZoneCleared`, `DNSZonehashChanged` (**L102–109**). Indexers and off-chain DNS bridges depend on these. The Specification must list each event with its signature, indexed fields, and emission rules (e.g., must `setDNSRecords` emit one event per RRset, or one per record? Does clearing via `setDNSRecords` with an empty value emit `DNSRecordDeleted` or `DNSRecordChanged`?).

### 4. No RFC 2119 normative language

The document uses "should" in lowercase, e.g. **L39** "all records in the same RRset *should* be contiguous within the data; if not then the later RRsets will overwrite the earlier one(s)". This is actually a **MUST** for correctness — the implementation silently corrupts data otherwise. Promote to MUST and add the standard "The key words MUST, SHOULD, MAY... are to be interpreted as described in RFC 2119" boilerplate.

---

## Specification issues (line comments)

### L3 — Title

> title: Storage of DNS Records in ENS

Consider: "DNS Resolver Profile for ENS" — more accurate to what the document defines (a resolver interface), and matches the discussions-to title.

### L11 — `requires` is incomplete

> requires: 137

The reference implementation at **L112–114** ties zone hashes to **ERC-1577** content-hash binary format. Add `1577` to `requires` (or remove the dependency from the spec body if you intend to keep zonehash optional).

### L26 — Definition of "record set"

> A record set is uniquely defined by the tuple `(domain, name, resource record type)`

Minor: in DNS terminology this tuple is normally called an **RRset** (RFC 2181 §5). Consider using the standard term and citing RFC 2181 for precision; the implementation already uses `RRSET` in comments (**L101**).

### L28 — DNSSEC and zone-transfer limitations

> cannot completely support some features of DNS, such as zone transfers and DNSSEC

This is a security-relevant limitation, not just a design note. Move (or duplicate) into **Security Considerations** so integrators don't miss it. State explicitly that records served via this resolver are **not DNSSEC-validated** and that resolvers consuming them should treat the source as authoritative-by-ENS-ownership only.

### L32, L42, L52, L64 — Function signatures need full canonical form

Each section gives a hex selector (`0x0af179d7`, `0xad5780af`, `0x2461e851`, `0x4cbf6ba4`) but not the canonical signature string used to derive it. Add e.g.:

> `setDNSRecords(bytes32,bytes)` → selector `0x0af179d7`

This lets implementers verify selector correctness without re-deriving. Selector `0x2461e851` should also be verified once function name (Blocker #1) is resolved.

### L39 — Behavior on non-contiguous RRsets

> Any record that is supplied without a value will be cleared. Note that all records in the same RRset should be contiguous within the data; if not then the later RRsets will overwrite the earlier one(s)

Two issues:
1. "Any record supplied without a value will be cleared" — wire format does not have a natural "no value" encoding. Clarify: is this an `rdata` of length 0? The implementation at **L249–254** detects deletion via `value.length == 0` captured from the **first** record of the RRset (**L155, L172**), not per-record. Document this exact rule.
2. Promote the contiguity rule to **MUST** (see Blocker #4) and define what implementations should do on violation: revert, or accept the lossy overwrite? The reference implementation silently overwrites, which is dangerous. I recommend revert.

### L48 — Typo

> The arguments for the function **is** as follows

→ "are as follows" (also affects L70 indirectly; check the whole doc for consistency).

### L52, L59 — `name` parameter type confusion

> dnsRecords(bytes32 node, **bytes32** name, uint16 resource)
> name: the `keccak256()` hash of the name of the record in DNS wire format.

Whereas in `setDNSRecords` the name is implicit inside the wire-format `data`. Make explicit: `name` here is `keccak256(<dns-wire-format-encoded-name>)` — i.e., the same hashing applied at **L162** (`keccak256(abi.encodePacked(name))` where `name` came from `iter.name()` which returns the wire-format-encoded name including length-prefixed labels). A reader cannot derive this from the current text without reading the implementation.

Also, `bytes32` for a name parameter is unusual; clarify why a hash is used (gas) rather than the raw wire-format bytes.

### L62 — Return value when no records

> If there are no records present the function will return nothing.

"Nothing" is ambiguous in Solidity ABI. Specify: returns an empty `bytes` (length 0). Same clarification needed for `zonehash(node)` in the new spec section requested in Blocker #2.

### L68 — Reference to RFC 4592

> This function is needed by DNS resolvers when working with wildcard resources as defined in RFC4592.

Good. Hyperlink the RFC: `[RFC 4592](https://www.rfc-editor.org/rfc/rfc4592)`. Same suggestion for RFC 1035 mention at **L60**.

### L75 — `hasDNSRecords` semantics on resource boundary

The function takes `(node, name)` but not `resource`. The implementation at **L198** returns true iff *any* resource type for that name has records. State this in the spec — currently it merely says "any records for the provided node and name" which is fine but should be explicit that resource type is irrelevant.

---

## Reference Implementation issues

### L90 — Stale Solidity version

> pragma solidity ^0.7.4;

0.7.x is end-of-life. Update to `^0.8.20` (or current). Note that the arithmetic in `versions[node]++` (**L206**) and counter increments/decrements (**L251, L257**) is fine under 0.8 checked math, but worth verifying — the underflow at **L251** when `length != 0` is safe because the count was incremented when the record was first set; document this invariant.

### L98–99 — Interface IDs

```
bytes4 constant private DNS_RECORD_INTERFACE_ID = 0xa8fa5682;
bytes4 constant private DNS_ZONE_INTERFACE_ID = 0x5c47637c;
```

Specification body should declare both IDs and the function set each ID covers. Without that, ERC-165 detection is non-portable.

### L115, L121, L125, L130 — Storage layout commentary

The nested mappings are reasonable, but storage layout is *normative* for upgrade-path compatibility. Either declare it normative in the spec or explicitly mark the implementation as illustrative-only.

### L151 (`setDNSRecords`) — `nameHash` computed but unused

```
nameHash = keccak256(abi.encodePacked(name));
```

at **L162** and **L171**, but `nameHash` is never read in the function body — `setDNSRRSet` recomputes `keccak256(name)` at **L247**. Remove the dead assignments, or pass `nameHash` into `setDNSRRSet` to avoid the duplicate hash.

Also, **L162** uses `keccak256(abi.encodePacked(name))` while **L171** and **L247** use `keccak256(name)`. For `bytes memory` these produce the same hash, but the inconsistency is confusing — pick one form.

### L158 — Iterator correctness on malformed input

`RRUtils.iterateRRs` is from `@ensdomains/dnssec-oracle`. If the input bytes are malformed (truncated, bad length prefixes), what is the failure mode? The spec should require revert rather than silent partial application — particularly because partial application leaves the on-chain state inconsistent with the caller's intent.

### L166 — Boundary condition

```
if (resource != iter.dnstype || !name.equals(newName)) {
    setDNSRRSet(node, name, resource, data, offset, iter.offset - offset, value.length == 0);
```

The `value.length == 0` deletion signal uses the value of the **first** record in the run. If a caller passes two records of the same `(name, resource)` where the first has empty rdata and the second has a real value, the entire RRset is treated as a deletion and the real record is dropped. State this rule explicitly in the spec, or change the semantics to "deletion iff *all* records in the run have empty rdata".

### L205 — `clearDNSZone` does not clear `zonehashes`

Bumping `versions[node]` invalidates record/RRset storage but `zonehashes[node]` (**L115**) is keyed only by node and survives. Either:
- document that `clearDNSZone` is *records-only* and callers must call `setZonehash(node, "")` separately, or
- delete the zonehash too.

I recommend the former (more predictable) but it must be documented.

---

## Security Considerations (L266–268) — needs substantial expansion

The current text is a single sentence. At minimum, add:

1. **Wire-format parsing on-chain.** The resolver parses DNS wire format via `RRUtils`. Bugs in the iterator have historically caused issues; integrators should pin a specific audited version.
2. **Gas-DoS via large `data`.** `setDNSRecords` is unbounded; document recommended limits or warn about per-record gas costs.
3. **No DNSSEC.** Records are authoritative only insofar as the ENS owner is trusted. State this explicitly.
4. **Versioning side-effect.** `clearDNSZone` does not actually free storage — it only bumps a version counter. Refunds are not granted. Integrators auditing storage growth should know this.
5. **Zone-hash content trust.** The zonehash points off-chain (ERC-1577 contenthash). Resolvers consuming this must validate the off-chain content against the on-chain hash.
6. **Wildcards (RFC 4592).** Note the precise wildcard semantics implementations are expected to follow when answering against this resolver, and that `hasDNSRecords` is the only on-chain primitive supporting them.

---

## Editorial / Process

- **L7** Status `Review` — fine, but address the blockers above before moving to Last Call.
- **L13** Trailing whitespace after the front-matter delimiter (`---  `). Trim.
- **L268** Typo: "degenenrates" → "degenerates".
- **L83** "Backwards Compatibility: Not applicable." — Add one sentence explaining why (this is a *new* resolver profile and does not displace existing ones), so reviewers don't read it as a missing section.
- Consider a **Test Cases** section with a few canonical wire-format vectors and expected post-state — currently zero test vectors are normative.

---

## Recommendation

**Request changes** before this can advance from Review. Blockers 1–4 are all merge-blocking; the editorial items can be folded in alongside.
