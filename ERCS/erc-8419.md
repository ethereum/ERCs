---
eip: 8419
title: Know-Your-Agent (KYA) Framework
description: Scheme-agnostic registries and handshake for trust assertions about AI agents, with a zero-knowledge profile and agent-registry binding
author: Gary Yang (@garyyang-finchip)
discussions-to: https://ethereum-magicians.org/t/erc-8419-know-your-agent-kya-framework/29735
status: Draft
type: Standards Track
category: ERC
created: 2026-09-19
requires: 165, 712, 721, 1271, 8004
---

## Abstract

This ERC defines a framework for **Know-Your-Agent (KYA)**: a minimal on-chain data model and a set of interfaces through which any party can

1. register a **KYA Scheme** — an immutable, versioned, addressable description of *what* is checked about an agent, *what it binds to* (its identity, its controller or a specific instance), *how* the result is expressed, and *how* assertions under it are admitted;
2. record a **KYA Assertion** — a conclusion about an agent under a given scheme, with result, validity window, evidence commitment, trust anchor, supersession and revocation;
3. **resolve** assertions on-chain and **present** them off-chain in a standard handshake between agents or between an agent and a relying party.

The framework is deliberately **scheme-agnostic**: it does not define how an agent is verified nor what makes an agent trustworthy. Those rules live in scheme descriptors and in pluggable verifier contracts. A **zero-knowledge (ZK) KYA profile** — **ZK-KYA** below — specifies how an assertion is admitted on the strength of a zero-knowledge proof instead of an issuer signature, using the same registry and the same assertion structure; it hides the fact issuer and the underlying facts, not the subject. An **[ERC-8004](./eip-8004.md) binding profile** makes ERC-8004 agents the primary subject type and mirrors KYA conclusions into the ERC-8004 Validation Registry so that ERC-8004-only clients can consume them without change.

## Motivation

ERC-8004 gives agents a portable identity and a place to accumulate raw trust *signals*: client feedback in the Reputation Registry and third-party judgements in the Validation Registry. It intentionally stops there. What it does not provide is a shared vocabulary for trust *conclusions* — the answer to "is this agent acceptable for this interaction?" — expressed so that both sides can name what was checked, under which rules, by whom, until when, and whether it still holds.

Off-chain "Know Your Agent" offerings are multiplying: payment networks gate agent wallets, compliance vendors score agent operators, marketplaces vet agent provenance. Each publishes its own verdict format and none is intelligible to the others. An agent that has been vetted by one provider cannot show that fact to a counterparty that speaks a different provider's dialect; a counterparty cannot say, in one machine-readable sentence, "I accept level 3 or better under scheme X from issuers A or B". The autonomous economy needs a single place to *look up* a trust conclusion and a single message to *ask for* one, regardless of which vendor or algorithm produced it.

Privacy sharpens the requirement. Many KYA facts — the controlling legal entity, its jurisdiction, its capital backing, the model lineage behind an agent — must not be disclosed to every counterparty. A framework that cannot admit a zero-knowledge proof as a first-class assertion source forces disclosure by design and will be bypassed by exactly the operators who most need to be known.

The relationship to ERC-8004 is the same as ERC-8004's relationship to [ERC-721](./eip-721.md): a registry, not a policy. ERC-721 records *who owns*; ERC-8004 records *what was signalled*; this ERC records *what was concluded and under which principle*. In the same way that token-bound extensions of ERC-721 such as the companion proposals Token-Bound Executable Skills and Token-Bound Task Tenders add executable or task semantics without redefining the token, this ERC adds assurance semantics to ERC-8004 agents without redefining the agent.

This ERC records conclusions about a *subject*. It does not authorise actions. A standard such as [ERC-8354](./eip-8354.md) answers "may this specific proposed action proceed?" for one action, one executor and one committed policy; this ERC answers "what has been concluded about this agent, under which scheme, by whom, until when?" The two compose — a KYA conclusion can be an input to an action policy, and an action verdict can be evidence under a declared scheme — but neither mapping is implicit: a subject-trust conclusion is not an execution authorisation, and one permitted action does not become a general trust conclusion by being encoded as a `level`. Likewise, a validation network that aggregates independent validators can *produce* KYA assertions through the ordinary attested path (the contract that records the assertion — the caller of `attest`, Section 4 — is the recorded issuer) and its results can be cited as evidence; it does not need, and this ERC does not define, a separate admission mode for that.

Illustrative flows this framework enables (informative):

- A skill provider under a token-bound skill standard (Token-Bound Executable Skills) presents a KYA assertion before delivery; the buyer's contract asks the registry whether the provider meets a minimum level under a chosen scheme from issuers it trusts (`check`, Section 4) as a purchase precondition.
- A task fulfiller under a token-bound task standard (Token-Bound Task Tenders) is required by the task's descriptor to satisfy a registered KYA policy (`policyId`, Section 7) before reserving the task; the adjudicators of that task may in turn be required to satisfy another scheme.
- Two agents perform mutual KYA over an [EIP-712](./eip-712.md) challenge/presentation exchange before opening a payment channel; one of them proves accountability with a zero-knowledge proof whose issuer is never revealed.
- A lender agent publishes its own underwriting rule as a scheme ("net inflow over 180 days above a threshold, no interaction with a sanctions list, at least N settled tasks"); a borrower agent evaluates the rule over its authenticated private history inside a proof and presents only the verdict. The lender never has to receive the history, and no third party had to issue a credit verdict beforehand.
- A payment processor that only understands ERC-8004 reads the same KYA outcome from the ERC-8004 Validation Registry under a `kya:` tag.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### 1. Terminology

- **Subject** — the entity a KYA assertion is about, encoded as `(subjectType, subjectData)` and identified by `subjectKey`.
- **Binding** — what an assertion attaches to within a subject: the subject's *identity* record, its current *controller*, or a specific *instance* (code, model or configuration digest). Declared per scheme.
- **Scheme** — a registered, versioned and semantically immutable description of a KYA principle: which dimensions are checked, what it binds to, how results are expressed, which evidence kinds are admissible, and — for proved schemes — which verifier contract admits proofs.
- **Assertion** — a conclusion about a subject under a scheme, recorded in a KYA Registry.
- **Fact issuer** — the party that actually performed the check and vouches for the underlying facts (an attester, or the hidden attestor behind a zero-knowledge proof).
- **Issuer** (on-chain field) — for an attested assertion, the fact issuer's address; for a proved assertion, the *admitting verifier* contract. In the proved case the fact issuer is not named on-chain; its accountability is carried by the assertion's `anchor`.
- **Anchor** — a verifier-defined commitment to what a proof was checked against (for the reference circuit, the Merkle root of the permitted attestor set). Relying parties trust a proved assertion as the pair `(verifier, anchor)`.
- **Verifier** — a contract implementing `IKYAVerifier` that maps a proof and its public inputs to framework fields and enforces the scheme's time-window rule.
- **Relying party** — any consumer of assertions: an agent, a contract, an indexer.
- **Policy** — a relying party's declared requirement over `(scheme, minLevel, issuers)` combinations.
- **Ordered-Level Profile** — the OPTIONAL convention under which a scheme's `level` values are totally ordered and "higher is stronger", enabling `minLevel` comparisons and highest-level resolution. Schemes that do not adopt it use `level` as an opaque code or leave it `0`.
- **Mode** — how assertions under a scheme are admitted: `ATTESTED` (0) or `PROVED` (1).

### 2. Subject

```solidity
struct Subject {
    bytes32 subjectType;   // keccak256 of a registered type string, e.g. keccak256("erc8004")
    bytes   subjectData;   // ABI-encoded per subjectType
}
```

`subjectKey` MUST be computed as `keccak256(abi.encode(subjectType, subjectData))` — that is, the two fields encoded as a pair, *not* the struct encoded as a single tuple.

Registered subject types:

| type string | `subjectData` encoding | conformance |
|---|---|---|
| `erc8004` | `abi.encode(uint256 chainId, address identityRegistry, uint256 agentId)` | MUST be supported by every KYA Registry |
| `account` | `abi.encode(uint256 chainId, address account)` | SHOULD |
| `erc721`  | `abi.encode(uint256 chainId, address collection, uint256 tokenId)` | MAY |
| `did`     | UTF-8 bytes of the Decentralized Identifier (DID) string | MAY |

Later ERCs MAY register additional subject types. Registries MUST NOT reject an unknown `subjectType` on write; resolution semantics for unknown types are implementation-defined.

#### 2.1 Binding

A `subjectKey` names a record, not necessarily the party that matters to a relying party. An `erc8004` subject is an [ERC-721](./eip-721.md) token: its owner can change, the software behind it can change, and neither event touches the registry. Every scheme therefore declares, in its descriptor, one `binding`:

| `binding` | the assertion is about | invalidated by |
|---|---|---|
| `identity` | the subject record itself, whoever controls it | nothing but revocation or expiry |
| `controller` | the party controlling the subject at `issuedAt` | the current controller differing from the one at `issuedAt` (for `erc8004`: `ownerOf(agentId)` now ≠ `ownerOf(agentId)` then) |
| `instance` | a specific code, model or configuration of the subject, identified by `claimDigest` | any change to that instance |

The binding kind is scheme-level semantics and is recorded on-chain in the `Scheme` (Section 3); it MUST NOT vary per assertion. Each assertion carries a **binding witness** — the committed binding state at issuance — and each resolution evaluates a **binding predicate** against current state. Conceptually `valid(A, now) = ACTIVE ∧ unexpired ∧ bindingPredicate(A, now)`.

| `binding` | witness captured at issuance | predicate at resolution |
|---|---|---|
| `identity` | `0x0` | always satisfied (NOT_APPLICABLE) |
| `controller` | `keccak256(abi.encode(controller))` — for `erc8004`: `ownerOf(agentId)` read from the identity registry named in `subjectData` | SATISFIED iff the current controller's witness equals the recorded one; otherwise VIOLATED |
| `instance` | `claimDigest` | satisfied from the registry's view; relying parties MUST compare `claimDigest` to the instance they interact with |

Rules:

- A registry MUST capture the witness at issuance according to the scheme's binding kind. For `controller`-bound schemes it MUST evaluate the witness natively for `erc8004` subjects on its own chain (`subjectData.chainId == block.chainid`, `ownerOf` on the named identity registry). If it cannot evaluate the witness for a subject (foreign chain, other subject types without a resolver), it MUST refuse to record the assertion (`KYA_BindingUnevaluable`) rather than record one whose binding it can never check.
- Complete resolution (`resolve`, `check`, and any on-chain policy evaluation built on them) MUST evaluate the binding predicate and MUST exclude assertions whose predicate is VIOLATED or UNEVALUABLE. Registry-local resolution (`resolveLocal`) ignores the predicate and MUST NOT be presented as complete policy satisfaction. `bindingStatus(assertionId)` exposes the predicate's result.
- A scheme MAY legitimately depend on state that changes under rules it declares (a revocation list, an issuer set with a declared rotation mechanism, authenticated chain state); such updates are part of the scheme's meaning, not a change of it. What MUST NOT change under one `schemeId` is the meaning, the authority or the interpretation of those rules (Section 3).
- The `controller` predicate is a *state* comparison, not a *history* check: it asks whether the party controlling the subject now is the party that controlled it at `issuedAt`, not whether control has been uninterrupted since. A subject transferred away and later transferred back to the original controller therefore satisfies the predicate again, and the original assertion — if it is still ACTIVE, unexpired and still that issuer's latest for the pair — counts again in complete resolution without a fresh assessment. Because resolution considers each issuer's latest assertion only (Section 4), an issuer that re-attested to the intervening controller supersedes the original, and the round trip does not revive it. The stronger guarantee, "no change of controller since issuance", is not evaluable by the registry: neither ERC-721 nor the ERC-8004 identity registry exposes a transfer count or last-transfer time that a contract can read, and a registry MUST NOT claim a predicate it cannot check. Relying parties that need it MUST establish it themselves (for `erc8004`, from the identity registry's `Transfer` events since `issuedAt`), or use a scheme whose issuer re-attests and keeps `expiresAt` short enough that a round trip inside one validity window is not worth the effort. A future binding kind MAY carry an on-chain form of the history guarantee if the underlying registry ever exposes the state it needs; it would be a distinct kind, not a change to `controller`.
- Issuers of `controller`-bound schemes SHOULD keep `expiresAt` short and MAY re-attest to the new controller after a transfer; the new assertion carries the new witness.
- Assertions carry no interaction context. A relying party that needs "trusted for this counterparty / this amount / this task" expresses it in a Policy (Section 7) or in the handshake challenge (Section 6), never by reinterpreting `level`.

### 3. Scheme Registry

```solidity
interface IKYASchemeRegistry /* is IERC165 */ {
    enum SchemeMode { ATTESTED, PROVED }   // uint8; values >= 2 reserved

    enum BindingKind { IDENTITY, CONTROLLER, INSTANCE }   // uint8; values >= 3 reserved

    enum ResultKind { ORDERED_LEVEL, CATEGORICAL, OPAQUE } // uint8; values >= 3 reserved (Section 3.1)

    struct SchemeInput {               // what registerScheme takes; everything but schemeURI is then IMMUTABLE
        string  schemeURI;
        bytes32 schemeHash;
        uint8   mode;
        uint8   binding;
        uint8   resultKind;
        uint256 levelMask;             // bit n set <=> level n is a declared, valid result
        address verifier;
        bytes32 predecessor;
    }

    struct Scheme {                    // everything but schemeURI/controller/frozen is IMMUTABLE
        address controller;
        string  schemeURI;             // may be re-pointed to another copy of the same bytes
        bytes32 schemeHash;            // keccak256 of the descriptor bytes; non-zero
        uint8   mode;
        uint8   binding;               // BindingKind (Section 2.1)
        uint8   resultKind;            // ResultKind — the shape of the result domain (Section 3.1)
        uint256 levelMask;             // the result domain itself: bit n set <=> level n is valid
        address verifier;              // non-zero iff mode == PROVED
        bytes32 verifierCodehash;      // EXTCODEHASH of verifier at registration; pinned
        bytes32 predecessor;           // previous version's schemeId, or 0x0
        bool    frozen;
    }

    event SchemeRegistered(bytes32 indexed schemeId, address indexed controller, uint8 mode, uint8 binding,
                           uint8 resultKind, uint256 levelMask, address verifier, bytes32 verifierCodehash,
                           string schemeURI, bytes32 schemeHash, bytes32 predecessor);
    event SchemeURIUpdated(bytes32 indexed schemeId, string schemeURI);
    event SchemeFrozen(bytes32 indexed schemeId);
    event SchemeControllerTransferred(bytes32 indexed schemeId, address indexed from, address indexed to);

    function registerScheme(SchemeInput calldata input) external returns (bytes32 schemeId);
    function setSchemeURI(bytes32 schemeId, string calldata schemeURI) external;
    function freezeScheme(bytes32 schemeId) external;
    function transferSchemeController(bytes32 schemeId, address newController) external;

    function getScheme(bytes32 schemeId) external view returns (Scheme memory);
    function schemeExists(bytes32 schemeId) external view returns (bool);
    function schemeNonce(address controller) external view returns (uint256);
}
```

Rules:

- `schemeId` MUST equal `keccak256(abi.encode(block.chainid, address(schemeRegistry), msg.sender, schemeHash, nonce))` where `nonce` is a per-controller counter starting at 0 and incremented on every successful `registerScheme`. Including the chain and the scheme registry makes a `schemeId` unique across chains and catalogues, so a credential bound to a `schemeId` (Section 5) is bound to one rule on one chain. A `schemeId` names a *rule*, not a place of use: several KYA Registries MAY share one Scheme Registry and admit assertions under the same scheme, and the registry that admits a given proof enters the proof's *admission domain* (Section 5), not the scheme's identity.
- `mode` MUST be 0 or 1, `binding` MUST be 0, 1 or 2 and `resultKind` MUST be 0, 1 or 2; any other value MUST revert.
- **Result domain.** `levelMask` commits the complete set of valid `level` values for the scheme: bit *n* set means level *n* is a declared result. Registration MUST revert (`KYA_InvalidLevelMask`) unless the mask fits the kind: for `ORDERED_LEVEL` bit 0 MUST be set (level 0 is "not verified / failed") and at least one higher bit MUST be set; for `CATEGORICAL` the mask MUST be non-zero; for `OPAQUE` the mask MUST be exactly `1` (level 0 only). The mask MUST equal the key set of the descriptor's `levels` (ordered) or `result.codes` (categorical) (Section 3.1). A KYA Registry MUST refuse (`KYA_LevelNotDeclared`) any assertion — attested or proved — whose level is not in the mask, so an undeclared level never enters a registry and `check`, `evaluate` and bridges only ever see values the scheme assigned a meaning to. For `PROVED`, `verifier` MUST be a contract (non-empty code) and its `EXTCODEHASH` MUST be recorded as `verifierCodehash`. For `ATTESTED`, implementations MUST store `verifier` as the zero address.
- `predecessor`, when non-zero, MUST reference an existing scheme whose `controller` is `msg.sender`.
- **Semantic immutability.** `schemeHash`, `mode`, `binding`, `resultKind`, `levelMask`, `verifier`, `verifierCodehash` and `predecessor` MUST NOT change after registration; the interface exposes no entry point that changes them. Any change to what a scheme checks, what it binds to, how it expresses results or which verifier admits proofs MUST be registered as a new scheme with `predecessor` set. Consequently a `schemeId` denotes exactly one meaning for its whole life, and a policy that pins a `schemeId` cannot be repointed underneath it.
- **Verifier immutability.** The meaning of a PROVED scheme includes the verifier's behaviour. Every code path, verification key, pinned issuer set or other dependency capable of changing which proofs the verifier admits MUST be semantically immutable for the life of the `schemeId`; a verifier that is an upgradeable proxy, or that reads admission parameters from mutable storage not governed by rules the descriptor declares, MUST NOT be registered. Registries MUST refuse admission (`KYA_VerifierCodeChanged`) when the code at `verifier` no longer matches `verifierCodehash`; this catches redeployment behind the address but not delegation, which is why the normative rule is needed in addition. Upgradeable infrastructure remains free to exist — it simply cannot retroactively change an already-registered scheme; the upgrade is a successor scheme.
- `setSchemeURI` MUST revert unless called by the controller, MUST revert on a frozen scheme, and MUST NOT alter `schemeHash`; clients MUST verify the fetched descriptor against `schemeHash`. `freezeScheme` MUST revert unless called by the controller; a frozen scheme accepts no further `setSchemeURI`.
- `schemeHash` MUST be the keccak256 of the descriptor bytes and MUST be non-zero (`KYA_SchemeHashRequired`), including for content-addressed URIs.
- Implementations MUST support [ERC-165](./eip-165.md) and MUST return `true` for the `IKYASchemeRegistry` interface id.

#### 3.1 Scheme Descriptor

`schemeURI` MUST resolve to a JSON document conforming to the schema in [`kya-scheme.schema.json`](../assets/eip-8419/schemas/kya-scheme.schema.json). Required members are `type`, `name`, `description`, `version`, `mode`, `binding`, `result` and `dimensions`; `levels` is additionally REQUIRED when `result.kind` is `"ordered-level"`, and `circuit` when `mode` is `"proved"`.

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-8419#kya-scheme-v1",
  "name": "Accountable Operator (ZK) v1",
  "description": "Proves, without disclosure, that an identified legal entity stands behind the agent's ERC-8004 registration.",
  "version": "1.0.0",
  "mode": "proved",
  "binding": "controller",
  "result": { "kind": "ordered-level" },
  "dimensions": ["controller-binding", "accountability", "compliance"],
  "levels": {
    "0": { "label": "not verified",      "erc8004Response": 0 },
    "2": { "label": "controller-linked", "erc8004Response": 50 },
    "4": { "label": "accountable",       "erc8004Response": 100 }
  },
  "evidenceKinds": ["zk-proof", "vc-jwt", "erc8004-validation"],
  "issuerPolicy": { "kind": "verifier-only" },
  "circuit": {
    "system": "groth16",
    "vkHash": "0x9f1c7e2d5b3a4c6e8f0a1b2c3d4e5f60718293a4b5c6d7e8f9a0b1c2d3e4f5a6",
    "publicInputLayout": ["subjectKey", "nullifier", "level", "claimDigest", "expiresAt", "issuerSetRoot", "epoch"],
    "publicInputAbi": ["bytes32", "bytes32", "uint8", "bytes32", "uint64", "bytes32", "uint64"],
    "nullifierScope": "scheme-epoch",
    "proofBinding": ["schemeId", "admissionDomain"],
    "epochSeconds": 2592000,
    "epochGrace": 1,
    "issuerHiding": true,
    "issuerSetRoot": "0x1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809"
  }
}
```

- `result.kind` is `"ordered-level"` (the Ordered-Level Profile: `level` is totally ordered, higher is stronger, `minLevel` is meaningful), `"categorical"` (`level` is an opaque code from `result.codes`, comparison is equality) or `"opaque"` (`level` MUST be `0`; the result is whatever `claimDigest` commits to, as defined by `result.description`). It MUST equal the on-chain `resultKind` (`0`, `1`, `2` respectively); the on-chain value is authoritative for resolution.
- Under `"ordered-level"`, `levels` MUST contain key `"0"`, whose meaning is "not verified / failed". **The key set of `levels` is the complete valid result domain**, not a set of named points on an unrestricted `uint8` axis: it MUST equal the bits set in the on-chain `levelMask`, and the registry refuses any other level at admission (Section 3). The same holds for the key set of `result.codes` under `"categorical"`. Each level MAY carry `erc8004Response` (0–100), the value a KYA Bridge (Section 8) SHOULD mirror for that level; a bridge configuration MUST map every declared level.
- `binding` is one of `identity`, `controller`, `instance` (Section 2.1) and MUST equal the `binding` recorded on-chain for the scheme (`0`, `1`, `2` respectively); the on-chain value is authoritative for resolution.
- For proved schemes, `circuit.epochSeconds` and `circuit.epochGrace` define the verifier's time window (Section 5) and `circuit.issuerSetRoot`, when present, is the anchor the verifier pins.
- `dimensions` and `evidenceKinds` are open vocabularies; Section 11 registers initial values.
- `issuerPolicy` is declarative. The framework does not enforce who may issue; relying parties enforce it by choosing `issuers` (Section 4).
- The framework does not interpret `dimensions`, `evidenceKinds`, `issuerPolicy` or `circuit` beyond requiring their presence and shape. **This is where KYA principles and ZK-KYA algorithms live; this ERC standardises the container, not the contents.**

### 4. KYA Registry (Assertions)

```solidity
interface IKYARegistry /* is IERC165 */ {
    enum AssertionStatus { ACTIVE, REVOKED, SUPERSEDED }

    struct Assertion {
        bytes32 subjectKey;
        bytes32 schemeId;
        address issuer;         // attester, or admitting verifier (PROVED)
        uint8   level;          // scheme-defined result code; 0 when result.kind is "opaque"
        bytes32 claimDigest;    // commitment to the scheme-defined result / disclosed claims
        uint64  issuedAt;
        uint64  expiresAt;      // 0 = no expiry (NOT RECOMMENDED)
        bytes32 evidenceHash;
        bytes32 anchor;         // PROVED: verifier-reported trust anchor; ATTESTED: 0x0
        bytes32 bindingWitness; // committed binding state at issuance (Section 2.1)
        uint8   status;
    }

    enum BindingStatus { NOT_APPLICABLE, SATISFIED, VIOLATED, UNEVALUABLE }

    event Asserted(bytes32 indexed assertionId, bytes32 indexed subjectKey, bytes32 indexed schemeId, address issuer,
                   uint8 level, bytes32 claimDigest, uint64 expiresAt, string evidenceURI, bytes32 evidenceHash,
                   bytes32 anchor, bytes32 bindingWitness);
    event Revoked(bytes32 indexed assertionId, bytes32 indexed subjectKey, address indexed revoker, uint16 reasonCode);
    event Superseded(bytes32 indexed previousAssertionId, bytes32 indexed newAssertionId);

    function getSchemeRegistry() external view returns (address);

    // ATTESTED mode — caller is the issuer
    function attest(Subject calldata subject, bytes32 schemeId, uint8 level, bytes32 claimDigest, uint64 expiresAt,
                    string calldata evidenceURI, bytes32 evidenceHash) external returns (bytes32 assertionId);

    // PROVED mode (ZK-KYA) — anyone may relay; admission is decided by scheme.verifier
    function attestWithProof(Subject calldata subject, bytes32 schemeId, bytes calldata publicInputs,
                             bytes calldata proof, string calldata evidenceURI) external returns (bytes32 assertionId);

    function revoke(bytes32 assertionId, uint16 reasonCode) external;

    function getAssertion(bytes32 assertionId) external view returns (Assertion memory);
    function latestAssertion(bytes32 subjectKey, bytes32 schemeId, address issuer) external view returns (bytes32);
    function isNullifierUsed(bytes32 schemeId, bytes32 nullifier) external view returns (bool);
    function subjectKeyOf(Subject calldata subject) external pure returns (bytes32);
    function admissionDomain() external view returns (bytes32);   // Section 5: what this registry binds proofs to
    function resultDomain(bytes32 schemeId) external view returns (uint8 resultKind, uint256 levelMask); // Section 3: committed result domain

    // Resolution (Ordered-Level Profile) — `issuers` MUST be non-empty
    function resolve(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)          // COMPLETE
        external view returns (uint8 level, uint64 expiresAt, bytes32 assertionId);
    function resolveLocal(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)     // registry-local
        external view returns (uint8 level, uint64 expiresAt, bytes32 assertionId);
    function check(Subject calldata subject, bytes32 schemeId, uint8 minLevel, address[] calldata issuers)
        external view returns (bool);
    function bindingStatus(bytes32 assertionId) external view returns (uint8);
}
```

Rules:

- `attest` MUST revert if the scheme does not exist or its `mode` is not `ATTESTED`. `attestWithProof` MUST revert if the scheme does not exist, its `mode` is not `PROVED`, its `verifier` is zero, or the code at `verifier` no longer matches the scheme's `verifierCodehash`.
- Both MUST capture `bindingWitness` per Section 2.1 and MUST revert with `KYA_BindingUnevaluable` when the scheme's binding cannot be evaluated for the subject.
- `assertionId` MUST equal `keccak256(abi.encode(subjectKey, schemeId, issuer, issuerNonce))` where `issuerNonce` is a per-issuer counter starting at 0 and incremented on every successful record.
- A non-zero `expiresAt` that is not in the future MUST revert.
- `claimDigest` MUST be a commitment to the scheme-defined result or disclosed claims — a hash over the claims together with a salt of at least 128 bits of entropy, or the zero value when the scheme defines no claim — and MUST NOT be a direct encoding of a small claim space, since every recorded `claimDigest` is public and a low-entropy encoding is recoverable by enumeration. The scheme descriptor defines what the commitment covers.
- Recording a new assertion for a `(subjectKey, schemeId, issuer)` triple that already has an ACTIVE assertion MUST mark the previous one `SUPERSEDED` and emit `Superseded`. `latestAssertion` MUST return the most recently recorded id for the triple regardless of status.
- `revoke` MUST revert unless the caller is the assertion's `issuer` or the scheme's current `controller`, and MUST revert if the assertion is not ACTIVE.
- `resolve` MUST revert if `issuers` is empty. It MUST consider, for each listed issuer, only that issuer's latest assertion for the pair, and only if it is ACTIVE, unexpired (`expiresAt == 0 || expiresAt > block.timestamp`) and its binding predicate evaluates SATISFIED or NOT_APPLICABLE. It MUST return the highest `level` among them, breaking ties by latest `issuedAt`; when none qualifies it MUST return `(0, 0, 0x0)`. A non-zero `assertionId` from `resolve` therefore means every condition the registry can know about — status, expiry and the scheme's declared binding — was evaluated and holds. This "highest wins" rule is the Ordered-Level Profile and is meaningless for other result kinds, so `resolve` and `resolveLocal` MUST revert (`KYA_NotOrderedLevel`) for a scheme whose on-chain `resultKind` is not `ORDERED_LEVEL`; for `categorical` or `opaque` schemes callers read the specific assertions (`latestAssertion` + `getAssertion`) instead.
- `resolveLocal` MUST behave as `resolve` without the binding predicate. Its result is registry-local and MUST NOT be presented as complete policy satisfaction; it exists for indexers and for consumers that evaluate binding themselves.
- `check` answers "does the subject meet this threshold", never "does an assertion exist". It MUST revert (`KYA_ZeroThreshold`) when `minLevel == 0`, because level 0 is by definition "not verified / failed" and a failed result MUST NOT satisfy any threshold; existence is `resolve`'s question. For `minLevel > 0` it MUST return `true` iff `resolve` (complete) returns a non-zero `assertionId` with `level >= minLevel`. `minLevel` need not itself be a declared level (it is a threshold, and declared levels at or above it satisfy it). `check` inherits `resolve`'s `KYA_NotOrderedLevel` revert for non-ordered schemes.
- `resultDomain(schemeId)` MUST return the scheme's `(resultKind, levelMask)` as recorded in the Scheme Registry, so evaluators and bridges can validate against the committed domain without parsing the descriptor.
- `evidenceURI` MUST be emitted and MUST NOT be stored. For proved assertions the registry MUST set `evidenceHash = keccak256(publicInputs)` and `anchor` to the value returned by the verifier; for attested assertions `anchor` MUST be `0x0`. The registry MUST retain enough of the subject (its type and data) to re-evaluate the binding predicate later.
- Registries MUST support the `erc8004` subject type and MUST return `true` from `supportsInterface` for the `IKYARegistry` interface id.

### 5. ZK-KYA Profile (PROVED mode)

```solidity
interface IKYAVerifier {
    function verify(bytes32 schemeId, bytes32 admissionDomain, bytes calldata publicInputs, bytes calldata proof)
        external view
        returns (bool ok, bytes32 subjectKey, bytes32 nullifier, uint8 level, bytes32 claimDigest, uint64 expiresAt,
                 bytes32 anchor);
}
```

`verify` MUST be `view`. It MUST return `ok == false` or revert on any verification failure. `anchor` is the verifier's commitment to what the proof was checked against (for the reference circuit, the issuer-set Merkle root); it MAY be `0x0` for verifiers that have no such notion.

Two identifiers answer two different questions. `schemeId` says *under which registered rule* the proof is interpreted and verified; `admissionDomain` says *where this particular proof is being used* — which chain and which consuming contract. The caller computes `admissionDomain` from its own state and passes it in; a verifier MUST bind the proof's statement to the value it receives. For registry admission:

```
REGISTRY_ADMISSION_TYPE = keccak256("erc-kya-registry-admission-v1")
admissionDomain         = keccak256(abi.encode(REGISTRY_ADMISSION_TYPE, block.chainid, schemeRegistry, kyaRegistry))
```

where `kyaRegistry` is the contract that records the assertion and consumes the nullifier, and `schemeRegistry` is the catalogue it reads schemes from. `IKYARegistry.admissionDomain()` exposes the value so provers can reproduce it.

**Roles.** In PROVED mode the on-chain `issuer` is the *admitting verifier*: the contract that checked the proof. It is neither the source of the underlying facts nor a guarantor of the conclusion; it identifies which verification logic admitted the assertion. What stands behind the verifier differs by usage pattern (Section 5.1): in the credential pattern a *fact issuer* (attestor) examined the subject off-chain and signed a verdict, and `anchor` commits to the set of attestors the verifier accepts; in the predicate pattern the verdict is computed by the scheme's own rule over authenticated inputs, and `anchor` commits to the input source (a block hash, a notary set, a data-signer set). In both cases a relying party that lists a verifier in `issuers[]` is trusting the circuit and verification key behind it plus whatever `anchor` commits to, and policies SHOULD pin both; the reference adapter enforces a fixed anchor on-chain so that the pair collapses to the address.

On `attestWithProof` the registry MUST, in order:

1. Load the scheme and require `mode == PROVED` and `verifier != 0`.
2. Compute its own `admissionDomain` as above — from `block.chainid`, its scheme registry and `address(this)`, never from calldata — and call `verifier.verify(schemeId, admissionDomain, publicInputs, proof)`; require `ok`.
3. Require the returned `subjectKey` equals `keccak256(abi.encode(subject.subjectType, subject.subjectData))`.
4. Require `nullifier` has not been consumed for `schemeId`; mark it consumed.
5. Reject a non-zero `expiresAt` that is not in the future.
6. Record an assertion with `issuer = verifier`, the returned `level`, `claimDigest`, `expiresAt` and `anchor`, and `evidenceHash = keccak256(publicInputs)`.

Binding requirements on any circuit and verifier used under this profile. These are normative for the *public-input layout and the verifier's checks*, not for the proving system:

- **Subject binding.** The public inputs MUST include `subjectKey`, or a commitment the verifier can open to it. A verifier MUST NOT derive `subjectKey` from anything outside the proof's public inputs.
- **Scheme binding.** The statement a proof verifies MUST be bound to the `schemeId` the verifier was called with: adapters MUST feed that `schemeId` into the circuit as a public input (or equivalent), so that a proof made for one scheme is not accepted under another. In addition, where a signed object carries a *pre-made verdict under a scheme* (a credential issued at a given level; Section 5.1, credential pattern), the signed object itself MUST include the `schemeId` and the circuit MUST constrain the two to be equal — otherwise a credential issued under a lenient scheme is presentable under a strict one that accepts the same issuer set (cross-scheme replay). This second requirement does not apply to signed *inputs* that carry no verdict (a bank statement, an exchange export, a task-registry record): such data may legitimately predate and be reused across schemes, and its binding to the scheme is provided by the computation the circuit performs, not by the data's signature.
- **Replay resistance.** The public inputs MUST include a `nullifier` scoped at minimum to `(schemeId, admissionDomain)`. Schemes SHOULD scope it to `(schemeId, admissionDomain, epoch)` so a subject can re-prove periodically; the descriptor's `circuit.nullifierScope`, `epochSeconds` and `epochGrace` declare which.
- **Time window.** The authority over the replay domain is the invariant: the prover MUST NOT control the epoch that determines replay eligibility; the verifier MUST derive it from system state. For the `scheme-epoch` profile the mechanism is `current = floor(block.timestamp / epochSeconds)` and a proof MUST be rejected unless `current - epochGrace <= epoch <= current`; for `nullifierScope == "scheme"` the verifier MUST require `epoch == 0`. Future profiles MAY derive the epoch differently (block ranges, finalised periods) provided the authority rule holds; the mechanism is profile-defined, the authority is not descriptor-optional. A credential is thus presentable once per epoch; revocation of the fact issuer's credential takes effect at the next epoch boundary, and a scheme chooses `epochSeconds` as its maximum revocation latency.
- **Admission-domain binding (registry admission).** A proof admitted into a KYA Registry MUST be bound to that registry's `admissionDomain`: adapters MUST feed the `admissionDomain` they were called with into the circuit as a public input (or equivalent), and the circuit MUST derive the `nullifier` from it (together with `schemeId` and, where used, `epoch`). Two consequences follow, and both are intended. First, a proof generated for KYA Registry A does not verify at KYA Registry B — whether B reads a different Scheme Registry or shares A's — and B cannot make it verify, because B computes the domain from its own address and the submitter has no parameter through which to supply another. Second, the same underlying credential MAY be proved again for B, producing a B-scoped nullifier: domain separation is per *proof*, not per credential. This profile therefore does not provide, and does not claim, "one credential, one use across all registries"; a use case needing that requires shared consumption state and its own profile. Rules stay reusable across markets; a specific proof does not. Ephemeral peer-to-peer presentations (below) use a request-bound domain rather than a registry's and are a separate context.
- **Issuer hiding (OPTIONAL).** A circuit MAY prove membership of the underlying attestor in an issuer set committed to by `issuerSetRoot`. The on-chain `issuer` is then the verifier address, the real attestor is not disclosed, and the verifier MUST return `issuerSetRoot` as `anchor`. Verifiers SHOULD pin a required `issuerSetRoot`; a rotation of the issuer set is a new verifier and therefore a new scheme version.
- **Selective disclosure.** `claimDigest` MUST be the only claim-bearing output; the scheme descriptor defines what it commits to.
- **Canonical decomposition.** Where 256-bit values are carried as field elements, the split MUST be unique (alias-checked), or a prover can present two encodings of one nullifier.

**What this profile hides, and what it does not.** `subjectKey` is public: anyone can see that *this agent* obtained *this level* under *this scheme* at *this time*. The profile hides which attestor vouched for it and every underlying fact (identity documents, jurisdiction, capital, model lineage). It is issuer-hiding and fact-hiding, not anonymous; unlinkability of the subject is out of scope and would require a different subject type.

**Canonical layout `kya-public-v1`.** `publicInputs = abi.encode(bytes32 subjectKey, bytes32 nullifier, uint8 level, bytes32 claimDigest, uint64 expiresAt, bytes32 issuerSetRoot, uint64 epoch)`, where `epoch` is `0` for schemes whose `nullifierScope` is `scheme`. `schemeId` and `admissionDomain` are deliberately *not* part of `publicInputs`: they are the two arguments the caller supplies to `verify`, and adapters MUST append them to the signal vector themselves so that both bindings are enforced by the chain rather than by the prover. Adapters for field-arithmetic proving systems SHOULD split each 256-bit value into `(hi128, lo128)` field elements rather than truncating; the reference Groth16 adapter does both, producing fifteen signals (seven layout fields split as needed, then `schemeId` and `admissionDomain`), and enforces the time-window rule with `epochSeconds` and `epochGrace` fixed at deployment.

**Ephemeral presentation.** A proved assertion MAY be presented in a handshake (Section 6) without ever being recorded on-chain. The relying party then calls `verifier.verify` via `staticcall` (which applies the time-window rule) with an `admissionDomain` of its own: `keccak256(abi.encode(keccak256("erc-kya-ephemeral-admission-v1"), chainId, <relying party's address>, <KYAChallenge digest>))`, which binds the proof to this counterparty and this request rather than to any registry; it applies rules 3 and 5 itself and tracks nullifiers locally if it needs replay protection across sessions. Recorded and ephemeral proved assertions are semantically identical; only persistence and the domain differ, and neither kind of proof is valid in the other's domain.

Any proving system — Groth16, PLONK, STARKs, membership-proof schemes, zero-knowledge virtual machine (zkVM) execution proofs, or Trusted Execution Environment (TEE) quotes wrapped as proofs — enters the framework by supplying an `IKYAVerifier`. This adapter boundary is the mechanism by which the framework remains compatible with future ZK-KYA algorithms without amendment.

#### 5.1 Usage patterns of proved schemes (informative)

The rules above do not say *who decided* the conclusion a proof carries. Two patterns are common; they are not exhaustive and not mutually exclusive — a single circuit may verify source-signed data *and* evaluate a relying party's rule over it. A scheme descriptor states what it does through `circuit`, `issuerPolicy`, `dimensions` and `evidenceKinds`.

**Credential pattern.** A fact issuer examines the subject off-chain and signs a verdict under a named scheme; the proof shows possession of a valid credential from a permitted issuer set without naming the issuer or revealing the facts. The conclusion was made in advance; the proof transports it privately. The reference circuit `kya-public-v1` is of this pattern, which is why it has an `issuerSetRoot`, an `anchor` and an `issuerPolicy` of `verifier-only`, and why its signed credential must carry the `schemeId`.

**Predicate pattern.** The scheme *is* the decision rule. The scheme controller — often the relying party itself, or a community agreeing on an underwriting standard — publishes the rule as a circuit or zkVM program and deploys its verifier. A prover evaluates the rule over its own private, authenticated data inside the proof; the public outputs are the verdict (`level`, or `claimDigest` for `categorical`/`opaque` results) and the binding fields. No third party issued a credit verdict beforehand; the on-chain `issuer` identifies the admitting verifier, and the parties that authenticated the inputs (if any) are input sources, not guarantors. The handshake in Section 6 is symmetric, so two agents may each publish a predicate scheme and each answer the other's with an ephemeral proof: each learns a verdict about the counterparty without being sent the counterparty's underlying data.

What the predicate pattern provides, and what it does not:

- It removes the need to *disclose* raw data to the counterparty. It does not destroy data, and this specification does not require or verify that any party deletes local data, proofs, or interaction records. A proof and its public outputs may be retained by the receiver.
- The private inputs must be **authentic**, or the prover fabricates them. Three sources, in decreasing order of trustlessness: (a) on-chain state — the circuit consumes storage or receipt proofs against a block hash, so the `anchor` is that block hash; (b) transport or web proofs (zkTLS-style) — a notary set attests the transcript, so the `anchor` is the notary-set commitment; (c) data signed by its source (an exchange, a bank, a task registry) — structurally like the credential pattern's signature check, except that the signer supplies *inputs*, not a *verdict*, and the verdict is still computed by the rule. Descriptors SHOULD name the input source in `dimensions` / `evidenceKinds` so relying parties know what `anchor` commits to.
- Authenticity is not completeness. A proof that some records are genuine does not show they are *all* the relevant records. A verdict under this pattern is therefore "the subject satisfies rule P over the named data sources, time window and coverage", never an unqualified "the subject is creditworthy"; descriptors SHOULD state that scope and relying parties SHOULD read it.
- A prover deciding whether to answer a challenge is accepting the scheme's *public outputs, parameters and query shape*, not merely its proof system. Scheme immutability (Section 3) lets a prover audit a rule once and recognise it again by `schemeId`; it does not make that audit permanently valid, and repeated answers to related rules can leak more than any single answer (Security Considerations).

**Ad-hoc rules (future extension).** With a universal zkVM verifier one scheme could bind the verifier once and let a relying party ship a *new* rule per interaction, its program commitment travelling as a public input. That requires a binding among the request, the program, its parameters and the data scope, so that the prover can audit exactly what it is about to answer and the relying party can check the proof is for exactly that; a program hash alone is not sufficient. Whether the binding is best carried inside `publicInputs`, in a new typed-data message, or as a versioned extension of the handshake is left to a follow-up; note that adding a member to `KYAChallenge` changes its EIP-712 type hash and is therefore a new message type, not a backward-compatible edit. This document specifies no such mechanism.

### 6. Handshake (off-chain, typed data)

Domain: `{ name: "KYA", version: "1", chainId, verifyingContract: <kyaRegistry> }`.

```
KYAChallenge(bytes32 verifierSubjectKey,bytes32 proverSubjectKey,bytes32[] schemeIds,bytes32 policyId,bytes32 nonce,uint64 expiry)
KYAPresentation(bytes32 challengeHash,bytes32[] assertionIds,bytes32 proofSchemeId,bytes publicInputs,bytes proof)
```

- `challengeHash` is the [EIP-712](./eip-712.md) digest of the `KYAChallenge`.
- A presentation carries recorded assertions by id, or one ephemeral proof (`proofSchemeId`, `publicInputs`, `proof`), or both. Unused fields are empty (`assertionIds = []`, `proofSchemeId = 0x0`, `publicInputs = proof = 0x`).
- The prover MUST sign the `KYAPresentation` with a key that controls `proverSubjectKey` under its subject type. For `erc8004` that is the agent's ERC-721 owner or an approved operator; contract accounts sign per [ERC-1271](./eip-1271.md).

Acceptance rules. A relying party MUST reject a presentation unless all of the following hold:

1. The signature is valid for `proverSubjectKey`'s controller *at the time of verification*.
2. `challengeHash` matches a challenge the relying party issued, `expiry` has not passed, and the challenge has not been answered before — each `nonce` is single-use, so a second presentation for the same challenge MUST be rejected even if it is otherwise valid.
3. Every listed assertion exists in the relying party's KYA Registry, has `subjectKey == proverSubjectKey`, is ACTIVE and unexpired, and its `schemeId` is one of the challenge's `schemeIds`; assertions under unlisted schemes MUST be ignored, and an assertion whose `issuer` (and, for proved assertions, `anchor`) is not accepted by the relying party's policy MUST NOT count.
4. If `policyId` is non-zero, the relying party evaluates that policy against the presented material; the policy, not the prover, decides which assertions matter.
5. An ephemeral proof, if present, passes the checks of Section 5 for `proofSchemeId`, and `proofSchemeId` is one of the challenge's `schemeIds`.
6. An empty presentation (no assertions and no proof) satisfies only a challenge whose `schemeIds` is empty and whose `policyId` is zero; otherwise it MUST be rejected.

Partial satisfaction is a policy question: a presentation that covers some but not all requested schemes is accepted iff the policy is satisfied. A presentation MAY carry at most one ephemeral proof; a prover that must prove under several schemes answers with several presentations to the same challenge only if the relying party issued it with that intent (by reusing `nonce` it explicitly re-issues), otherwise it records the proofs first and presents assertion ids.

- Mutual KYA is two independent challenge/presentation exchanges.
- Transport bindings (HTTP POST, an Agent-to-Agent (A2A) protocol message extension, Model Context Protocol (MCP) initialisation metadata) are informative here and MAY be specified by companion documents.

**Discovery.** An agent MAY publish `https://{domain}/.well-known/kya.json` conforming to [`kya-discovery.schema.json`](../assets/eip-8419/schemas/kya-discovery.schema.json):

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-8419#kya-discovery-v1",
  "kyaRegistry": "eip155:1:0x4444444444444444444444444444444444444444",
  "presentableSchemes": ["0x496a268d899db6a77e2e6c2716b129c1635a06b1d2738b83a906f21390e4cb8f"],
  "acceptedPolicies": ["0x0000000000000000000000000000000000000000000000000000000000000001"],
  "challengeEndpoint": "https://agent.example/kya/challenge"
}
```

### 7. Policy (minimal)

```solidity
interface IKYAPolicyRegistry /* is IERC165 */ {          // REQUIRED for policy registries
    event PolicyRegistered(bytes32 indexed policyId, address indexed owner, string policyURI, bytes32 policyHash,
                           bytes32 rulesHash);

    function registerPolicy(string calldata policyURI, bytes32 policyHash) external returns (bytes32 policyId);
    function getPolicy(bytes32 policyId) external view
        returns (address owner, string memory policyURI, bytes32 policyHash, bytes32 rulesHash);
}

interface IKYAPolicyEvaluator /* is IERC165 */ {         // OPTIONAL extension
    struct Rule { bytes32 schemeId; uint8 minLevel; address[] issuers; }

    function registerPolicyWithRules(string calldata policyURI, bytes32 policyHash, Rule[] calldata allOf)
        external returns (bytes32 policyId);
    function getRules(bytes32 policyId) external view returns (Rule[] memory);
    function rulesHashOf(Rule[] calldata allOf) external pure returns (bytes32);
    function evaluate(Subject calldata subject, bytes32 policyId) external view returns (bool);
}
```

- `policyId` MUST equal `keccak256(abi.encode(msg.sender, policyHash, rulesHash, nonce))` with a per-owner counter, where `rulesHash` is the commitment to the executable projection registered with the policy, or `0x0` when none is. One `policyId` therefore identifies one policy document and one exact executable projection; a stricter document cannot share an id with a weaker projection.
- `policyURI` MUST resolve to a document conforming to [`kya-policy.schema.json`](../assets/eip-8419/schemas/kya-policy.schema.json): a tree of `allOf` / `anyOf` nodes over rules `{schemeId, minLevel | level, issuers[], anchors[]?}`; `issuers` MUST be non-empty in every rule. Rules over `ordered-level` schemes use `minLevel`; rules over `categorical` schemes use `level` (equality); `anchors`, when present, restricts proved assertions to the listed trust anchors.
- **Executable projection.** On-chain evaluation is OPTIONAL and lives in `IKYAPolicyEvaluator`, so a client can detect via ERC-165 whether a registry evaluates or merely stores. The projection this interface can express is exactly: a top-level conjunction of rules over `ordered-level` schemes, each with a `minLevel > 0` and a non-empty issuer list; `registerPolicyWithRules` MUST revert on a rule whose `minLevel` is `0` (`KYA_ZeroThreshold`) or whose scheme's on-chain `resultKind` is not `ORDERED_LEVEL` (`KYA_NotOrderedLevel`), so a projection can neither encode "any assertion exists" as satisfaction nor rank a categorical code. `rulesHash` MUST equal `keccak256(abi.encode(allOf))` over the canonical ABI encoding of the `Rule[]`. A descriptor that advertises an on-chain projection MUST carry the same `rulesHash` (schema member `onchain.rulesHash`) and MUST NOT contain conditions the projection cannot express (`anyOf`, `level` equality, `anchors`) unless it also states that on-chain `evaluate` is a necessary-but-not-sufficient check. Committing two hashes does not by itself make document and projection equivalent; the correspondence is the descriptor author's claim, verifiable by anyone who compares the document's top-level `allOf` with `getRules`. `evaluate` MUST compute the stored rules as a conjunction of complete `IKYARegistry.check` calls (so binding predicates are included) and MUST revert if no rules are stored. Off-chain evaluation over the full tree is the general case.

### 8. ERC-8004 Binding Profile

1. **Subject.** `subjectType = keccak256("erc8004")`, `subjectData = abi.encode(chainId, identityRegistry, agentId)`.
2. **Registration file.** The ERC-8004 registration file's `supportedTrust` array MAY include `"kya"` and `"zk-kya"`. Its `services` array MAY include `{ "name": "KYA", "endpoint": "https://…/.well-known/kya.json", "version": "v1" }`.
3. **On-chain metadata.** The ERC-8004 metadata key `"kya"` is RECOMMENDED, set via `setMetadata(agentId, "kya", abi.encode(address kyaRegistry, bytes32[] advertisedSchemeIds))`.
4. **Mirror into the Validation Registry (MAY).** A *KYA Bridge* is a contract that acts as an ERC-8004 validator and mirrors KYA outcomes. The mirror is an OPTIONAL, LOSSY SNAPSHOT: it exports one 0–100 number per `(agent, scheme)` at the moment of `sync`, carries no expiry, revocation, binding or anchor information, and is only as fresh as its last sync. The KYA Registry remains the authoritative source; the bridge exists so that ERC-8004-only clients get a usable approximation without new code.
   - The bridge's operator configures, per scheme, the `issuers` it trusts and a `responseMap` from level to the 0–100 ERC-8004 scale (taken from the descriptor's `erc8004Response` values). The bridge MUST refuse (`BadResponseMap`) a map whose `responseMap[0]` is not `0` — level 0 is "not verified / failed" and is also what a missing, revoked, expired or binding-violated assertion resolves to, so a map that scored it would hand every unassessed agent a score — and MUST refuse a map that is not non-decreasing (`responseMap[i] >= responseMap[i-1]`), since the bridge mirrors ordered levels only and a higher level cannot mean a lower score; the map MUST also cover every level the scheme declares (see below). These are configuration-identity rules: `responseMap` is part of `configHash`, so a map that could change a verdict is treated like every other input to one and is refused rather than merely discouraged. Each configuration has an **interpretation identity** `configHash = keccak256(abi.encode(schemeId, trustedIssuers, responseMap))`. Reconfiguring is an authorised change of live interpretation, not a new scheme: it produces a new `configHash` that every subsequent response names, while the ERC-8004 request stays the same continuing mirror.
   - The agent owner or operator calls ERC-8004 `validationRequest(bridge, agentId, requestURI, requestHash)` with `requestHash = keccak256(abi.encode(keccak256("erc-kya-request-v1"), chainId, identityRegistry, bridge, agentId, schemeId))`. The request means "keep this bridge's mirror of this agent under this scheme current, naming the configuration in each response" — not "judge once under a configuration that never changes". It is stable over the life of `(bridge, agent, scheme)` and deliberately does not include the configuration, so that ERC-8004 aggregation (`getSummary`) filtered to this bridge and tag sees one record per agent and scheme rather than one per historical configuration. The committed request payload is that canonical ABI encoding; `requestURI` SHOULD resolve to a JSON document repeating the six fields for readers, and its bytes are not what `requestHash` commits to.
   - Anyone MAY call `bridge.sync(agentId, schemeId)`. The bridge MUST verify that the request exists and names the bridge as validator, resolve the subject under the configured issuers using complete resolution (`resolve`, so binding predicates apply), and call `validationResponse(requestHash, responseMap[level], "", responseHash, tag)` with `tag = "kya:" || <full schemeId as 64 lowercase hex characters>` and `responseHash = keccak256(abi.encode(assertionId, level, configHash))`. Each response therefore proves exactly which configuration produced it, and a reconfiguration followed by `sync` overwrites the same ERC-8004 record. A revoked, expired or binding-violated assertion resolves to level 0 and therefore drives the mirrored response to `responseMap[0]`. A bridge MUST refuse to configure a scheme whose on-chain `resultKind` is not `ORDERED_LEVEL` (`KYA_NotOrderedLevel`) and MUST refuse a `responseMap` that does not cover every level in the scheme's `levelMask` (`ResponseMapIncomplete`), so that a declared result can never reach `sync` unmapped; as defence in depth a level the map does not cover MUST still make `sync` revert rather than be guessed upward.
   - Because the mirror is a snapshot, an ERC-721 transfer of the agent after `sync` leaves a `controller`-bound conclusion visible in the Validation Registry until someone re-syncs (at which point complete resolution drives it to `responseMap[0]`), and likewise a reconfiguration leaves the previous configuration's result visible until the next `sync`. ERC-8004 clients that care about binding or about the current interpretation MUST consult the KYA Registry, or recompute `responseHash` from the configuration the bridge exposes through the view interface below.
   - A bridge MUST expose the following view interface so that clients can locate the registry it mirrors and recompute `configHash` and `responseHash`; it is not part of the ERC-165 identifiers in Section 10:

     ```solidity
     interface IKYABridge8004View {
         function kyaRegistry() external view returns (address);                        // the KYA Registry this bridge resolves against
         function getSchemeConfig(bytes32 schemeId) external view
             returns (address[] memory trustedIssuers, uint8[] memory responseMap, bytes32 configHash, bool configured);
     }
     ```
   - Three states are observable on the ERC-8004 side, two of them from ERC-8004 alone. An agent that was never synced has no `kya:`-tagged response at all (the bridge only writes on `sync`). An agent that was synced and has a *qualifying level-0 assertion* receives response `responseMap[0] = 0` with a `responseHash` that commits to that assertion's id. An agent with *no qualifying assertion* — none issued, revoked, expired or binding-violated — receives the same response `0` with a `responseHash` committing to `assertionId = 0x0`. A client that reads only the 0–100 score sees the last two alike; this is intentional. The mirror is a lossy snapshot whose default MUST be "not verified", and distinguishing "revoked" from "never assessed" on the ERC-8004 side would place revocation semantics into a snapshot that, by the paragraph above, carries none. A client that needs the distinction reads `responseHash`, or the KYA Registry.
   - ERC-8004-only clients read KYA outcomes through `getSummary(agentId, [bridge], tag)` and `getValidationStatus(requestHash)`, filtering on the *current* bridge deployment. A superseded bridge's records remain in the Validation Registry under the same tag; the stability guarantee above is per bridge, and a query that lists several bridges as validators aggregates across them by the client's own choice.
5. **Reputation as evidence (MAY).** Schemes MAY declare `erc8004-reputation` and `erc8004-validation` as evidence kinds. ERC-8004 signals are inputs to KYA; KYA assertions are conclusions. Neither replaces the other.
6. **Credential view (OPTIONAL).** A registry MAY additionally expose a single-key credential resolution function where `key = "kya:" || hex(schemeId)` returns `abi.encode(Assertion)` for the resolving subject, for clients that speak a generic credential-resolution interface.
7. **Scope of the `kya` names.** This ERC claims no global reservation of `kya`, `kya:` or `kya.*`. The metadata key, the `supportedTrust` values, the discovery document, the bridge tag and the optional credential-view key have their specified meaning only in the protocol context each is defined in above. Clients MUST NOT infer conformance to this ERC, or equivalence of levels, from the presence of `kya` or a level-like token in an identifier defined elsewhere; unrelated systems using such names do not collide with anything this ERC defines.

### 9. Errors

Implementations SHOULD use these custom errors: `KYA_SchemeNotFound(bytes32)`, `KYA_ModeMismatch(bytes32,uint8,uint8)`, `KYA_InvalidMode(uint8)`, `KYA_InvalidBinding(uint8)`, `KYA_InvalidResultKind(uint8)`, `KYA_InvalidLevelMask(uint8,uint256)`, `KYA_LevelNotDeclared(bytes32,uint8)`, `KYA_NotOrderedLevel(bytes32,uint8)`, `KYA_ZeroThreshold()`, `KYA_VerifierRequired()`, `KYA_VerifierNotContract(address)`, `KYA_VerifierCodeChanged(bytes32,bytes32,bytes32)`, `KYA_BindingUnevaluable(bytes32,uint8)`, `KYA_SchemeHashRequired()`, `KYA_VerifierRejected()`, `KYA_SubjectMismatch(bytes32,bytes32)`, `KYA_NullifierUsed(bytes32,bytes32)`, `KYA_EmptyIssuers()`, `KYA_Frozen(bytes32)`, `KYA_NotController(bytes32,address)`, `KYA_NotIssuer(bytes32,address)`, `KYA_AssertionNotFound(bytes32)`, `KYA_AssertionNotActive(bytes32)`, `KYA_BadPredecessor(bytes32)`, `KYA_Expired(uint64)`, `KYA_PolicyNotFound(bytes32)`, `KYA_NoOnchainRules(bytes32)`.

### 10. Interface identifiers

| interface | ERC-165 id |
|---|---|
| `IKYASchemeRegistry` | `0xe6dbd933` |
| `IKYARegistry` | `0x5d1bec61` |
| `IKYAPolicyRegistry` | `0x1cf9e558` |
| `IKYAPolicyEvaluator` | `0x173ff2b6` |
| `IKYAVerifier` | `0xfc2b4271` |

### 11. Initial vocabulary (informative)

`dimensions`: `controller-binding`, `provenance`, `capability`, `accountability`, `behavioral`, `compliance`, `runtime-integrity`.

`evidenceKinds`: `erc8004-reputation`, `erc8004-validation`, `vc-jwt`, `vc-ld`, `tee-quote`, `zk-proof`, `domain-proof`, `payment-history`.

### 12. Ordered-Level Profile: common ladder (informative)

Schemes adopting the Ordered-Level Profile (`result.kind == "ordered-level"`) are encouraged to align with this ladder.

| level | label | meaning |
|---|---|---|
| 0 | unknown / failed | no conclusion, or explicit fail |
| 1 | self-asserted | the subject's own claims, unverified |
| 2 | controller-linked | control of keys and endpoints demonstrated |
| 3 | provenance-verified | origin, code or model lineage verified by a third party |
| 4 | accountable | an identified legal or economic party stands behind the agent |
| 5 | continuously monitored | ongoing runtime or behavioural attestation in force |

Schemes are free to define their own ladders; this table is a shared reference so that descriptor authors converge and relying parties can read unfamiliar schemes quickly.

## Rationale

**A framework, not an algorithm.** ERC-8004 refused to standardise reputation math and thereby stayed useful to every reputation system. This ERC makes the same refusal one layer up: it standardises how a conclusion is *addressed, versioned, admitted, resolved and presented*, and leaves what the conclusion *means* to the scheme descriptor. Any attempt to fix a KYA rule set on-chain would be obsolete before it was finalised; a container for rule sets is not.

**Relying parties choose issuers.** `resolve` and `check` refuse an empty `issuers` list for the same reason ERC-8004's `getSummary` requires `clientAddresses`: an aggregate over "whoever wrote something" is Sybil-inflatable by construction. Trust in issuers is a relying-party decision and the interface makes that decision explicit and auditable — the issuers used are part of every bridge `responseHash`.

**One assertion structure, two admission paths.** ZK-KYA could have been a separate registry. Making it a *mode* of the same registry means a policy, a resolver, an indexer and a bridge treat an attested level 4 and a proved level 4 identically; the only difference is who is recorded as `issuer` and that a proved assertion carries an `anchor`. Recording the verifier as issuer lets relying parties express "I trust proofs admitted by this verifier" with the same `issuers[]` vocabulary they use for human attesters, and `anchor` keeps the hidden fact issuers accountable as a set even though none is named.

**Verifier as adapter.** Putting the proving system behind `IKYAVerifier` and fixing only the *public-input layout and the verifier's obligations* is what makes the profile future-proof. The registry never learns whether a proof was Groth16, a STARK or a TEE quote; it learns seven fields. New systems require a new adapter contract, not a new ERC.

**Why the ZK profile is not tied to issuers.** It would have been simpler to define ZK-KYA as "private presentation of a credential". The framework deliberately stops at the verifier boundary so that a scheme may also *be* the decision rule (Section 5.1, predicate pattern): a relying party publishes its underwriting standard, the counterparty proves it satisfies it over private data, and the chain records — or the handshake conveys — only the verdict. That pattern needs no pre-issued credit verdict and lets a relying party's own rule be evaluated without receiving the counterparty's data; the credential pattern remains the right tool where a check cannot be expressed as a rule over authenticated data (a human compliance review, for instance), and the two combine freely. Supporting both through one interface is why `issuer` is defined as "the admitting verifier" for proved assertions rather than "the party who examined the subject" — the field records which verification logic admitted the assertion, not who is answerable for the facts.

**Scheme immutability.** If a controller could re-point an unfrozen scheme's descriptor or verifier, `schemeId` would be an unstable reference: a policy pinning it could be redefined underneath it, and an assertion's meaning could change after it was recorded. Making scheme semantics immutable and routing every change through `predecessor` costs one registration per version and removes that whole class of problems; `freeze` therefore only stops URI re-pointing.

**`level` as `uint8` with scheme-scoped semantics, ordering as a profile.** A single numeric axis gives contracts a cheap comparison (`level >= minLevel`) while leaving meaning to the descriptor. Not every KYA result is a rank, however: a sanctions screen is pass/fail, a jurisdiction is a category. Rather than force those into a ladder, the total-order assumption behind `resolve`'s "highest wins", `check`'s `minLevel` and the bridge's `responseMap` is isolated as the Ordered-Level Profile, and other result kinds use `level` as a code or leave it `0` with the result in `claimDigest`. Section 12 offers a common ladder so ordered schemes converge, but comparing levels across schemes without reading descriptors is unsafe and the specification says so.

**The result domain is committed on-chain.** Keeping `levels` as a descriptor-only table while `attest` accepts any `uint8` and `check` compares whatever it finds has two consequences: a trusted issuer can record a level the scheme never defined (255 under a scheme declaring `{0, 2, 4}`) and have it satisfy a threshold, and a level-0 "failed" assertion satisfies `check` at `minLevel == 0`, so zero means "an assertion exists" rather than "verified to at least this level". Both are instances of the same defect that `rulesHash` closes for policies and `configHash` closes for bridges: a value capable of changing a decision that is not committed by the identity of the thing being evaluated. The registry cannot read the descriptor, so the domain is put where the registry can enforce it — `resultKind` and a 256-bit `levelMask` in the immutable `Scheme`, checked at admission — and `check` refuses a zero threshold rather than silently answering a different question. Ordering is still a profile; its inputs are committed rather than assumed.

**Binding, and why the registry evaluates it.** The framework cannot know whether "this agent is accountable" survives the agent's sale to a new owner, so each scheme states what it binds to. Leaving the transfer check entirely to relying parties would produce two answers to "does this subject satisfy policy P?" from one registry state: a compliant relying party says no after a transfer while the on-chain evaluator still says yes. Binding is therefore split into scheme-level *kind*, assertion-level *witness* and resolution-time *predicate*, and complete resolution evaluates the predicate. The registry evaluates it natively only for the subject type it is required to support (`erc8004` on its own chain) and refuses to record controller-bound assertions it could never check, rather than pretending; other subject types can add resolvers in follow-ups. A registry-local view remains for indexers, explicitly labelled as not complete.

**Identities commit what executes.** Three identifiers commit what executes, for the same reason: a `policyId` commits the executable projection (`rulesHash`), a bridge *response* commits the configuration that produced it (`configHash`), and a proof commits the admission domain that consumes it (`admissionDomain`). In each case a derivation that omitted the committed element would allow an executable path — different rules, a different response map, a second KYA Registry sharing the same scheme catalogue — to exercise authority its identity did not name. The bridge configuration deliberately goes into the response rather than the request: the scheme does not become a different object when a bridge operator changes a mapping, so the request remains the continuing mirror of `(bridge, agent, scheme)` and only the provenance of each result changes; putting it in the request would leave one frozen record per historical configuration for `getSummary` to average.

**Two registries, co-deployable.** Schemes and assertions have different governance: schemes are curated by controllers and rarely change; assertions are written constantly by many issuers. Separate interfaces let them be upgraded or governed independently; nothing prevents one contract from implementing both, mirroring ERC-8004's three-registry design.

**Mirroring into Validation, not Reputation.** ERC-8004 Validation is third-party judgement on a 0–100 scale posted by a designated validator — exactly the shape of a mirrored KYA conclusion. Reputation is client feedback and would misrepresent an issuer's verdict as a customer's opinion. Requiring the agent to file the `validationRequest` preserves ERC-8004's rule that only the agent may invite a validator, while letting anyone trigger `sync` keeps mirrored state fresh after revocations.

**Admission domain rather than registry-bound schemes.** Binding a proof to the chain and the Scheme Registry does not bind it to the contract that actually consumes its nullifier: two KYA Registries reading one catalogue receive the same `schemeId`, the same proof and the same nullifier, and keep separate consumption maps. Two fixes are available. Folding the admitting registry into `schemeId` closes the gap with no circuit change, but it makes a scheme a "rule for one registry": two markets wanting the same underwriting rule must register two schemes, and — because a credential in the credential pattern signs the `schemeId` — attestors must issue a separate credential per registry. That trades away the property the framework is for. This specification instead keeps `schemeId` as the rule's identity and gives the proof a second, explicit context: an `admissionDomain` computed by the consuming contract from its own chain, catalogue and address, fed to the circuit as a public input and folded into the nullifier. The same credential can be proved for several registries; a specific proof works in exactly one. The cost is a public-input change relative to a design without the domain, which is why the domain is part of the canonical layout rather than an optional extension.

**Deterministic `requestHash`.** Deriving the bridge's request hash from `(chainId, identityRegistry, bridge, agentId, schemeId)` lets any observer verify that a mirrored validation corresponds to a specific scheme without fetching `requestURI`, prevents one request from being synced under a different scheme, and keeps two bridges from colliding; the interpretation that produced a given result is recoverable from its `responseHash`. The tag carries the full `schemeId` because a 32-bit prefix is cheap to collide deliberately, and consumers aggregate by tag.

**Relationship to prior work.** Single-function credential-resolution interfaces answer "how do I fetch a credential by key"; general attestation services answer "how do I store a typed attestation". Neither provides a subject abstraction spanning ERC-8004 agents and other agent forms, a level with scheme-scoped semantics, verifier-gated admission, per-issuer supersession and revocation, or a normative mirror into ERC-8004. Both can serve as storage or access layers *beneath* this ERC — an implementation may persist assertions in an attestation service and expose the credential view of Section 8.6 — which is why this ERC defines the KYA semantic layer rather than another generic attestation primitive.

## Backwards Compatibility

No changes to ERC-8004 contracts are required. All ERC-8004 interactions use the existing `setMetadata`, `validationRequest`, `validationResponse`, `getSummary` and `getValidationStatus` entry points. ERC-8004 registration files remain valid with or without the optional KYA members. Agents that are not registered under ERC-8004 participate through the `account`, `erc721` or `did` subject types.

## Test Cases

Deterministic vectors are provided in [`vectors.json`](../assets/eip-8419/vectors/vectors.json). They cover: `subjectType` hashes; `subjectKey` for an `erc8004` subject; `schemeId` (with chain and scheme registry), the scheme's `resultKind` and `levelMask` derived from the example descriptor, `admissionDomain`, `assertionId`, `rulesHash` and `policyId` derivations; a controller binding witness; the canonical `kya-public-v1` public-input encoding, its `evidenceHash`, and its fifteen-signal Groth16 split (layout, then `schemeId`, then `admissionDomain`); the bridge `configHash`, `requestHash`, `responseHash`, `tag` and metadata value; EIP-712 digests for `KYAChallenge`, an assertion-based `KYAPresentation` and an ephemeral ZK `KYAPresentation`, with a signature from a well-known test key; and the five ERC-165 interface ids of Section 10. Every vector can be recomputed from the definitions in this document and checked against the reference contracts in the assets.

A conforming implementation is expected to exhibit at least the following behaviours, each of which follows from a normative rule above:

- scheme lifecycle: semantic immutability after registration, controller-only `freeze` and URI re-pointing, `predecessor` chaining (Section 3);
- attested recording, supersession of the issuer's previous assertion, revocation and expiry (Section 4);
- resolution ordering, the non-empty-`issuers` rule and the `minLevel == 0` refusal (Section 4);
- proved admission with subject-mismatch, replay and mode-mismatch rejections, `issuerSetRoot` pinning and the epoch window (Section 5);
- a controller-bound assertion ceasing to satisfy complete `check` / `evaluate` after an ERC-721 transfer while remaining visible to `resolveLocal`, satisfying again after a transfer back while it is still the issuer's latest, and not when the issuer re-attested to the interim controller in between (Section 2.1);
- a strict policy document and a weaker executable projection never sharing a `policyId` (Section 7);
- bridge reconfiguration changing `configHash` but not `requestHash`, the previous result remaining visible until the next `sync`, and `getSummary` filtered to one bridge reading one record with the current response — a map that scored a level 100 and is reconfigured to score it 0 reads 0 after re-sync, not an average — while a superseded bridge's record is excluded by that filter and included only when the client asks for both (Section 8);
- a changed verifier code hash refused at admission; distinct `schemeId`s sharing a 32-bit prefix producing distinct tags (Sections 3, 8);
- admission domains: identical scheme inputs on a second Scheme Registry yielding a different `schemeId`; one Scheme Registry with two KYA Registries A and B yielding one `schemeId` and two domains, a proof made for A refused by B both before and after A consumes it, the same credential re-proved for B admitted with a B-scoped nullifier, and no parameter through which a submitter can supply a domain (Section 5);
- result domain: a scheme declaring `{0, 2, 4}` refusing level 255 and level 3 at admission on both the attested and the proved path; a level-0 assertion visible to `resolve` while `check` refuses `minLevel == 0`; a policy rule with `minLevel == 0` refused; a categorical scheme's assertions readable but not comparable, mirrored or placed in a policy projection; an opaque scheme refusing a non-zero level; malformed masks (ordered without level 0, opaque with a higher bit, empty categorical) refused at registration (Sections 3, 4, 7, 8);
- response maps: a map whose first entry is non-zero or that is not non-decreasing refused at configuration, equal steps accepted; a never-synced agent having no mirrored response, a synced agent with no qualifying assertion having response 0 with `responseHash` committing to `assertionId = 0x0`, a synced agent with a qualifying level-0 assertion having response 0 with `responseHash` committing to that assertion, and revocation returning the commitment to `0x0` (Section 8);
- for proving systems plugged in through `IKYAVerifier`: prover-chosen future or stale epochs, cross-scheme replay of a credential, tampered public inputs, aliased field-element encodings and an attestor outside the pinned issuer set all refused, and a verifier accepting a proof under one registry's admission domain while rejecting the same proof under another's (Section 5).

## Reference Implementation

A reference implementation is provided under the assets of this proposal:

- Interfaces: [`IKYATypes.sol`](../assets/eip-8419/contracts/interfaces/IKYATypes.sol), [`IKYASchemeRegistry.sol`](../assets/eip-8419/contracts/interfaces/IKYASchemeRegistry.sol), [`IKYARegistry.sol`](../assets/eip-8419/contracts/interfaces/IKYARegistry.sol), [`IKYAPolicyRegistry.sol`](../assets/eip-8419/contracts/interfaces/IKYAPolicyRegistry.sol), [`IKYAVerifier.sol`](../assets/eip-8419/contracts/interfaces/IKYAVerifier.sol), and a minimal [`IERC8004Validation.sol`](../assets/eip-8419/contracts/interfaces/IERC8004Validation.sol).
- Registries: [`KYASchemeRegistry.sol`](../assets/eip-8419/contracts/KYASchemeRegistry.sol), [`KYARegistry.sol`](../assets/eip-8419/contracts/KYARegistry.sol), [`KYAPolicyRegistry.sol`](../assets/eip-8419/contracts/KYAPolicyRegistry.sol) — permissionless.
- Bridge: [`KYABridge8004.sol`](../assets/eip-8419/contracts/KYABridge8004.sol) — curated ERC-8004 validator mirroring KYA outcomes.
- Verifier adapter: [`Groth16KYAVerifierAdapter.sol`](../assets/eip-8419/contracts/verifiers/Groth16KYAVerifierAdapter.sol) — adapts a snarkjs-style Groth16 verifier to `IKYAVerifier` using the `kya-public-v1` layout.

Schemas for the scheme, policy and discovery documents: [`kya-scheme.schema.json`](../assets/eip-8419/schemas/kya-scheme.schema.json), [`kya-policy.schema.json`](../assets/eip-8419/schemas/kya-policy.schema.json), [`kya-discovery.schema.json`](../assets/eip-8419/schemas/kya-discovery.schema.json).

## Security Considerations

**Issuer trust is out of scope by design.** The framework guarantees only that an assertion was recorded by the stated issuer (or admitted by the stated verifier) under the stated scheme. Whether that issuer is competent or honest is a relying-party decision expressed through `issuers[]`. Registries do not aggregate across unspecified issuers (`resolve` rejects an empty issuer list, Section 4), and clients are well advised to treat any UI that shows "a KYA level" without naming issuers as misleading.

**Subject substitution.** A proof that verifies but binds a different `subjectKey` must never be recorded for the presented subject; this is why rule 3 of Section 5 requires verifiers to derive `subjectKey` from the proof's public inputs alone. Ephemeral presentations require the relying party to perform the same check.

**Proof replay.** Nullifier consumption is per scheme within one KYA Registry, and a KYA Registry is not the Scheme Registry it reads from: several may share one catalogue. A proof is therefore bound to the *admission domain* of the KYA Registry that consumes it — chain, catalogue and registry address, computed by that registry and fed to the circuit — and its nullifier is derived from that domain (Section 5). A proof admitted at KYA Registry A is not valid at KYA Registry B, whether B shares A's Scheme Registry or not, and B cannot make it valid. The same credential can be proved afresh for B; this profile prevents moving a proof, not re-proving a fact. Relying parties accepting ephemeral proofs use a request-bound domain and are expected to track nullifiers themselves (Section 6). Epoch-scoped nullifiers deliberately permit re-proving after an epoch boundary; schemes choose the epoch length to balance revocation latency against linkability. The epoch is enforced by the verifier from `block.timestamp` (Section 5, time window) — a prover who can pick the epoch can pick a fresh nullifier at will, which reduces replay protection to nothing.

**Cross-scheme replay.** If a credential carrying a pre-made verdict does not name the scheme, the same credential is presentable under every scheme whose verifier accepts that issuer, and a level meant under a lenient ladder is read under a strict one. The scheme-binding rule of Section 5 closes this; adapters that receive `schemeId` from the registry and feed it into the circuit as a public signal make it unforgeable by the prover. Signed inputs without a verdict are exempt from the credential half of the rule; their reuse across schemes is intended, and what prevents misuse is that the circuit, not the data, encodes the rule.

**Query composition under the predicate pattern.** A proof system being zero-knowledge bounds what one proof reveals; it says nothing about what a *sequence* of answers reveals. A relying party that may pose "balance above 100?", then "above 50?", then "above 75?" learns the balance to arbitrary precision from perfectly zero-knowledge answers. Provers are advised to treat each scheme's public outputs and parameters, and the set of schemes they are willing to answer for one counterparty, as the disclosure decision — not the proof system — and to refuse challenges whose combination narrows a private value. This specification defines no privacy budget; schemes intended for repeated querying are expected to say so in their descriptor and to choose outputs (coarse levels rather than thresholds close together) accordingly. Immutable scheme semantics let a prover recognise an audited rule, but an audit is a judgement at a point in time and needs revisiting as circuits and proof systems age.

**Verifier and issuer-set choice.** A verifier's meaning is fixed by its circuit, verification key and accepted issuer set. Since scheme semantics are immutable, changing any of these is a new scheme; relying parties are advised to pin `schemeId` and, for proved schemes, the expected `anchor`, and to treat a new `predecessor` chain entry as a trust decision rather than an upgrade to accept automatically.

**Binding and transfer.** An `erc8004` subject can be sold. A `controller`-bound assertion recorded before the sale says nothing about the buyer, yet remains ACTIVE in the registry. Complete resolution excludes it once the controller witness no longer matches; registry-local resolution does not, and consumers of `resolveLocal` or of raw events have to apply the predicate themselves (Section 4 forbids presenting a registry-local result as complete policy satisfaction). Issuers of controller-bound schemes are advised to keep `expiresAt` short and can re-attest to the new controller. The predicate compares controllers, not custody history: a transfer away and back restores a still-active assertion (Section 2.1), so an attacker who briefly acquires and returns an agent gains nothing from the round trip itself, while a seller who buys the agent back regains the conclusions issued to them — including any that the interim owner's changes to keys, endpoints or model may have made stale. `expiresAt` is the bound on that exposure; relying parties who need an unbroken chain of custody check `Transfer` events off-chain. Bridges mirror snapshots: a mirrored value is stale until the next `sync`.

**Verifier mutation.** A PROVED scheme's meaning includes its verifier's behaviour. Code-hash pinning at registration detects a different contract appearing at the verifier's address; it cannot detect a proxy whose implementation changes, which is why Section 3 prohibits upgradeable or externally parameterised verifiers; relying parties are nevertheless advised to inspect a verifier's code before trusting a scheme. Declared, rule-governed state (a revocation source, a rotation mechanism) is not mutation; undeclared authority to change admission is.

**Controller revocation power.** Scheme controllers may revoke any assertion under their scheme. This is intended (a scheme operator withdrawing a compromised issuer's verdicts) but concentrates power; policies that cannot tolerate it can reference frozen schemes whose controller is a multisig or governance contract.

**Level inflation and semantic drift.** Levels are scheme-scoped `uint8` values. A scheme that maps trivial checks to high levels is not a protocol violation, only a bad scheme; the defence is issuer and scheme selection, and the `levels` table in the descriptor, which relying parties are expected to read before setting `minLevel`. What the registry does guarantee is narrower and mechanical: a level that the scheme did not declare is refused at admission, and a zero threshold cannot be asked, so neither an undeclared value nor a declared failure can satisfy a policy. A relying party that reads a non-zero `check` result may rely on the level being one the descriptor defines; what that level *means* remains the descriptor's claim. On the ERC-8004 mirror the same guarantee is mechanical as well: a bridge cannot be configured to score level 0 or to score a higher level below a lower one, so an operator cannot turn "no assertion" into a passing number or invert a scheme's ladder through configuration; the remaining freedom — which number a declared level maps to — is visible in `configHash` and `getSchemeConfig`.

**Supersession by the same issuer.** Because a new assertion supersedes the issuer's previous one, an issuer can silently downgrade a subject. This is by design — it is how issuers correct themselves — but clients tracking a subject are advised to subscribe to `Asserted` and `Superseded` events rather than caching a level.

**Revocation latency and expiry.** Revocation is effective from the block it is mined; off-chain caches and mirrored ERC-8004 responses lag until the next `sync`. Schemes are expected to set finite `expiresAt` values so stale conclusions age out even if no one revokes them (Section 4 marks a zero `expiresAt` as not recommended). Bridges are best synced by the party relying on them, not only by the agent.

**Privacy.** Every recorded assertion, attested or proved, reveals `(subjectKey, schemeId, level, issuedAt, expiresAt)` on-chain, and `subjectKey` for an `erc8004` subject is trivially linkable to the agent. The ZK-KYA profile hides the fact issuer and the underlying facts; it does not hide the subject, and epoch-scoped re-proofs of the same subject are linkable by `subjectKey` regardless of the nullifier. Parties that need to hide even the existence of a check can use ephemeral proved presentations, which leave no on-chain trace. `claimDigest` is required by Section 4 to be a salted commitment rather than a direct encoding of the underlying claims, because a low-entropy encoding is a dictionary-attackable disclosure. Implementers are advised not to describe ZK-KYA as anonymous.

**Bridge honesty and staleness.** A bridge is only as trustworthy as its operator's issuer configuration; a malicious bridge can mirror arbitrary responses, and an honest one is stale between syncs. ERC-8004 clients are expected to verify a bridge's `kyaRegistry()` and `getSchemeConfig(schemeId)` (the view interface in Section 8) before trusting the `kya:` tag, exactly as they would vet any other validator address, and to treat the mirrored number as an approximation of the KYA Registry, never as the record.

**Gas and denial of service.** `resolve` is linear in `issuers.length`; policies are well advised to keep issuer lists short. Scheme and policy registration are permissionless and cheap, so ids are namespaced by controller and cannot collide or be squatted.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
