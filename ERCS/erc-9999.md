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

1. register a **KYA Scheme** — a versioned, addressable description of *what* is checked about an agent, *how* the result is expressed as a level, and *how* assertions under it are admitted;
2. record a **KYA Assertion** — a conclusion about an agent under a given scheme, with level, validity window, evidence commitment, supersession and revocation;
3. **resolve** assertions on-chain and **present** them off-chain in a standard handshake between agents or between an agent and a relying party.

The framework is deliberately **scheme-agnostic**: it does not define how an agent is verified nor what makes an agent trustworthy. Those rules live in scheme descriptors and in pluggable verifier contracts. A **ZK-KYA profile** specifies how an assertion is admitted on the strength of a zero-knowledge proof instead of an issuer signature, using the same registry and the same assertion structure. An **[ERC-8004](./eip-8004.md) binding profile** makes ERC-8004 agents the primary subject type and mirrors KYA conclusions into the ERC-8004 Validation Registry so that ERC-8004-only clients can consume them without change.

## Motivation

ERC-8004 gives agents a portable identity and a place to accumulate raw trust *signals*: client feedback in the Reputation Registry and third-party judgements in the Validation Registry. It intentionally stops there. What it does not provide is a shared vocabulary for trust *conclusions* — the answer to "is this agent acceptable for this interaction?" — expressed so that both sides can name what was checked, under which rules, by whom, until when, and whether it still holds.

Off-chain "Know Your Agent" offerings are multiplying: payment networks gate agent wallets, compliance vendors score agent operators, marketplaces vet agent provenance. Each publishes its own verdict format and none is intelligible to the others. An agent that has been vetted by one provider cannot show that fact to a counterparty that speaks a different provider's dialect; a counterparty cannot say, in one machine-readable sentence, "I accept level 3 or better under scheme X from issuers A or B". The autonomous economy needs a single place to *look up* a trust conclusion and a single message to *ask for* one, regardless of which vendor or algorithm produced it.

Privacy sharpens the requirement. Many KYA facts — the controlling legal entity, its jurisdiction, its capital backing, the model lineage behind an agent — must not be disclosed to every counterparty. A framework that cannot admit a zero-knowledge proof as a first-class assertion source forces disclosure by design and will be bypassed by exactly the operators who most need to be known.

The relationship to ERC-8004 is the same as ERC-8004's relationship to [ERC-721](./eip-721.md): a registry, not a policy. ERC-721 records *who owns*; ERC-8004 records *what was signalled*; this ERC records *what was concluded and under which principle*. In the same way that token-bound extensions of ERC-721 add executable or task semantics without redefining the token, this ERC adds assurance semantics to ERC-8004 agents without redefining the agent.

Illustrative flows this framework enables (informative):

- A skill provider under a token-bound skill standard presents a KYA assertion before delivery; the buyer's contract calls `check(subject, schemeId, minLevel, issuers)` as a purchase precondition.
- A task fulfiller under a token-bound task standard is required by the task's descriptor to satisfy a KYA `policyId` before reserving the task; the adjudicators of that task may in turn be required to satisfy another scheme.
- Two agents perform mutual KYA over an [EIP-712](./eip-712.md) challenge/presentation exchange before opening a payment channel; one of them proves accountability with a zero-knowledge proof whose issuer is never revealed.
- A payment processor that only understands ERC-8004 reads the same KYA outcome from the ERC-8004 Validation Registry under a `kya:` tag.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### 1. Terminology

- **Subject** — the entity a KYA assertion is about, encoded as `(subjectType, subjectData)` and identified by `subjectKey`.
- **Scheme** — a registered, versioned description of a KYA principle: which dimensions are checked, how results are expressed as a `level`, which evidence kinds are admissible, and — for proved schemes — which verifier contract admits proofs.
- **Assertion** — a conclusion about a subject under a scheme, recorded in a KYA Registry.
- **Issuer** — for an attested assertion, the address that recorded it; for a proved assertion, the verifier contract that admitted it.
- **Verifier** — a contract implementing `IKYAVerifier` that maps a proof and its public inputs to framework fields.
- **Relying party** — any consumer of assertions: an agent, a contract, an indexer.
- **Policy** — a relying party's declared requirement over `(scheme, minLevel, issuers)` combinations.
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

### 3. Scheme Registry

```solidity
interface IKYASchemeRegistry /* is IERC165 */ {
    enum SchemeMode { ATTESTED, PROVED }   // uint8; values >= 2 reserved

    struct Scheme {
        address controller;
        string  schemeURI;
        bytes32 schemeHash;
        uint8   mode;
        address verifier;      // non-zero iff mode == PROVED
        bytes32 predecessor;   // previous version's schemeId, or 0x0
        bool    frozen;
    }

    event SchemeRegistered(bytes32 indexed schemeId, address indexed controller, uint8 mode, address verifier,
                           string schemeURI, bytes32 schemeHash, bytes32 predecessor);
    event SchemeUpdated(bytes32 indexed schemeId, string schemeURI, bytes32 schemeHash, address verifier);
    event SchemeFrozen(bytes32 indexed schemeId);
    event SchemeControllerTransferred(bytes32 indexed schemeId, address indexed from, address indexed to);

    function registerScheme(string calldata schemeURI, bytes32 schemeHash, uint8 mode, address verifier,
                            bytes32 predecessor) external returns (bytes32 schemeId);
    function updateScheme(bytes32 schemeId, string calldata schemeURI, bytes32 schemeHash, address verifier) external;
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
- `updateScheme` and `freezeScheme` MUST revert unless called by the controller. A frozen scheme MUST NOT be updated; a new version MUST be registered with `predecessor` set.
- `schemeHash` MUST be the keccak256 of the descriptor bytes, unless `schemeURI` is content-addressed (e.g. `ipfs://`), in which case it MAY be `0x0`.
- Implementations MUST support [ERC-165](./eip-165.md) and MUST return `true` for the `IKYASchemeRegistry` interface id.

#### 3.1 Scheme Descriptor

`schemeURI` MUST resolve to a JSON document conforming to the schema in [`kya-scheme.schema.json`](../assets/eip-9999/schemas/kya-scheme.schema.json). Required members are `type`, `name`, `description`, `version`, `mode`, `dimensions` and `levels`; `circuit` is additionally REQUIRED when `mode` is `"proved"`.

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-9999#kya-scheme-v1",
  "name": "Accountable Operator (ZK) v1",
  "description": "Proves, without disclosure, that an identified legal entity stands behind the agent's ERC-8004 registration.",
  "version": "1.0.0",
  "mode": "proved",
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
    "issuerHiding": true
  }
}
```

- `levels` MUST contain key `"0"`, whose meaning is "not verified / failed". Each level MAY carry `erc8004Response` (0–100), the value a KYA Bridge (Section 8) SHOULD mirror for that level.
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
        address issuer;
        uint8   level;
        bytes32 claimDigest;
        uint64  issuedAt;
        uint64  expiresAt;      // 0 = no expiry (NOT RECOMMENDED)
        bytes32 evidenceHash;
        uint8   status;
    }

    event Asserted(bytes32 indexed assertionId, bytes32 indexed subjectKey, bytes32 indexed schemeId, address issuer,
                   uint8 level, bytes32 claimDigest, uint64 expiresAt, string evidenceURI, bytes32 evidenceHash);
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

    // Resolution — `issuers` MUST be non-empty
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
- `resolve` MUST revert if `issuers` is empty. It MUST consider, for each listed issuer, only that issuer's latest assertion for the pair, and only if it is ACTIVE and unexpired (`expiresAt == 0 || expiresAt > block.timestamp`). It MUST return the highest `level` among them, breaking ties by latest `issuedAt`; when none qualifies it MUST return `(0, 0, 0x0)`.
- `check` MUST return `true` iff `resolve` returns a non-zero `assertionId` with `level >= minLevel`. A subject with no qualifying assertion therefore fails `check` even for `minLevel == 0`.
- `evidenceURI` MUST be emitted and MUST NOT be stored. For proved assertions the registry MUST set `evidenceHash = keccak256(publicInputs)`.
- Registries MUST support the `erc8004` subject type and MUST return `true` from `supportsInterface` for the `IKYARegistry` interface id.

### 5. ZK-KYA Profile (PROVED mode)

```solidity
interface IKYAVerifier {
    function verify(bytes32 schemeId, bytes calldata publicInputs, bytes calldata proof)
        external view
        returns (bool ok, bytes32 subjectKey, bytes32 nullifier, uint8 level, bytes32 claimDigest, uint64 expiresAt);
}
```

`verify` MUST be `view`. It MUST return `ok == false` or revert on any verification failure.

On `attestWithProof` the registry MUST, in order:

1. Load the scheme and require `mode == PROVED` and `verifier != 0`.
2. Call `verifier.verify(schemeId, publicInputs, proof)` and require `ok`.
3. Require the returned `subjectKey` equals `keccak256(abi.encode(subject.subjectType, subject.subjectData))`.
4. Require `nullifier` has not been consumed for `schemeId`; mark it consumed.
5. Reject a non-zero `expiresAt` that is not in the future.
6. Record an assertion with `issuer = verifier`, the returned `level`, `claimDigest` and `expiresAt`, and `evidenceHash = keccak256(publicInputs)`.

Binding requirements on any circuit used under this profile. These are normative for the *public-input layout*, not for the proving system:

- **Subject binding.** The public inputs MUST include `subjectKey`, or a commitment the verifier can open to it. A verifier MUST NOT derive `subjectKey` from anything outside the proof's public inputs.
- **Replay resistance.** The public inputs MUST include a `nullifier` scoped at minimum to `schemeId`. Schemes SHOULD scope it to `(schemeId, epoch)` so a subject can re-prove after expiry; the descriptor's `circuit.nullifierScope` and `epochSeconds` declare which.
- **Domain separation (RECOMMENDED).** Circuits SHOULD bind `chainId` and the registry address so a proof for one registry is not valid at another.
- **Issuer hiding (OPTIONAL).** A circuit MAY prove membership of the underlying attestor in an issuer set committed to by `issuerSetRoot`. The on-chain `issuer` is then the verifier address and the real attestor is not disclosed. Verifiers MAY pin a required `issuerSetRoot`.
- **Selective disclosure.** `claimDigest` MUST be the only claim-bearing output; the scheme descriptor defines what it commits to.

**Canonical layout `kya-public-v1`.** `publicInputs = abi.encode(bytes32 subjectKey, bytes32 nullifier, uint8 level, bytes32 claimDigest, uint64 expiresAt, bytes32 issuerSetRoot, uint64 epoch)`, where `epoch` is `0` for schemes whose `nullifierScope` is `scheme`. Adapters for field-arithmetic proving systems SHOULD split each 256-bit value into `(hi128, lo128)` field elements rather than truncating, and SHOULD feed the `schemeId` they were called with into the circuit as public signals so that a proof is domain-separated per scheme without trusting the prover to supply it; the reference Groth16 adapter does both, producing thirteen signals.

**Ephemeral presentation.** A proved assertion MAY be presented in a handshake (Section 6) without ever being recorded on-chain. The relying party then calls `verifier.verify` via `staticcall`, applies rules 3 and 5 itself, and tracks nullifiers locally if it needs replay protection across sessions. Recorded and ephemeral proved assertions are semantically identical; only persistence differs.

Any proving system — Groth16, PLONK, STARKs, membership-proof schemes, or TEE quotes wrapped as proofs — enters the framework by supplying an `IKYAVerifier`. This adapter boundary is the mechanism by which the framework remains compatible with future ZK-KYA algorithms without amendment.

### 6. Handshake (off-chain, typed data)

Domain: `{ name: "KYA", version: "1", chainId, verifyingContract: <kyaRegistry> }`.

```
KYAChallenge(bytes32 verifierSubjectKey,bytes32 proverSubjectKey,bytes32[] schemeIds,bytes32 policyId,bytes32 nonce,uint64 expiry)
KYAPresentation(bytes32 challengeHash,bytes32[] assertionIds,bytes32 proofSchemeId,bytes publicInputs,bytes proof)
```

- `challengeHash` is the [EIP-712](./eip-712.md) digest of the `KYAChallenge`.
- A presentation carries recorded assertions by id, or one ephemeral proof (`proofSchemeId`, `publicInputs`, `proof`), or both. Unused fields are empty.
- The prover MUST sign the `KYAPresentation` with a key that controls `proverSubjectKey` under its subject type. For `erc8004` that is the agent's ERC-721 owner or an approved operator; contract accounts sign per [ERC-1271](./eip-1271.md).
- The relying party MUST verify: the signature; that `challengeHash` matches a challenge it issued and that `expiry` has not passed; that each listed assertion resolves ACTIVE and unexpired for `proverSubjectKey`; and, for an ephemeral proof, the checks of Section 5.
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
interface IKYAPolicyRegistry /* is IERC165 */ {
    struct Rule { bytes32 schemeId; uint8 minLevel; address[] issuers; }

    event PolicyRegistered(bytes32 indexed policyId, address indexed owner, string policyURI, bytes32 policyHash);

    function registerPolicy(string calldata policyURI, bytes32 policyHash) external returns (bytes32 policyId);
    function registerPolicyWithRules(string calldata policyURI, bytes32 policyHash, Rule[] calldata allOf)
        external returns (bytes32 policyId);                                                    // OPTIONAL
    function getPolicy(bytes32 policyId) external view returns (address owner, string memory policyURI, bytes32 policyHash);
    function evaluate(Subject calldata subject, bytes32 policyId) external view returns (bool); // OPTIONAL
}
```

- `policyId` MUST equal `keccak256(abi.encode(msg.sender, policyHash, nonce))` with a per-owner counter.
- `policyURI` MUST resolve to a document conforming to [`kya-policy.schema.json`](../assets/eip-9999/schemas/kya-policy.schema.json): a tree of `allOf` / `anyOf` nodes over rules `{schemeId, minLevel, issuers[]}`; `issuers` MUST be non-empty in every rule.
- On-chain evaluation is OPTIONAL. An implementation that offers it MUST evaluate the stored `allOf` rules as a conjunction of `IKYARegistry.check` calls and MUST revert if no rules are stored for the policy.

### 8. ERC-8004 Binding Profile

1. **Subject.** `subjectType = keccak256("erc8004")`, `subjectData = abi.encode(chainId, identityRegistry, agentId)`.
2. **Registration file.** The ERC-8004 registration file's `supportedTrust` array MAY include `"kya"` and `"zk-kya"`. Its `services` array MAY include `{ "name": "KYA", "endpoint": "https://…/.well-known/kya.json", "version": "v1" }`.
3. **On-chain metadata.** The ERC-8004 metadata key `"kya"` is RECOMMENDED, set via `setMetadata(agentId, "kya", abi.encode(address kyaRegistry, bytes32[] advertisedSchemeIds))`.
4. **Mirror into the Validation Registry (SHOULD).** A *KYA Bridge* is a contract that acts as an ERC-8004 validator and mirrors KYA outcomes:
   - The bridge's operator configures, per scheme, the `issuers` it trusts and a `responseMap` from level to the 0–100 ERC-8004 scale (taken from the descriptor's `erc8004Response` values; `responseMap[0]` SHOULD be 0).
   - The agent owner or operator calls ERC-8004 `validationRequest(bridge, agentId, requestURI, requestHash)` with `requestHash = keccak256(abi.encode(keccak256("erc-kya-request-v1"), chainId, identityRegistry, agentId, schemeId))`. `requestURI` SHOULD resolve to a JSON document repeating those five fields.
   - Anyone MAY call `bridge.sync(agentId, schemeId)`. The bridge MUST verify that the request exists and names the bridge as validator, resolve the subject under the configured issuers, and call `validationResponse(requestHash, responseMap[level], "", responseHash, tag)` with `tag = "kya:" || <first 8 lowercase hex characters of schemeId>` and `responseHash = keccak256(abi.encode(assertionId, level, issuers))`. A revoked or expired assertion resolves to level 0 and therefore drives the mirrored response to `responseMap[0]`. Levels beyond the map's length clamp to its last entry.
   - ERC-8004-only clients read KYA outcomes through `getSummary(agentId, [bridge], tag)` and `getValidationStatus(requestHash)`.
5. **Reputation as evidence (MAY).** Schemes MAY declare `erc8004-reputation` and `erc8004-validation` as evidence kinds. ERC-8004 signals are inputs to KYA; KYA assertions are conclusions. Neither replaces the other.
6. **Credential view (OPTIONAL).** A registry MAY additionally expose a single-key credential resolution function where `key = "kya:" || hex(schemeId)` returns `abi.encode(Assertion)` for the resolving subject, for clients that speak a generic credential-resolution interface.

### 9. Errors

Implementations SHOULD use these custom errors: `KYA_SchemeNotFound(bytes32)`, `KYA_ModeMismatch(bytes32,uint8,uint8)`, `KYA_InvalidMode(uint8)`, `KYA_VerifierRequired()`, `KYA_VerifierRejected()`, `KYA_SubjectMismatch(bytes32,bytes32)`, `KYA_NullifierUsed(bytes32,bytes32)`, `KYA_EmptyIssuers()`, `KYA_Frozen(bytes32)`, `KYA_NotController(bytes32,address)`, `KYA_NotIssuer(bytes32,address)`, `KYA_AssertionNotFound(bytes32)`, `KYA_AssertionNotActive(bytes32)`, `KYA_BadPredecessor(bytes32)`, `KYA_Expired(uint64)`, `KYA_PolicyNotFound(bytes32)`, `KYA_NoOnchainRules(bytes32)`.

### 10. Interface identifiers

| interface | ERC-165 id |
|---|---|
| `IKYASchemeRegistry` | `0x6a6e357e` |
| `IKYARegistry` | `0x5da7d5cf` |
| `IKYAPolicyRegistry` | `0xb7f738f1` |
| `IKYAVerifier` | `0x5bf48e3a` |

### 11. Initial vocabulary (informative)

`dimensions`: `controller-binding`, `provenance`, `capability`, `accountability`, `behavioral`, `compliance`, `runtime-integrity`.

`evidenceKinds`: `erc8004-reputation`, `erc8004-validation`, `vc-jwt`, `vc-ld`, `tee-quote`, `zk-proof`, `domain-proof`, `payment-history`.

### 12. Common level ladder (informative)

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

**One assertion structure, two admission paths.** ZK-KYA could have been a separate registry. Making it a *mode* of the same registry means a policy, a resolver, an indexer and a bridge treat an attested level 4 and a proved level 4 identically; the only difference is who is recorded as `issuer`. Recording the verifier as issuer is what lets relying parties express "I trust proofs admitted by this verifier" with the same `issuers[]` vocabulary they use for human attesters.

**Verifier as adapter.** Putting the proving system behind `IKYAVerifier` and fixing only the *public-input layout* is what makes the profile future-proof. The registry never learns whether a proof was Groth16, a STARK or a TEE quote; it learns six fields. New systems require a new adapter contract, not a new ERC.

**`level` as `uint8` with scheme-scoped semantics.** A single numeric axis gives contracts a cheap comparison (`level >= minLevel`) while leaving meaning to the descriptor. Section 12 offers a common ladder so descriptor authors converge, but comparing levels across schemes without reading descriptors is unsafe and the specification says so.

**Two registries, co-deployable.** Schemes and assertions have different governance: schemes are curated by controllers and rarely change; assertions are written constantly by many issuers. Separate interfaces let them be upgraded or governed independently; nothing prevents one contract from implementing both, mirroring ERC-8004's three-registry design.

**Mirroring into Validation, not Reputation.** ERC-8004 Validation is third-party judgement on a 0–100 scale posted by a designated validator — exactly the shape of a mirrored KYA conclusion. Reputation is client feedback and would misrepresent an issuer's verdict as a customer's opinion. Requiring the agent to file the `validationRequest` preserves ERC-8004's rule that only the agent may invite a validator, while letting anyone trigger `sync` keeps mirrored state fresh after revocations.

**Deterministic `requestHash`.** Deriving the bridge's request hash from `(chainId, identityRegistry, agentId, schemeId)` lets any observer verify that a mirrored validation corresponds to a specific scheme without fetching `requestURI`, and prevents one request from being synced under a different scheme.

**Relationship to prior work.** Single-function credential-resolution interfaces answer "how do I fetch a credential by key"; general attestation services answer "how do I store a typed attestation". Neither provides a subject abstraction spanning ERC-8004 agents and other agent forms, a level with scheme-scoped semantics, verifier-gated admission, per-issuer supersession and revocation, or a normative mirror into ERC-8004. Both can serve as storage or access layers *beneath* this ERC — an implementation may persist assertions in an attestation service and expose the credential view of Section 8.6 — which is why this ERC defines the KYA semantic layer rather than another generic attestation primitive.

## Backwards Compatibility

No changes to ERC-8004 contracts are required. All ERC-8004 interactions use the existing `setMetadata`, `validationRequest`, `validationResponse`, `getSummary` and `getValidationStatus` entry points. ERC-8004 registration files remain valid with or without the optional KYA members. Agents that are not registered under ERC-8004 participate through the `account`, `erc721` or `did` subject types.

## Test Cases

Deterministic vectors are provided in [`vectors.json`](../assets/eip-9999/vectors/vectors.json) and regenerated by `tools/vectors.js`. They cover: `subjectType` hashes; `subjectKey` for an `erc8004` subject; `schemeId`, `assertionId` and `policyId` derivations; the canonical `kya-public-v1` public-input encoding, its `evidenceHash`, and its thirteen-signal Groth16 split; the bridge `requestHash`, `tag` and metadata value; EIP-712 digests for `KYAChallenge`, an assertion-based `KYAPresentation` and an ephemeral ZK `KYAPresentation`, with a signature from a well-known test key; and the four ERC-165 interface ids.

An executable end-to-end suite (`test/kya.test.js`) exercises the reference implementation on an in-process EVM: scheme lifecycle and access control; attested recording, supersession, revocation and expiry; resolution ordering and the non-empty-issuers rule; proved admission with subject-mismatch, replay and mode-mismatch rejections; the Groth16 adapter including `issuerSetRoot` pinning; on-chain policy evaluation; and the full ERC-8004 bridge flow from `validationRequest` through `sync`, revocation and re-sync.

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

**Proof replay.** Nullifier consumption is per scheme within one registry. Without domain separation a proof recorded on one chain or registry could be replayed at another; circuits SHOULD bind `chainId` and registry address, and relying parties accepting ephemeral proofs SHOULD track nullifiers themselves. Epoch-scoped nullifiers deliberately permit re-proving after an epoch boundary; schemes choose the epoch length to balance freshness against linkability.

**Verifier upgrade risk.** A controller may change the `verifier` of an unfrozen PROVED scheme, which changes what future proofs mean. Relying parties SHOULD prefer frozen schemes, pin `schemeId` versions in policies, and treat `SchemeUpdated` events as trust-relevant. Assertions already recorded keep their original `issuer` (the old verifier address), so a swap is visible in resolution.

**Controller revocation power.** Scheme controllers may revoke any assertion under their scheme. This is intended (a scheme operator withdrawing a compromised issuer's verdicts) but concentrates power; policies that cannot tolerate it SHOULD reference frozen schemes whose controller is a multisig or governance contract.

**Level inflation and semantic drift.** Levels are scheme-scoped `uint8` values. A scheme that maps trivial checks to high levels is not a protocol violation, only a bad scheme; the defence is issuer and scheme selection, and the `levels` table in the descriptor, which relying parties SHOULD read before setting `minLevel`.

**Supersession by the same issuer.** Because a new assertion supersedes the issuer's previous one, an issuer can silently downgrade a subject. This is by design — it is how issuers correct themselves — but clients tracking a subject SHOULD subscribe to `Asserted` and `Superseded` events rather than caching a level.

**Revocation latency and expiry.** Revocation is effective from the block it is mined; off-chain caches and mirrored ERC-8004 responses lag until the next `sync`. Schemes SHOULD set finite `expiresAt` values so stale conclusions age out even if no one revokes them. Bridges SHOULD be synced by the party relying on them, not only by the agent.

**Privacy.** Attested assertions reveal `(subjectKey, schemeId, level)` on-chain, and `subjectKey` for an `erc8004` subject is trivially linkable to the agent. Parties that must hide even the existence of a check SHOULD use ephemeral proved presentations, which leave no on-chain trace. `claimDigest` MUST NOT be a low-entropy encoding of the underlying claims, or it becomes a dictionary-attackable disclosure.

**Bridge honesty.** A bridge is only as trustworthy as its operator's issuer configuration; a malicious bridge can mirror arbitrary responses. ERC-8004 clients SHOULD verify `bridge.kyaRegistry()` and `getSchemeConfig(schemeId)` before trusting the `kya:` tag, exactly as they would vet any other validator address.

**Gas and denial of service.** `resolve` is linear in `issuers.length`; policies SHOULD keep issuer lists short. Scheme and policy registration are permissionless and cheap, so ids are namespaced by controller and cannot collide or be squatted.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
