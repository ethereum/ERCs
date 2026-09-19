---
eip: 9999
title: Know-Your-Agent (KYA) Framework
description: Scheme-agnostic registries and handshake for trust assertions about AI agents, with a zero-knowledge profile and agent-registry binding
author: Gary Yang (@garyyang-finchip)
discussions-to: https://ethereum-magicians.org/t/draft-erc-know-your-agent-kya-framework-trust-assertions-for-agents-zk-kya-profile-erc-8004-binding/29735
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

The framework is deliberately **scheme-agnostic**: it does not define how an agent is verified nor what makes an agent trustworthy. Those rules live in scheme descriptors and in pluggable verifier contracts. A **ZK-KYA profile** specifies how an assertion is admitted on the strength of a zero-knowledge proof instead of an issuer signature, using the same registry and the same assertion structure; it hides the fact issuer and the underlying facts, not the subject. An **[ERC-8004](./eip-8004.md) binding profile** makes ERC-8004 agents the primary subject type and mirrors KYA conclusions into the ERC-8004 Validation Registry so that ERC-8004-only clients can consume them without change.

## Motivation

ERC-8004 gives agents a portable identity and a place to accumulate raw trust *signals*: client feedback in the Reputation Registry and third-party judgements in the Validation Registry. It intentionally stops there. What it does not provide is a shared vocabulary for trust *conclusions* — the answer to "is this agent acceptable for this interaction?" — expressed so that both sides can name what was checked, under which rules, by whom, until when, and whether it still holds.

Off-chain "Know Your Agent" offerings are multiplying: payment networks gate agent wallets, compliance vendors score agent operators, marketplaces vet agent provenance. Each publishes its own verdict format and none is intelligible to the others. An agent that has been vetted by one provider cannot show that fact to a counterparty that speaks a different provider's dialect; a counterparty cannot say, in one machine-readable sentence, "I accept level 3 or better under scheme X from issuers A or B". The autonomous economy needs a single place to *look up* a trust conclusion and a single message to *ask for* one, regardless of which vendor or algorithm produced it.

Privacy sharpens the requirement. Many KYA facts — the controlling legal entity, its jurisdiction, its capital backing, the model lineage behind an agent — must not be disclosed to every counterparty. A framework that cannot admit a zero-knowledge proof as a first-class assertion source forces disclosure by design and will be bypassed by exactly the operators who most need to be known.

The relationship to ERC-8004 is the same as ERC-8004's relationship to [ERC-721](./eip-721.md): a registry, not a policy. ERC-721 records *who owns*; ERC-8004 records *what was signalled*; this ERC records *what was concluded and under which principle*. In the same way that token-bound extensions of ERC-721 add executable or task semantics without redefining the token, this ERC adds assurance semantics to ERC-8004 agents without redefining the agent.

Illustrative flows this framework enables (informative):

- A skill provider under a token-bound skill standard presents a KYA assertion before delivery; the buyer's contract calls `check(subject, schemeId, minLevel, issuers)` as a purchase precondition.
- A task fulfiller under a token-bound task standard is required by the task's descriptor to satisfy a KYA `policyId` before reserving the task; the adjudicators of that task may in turn be required to satisfy another scheme.
- Two agents perform mutual KYA over an [EIP-712](./eip-712.md) challenge/presentation exchange before opening a payment channel; one of them proves accountability with a zero-knowledge proof whose issuer is never revealed.
- A lender agent publishes its own underwriting rule as a scheme ("net inflow over 180 days above a threshold, no interaction with a sanctions list, at least N settled tasks"); a borrower agent evaluates the rule over its authenticated private history inside a proof and presents only the verdict. The lender never has to receive the history, and no third party had to issue a credit verdict beforehand.
- A payment processor that only understands ERC-8004 reads the same KYA outcome from the ERC-8004 Validation Registry under a `kya:` tag.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

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
| `did`     | UTF-8 bytes of the DID string | MAY |

Later ERCs MAY register additional subject types. Registries MUST NOT reject an unknown `subjectType` on write; resolution semantics for unknown types are implementation-defined.

#### 2.1 Binding

A `subjectKey` names a record, not necessarily the party that matters to a relying party. An `erc8004` subject is an [ERC-721](./eip-721.md) token: its owner can change, the software behind it can change, and neither event touches the registry. Every scheme therefore declares, in its descriptor, one `binding`:

| `binding` | the assertion is about | invalidated by |
|---|---|---|
| `identity` | the subject record itself, whoever controls it | nothing but revocation or expiry |
| `controller` | the party controlling the subject at `issuedAt` | a change of controller (for `erc8004`: an ERC-721 transfer) |
| `instance` | a specific code, model or configuration of the subject, identified by `claimDigest` | any change to that instance |

Rules:

- The registry does not track controller changes. For a `controller`-bound scheme, relying parties MUST treat an assertion as invalid if the subject's controller changed after the assertion's `issuedAt` (for `erc8004`: `Transfer` events of the identity registry, or a comparison of `ownerOf(agentId)` against evidence the issuer published), and issuers SHOULD set short `expiresAt` values.
- For an `instance`-bound scheme, `claimDigest` MUST commit to the instance identifier defined by the descriptor, and relying parties MUST compare it to the instance they are about to interact with.
- Assertions carry no interaction context. A relying party that needs "trusted for this counterparty / this amount / this task" expresses it in a Policy (Section 7) or in the handshake challenge (Section 6), never by reinterpreting `level`.

### 3. Scheme Registry

```solidity
interface IKYASchemeRegistry /* is IERC165 */ {
    enum SchemeMode { ATTESTED, PROVED }   // uint8; values >= 2 reserved

    struct Scheme {                // schemeHash, mode, verifier and predecessor are IMMUTABLE
        address controller;
        string  schemeURI;         // may be re-pointed to another copy of the same bytes
        bytes32 schemeHash;        // keccak256 of the descriptor bytes; non-zero
        uint8   mode;
        address verifier;      // non-zero iff mode == PROVED
        bytes32 predecessor;   // previous version's schemeId, or 0x0
        bool    frozen;
    }

    event SchemeRegistered(bytes32 indexed schemeId, address indexed controller, uint8 mode, address verifier,
                           string schemeURI, bytes32 schemeHash, bytes32 predecessor);
    event SchemeURIUpdated(bytes32 indexed schemeId, string schemeURI);
    event SchemeFrozen(bytes32 indexed schemeId);
    event SchemeControllerTransferred(bytes32 indexed schemeId, address indexed from, address indexed to);

    function registerScheme(string calldata schemeURI, bytes32 schemeHash, uint8 mode, address verifier,
                            bytes32 predecessor) external returns (bytes32 schemeId);
    function setSchemeURI(bytes32 schemeId, string calldata schemeURI) external;
    function freezeScheme(bytes32 schemeId) external;
    function transferSchemeController(bytes32 schemeId, address newController) external;

    function getScheme(bytes32 schemeId) external view returns (Scheme memory);
    function schemeExists(bytes32 schemeId) external view returns (bool);
    function schemeNonce(address controller) external view returns (uint256);
}
```

Rules:

- `schemeId` MUST equal `keccak256(abi.encode(msg.sender, schemeHash, nonce))` where `nonce` is a per-controller counter starting at 0 and incremented on every successful `registerScheme`.
- `mode` MUST be 0 or 1; any other value MUST revert. For `PROVED`, `verifier` MUST be non-zero. For `ATTESTED`, implementations MUST store `verifier` as the zero address.
- `predecessor`, when non-zero, MUST reference an existing scheme whose `controller` is `msg.sender`.
- **Semantic immutability.** `schemeHash`, `mode`, `verifier` and `predecessor` MUST NOT change after registration; the interface exposes no entry point that changes them. Any change to what a scheme checks, how it expresses results or which verifier admits proofs MUST be registered as a new scheme with `predecessor` set. Consequently a `schemeId` denotes exactly one meaning for its whole life, and a policy that pins a `schemeId` cannot be repointed underneath it.
- `setSchemeURI` MUST revert unless called by the controller, MUST revert on a frozen scheme, and MUST NOT alter `schemeHash`; clients MUST verify the fetched descriptor against `schemeHash`. `freezeScheme` MUST revert unless called by the controller; a frozen scheme accepts no further `setSchemeURI`.
- `schemeHash` MUST be the keccak256 of the descriptor bytes and MUST be non-zero (`KYA_SchemeHashRequired`), including for content-addressed URIs.
- Implementations MUST support [ERC-165](./eip-165.md) and MUST return `true` for the `IKYASchemeRegistry` interface id.

#### 3.1 Scheme Descriptor

`schemeURI` MUST resolve to a JSON document conforming to the schema in [`kya-scheme.schema.json`](../assets/eip-9999/schemas/kya-scheme.schema.json). Required members are `type`, `name`, `description`, `version`, `mode`, `binding`, `result` and `dimensions`; `levels` is additionally REQUIRED when `result.kind` is `"ordered-level"`, and `circuit` when `mode` is `"proved"`.

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-9999#kya-scheme-v1",
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
    "epochSeconds": 2592000,
    "epochGrace": 1,
    "issuerHiding": true,
    "issuerSetRoot": "0x1a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f809"
  }
}
```

- `result.kind` is `"ordered-level"` (the Ordered-Level Profile: `level` is totally ordered, higher is stronger, `minLevel` is meaningful), `"categorical"` (`level` is an opaque code from `result.codes`, comparison is equality) or `"opaque"` (`level` MUST be `0`; the result is whatever `claimDigest` commits to, as defined by `result.description`).
- Under `"ordered-level"`, `levels` MUST contain key `"0"`, whose meaning is "not verified / failed". Each level MAY carry `erc8004Response` (0–100), the value a KYA Bridge (Section 8) SHOULD mirror for that level.
- `binding` is one of `identity`, `controller`, `instance` (Section 2.1).
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
        uint8   status;
    }

    event Asserted(bytes32 indexed assertionId, bytes32 indexed subjectKey, bytes32 indexed schemeId, address issuer,
                   uint8 level, bytes32 claimDigest, uint64 expiresAt, string evidenceURI, bytes32 evidenceHash, bytes32 anchor);
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

    // Resolution (Ordered-Level Profile) — `issuers` MUST be non-empty
    function resolve(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)
        external view returns (uint8 level, uint64 expiresAt, bytes32 assertionId);
    function check(Subject calldata subject, bytes32 schemeId, uint8 minLevel, address[] calldata issuers)
        external view returns (bool);
}
```

Rules:

- `attest` MUST revert if the scheme does not exist or its `mode` is not `ATTESTED`. `attestWithProof` MUST revert if the scheme does not exist, its `mode` is not `PROVED`, or its `verifier` is zero.
- `assertionId` MUST equal `keccak256(abi.encode(subjectKey, schemeId, issuer, issuerNonce))` where `issuerNonce` is a per-issuer counter starting at 0 and incremented on every successful record.
- A non-zero `expiresAt` that is not in the future MUST revert.
- Recording a new assertion for a `(subjectKey, schemeId, issuer)` triple that already has an ACTIVE assertion MUST mark the previous one `SUPERSEDED` and emit `Superseded`. `latestAssertion` MUST return the most recently recorded id for the triple regardless of status.
- `revoke` MUST revert unless the caller is the assertion's `issuer` or the scheme's current `controller`, and MUST revert if the assertion is not ACTIVE.
- `resolve` MUST revert if `issuers` is empty. It MUST consider, for each listed issuer, only that issuer's latest assertion for the pair, and only if it is ACTIVE and unexpired (`expiresAt == 0 || expiresAt > block.timestamp`). It MUST return the highest `level` among them, breaking ties by latest `issuedAt`; when none qualifies it MUST return `(0, 0, 0x0)`. This "highest wins" rule is the Ordered-Level Profile; for `categorical` or `opaque` schemes the caller MUST NOT interpret the returned `level` as a rank and SHOULD read the specific assertions (`latestAssertion` + `getAssertion`) instead.
- `check` MUST return `true` iff `resolve` returns a non-zero `assertionId` with `level >= minLevel`. A subject with no qualifying assertion therefore fails `check` even for `minLevel == 0`. `check` is only meaningful for `ordered-level` schemes.
- `evidenceURI` MUST be emitted and MUST NOT be stored. For proved assertions the registry MUST set `evidenceHash = keccak256(publicInputs)` and `anchor` to the value returned by the verifier; for attested assertions `anchor` MUST be `0x0`.
- Registries MUST support the `erc8004` subject type and MUST return `true` from `supportsInterface` for the `IKYARegistry` interface id.

### 5. ZK-KYA Profile (PROVED mode)

```solidity
interface IKYAVerifier {
    function verify(bytes32 schemeId, bytes calldata publicInputs, bytes calldata proof)
        external view
        returns (bool ok, bytes32 subjectKey, bytes32 nullifier, uint8 level, bytes32 claimDigest, uint64 expiresAt,
                 bytes32 anchor);
}
```

`verify` MUST be `view`. It MUST return `ok == false` or revert on any verification failure. `anchor` is the verifier's commitment to what the proof was checked against (for the reference circuit, the issuer-set Merkle root); it MAY be `0x0` for verifiers that have no such notion.

**Roles.** In PROVED mode the on-chain `issuer` is the *admitting verifier*: the contract that checked the proof. It is neither the source of the underlying facts nor a guarantor of the conclusion; it identifies which verification logic admitted the assertion. What stands behind the verifier differs by usage pattern (Section 5.1): in the credential pattern a *fact issuer* (attestor) examined the subject off-chain and signed a verdict, and `anchor` commits to the set of attestors the verifier accepts; in the predicate pattern the verdict is computed by the scheme's own rule over authenticated inputs, and `anchor` commits to the input source (a block hash, a notary set, a data-signer set). In both cases a relying party that lists a verifier in `issuers[]` is trusting the circuit and verification key behind it plus whatever `anchor` commits to, and policies SHOULD pin both; the reference adapter enforces a fixed anchor on-chain so that the pair collapses to the address.

On `attestWithProof` the registry MUST, in order:

1. Load the scheme and require `mode == PROVED` and `verifier != 0`.
2. Call `verifier.verify(schemeId, publicInputs, proof)` and require `ok`.
3. Require the returned `subjectKey` equals `keccak256(abi.encode(subject.subjectType, subject.subjectData))`.
4. Require `nullifier` has not been consumed for `schemeId`; mark it consumed.
5. Reject a non-zero `expiresAt` that is not in the future.
6. Record an assertion with `issuer = verifier`, the returned `level`, `claimDigest`, `expiresAt` and `anchor`, and `evidenceHash = keccak256(publicInputs)`.

Binding requirements on any circuit and verifier used under this profile. These are normative for the *public-input layout and the verifier's checks*, not for the proving system:

- **Subject binding.** The public inputs MUST include `subjectKey`, or a commitment the verifier can open to it. A verifier MUST NOT derive `subjectKey` from anything outside the proof's public inputs.
- **Scheme binding.** The statement a proof verifies MUST be bound to the `schemeId` the verifier was called with: adapters MUST feed that `schemeId` into the circuit as a public input (or equivalent), so that a proof made for one scheme is not accepted under another. In addition, where a signed object carries a *pre-made verdict under a scheme* (a credential issued at a given level; Section 5.1, credential pattern), the signed object itself MUST include the `schemeId` and the circuit MUST constrain the two to be equal — otherwise a credential issued under a lenient scheme is presentable under a strict one that accepts the same issuer set (cross-scheme replay). This second requirement does not apply to signed *inputs* that carry no verdict (a bank statement, an exchange export, a task-registry record): such data may legitimately predate and be reused across schemes, and its binding to the scheme is provided by the computation the circuit performs, not by the data's signature.
- **Replay resistance.** The public inputs MUST include a `nullifier` scoped at minimum to `schemeId`. Schemes SHOULD scope it to `(schemeId, epoch)` so a subject can re-prove periodically; the descriptor's `circuit.nullifierScope`, `epochSeconds` and `epochGrace` declare which.
- **Time window.** The prover MUST NOT be trusted to choose `epoch`. A verifier for an epoch-scoped scheme MUST compute `current = floor(block.timestamp / epochSeconds)` and MUST reject a proof unless `current - epochGrace <= epoch <= current`; for `nullifierScope == "scheme"` it MUST require `epoch == 0`. A credential is thus presentable once per epoch; revocation of the fact issuer's credential takes effect at the next epoch boundary, and a scheme chooses `epochSeconds` as its maximum revocation latency.
- **Domain separation (RECOMMENDED).** Circuits SHOULD additionally bind `chainId` and the registry address so a proof for one registry is not valid at another.
- **Issuer hiding (OPTIONAL).** A circuit MAY prove membership of the underlying attestor in an issuer set committed to by `issuerSetRoot`. The on-chain `issuer` is then the verifier address, the real attestor is not disclosed, and the verifier MUST return `issuerSetRoot` as `anchor`. Verifiers SHOULD pin a required `issuerSetRoot`; a rotation of the issuer set is a new verifier and therefore a new scheme version.
- **Selective disclosure.** `claimDigest` MUST be the only claim-bearing output; the scheme descriptor defines what it commits to.
- **Canonical decomposition.** Where 256-bit values are carried as field elements, the split MUST be unique (alias-checked), or a prover can present two encodings of one nullifier.

**What this profile hides, and what it does not.** `subjectKey` is public: anyone can see that *this agent* obtained *this level* under *this scheme* at *this time*. The profile hides which attestor vouched for it and every underlying fact (identity documents, jurisdiction, capital, model lineage). It is issuer-hiding and fact-hiding, not anonymous; unlinkability of the subject is out of scope and would require a different subject type.

**Canonical layout `kya-public-v1`.** `publicInputs = abi.encode(bytes32 subjectKey, bytes32 nullifier, uint8 level, bytes32 claimDigest, uint64 expiresAt, bytes32 issuerSetRoot, uint64 epoch)`, where `epoch` is `0` for schemes whose `nullifierScope` is `scheme`. Adapters for field-arithmetic proving systems SHOULD split each 256-bit value into `(hi128, lo128)` field elements rather than truncating, and MUST feed the `schemeId` they were called with into the circuit as public signals so that the scheme binding above is enforced by the chain rather than by the prover; the reference Groth16 adapter does both, producing thirteen signals, and enforces the time-window rule with `epochSeconds` and `epochGrace` fixed at deployment.

**Ephemeral presentation.** A proved assertion MAY be presented in a handshake (Section 6) without ever being recorded on-chain. The relying party then calls `verifier.verify` via `staticcall` (which applies the time-window rule), applies rules 3 and 5 itself, and tracks nullifiers locally if it needs replay protection across sessions. Recorded and ephemeral proved assertions are semantically identical; only persistence differs.

Any proving system — Groth16, PLONK, STARKs, membership-proof schemes, zkVM execution proofs, or TEE quotes wrapped as proofs — enters the framework by supplying an `IKYAVerifier`. This adapter boundary is the mechanism by which the framework remains compatible with future ZK-KYA algorithms without amendment.

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
- Transport bindings (HTTP POST, A2A message extension, MCP initialisation metadata) are informative here and MAY be specified by companion documents.

**Discovery.** An agent MAY publish `https://{domain}/.well-known/kya.json` conforming to [`kya-discovery.schema.json`](../assets/eip-9999/schemas/kya-discovery.schema.json):

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-9999#kya-discovery-v1",
  "kyaRegistry": "eip155:1:0x4444444444444444444444444444444444444444",
  "presentableSchemes": ["0x496a268d899db6a77e2e6c2716b129c1635a06b1d2738b83a906f21390e4cb8f"],
  "acceptedPolicies": ["0x0000000000000000000000000000000000000000000000000000000000000001"],
  "challengeEndpoint": "https://agent.example/kya/challenge"
}
```

### 7. Policy (minimal)

```solidity
interface IKYAPolicyRegistry /* is IERC165 */ {          // REQUIRED for policy registries
    event PolicyRegistered(bytes32 indexed policyId, address indexed owner, string policyURI, bytes32 policyHash);

    function registerPolicy(string calldata policyURI, bytes32 policyHash) external returns (bytes32 policyId);
    function getPolicy(bytes32 policyId) external view returns (address owner, string memory policyURI, bytes32 policyHash);
}

interface IKYAPolicyEvaluator /* is IERC165 */ {         // OPTIONAL extension
    struct Rule { bytes32 schemeId; uint8 minLevel; address[] issuers; }

    function registerPolicyWithRules(string calldata policyURI, bytes32 policyHash, Rule[] calldata allOf)
        external returns (bytes32 policyId);
    function getRules(bytes32 policyId) external view returns (Rule[] memory);
    function evaluate(Subject calldata subject, bytes32 policyId) external view returns (bool);
}
```

- `policyId` MUST equal `keccak256(abi.encode(msg.sender, policyHash, nonce))` with a per-owner counter.
- `policyURI` MUST resolve to a document conforming to [`kya-policy.schema.json`](../assets/eip-9999/schemas/kya-policy.schema.json): a tree of `allOf` / `anyOf` nodes over rules `{schemeId, minLevel, issuers[], anchors[]?}`; `issuers` MUST be non-empty in every rule. Rules over `ordered-level` schemes use `minLevel`; rules over `categorical` schemes use `level` (equality); `anchors`, when present, restricts proved assertions to the listed trust anchors.
- On-chain evaluation is OPTIONAL and lives in `IKYAPolicyEvaluator`, so a client can detect via ERC-165 whether a registry evaluates or merely stores. An implementation that offers it MUST evaluate the stored `allOf` rules as a conjunction of `IKYARegistry.check` calls and MUST revert if no rules are stored for the policy. Off-chain evaluation over the full `allOf`/`anyOf` tree is the general case.

### 8. ERC-8004 Binding Profile

1. **Subject.** `subjectType = keccak256("erc8004")`, `subjectData = abi.encode(chainId, identityRegistry, agentId)`.
2. **Registration file.** The ERC-8004 registration file's `supportedTrust` array MAY include `"kya"` and `"zk-kya"`. Its `services` array MAY include `{ "name": "KYA", "endpoint": "https://…/.well-known/kya.json", "version": "v1" }`.
3. **On-chain metadata.** The ERC-8004 metadata key `"kya"` is RECOMMENDED, set via `setMetadata(agentId, "kya", abi.encode(address kyaRegistry, bytes32[] advertisedSchemeIds))`.
4. **Mirror into the Validation Registry (MAY).** A *KYA Bridge* is a contract that acts as an ERC-8004 validator and mirrors KYA outcomes. The mirror is an OPTIONAL, LOSSY SNAPSHOT: it exports one 0–100 number per `(agent, scheme)` at the moment of `sync`, carries no expiry, revocation, binding or anchor information, and is only as fresh as its last sync. The KYA Registry remains the authoritative source; the bridge exists so that ERC-8004-only clients get a usable approximation without new code.
   - The bridge's operator configures, per scheme, the `issuers` it trusts and a `responseMap` from level to the 0–100 ERC-8004 scale (taken from the descriptor's `erc8004Response` values; `responseMap[0]` SHOULD be 0).
   - The agent owner or operator calls ERC-8004 `validationRequest(bridge, agentId, requestURI, requestHash)` with `requestHash = keccak256(abi.encode(keccak256("erc-kya-request-v1"), chainId, identityRegistry, bridge, agentId, schemeId))`. Including the bridge address means two bridges mirroring the same scheme for the same agent never share a request. `requestURI` SHOULD resolve to a JSON document repeating those six fields.
   - Anyone MAY call `bridge.sync(agentId, schemeId)`. The bridge MUST verify that the request exists and names the bridge as validator, resolve the subject under the configured issuers, and call `validationResponse(requestHash, responseMap[level], "", responseHash, tag)` with `tag = "kya:" || <first 8 lowercase hex characters of schemeId>` and `responseHash = keccak256(abi.encode(assertionId, level, issuers))`. A revoked or expired assertion resolves to level 0 and therefore drives the mirrored response to `responseMap[0]`. A resolved level that the map does not cover MUST make `sync` revert — a bridge MUST NOT guess upward. Bridges SHOULD only be configured for `ordered-level` schemes.
   - Because the mirror is a snapshot, an ERC-721 transfer of the agent after `sync` leaves a `controller`-bound conclusion visible in the Validation Registry until someone re-syncs; ERC-8004 clients that care about binding MUST consult the KYA Registry.
   - ERC-8004-only clients read KYA outcomes through `getSummary(agentId, [bridge], tag)` and `getValidationStatus(requestHash)`.
5. **Reputation as evidence (MAY).** Schemes MAY declare `erc8004-reputation` and `erc8004-validation` as evidence kinds. ERC-8004 signals are inputs to KYA; KYA assertions are conclusions. Neither replaces the other.
6. **Credential view (OPTIONAL).** A registry MAY additionally expose a single-key credential resolution function where `key = "kya:" || hex(schemeId)` returns `abi.encode(Assertion)` for the resolving subject, for clients that speak a generic credential-resolution interface.

### 9. Errors

Implementations SHOULD use these custom errors: `KYA_SchemeNotFound(bytes32)`, `KYA_ModeMismatch(bytes32,uint8,uint8)`, `KYA_InvalidMode(uint8)`, `KYA_VerifierRequired()`, `KYA_SchemeHashRequired()`, `KYA_VerifierRejected()`, `KYA_SubjectMismatch(bytes32,bytes32)`, `KYA_NullifierUsed(bytes32,bytes32)`, `KYA_EmptyIssuers()`, `KYA_Frozen(bytes32)`, `KYA_NotController(bytes32,address)`, `KYA_NotIssuer(bytes32,address)`, `KYA_AssertionNotFound(bytes32)`, `KYA_AssertionNotActive(bytes32)`, `KYA_BadPredecessor(bytes32)`, `KYA_Expired(uint64)`, `KYA_PolicyNotFound(bytes32)`, `KYA_NoOnchainRules(bytes32)`.

### 10. Interface identifiers

| interface | ERC-165 id |
|---|---|
| `IKYASchemeRegistry` | `0xb80345a1` |
| `IKYARegistry` | `0x5da7d5cf` |
| `IKYAPolicyRegistry` | `0x1cf9e558` |
| `IKYAPolicyEvaluator` | `0x234f3d87` |
| `IKYAVerifier` | `0x5bf48e3a` |

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

**Scheme immutability.** An earlier draft allowed a controller to re-point an unfrozen scheme's descriptor and verifier. Review showed that this makes `schemeId` an unstable reference: a policy pinning it could be redefined underneath it, and an assertion's meaning could change after it was recorded. Making semantics immutable and routing every change through `predecessor` costs one registration per version and removes the whole class of problems; `freeze` now only stops URI re-pointing.

**`level` as `uint8` with scheme-scoped semantics, ordering as a profile.** A single numeric axis gives contracts a cheap comparison (`level >= minLevel`) while leaving meaning to the descriptor. Not every KYA result is a rank, however: a sanctions screen is pass/fail, a jurisdiction is a category. Rather than force those into a ladder, the total-order assumption behind `resolve`'s "highest wins", `check`'s `minLevel` and the bridge's `responseMap` is isolated as the Ordered-Level Profile, and other result kinds use `level` as a code or leave it `0` with the result in `claimDigest`. Section 12 offers a common ladder so ordered schemes converge, but comparing levels across schemes without reading descriptors is unsafe and the specification says so.

**Binding.** The framework cannot know whether "this agent is accountable" survives the agent's sale to a new owner. Instead of guessing, each scheme states what it binds to, and relying parties get a rule they can implement (check for transfers since `issuedAt`). The registry stays ignorant of ERC-721 mechanics, which keeps it usable for `account` and `did` subjects.

**Two registries, co-deployable.** Schemes and assertions have different governance: schemes are curated by controllers and rarely change; assertions are written constantly by many issuers. Separate interfaces let them be upgraded or governed independently; nothing prevents one contract from implementing both, mirroring ERC-8004's three-registry design.

**Mirroring into Validation, not Reputation.** ERC-8004 Validation is third-party judgement on a 0–100 scale posted by a designated validator — exactly the shape of a mirrored KYA conclusion. Reputation is client feedback and would misrepresent an issuer's verdict as a customer's opinion. Requiring the agent to file the `validationRequest` preserves ERC-8004's rule that only the agent may invite a validator, while letting anyone trigger `sync` keeps mirrored state fresh after revocations.

**Deterministic `requestHash`.** Deriving the bridge's request hash from `(chainId, identityRegistry, bridge, agentId, schemeId)` lets any observer verify that a mirrored validation corresponds to a specific scheme without fetching `requestURI`, prevents one request from being synced under a different scheme, and keeps two bridges from colliding.

**Relationship to prior work.** Single-function credential-resolution interfaces answer "how do I fetch a credential by key"; general attestation services answer "how do I store a typed attestation". Neither provides a subject abstraction spanning ERC-8004 agents and other agent forms, a level with scheme-scoped semantics, verifier-gated admission, per-issuer supersession and revocation, or a normative mirror into ERC-8004. Both can serve as storage or access layers *beneath* this ERC — an implementation may persist assertions in an attestation service and expose the credential view of Section 8.6 — which is why this ERC defines the KYA semantic layer rather than another generic attestation primitive.

## Backwards Compatibility

No changes to ERC-8004 contracts are required. All ERC-8004 interactions use the existing `setMetadata`, `validationRequest`, `validationResponse`, `getSummary` and `getValidationStatus` entry points. ERC-8004 registration files remain valid with or without the optional KYA members. Agents that are not registered under ERC-8004 participate through the `account`, `erc721` or `did` subject types.

## Test Cases

Deterministic vectors are provided in [`vectors.json`](../assets/eip-9999/vectors/vectors.json) and regenerated by `tools/vectors.js`. They cover: `subjectType` hashes; `subjectKey` for an `erc8004` subject; `schemeId`, `assertionId` and `policyId` derivations; the canonical `kya-public-v1` public-input encoding, its `evidenceHash`, and its thirteen-signal Groth16 split; the bridge `requestHash`, `tag` and metadata value; EIP-712 digests for `KYAChallenge`, an assertion-based `KYAPresentation` and an ephemeral ZK `KYAPresentation`, with a signature from a well-known test key; and the four ERC-165 interface ids.

An executable end-to-end suite (`test/kya.test.js`) exercises the reference implementation on an in-process EVM: scheme lifecycle, semantic immutability and access control; attested recording, supersession, revocation and expiry; resolution ordering and the non-empty-issuers rule; proved admission with subject-mismatch, replay and mode-mismatch rejections; the Groth16 adapter including `issuerSetRoot` pinning and the epoch window under time travel; on-chain policy evaluation; and the full ERC-8004 bridge flow from `validationRequest` through `sync`, revocation, re-sync and the unmapped-level rejection. A companion suite with a real Groth16 circuit adds adversarial cases: prover-chosen future or stale epochs, cross-scheme replay of a credential, tampered public inputs, aliased field-element encodings, and an attestor outside the pinned issuer set.

## Reference Implementation

A reference implementation is provided under the assets of this proposal:

- Interfaces: [`IKYATypes.sol`](../assets/eip-9999/contracts/interfaces/IKYATypes.sol), [`IKYASchemeRegistry.sol`](../assets/eip-9999/contracts/interfaces/IKYASchemeRegistry.sol), [`IKYARegistry.sol`](../assets/eip-9999/contracts/interfaces/IKYARegistry.sol), [`IKYAPolicyRegistry.sol`](../assets/eip-9999/contracts/interfaces/IKYAPolicyRegistry.sol), [`IKYAVerifier.sol`](../assets/eip-9999/contracts/interfaces/IKYAVerifier.sol), and a minimal [`IERC8004Validation.sol`](../assets/eip-9999/contracts/interfaces/IERC8004Validation.sol).
- Registries: [`KYASchemeRegistry.sol`](../assets/eip-9999/contracts/KYASchemeRegistry.sol), [`KYARegistry.sol`](../assets/eip-9999/contracts/KYARegistry.sol), [`KYAPolicyRegistry.sol`](../assets/eip-9999/contracts/KYAPolicyRegistry.sol) — permissionless.
- Bridge: [`KYABridge8004.sol`](../assets/eip-9999/contracts/KYABridge8004.sol) — curated ERC-8004 validator mirroring KYA outcomes.
- Verifier adapter: [`Groth16KYAVerifierAdapter.sol`](../assets/eip-9999/contracts/verifiers/Groth16KYAVerifierAdapter.sol) — adapts a snarkjs-style Groth16 verifier to `IKYAVerifier` using the `kya-public-v1` layout.

Schemas for the scheme, policy and discovery documents: [`kya-scheme.schema.json`](../assets/eip-9999/schemas/kya-scheme.schema.json), [`kya-policy.schema.json`](../assets/eip-9999/schemas/kya-policy.schema.json), [`kya-discovery.schema.json`](../assets/eip-9999/schemas/kya-discovery.schema.json).

## Security Considerations

**Issuer trust is out of scope by design.** The framework guarantees only that an assertion was recorded by the stated issuer (or admitted by the stated verifier) under the stated scheme. Whether that issuer is competent or honest is a relying-party decision expressed through `issuers[]`. Registries MUST NOT aggregate across unspecified issuers, and clients SHOULD treat any UI that shows "a KYA level" without naming issuers as misleading.

**Subject substitution.** A proof that verifies but binds a different `subjectKey` must never be recorded for the presented subject; rule 3 of Section 5 is therefore mandatory and verifiers MUST derive `subjectKey` from the proof's public inputs alone. Ephemeral presentations require the relying party to perform the same check.

**Proof replay.** Nullifier consumption is per scheme within one registry. Without domain separation a proof recorded on one chain or registry could be replayed at another; circuits SHOULD bind `chainId` and registry address, and relying parties accepting ephemeral proofs SHOULD track nullifiers themselves. Epoch-scoped nullifiers deliberately permit re-proving after an epoch boundary; schemes choose the epoch length to balance revocation latency against linkability. The epoch MUST be enforced by the verifier from `block.timestamp` — a prover who can pick the epoch can pick a fresh nullifier at will, which reduces replay protection to nothing.

**Cross-scheme replay.** If a credential carrying a pre-made verdict does not name the scheme, the same credential is presentable under every scheme whose verifier accepts that issuer, and a level meant under a lenient ladder is read under a strict one. The scheme-binding rule of Section 5 closes this; adapters that receive `schemeId` from the registry and feed it into the circuit as a public signal make it unforgeable by the prover. Signed inputs without a verdict are exempt from the credential half of the rule; their reuse across schemes is intended, and what prevents misuse is that the circuit, not the data, encodes the rule.

**Query composition under the predicate pattern.** A proof system being zero-knowledge bounds what one proof reveals; it says nothing about what a *sequence* of answers reveals. A relying party that may pose "balance above 100?", then "above 50?", then "above 75?" learns the balance to arbitrary precision from perfectly zero-knowledge answers. Provers SHOULD treat each scheme's public outputs and parameters, and the set of schemes they are willing to answer for one counterparty, as the disclosure decision — not the proof system — and MAY refuse challenges whose combination narrows a private value. This specification defines no privacy budget; schemes intended for repeated querying SHOULD say so in their descriptor and choose outputs (coarse levels rather than thresholds close together) accordingly. Immutable scheme semantics let a prover recognise an audited rule, but an audit is a judgement at a point in time and SHOULD be revisited as circuits and proof systems age.

**Verifier and issuer-set choice.** A verifier's meaning is fixed by its circuit, verification key and accepted issuer set. Since scheme semantics are immutable, changing any of these is a new scheme; relying parties SHOULD pin `schemeId` and, for proved schemes, the expected `anchor`, and treat a new `predecessor` chain entry as a trust decision rather than an upgrade to accept automatically.

**Binding and transfer.** An `erc8004` subject can be sold. A `controller`-bound assertion recorded before the sale says nothing about the buyer, yet remains ACTIVE in the registry. Relying parties MUST apply the binding rule of Section 2.1; issuers of controller-bound schemes SHOULD keep `expiresAt` short and MAY revoke on observing a transfer. Bridges mirror snapshots and do not help here.

**Controller revocation power.** Scheme controllers may revoke any assertion under their scheme. This is intended (a scheme operator withdrawing a compromised issuer's verdicts) but concentrates power; policies that cannot tolerate it SHOULD reference frozen schemes whose controller is a multisig or governance contract.

**Level inflation and semantic drift.** Levels are scheme-scoped `uint8` values. A scheme that maps trivial checks to high levels is not a protocol violation, only a bad scheme; the defence is issuer and scheme selection, and the `levels` table in the descriptor, which relying parties SHOULD read before setting `minLevel`.

**Supersession by the same issuer.** Because a new assertion supersedes the issuer's previous one, an issuer can silently downgrade a subject. This is by design — it is how issuers correct themselves — but clients tracking a subject SHOULD subscribe to `Asserted` and `Superseded` events rather than caching a level.

**Revocation latency and expiry.** Revocation is effective from the block it is mined; off-chain caches and mirrored ERC-8004 responses lag until the next `sync`. Schemes SHOULD set finite `expiresAt` values so stale conclusions age out even if no one revokes them. Bridges SHOULD be synced by the party relying on them, not only by the agent.

**Privacy.** Every recorded assertion, attested or proved, reveals `(subjectKey, schemeId, level, issuedAt, expiresAt)` on-chain, and `subjectKey` for an `erc8004` subject is trivially linkable to the agent. The ZK-KYA profile hides the fact issuer and the underlying facts; it does not hide the subject, and epoch-scoped re-proofs of the same subject are linkable by `subjectKey` regardless of the nullifier. Parties that must hide even the existence of a check SHOULD use ephemeral proved presentations, which leave no on-chain trace. `claimDigest` MUST NOT be a low-entropy encoding of the underlying claims, or it becomes a dictionary-attackable disclosure. Implementers SHOULD NOT describe ZK-KYA as anonymous.

**Bridge honesty and staleness.** A bridge is only as trustworthy as its operator's issuer configuration; a malicious bridge can mirror arbitrary responses, and an honest one is stale between syncs. ERC-8004 clients SHOULD verify `bridge.kyaRegistry()` and `getSchemeConfig(schemeId)` before trusting the `kya:` tag, exactly as they would vet any other validator address, and SHOULD treat the mirrored number as an approximation of the KYA Registry, never as the record.

**Gas and denial of service.** `resolve` is linear in `issuers.length`; policies SHOULD keep issuer lists short. Scheme and policy registration are permissionless and cheap, so ids are namespaced by controller and cannot collide or be squatted.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
