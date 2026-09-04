# pq_key_binding.v0 — anchored PQ-key binding + cutoff (shared cross-impl profile)

The post-quantum migration shape for signature-based identity, converged in the working group
(babyblueviper1 · pipavlo82 · blockbird · TMerlini, 2026-07-30). Both **invinoveritas** (Nostr verdicts,
OTS→Bitcoin anchor) and the **KYA-L4 attestor** (gateway EIP-712, OCP→chain anchor) conform to this
shape, so a verifier binds identically regardless of implementation.

## Why (the load-bearing point)
A supplementary PQ signature is **decorative** on its own: a post-CRQC forger who derives the classical
key mints valid classical events and simply **omits** the second signature — indistinguishable from
honest pre-cutoff history. Security lives in **an anchored key-binding + a cutoff**, not in the second
signature. Also: the PQ risk is *prospective forgery, not retroactive decryption* — so **everything
already anchored is already PQ-safe** (you can't backdate into an anchor). This profile gates only *new*
statements minted after the cutoff.

## The binding statement — byte-compatible via JCS
```
canonical_content        = JCS(statement)                    # RFC-8785 / receiptos-c14n: sorted-key, compact, non-ASCII literal
canonical_content_sha256 = sha256(canonical_content)
```
`statement` MUST carry at least `{ schema, secp256k1_pubkey (classical key), pq_pubkey, algorithm }` (a
`bound_at` and a `profile`/version tag are RECOMMENDED). **Byte-compatibility across impls is exactly:
canonicalize the same field set with JCS → the same `canonical_content_sha256`.** That's the whole
interop requirement; the family already shares JCS via receiptos-c14n.

## Companion, not tag
The binding rides a **detached companion** that signs the primary object's **content-address** — the
NIP-01 `event_id` for a Nostr carrier, the attestation/OCP digest for KYA-L4 — never an in-object tag. A
tag lives inside the id preimage, so retrofitting one re-mints the id and **orphans the existing anchor**;
the companion signs the 32-byte id everyone already computes, identically for past and future events.

## Dual-signed, self-verifying, anchored
- **Dual-signed:** both signatures cover the **same** content-address. Classical = BIP-340 Schnorr
  (invinoveritas) / EIP-712 ECDSA (KYA-L4). PQ signs the 32-byte id directly. `algorithm` ∈
  { **ML-DSA-65** (FIPS-204, operational default) · **SLH-DSA** (FIPS-205, hash-only profile) } — a
  field in the statement, not a fork. Co-sign the **genesis** binding with **both** keys (proof of
  possession of each; neither key alone can claim the other).
- **Self-verifying:** the verifier **recomputes** `canonical_content_sha256` and the companion id from
  raw bytes. The key manifest (`verifier-keys.json` / KYA-L4 key manifest) is **discovery only, never
  authority** — OTS proves *content existed before T*, not *what the endpoint serves now*.
- **Anchored:** the binding's content-address is anchored — OTS→Bitcoin (invinoveritas) or OCP→chain
  (KYA-L4). The anchor substrate is a field; what it proves is *existence before time T*. **An anchor is
  only a cutoff for a verifier who can *fetch* it (blockbird, 2026-07-30):** an on-chain anchor is
  permissionless — anyone reads the chain and recovers the anchor time, today — whereas an off-chain
  proof (`.ots`) is only as available as the endpoint serving it. An implementation MUST serve its anchor
  proof bytes for the cutoff to be publicly evaluable; an unreachable proof (a 404'd `.ots`) collapses the
  cutoff to something only the holder can check, losing parity with the on-chain lane.

## Verifier rule — cutoff by ANCHOR TIME, consumer policy
Accept an event iff it is **proven anchored before the consumer's cutoff**, **OR** it carries a valid PQ
companion signature under the pre-bound `pq_pubkey`. The cutoff is by **anchor time, never `created_at`**
(backdatable), and is **consumer-side policy**, not issuer-declared. The back catalog is owed nothing:
pre-cutoff-anchored events stay eligible for classical-only verification; PQ companions for them are
optional.

**Reference enforcer (this suite — `cutoff_enforce.py`).** The rule is executable and recomputable. Given
the binding chain, a consumer cutoff, and an artifact, it (1) resolves the **in-force binding** — the one
governing the artifact at *its* anchor time — then (2) admits iff the artifact is proven anchored before
the cutoff, **or** carries a PQ companion valid *under that in-force key* (so the companion is bound to the
resolution — a valid signature under a non-in-force key does not count). By design (pipavlo82) it resolves
from the chain **even at length one**, and the admit/reject path carries a **revocation slot** from the
start: a binding's authority ends at its `revoked_at`, an artifact anchored at/after that time is no longer
governed by it, and artifacts anchored earlier stay valid. Its vectors assert the **resolution step**, not
only the admit/reject outcome — so exercised rotation and the revocation lane *extend* this predicate
rather than rewrite it. **Until a consumer deploys this rule the companion is available but not
load-bearing** — that is the gap between a binding being *demonstrated* and the migration being *operative*.

## Rotation
An **anchored chain** of binding statements plus a **deterministic in-force rule** — "which binding
governed the artifact at its anchor time" — the `ruleset_version` shape. Post-cutoff rotations are signed
by the current PQ key so rotation survives the classical break.

**Exercised (#133), not just specified.** `kya-l4-genesis` (SLH-DSA `638c79a2…`) is rotated to
`kya-l4-rotation-1` — a new SLH-DSA key `8488157a…`, content-address `4fe636a4…` — whose statement links
the predecessor (`predecessor_content_address`) and is dual-signed over its own content-address by the
**predecessor PQ key** (continuity: the retired key authorizes its successor, so the chain survives the
classical break) and the **new key** (possession); both verify in the deep lane
(`pq-key-binding-v0.rotation.json`). The resolution is run across the two-binding chain in
`pq-key-binding-v0.rotation-vectors.json`: an artifact anchored *between* the rotations resolves to
genesis, one at/after resolves to rotation-1, and — the enforcement consequence — a post-cutoff artifact
whose companion is valid only under the **retired** key is rejected while the same under the new key
admits. Rotation is enforced, not declared; `cutoff_enforce.py`'s predicate consumed the length-2 chain
unchanged. rotation-1's on-chain anchor is the production-hardening step (as the mainnet record() was for
genesis).

## Revocation (not rotation)
Revocation is **not** rotation. Rotation is orderly succession — the retired binding still governed its
era. Revocation **invalidates** a binding. It is its **own anchored statement class**
(`kya.pq_key_revocation.v0`), names the binding it revokes by content-address, and takes effect at **its
own anchor time** — never a self-declared field (a self-declared `revoked_at` is backdatable, the same
trap as `created_at`). Artifacts anchored **before** the revocation's anchor time stay valid; artifacts
anchored **at/after** are no longer governed by that binding, and — absent a successor — are ungoverned.

**Exercised (#134).** An example binding (`964af387…`) is revoked by a `kya.pq_key_revocation.v0` statement
(`f01f7087…`) that names it and is PQ-authorized by the binding's own key
(`pq-key-binding-v0.revocation.json`, deep lane). `pq-key-binding-v0.revocation-vectors.json` runs the
temporal rule through `cutoff_enforce.py`: an artifact anchored before the revocation admits, at/after is
ungoverned — and a valid companion under the **revoked** key does not rescue a post-revocation artifact,
because the binding itself is gone (distinct from a missing-companion rejection). The revocation fills the
`revoked_at` slot `resolve_in_force` already honoured, so it extended the #132 predicate without a rewrite.

## Per-agent bindings, batch-Merkle anchored (per-agent Phase 2)
Beyond the single attestor binding, each agent carries its OWN PQ key (ML-DSA-65) bound by a
`pq_key_binding.v0` statement (owner-authorized). Anchoring one binding per agent doesn't scale, so all
active agent bindings are batched into a single **Merkle root** — sorted-pair sha256 over the sorted
per-agent binding content-addresses — and that root is `record()`'d on-chain once per epoch. An agent
proves inclusion with a Merkle path against the anchored root; the anchor's block time is the cutoff.
Fully recomputable, cold: re-derive the agent's `canonical_content_sha256` from its statement, fold it with
its path to the root (`node = sha256(min(x,y) ++ max(x,y))`), and read the same root back from the on-chain
OCP `record()`. A live snapshot is pinned in `pq-key-binding-v0.per-agent-anchor.json` (a real agent from
`gateway.ensub.org/pq/agent/<registry>/<id>/binding`).

**Per-attestation companion (per-agent Phase 3, live).** Every attestation now carries a per-agent
**ML-DSA-65 companion** signing the attestation's content-address (`sha256(JCS(WYRIWE commitment +
identity))`) under that agent's OWN bound key — verifiable by recompute at
`gateway.ensub.org/pq/companion/<inputHash>` (re-derive the content-address from the attestation, then
`ml_dsa65.verify(agent pq_pubkey, cc, signature)`). The companion is bound per-agent (another agent's key
does not verify it). It is recorded and checkable on every agent today; it becomes *load-bearing* — the
enforcer's `valid_pq_companion` path required rather than optional — when a consumer sets an active cutoff
(Phase 4). The `{algorithm}` split holds: attestor genesis = SLH-DSA, per-agent companions = ML-DSA.

## Conformance (this suite)
The recompute lane is **hash-only** (no signature libraries): re-derive `canonical_content_sha256 =
sha256(JCS(statement))` and, for a NIP-01 carrier, `event_id = sha256(compact-JSON[0, pubkey, created_at,
kind, tags, canonical_content])`, and match the claimed values. The BIP-340 + ML-DSA/SLH-DSA signature
checks and the anchor read are the separate deep lane. The gate **also lints this spec** (blockbird found
it, pipavlo82 named the class, 2026-07-30): every hex digest cited *in this document* MUST resolve to a
current pinned vector/artifact — because hash-pinning the spec proves the prose is *unaltered*, not
*correct*, and a stale digest once lingered in exactly this document. An orphaned digest fails the gate
(so the spec may never cite an unresolvable hash, not even in a cautionary aside — as this sentence obeys). Vector 1 is
**`invinoveritas.pq_key_binding.v1`** — the first real live binding
(`api.babyblueviper.com/.well-known/pq-key-binding.json`), binding the pinned invinoveritas verifier key
`6786e18a…` to an ML-DSA-65 PQ key, OTS-anchored, `canonical_content_sha256 7b85c0ae…`, `event_id
14a7335d…` — independently recomputed byte-exact.

**Dual-algorithm convergence (vector 2, `kya.pq_key_binding.v0`):** the KYA-L4 **production** binding uses
**SLH-DSA-SHA2-192s** (SPHINCS+, hash-based, NIST level 3 to match ML-DSA-65), anchored on **Ethereum
mainnet** via OCP `record(bytes32)` (no NIP-01 carrier). Two independent NIST-PQC families — ML-DSA
(lattice) and SLH-DSA (hash) — reproduce **byte-compatible content-addresses under one profile** via the
same JCS canon, cross-language (the `@noble/post-quantum` JS generator and this Python gate agree on
`b26a0159…`). That proves `{algorithm}` is a field, not a fork — interop rests on the shared
canonicalization, not a shared signature scheme. The content-address is recorded at TruthAnchor
`0x1e2A118a2bf1C240aE6fDe187c07f905D360f094` (tx `0x469655a08accf0300def211bf0c9ebd463e65b89f4ede1ac372ed2796e7ba916`,
block 25646404) — and the sharper result: the `record()` sender is the same `0xFf9a…ca14` the statement
names, so **the anchor transaction itself is the classical proof-of-possession**, no detached co-sign for
a post-CRQC forger to omit.
