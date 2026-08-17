---
eip: 8382
title: Private Referable NFTs
description: An ERC-721 extension for proof-verified hidden NFT references with optional selective disclosure.
author: Ruiqiang Li (@richard-620) <richard.620.research@gmail.com>, Qin Wang <qin.wang@data61.csiro.au>, Shiping Chen <shiping.chen@data61.csiro.au>, Saber Yu (@OniReimu), Brian Yecies <byecies@uow.edu.au>, John Le <johnle@uow.edu.au>
discussions-to: https://ethereum-magicians.org/t/private-referable-nfts/29442
status: Draft
type: Standards Track
category: ERC
created: 2026-08-17
requires: 165, 721, 5521
---

## Abstract

This ERC extends [ERC-721](./eip-721.md) with interoperable commitments to private NFT-to-NFT references. A token can publish one or more reference commitments without disclosing the referenced NFT, reference label, weight, or authorization material. Implementations expose a common discovery interface, may require a zero-knowledge or other privacy-preserving proof at mint time, and may support later selective disclosure of individual references.

The core interface is proof-system-neutral. It does not require Groth16, a particular elliptic curve, Poseidon, a fixed number of references, or a specific authorization registry. Optional extensions standardize proof-gated minting, selective reveal, registration-snapshot owner authorization, canonical public policies, and rank-governed DAG insertion.

## Motivation

[ERC-721](./eip-721.md) standardizes ownership and transfer of unique tokens but does not standardize relationships between tokens. [ERC-5521](./eip-5521.md) adds public referring and referred relationships, enabling an NFT graph to be queried and indexed. Public references are useful for provenance, remix attribution, licensing, collaboration, and recommendation, but they can disclose commercially or socially sensitive information before the holder is ready to reveal it.

A private reference should not be only an opaque hash. A relying contract may need evidence that:

1. the hidden parent is an existing eligible NFT;
2. a key registered by the parent NFT owner authorized the exact child and edge intent;
3. the hidden label and weight satisfy a publicly auditable policy;
4. the reference is not replayed;
5. the insertion obeys a declared graph-ordering rule; and
6. the committed reference can later be selectively disclosed and independently checked.

Existing applications can implement these properties with custom contracts, but custom event formats and query surfaces prevent wallets, marketplaces, indexers, and provenance explorers from discovering private references consistently. This ERC standardizes the observable lifecycle while leaving the proof system and cryptographic profile replaceable.

Private references may also be consumed by downstream royalty, revenue-sharing, licensing, reputation, or attribution systems. Cryptographic validity, owner authorization, and compliance with an application-defined policy establish that a reference satisfies the declared protocol conditions; they do not by themselves establish that the reference represents genuine creative contribution, an economically independent party, or an entitlement to payment. Applications that attach economic consequences to references therefore need separate payout-eligibility and contribution-authenticity rules.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Terminology

- **Child:** the [ERC-721](./eip-721.md) token containing one or more private references.
- **Parent:** the token addressed by a reference opening.
- **Reference commitment:** a 32-byte commitment to a private reference and all profile-required binding context.
- **Opening:** the public semantic fields disclosed for a committed reference.
- **Validation data:** profile-specific bytes needed to verify an opening, such as nonces, key material, a proof, or an authentication path.
- **Policy identifier:** a 32-byte identifier for the policy under which a reference was accepted.
- **Proof profile:** a 32-byte identifier for a fully specified statement, encoding, verifier type, hash suite, and version.
- **Authorization epoch:** a registry-defined time or governance interval used to scope owner authorization.
- **Rank namespace:** a domain in which immutable token ranks are compared.
- **Hidden state:** a committed reference whose semantic opening has not been published through the selective-reveal interface.
- **Revealed state:** a committed reference whose opening has been verified and stored.

### General requirements

A conforming core implementation:

1. MUST implement [ERC-721](./eip-721.md) and [ERC-165](./eip-165.md).
2. MUST implement `IERCXXXXPrivateReferences` below.
3. MUST assign each private reference a zero-based index local to the child token.
4. MUST NOT change the commitment or policy identifier at an existing `(tokenId, index)`.
5. MUST emit exactly one `PrivateReferenceCommitted` event when a reference is created.
6. MUST return the same commitment and policy identifier through `privateReference` that were emitted at creation.
7. MUST represent an existing unrevealed reference with status `0` and a revealed reference with status `1`.
8. MUST revert when an index is greater than or equal to `privateReferenceCount(tokenId)`.
9. MUST NOT expose the parent contract, parent token identifier, label, weight, secret nonce, owner public key, or authorization witness through the core interface while the reference remains hidden.
10. MUST advertise the core interface through [ERC-165](./eip-165.md).

A contract may create private references during mint or attach them through another application-defined lifecycle. If an implementation advertises `IERCXXXXProofMint`, it MUST follow the proof-gated mint requirements in this ERC.

### Interfaces and common data types

The interfaces below inherit `IERC165` so that supporting contracts can advertise compliance through [ERC-165](./eip-165.md). The core interface is mandatory; all other interfaces are optional extensions.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

struct ReferenceOpening {
    address parentContract;
    uint256 parentTokenId;
    uint256 parentRank;
    uint256 label;
    uint256 weight;
}

struct PrivateReferenceMintRequest {
    address recipient;
    bytes32 metadataHash;
    uint256 mintNonce;
    bytes32 childCommitment;
    bytes32 policyId;
    bytes32 authorizationRoot;
    uint64 authorizationEpoch;
    bytes32 rankNamespace;
    uint256 childRank;
    bytes32 externalNullifier;
    bytes32[] referenceCommitments;
    bytes32[] referenceNullifiers;
}
```

`metadataHash` is an application-selected digest bound by the proof profile. It does not replace [ERC-721](./eip-721.md) `tokenURI` semantics.

### Core private-reference interface

```solidity
interface IERCXXXXPrivateReferences is IERC165 {
    /// status: 0 = hidden, 1 = revealed
    event PrivateReferenceCommitted(
        uint256 indexed tokenId,
        uint256 indexed index,
        bytes32 commitment,
        bytes32 indexed policyId
    );

    event PrivateReferenceRevealed(
        uint256 indexed tokenId,
        uint256 indexed index,
        address indexed parentContract,
        uint256 parentTokenId,
        uint256 parentRank,
        uint256 label,
        uint256 weight
    );

    function privateReferenceCount(uint256 tokenId)
        external
        view
        returns (uint256 count);

    function privateReference(uint256 tokenId, uint256 index)
        external
        view
        returns (bytes32 commitment, bytes32 policyId, uint8 status);

    function revealedReference(uint256 tokenId, uint256 index)
        external
        view
        returns (ReferenceOpening memory opening);
}
```

`revealedReference` MUST revert while the reference is hidden. It MUST return the opening accepted by the selective-reveal operation after the reference is revealed.

### Optional selective-reveal extension

```solidity
interface IERCXXXXSelectiveReveal is IERC165 {
    function canRevealPrivateReference(
        uint256 tokenId,
        uint256 index,
        address operator
    ) external view returns (bool);

    function revealPrivateReference(
        uint256 tokenId,
        uint256 index,
        ReferenceOpening calldata opening,
        bytes calldata validationData
    ) external;
}
```

An implementation advertising this extension:

1. MUST verify that `opening` and `validationData` open the immutable commitment at `(tokenId, index)` under the active proof profile.
2. MUST reject a second reveal for the same index.
3. MUST reject a zero `parentContract`.
4. MUST change status from hidden to revealed only after successful verification.
5. MUST store the accepted `ReferenceOpening` and emit `PrivateReferenceRevealed` atomically.
6. MUST define an authorization policy for reveal. At minimum, the current token owner and operators approved under [ERC-721](./eip-721.md) SHOULD be supported unless the application deliberately uses a stricter policy.
7. MUST NOT interpret caller authorization as proof that the opening is correct; authorization and commitment verification are separate checks.

`validationData` is intentionally profile-specific. A profile MUST define its canonical encoding. For example, it may contain an edge nonce, approval nonce, owner public key, owner epoch, or a proof of opening.

This ERC does not define when a hidden or revealed reference becomes economically eligible in a downstream application. Applications that attach royalties, revenue shares, licensing benefits, reputation, or other economic effects to references MUST define which lifecycle event controls eligibility, such as commitment time, authorization time, reveal time, listing time, or another application-defined event, and whether later reveal has retroactive economic effect.

### Optional proof-gated mint extension

```solidity
interface IERCXXXXProofMint is IERC165 {
    event PrivateReferenceMinted(
        uint256 indexed tokenId,
        address indexed recipient,
        bytes32 childCommitment,
        bytes32 indexed policyId,
        bytes32 proofProfile
    );

    function proofProfile() external view returns (bytes32 profileId);

    function mintWithPrivateReferences(
        PrivateReferenceMintRequest calldata request,
        bytes calldata proof
    ) external returns (uint256 tokenId);
}
```

An implementation advertising this extension MUST, before minting:

1. reject the zero recipient;
2. check that `referenceCommitments.length` equals `referenceNullifiers.length` and is permitted by the proof profile;
3. check that every reference nullifier is canonical, pairwise distinct within the request, and unspent;
4. check that the child commitment has not previously been consumed if the profile defines child uniqueness;
5. derive or validate all contract-bound public context required by the profile, including `block.chainid`, the accepting contract, action selector, proof-profile identifier, policy identifier, authorization epoch, and any external nullifier;
6. validate the active authorization root and policy for the request epoch;
7. validate any required rank reservation and rank namespace;
8. verify `proof` against the exact canonical public input encoding defined by `proofProfile()`;
9. mark nullifiers and one-time commitments as consumed;
10. mint the [ERC-721](./eip-721.md) token, store every reference commitment and policy identifier, and emit one `PrivateReferenceCommitted` event per index; and
11. emit `PrivateReferenceMinted`.

All checks, replay-state updates, minting, storage writes, and events MUST be atomic. A failed operation MUST NOT consume a nullifier, reservation, or child commitment.

The proof verifier MAY be embedded in the token contract or delegated to another contract. `bytes proof` is opaque to this ERC. The profile defines its format and verification algorithm.

### Proof profile requirements

A profile identifier MUST commit to, or unambiguously identify, all consensus-relevant proof semantics, including:

- relation and schema versions;
- proof system and curve, if applicable;
- hash or commitment suite;
- domain-separation tags;
- field and byte encodings;
- public-signal names, order, widths, and canonical ranges;
- child commitment derivation;
- reference commitment derivation;
- nullifier derivation;
- owner-authorization statement;
- policy encoding;
- rank rules;
- batch-size rules; and
- verifier code or an immutable verifier identifier.

Any change to one of these items MUST produce a different profile identifier. Implementations MUST NOT verify a proof produced for one profile as though it belonged to another profile.

Profiles SHOULD derive commitments and nullifiers from a domain containing at least:

```text
(profileId, chainId, acceptingContract, actionSelector)
```

Registry-scoped authorization leaves SHOULD additionally bind the registry address and authorization schema version.

### Optional canonical-policy extension

```solidity
interface IERCXXXXCanonicalPolicy is IERC165 {
    event CanonicalPolicyRegistered(
        bytes32 indexed policyId,
        uint64 indexed activationEpoch,
        bytes canonicalPolicy
    );

    function canonicalPolicy(bytes32 policyId)
        external
        view
        returns (
            bytes memory canonicalPolicy,
            uint64 activationEpoch,
            bool registered
        );

    function isPolicyActive(bytes32 policyId, uint64 epoch)
        external
        view
        returns (bool);
}
```

An implementation advertising this extension:

1. MUST make the canonical policy preimage publicly queryable.
2. MUST document its canonical ABI encoding.
3. MUST guarantee that `policyId` is the profile-defined digest of the returned preimage.
4. MUST NOT change the preimage associated with a registered `policyId`.
5. MUST expose enough information for an observer to determine whether the policy was active for a specified epoch.

Publishing only an opaque accepted digest is not sufficient for this extension. Such a system may claim compliance with an accepted policy identifier, but not publicly auditable compliance with known policy fields.

Policy compliance is not contribution attestation. A canonical policy may constrain admissible labels, weight ranges, namespaces, epochs, or other machine-checkable fields, but an in-range or otherwise policy-compliant value does not prove that the value faithfully represents real-world creative contribution or economic importance. Downstream applications that monetize labels or weights SHOULD use additional attestation, admission, moderation, dispute-resolution, or other application-specific mechanisms when such authenticity matters.

### Optional registration-snapshot owner-authorization extension

```solidity
interface IERCXXXXOwnerAuthorization is IERC165 {
    event OwnerAuthorizationRegistered(
        address indexed parentContract,
        uint256 indexed parentTokenId,
        bytes32 indexed authorizationLeaf,
        bytes32 root,
        uint64 epoch,
        bytes4 keyScheme,
        bytes publicKey,
        bytes32 rankNamespace,
        uint256 parentRank
    );

    event OwnerAuthorizationRevoked(
        bytes32 indexed authorizationLeaf,
        uint64 indexed epoch
    );

    event AuthorizationEpochAdvanced(
        uint64 indexed previousEpoch,
        uint64 indexed newEpoch
    );

    function currentAuthorizationEpoch() external view returns (uint64);

    function isAuthorizationRootActive(
        bytes32 root,
        bytes32 policyId,
        uint64 epoch
    ) external view returns (bool);

    function registerOwnerAuthorization(
        address parentContract,
        uint256 parentTokenId,
        bytes4 keyScheme,
        bytes calldata publicKey,
        bytes32 rankNamespace
    ) external returns (bytes32 leaf, uint256 leafIndex, bytes32 newRoot);

    function revokeOwnerAuthorization(
        address parentContract,
        uint256 parentTokenId,
        bytes4 keyScheme,
        bytes calldata publicKey,
        bytes32 rankNamespace
    ) external returns (bytes32 leaf);
}
```

Registration MUST check the current [ERC-721](./eip-721.md) owner through `ownerOf(parentTokenId)`. A profile MUST define how the parent contract, token identifier, public key, rank, rank namespace, epoch, chain, and registry are encoded in the authorization leaf.

A root accepted for minting MUST be explicitly active for the current authorization epoch and applicable policy. An implementation MAY accept multiple activated roots within one epoch to preserve proof liveness during registry growth. If it does, activating a newer root MUST NOT silently deactivate older roots in that epoch. Roots from an older epoch MUST be rejected unless a separate carry-over or revocation relation is explicitly standardized by the profile.

Revocation semantics MUST be documented. Epoch rollover revocation and immediate intra-epoch revocation are distinct. An implementation that only prevents future re-registration MUST NOT claim immediate invalidation of previously activated roots.

Owner authorization establishes consent by the owner represented by the registry snapshot; it does not establish that the reference is economically independent, non-Sybil, or entitled to downstream compensation. In particular, an actor controlling both the child and parent assets may be able to satisfy authorization correctly. Applications that use authorized references for payments or other scarce benefits MUST treat authorization and economic eligibility as separate decisions.

`keyScheme` identifies the signature/public-key encoding. A key scheme profile MUST define canonical public-key and signature validation. Elliptic-curve profiles MUST specify on-curve, non-identity, subgroup, and scalar-canonicality requirements.

### Optional ranked-DAG extension

```solidity
interface IERCXXXXRankedReferences is IERC165 {
    event ChildRankReserved(
        bytes32 indexed childPreCommitment,
        bytes32 indexed rankNamespace,
        uint256 childRank,
        bytes32 reservationId
    );

    event TokenRankAssigned(
        address indexed tokenContract,
        uint256 indexed tokenId,
        bytes32 indexed rankNamespace,
        uint256 rank
    );

    function rankOf(
        address tokenContract,
        uint256 tokenId,
        bytes32 rankNamespace
    ) external view returns (uint256 rank, bool assigned);

    function reserveChildRank(
        bytes32 childPreCommitment,
        bytes32 rankNamespace
    ) external returns (uint256 childRank, bytes32 reservationId);

    function rankReservation(
        bytes32 childPreCommitment,
        bytes32 rankNamespace
    ) external view returns (
        uint256 childRank,
        bytes32 reservationId,
        bool active
    );
}
```

An implementation advertising this extension:

1. MUST assign at most one immutable rank to an asset in a rank namespace.
2. MUST bind a reservation to the accepting adapter, child precommitment, and rank namespace.
3. MUST prevent callers from substituting a different rank at mint.
4. MUST consume the exact reservation atomically with mint.
5. MUST enforce `parentRank < childRank` for every accepted ranked reference.
6. MUST define who may assign ranks and prevent unauthorized pre-assignment or namespace griefing.
7. MUST NOT claim arbitrary global dynamic acyclicity solely from the local inequality unless every relevant token has an immutable rank in the same namespace.

A reservation is publicly linkable to the mint that consumes its child precommitment. Relayers or account-abstraction systems may reduce wallet-identity linkage, but they do not hide the protocol-level reservation-to-mint relation.

### ERC-165 requirement

- Implementations MUST return `true` for `supportsInterface(type(IERCXXXXPrivateReferences).interfaceId)`.
- Implementations MUST return `true` only for optional extension identifiers whose complete semantics they implement.
- Events and inherited functions are not included when calculating the interface identifiers.
- Additional interfaces SHOULD be forwarded through the implementation's normal `supportsInterface` inheritance chain.

| Interface | Interface identifier |
| --- | --- |
| `IERCXXXXPrivateReferences` | `0x9d2c065b` |
| `IERCXXXXSelectiveReveal` | `0x15d38dfb` |
| `IERCXXXXProofMint` | `0xa6a4cad2` |
| `IERCXXXXCanonicalPolicy` | `0x8f43c3aa` |
| `IERCXXXXOwnerAuthorization` | `0x1a9dd556` |
| `IERCXXXXRankedReferences` | `0xce938bbe` |

### Key Components

#### Structs

- `ReferenceOpening` contains the parent contract, parent token identifier, parent rank, label, and weight disclosed for one reference.
- `PrivateReferenceMintRequest` contains the public mint context, commitments, nullifiers, policy, authorization root and epoch, rank namespace, and child rank.

#### Functions

- `privateReferenceCount` and `privateReference` provide batch-size-independent discovery of hidden or revealed references.
- `revealedReference` returns the immutable semantic opening after disclosure.
- `revealPrivateReference` verifies one indexed opening without revealing sibling references.
- `mintWithPrivateReferences` verifies a profile-specific proof and atomically mints the child token while consuming replay state.
- `canonicalPolicy` exposes the immutable policy preimage required for public semantic audit.
- `registerOwnerAuthorization` and `revokeOwnerAuthorization` manage registration-snapshot owner keys under documented epoch semantics.
- `reserveChildRank`, `rankReservation`, and `rankOf` support the optional ranked-DAG profile.

#### Events

- `PrivateReferenceCommitted` announces a new indexed commitment without publishing its parent endpoint.
- `PrivateReferenceRevealed` publishes the verified opening for one index.
- `PrivateReferenceMinted` records the child commitment, policy, and proof profile used for mint.
- Policy, authorization, epoch, and rank events expose the governance transitions needed by provers and indexers.

### Reference lifecycle

A proof-gated ranked implementation normally follows this lifecycle:

1. A parent NFT owner registers an authorization key for the parent and current epoch.
2. Governance or another specified mechanism activates one or more authorization roots and a canonical policy.
3. A prospective child minter computes a child precommitment and reserves a rank.
4. The parent owner signs an exact edge intent bound to the child commitment, policy, epoch, and fresh approval nonce.
5. The prover constructs a proof that hidden parent eligibility, owner authorization, policy compliance, replay derivation, and rank ordering hold.
6. `mintWithPrivateReferences` verifies the request and proof, consumes replay state and the reservation, mints the child, and stores commitments.
7. Wallets and indexers discover hidden references through the core interface and commitment events.
8. An authorized operator may later disclose one index. The contract verifies the opening and emits `PrivateReferenceRevealed`.
9. After disclosure, an implementation may also publish a public relationship compatible with [ERC-5521](./eip-5521.md).

### ERC-5521 interoperability

Before reveal, a private reference has no public parent endpoint and therefore cannot populate an [ERC-5521](./eip-5521.md) referring or referred list without defeating privacy.

After successful reveal, an implementation that also supports [ERC-5521](./eip-5521.md) MAY expose the reference through its [ERC-5521](./eip-5521.md) query surface. Such publication:

- MUST use the same parent contract and token identifier accepted by `revealPrivateReference`;
- MUST NOT create a different semantic edge;
- MUST preserve any [ERC-5521](./eip-5521.md) authorization and cross-contract callback requirements; and
- SHOULD occur atomically with reveal when both interfaces are implemented by the same contract.

This ERC does not require an unrevealed reverse index at the parent. A reverse index would reveal the hidden parent or require an additional privacy-preserving index protocol outside the scope of this ERC.

### Canonical encoding

All `bytes32` values are opaque at the core interface but canonical within a profile. When a profile maps a prime-field element into `bytes32`, it MUST specify byte order and MUST reject non-canonical values greater than or equal to the field modulus.

Addresses used inside field hashes MUST be encoded as their unsigned 160-bit value unless the profile specifies another unambiguous encoding. A `uint256` token identifier split into limbs MUST specify limb width and order.

Dynamic arrays MUST be bound with an unambiguous length and ordered index. A profile MUST NOT accept two byte encodings for the same public statement.

## Rationale

### Why standardize discovery rather than one circuit

Wallets, marketplaces, and indexers need stable commitment, status, and reveal interfaces. They do not need every project to use the same proving system. Requiring a particular circuit would make the ERC obsolete when proof systems or curves change and would turn every circuit revision into an interface revision.

### Why use `bytes32`

The current reference implementation uses BN254 scalar-field values represented as `uint256`. `bytes32` avoids implying ordinary integer arithmetic, accommodates field and non-field commitments, and creates a stable ABI across proof profiles. Profiles remain responsible for canonical range checks.

### Why use `bytes proof`

Proof encodings differ across Groth16, PLONK-family systems, STARKs, signatures, and future mechanisms. An opaque byte string plus a profile identifier avoids fixing verifier argument shapes such as `a`, `b`, `c`, or a fixed public-input array.

### Why index references

A fixed K1 or K2 ABI forces a new interface for each batch size. Indexed references provide one discovery and reveal surface for K1, K2, and larger fixed- or variable-cardinality implementations. A proof profile may still fix the allowed cardinality for efficiency.

### Why policy preimages are public

A public policy digest alone proves only compliance with some accepted opaque value. Returning the canonical preimage allows observers to recompute the identifier and understand the accepted labels, weights, namespace, activation epoch, or other policy fields without making all fields SNARK public signals.

### Why reveal is one-way

Once an opening is emitted and stored on-chain, it cannot become secret again. A one-way hidden-to-revealed state avoids ambiguous indexing and prevents a token owner from rewriting provenance after disclosure.

### Why owner authorization is registration-snapshot based

Checking only current ownership at proof submission does not show that the owner approved the exact hidden edge. Registration-snapshot authorization binds a key to an NFT owner at a defined epoch, after which the key signs the exact child and edge context. This model is explicit about ownership transfer and revocation boundaries.

### Why rank governance is optional

Some applications require a DAG; others allow cycles or do not need graph semantics. Rank assignment also introduces namespace governance and reservation complexity. Keeping it optional avoids imposing those costs on basic private-reference applications.

## Backwards Compatibility

This ERC is additive to [ERC-721](./eip-721.md). Existing [ERC-721](./eip-721.md) tokens and marketplaces remain valid.

Contracts that also implement [ERC-5521](./eip-5521.md) can expose revealed references through [ERC-5521](./eip-5521.md). Hidden references cannot be represented as ordinary [ERC-5521](./eip-5521.md) edges until disclosure because the parent endpoint is unavailable by design.

Implementations using `uint256` field elements can convert canonical values to and from `bytes32` at the interface boundary. Existing K1 and K2 contracts require adapter changes because their current public functions and events are batch-size-specific and do not advertise the interfaces in this ERC.

## Test Cases

A conforming test suite SHOULD include at least the following cases.

### Core interface

1. [ERC-165](./eip-165.md) reports the correct core and optional interface identifiers.
2. A minted token reports the correct private-reference count.
3. Every emitted commitment and policy identifier matches its query result.
4. Out-of-range indexes revert.
5. Hidden references do not expose semantic openings.
6. Commitments and policy identifiers cannot be changed after creation.

### Proof-gated mint

1. A valid proof mints and records every indexed commitment.
2. Invalid proofs revert without consuming state.
3. Wrong chain, accepting contract, action selector, profile, registry, epoch, policy, recipient, metadata hash, nonce, rank, or public-signal order fails.
4. Duplicate nullifiers within one request fail.
5. Reused nullifiers and child commitments fail.
6. Wrong or absent rank reservations fail.
7. Old-epoch roots fail.
8. If same-epoch multi-root acceptance is supported, activating a new root does not invalidate proofs against an older activated root in the same epoch.

### Selective reveal

1. A correct opening changes exactly one index to revealed.
2. A wrong parent, token ID, rank, label, weight, nonce, key, epoch, or policy fails commitment verification.
3. Unauthorized callers fail.
4. A second reveal fails.
5. Revealing one index does not reveal or modify another index.
6. The stored opening and emitted event agree.

### Owner authorization

1. Non-owners cannot register a key for a parent NFT.
2. Ownership transfer changes who may register or revoke future authorizations.
3. Off-curve, identity, small-order, wrong-subgroup, malformed signature points, and non-canonical scalars fail for an elliptic-curve profile.
4. Root activation, root expiry, epoch rollover, and revocation follow documented semantics.

### Policy and rank

1. The returned canonical policy recomputes to `policyId`.
2. Unknown, inactive, or mismatched policies fail.
3. Rank assignment is immutable within a namespace.
4. Unauthorized rank assignment and reservation substitution fail.
5. Equal or decreasing child rank fails; every accepted parent satisfies `parentRank < childRank`.

## Reference Implementation

The motivating experimental implementation is located in the zk-rNFT artifact and contains:

- `experiments/zk_rnft_eval/src/ZkRNFTV3K1Adapter.sol`: fixed-one-reference proof-gated mint and reveal;
- `experiments/zk_rnft_eval/src/ZkRNFTV3BatchK2Adapter.sol`: fixed-two-reference mint and per-index reveal;
- `experiments/zk_rnft_eval/src/OwnerKeyRegistry.sol`: [ERC-721](./eip-721.md) owner checks, epoch-versioned owner-key roots, and the experimental canonical rank registry;
- `experiments/zk_rnft_eval/src/PoseidonCanonical.sol`: typed Poseidon hashing;
- `experiments/zk_rnft_eval/circuits/zk_rnft/`: Circom relations; and
- `experiments/zk_rnft_eval/test/`: circuit, verifier, registry, adapter, replay, policy, rank, and reveal tests.

That artifact is a reference profile, not the normative Solidity interface. It currently uses Circom, Groth16 over BN254, typed Poseidon hashes, Baby Jubjub EdDSA-Poseidon authorization, depth-20 owner-key membership, fixed K1/K2 adapters, and versioned public-signal vectors.

Before presenting it as a conforming implementation, the following adaptation is required:

1. add the interfaces and [ERC-165](./eip-165.md) identifiers specified here;
2. map field commitments to canonical `bytes32` values;
3. expose indexed discovery independent of K1/K2;
4. use `bytes proof` at the standard boundary or document an equivalent profile adapter;
5. publish a stable proof-profile identifier;
6. restrict rank-registry writers and define namespace governance;
7. reconcile all relation-version documentation with the active circuits and verifier; and
8. document root activation and revocation behavior as required above.

## Security Considerations

### Proof and verifier binding

A valid proof is meaningful only for the exact relation and public-input encoding expected by the verifier. Implementations must prevent verifier substitution, signal reordering, profile confusion, and reuse across chains, contracts, actions, registries, or versions. Upgradeable verifiers require explicit governance, version changes, and migration rules.

### Commitment binding and hiding are different assumptions

Collision resistance supports binding but does not hide a low-entropy opening. A profile claiming hiding should use independently sampled high-entropy secret nonces and a commitment/hash construction with an appropriate hiding or pseudorandom-output assumption. A Poseidon profile may model each domain-separated invocation as a random oracle or explicitly assume pseudorandom outputs on inputs containing an independent secret nonce. Nonce reuse can reveal equality or enable dictionary attacks.

### Authorization-key validation

Signature-verification circuits and contracts must validate public keys and signature points according to the selected scheme. For elliptic-curve schemes this normally includes on-curve, non-identity, correct-subgroup, and canonical-scalar checks. Relying only on a library name without documenting its actual constraints is insufficient.

### Root churn and proof liveness

Generating a proof may take long enough for a registry root to change. A latest-root-only policy can invalidate in-flight proofs whenever another authorization is registered. Same-epoch activated multi-root windows improve liveness but increase the amount of state accepted until epoch rollover. The chosen window, activation rules, and emergency revocation limitations must be explicit.

### Revocation and ownership transfer

Registration-snapshot authorization does not imply that approval tracks the current parent owner forever. Implementations must state whether transfer, explicit revocation, epoch rollover, or another event invalidates an authorization. An old root must not be silently treated as current. Immediate mid-epoch revocation generally requires more than an append-only root history.

### Replay protection

Reference nullifiers must bind the exact approval and action domain. Nullifier state must be updated atomically with mint. Implementations must reject duplicate nullifiers within a batch and across transactions. Child commitments or rank reservations used as one-time identifiers require independent uniqueness checks.

### Rank reservations and front-running

A public child precommitment reservation is linkable to the mint that consumes it. An attacker may attempt to reserve identifiers, pre-assign ranks, or grief namespaces if writer permissions are weak. Reservation keys should bind the adapter and namespace, and registry write permissions must be explicit.

### Policy transparency

If only a policy digest is public, observers cannot determine which labels, weights, namespace, or other rules were proved. Implementations claiming publicly auditable policy compliance should expose a canonical immutable preimage. Otherwise they should describe the property as compliance with an accepted policy identifier.

### Economic interpretation of verified references

This ERC verifies protocol statements about private references; it does not define a universal notion of economic contribution. A proof can establish that a hidden parent is eligible under the selected profile, that an owner-authorized key approved the exact edge intent, that declared labels or weights satisfy a canonical policy, and that replay and DAG-ordering checks hold. These properties do not imply that the reference deserves a royalty, revenue share, licensing benefit, reputation increase, or other economic value.

Applications that monetize reference-derived features SHOULD treat economic eligibility as an application-level security boundary. In particular:

- authorization proves consent, not contribution authenticity or economic independence;
- policy-compliant labels or weights need not represent genuine contribution;
- distinct tokens, owner addresses, registered keys, or reference commitments MUST NOT automatically be assumed to represent distinct independent contributors; and
- commitment, authorization, reveal, listing, and sale times can have different economic meanings and MUST NOT be conflated unless the application explicitly defines them to be equivalent.

An application that makes payouts depend on graph position, path structure, weights, identity granularity, timing, or other reference-derived features SHOULD define corresponding admission, attestation, Sybil-resistance, temporal-eligibility, structural, and dispute-resolution controls as appropriate. Cryptographic validity of the provenance relation is necessary for some applications but is not, by itself, evidence that the relation is economically safe to monetize.

### Privacy leakage

This ERC hides reference openings, not all metadata. The following may remain public:

- the child token and owner;
- reference count;
- commitments and policy identifiers;
- authorization root and epoch;
- rank namespace and child rank;
- reservation and mint timing;
- transaction senders;
- reveal timing; and
- the protocol-level link between a rank reservation and its mint.

Relayers may reduce sender-to-wallet identity linkage but cannot hide public protocol identifiers. Candidate-set size, policy specificity, timing, public rank, and later disclosures may reduce anonymity. Applications should evaluate these channels under their deployment data rather than infer privacy solely from zero knowledge.

### Selective disclosure is irreversible

Reveal data and events are permanently public. Applications should require deliberate authorization and should not put unnecessary secret material into `ReferenceOpening`. Validation data passed in calldata is also public even if it is not stored.

### External calls and reentrancy

[ERC-721](./eip-721.md) safe minting, owner queries, verifier calls, registry calls, and [ERC-5521](./eip-5521.md) callbacks may execute external code. Implementations should follow checks-effects-interactions, use reentrancy protection where appropriate, and update replay state before untrusted callbacks while preserving transaction atomicity.

### Denial of service and unbounded arrays

Variable reference arrays can exceed practical gas or verifier limits. A proof profile must bound cardinality and validation-data size. Query APIs should support indexed access rather than returning unbounded arrays.

### Cryptographic agility

Proof profiles allow algorithm replacement, but accepting multiple profiles expands the attack surface. Each profile requires independent review, test vectors, canonical encoding, verifier deployment evidence, and a unique identifier.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
