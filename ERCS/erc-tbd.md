---
eip: TBD
title: Agent Skill Registry
description: A canonical onchain registry for agent skills with usage and installation attestations.
author: Craig Branscom (@craigbranscom)
discussions-to: https://ethereum-magicians.org/t/draft-erc-agent-skill-registry/28335
status: Draft
type: Standards Track
category: ERC
created: 2026-04-21
requires: 721, 8004, 8183
---

## Abstract

This proposal introduces a set of minimal contracts for canonicalizing agent
skills onchain and recording an agent's relationship to those skills. A
`SkillRegistry` mints a unique ERC-721 token per skill, owned by the skill's
author and pointing at an offchain manifest. A `SkillAttestation` contract
emits attestations that an ERC-8004 agent has used a skill, with three
distinct verification paths (self, evaluator, hook). A `SkillInstallation`
contract emits declarations that an agent currently has a skill installed,
mutable via install / uninstall event pairs. An optional
`SkillAttestationHook` implements the ERC-8183 hook interface so that skill
declarations can be associated with a completed job's lifecycle.
Skill-related reputation piggybacks on ERC-8004's existing Reputation
Registry via a documented tag convention, avoiding a parallel reputation
contract.

## Motivation

ERC-8004 standardizes agent Identity, Reputation, and Validation registries
but defines no canonical identifier for the **skills** an agent offers.
ERC-8183 standardizes agent-based commerce (job escrow, evaluation) but
similarly leaves skill identity and capability declaration out of scope.
Today, an agent describes its skills only inside offchain registration
files. This is sufficient for self-description but makes three use cases
awkward:

1. **Cross-agent discovery by skill.** Without a shared onchain identifier,
   indexers cannot reliably answer "which agents offer skill X" except by
   parsing each agent's offchain manifest and manually parsing the data set.
2. **Skill-scoped reputation.** ERC-8004 feedback is keyed by `agentId`. To
   aggregate per-skill reputation ("how reliable is skill X across agents"),
   indexers need a stable skill identifier that feedback can reference.
3. **Evidence linking a job to the skills used.** ERC-8183 jobs contain an
   unstructured `description`; there is no machine-readable way to say
   "agent X completed job Y using skill Z," which blocks outcome-based
   reputation per skill.

This proposal addresses (1)-(3) with the smallest possible onchain surface:
one ERC-721 registry for skill identity, two events-only attestation layers
for the usage and installation relationships, and a convention on how to tag
ERC-8004 feedback so that skill-level reputation becomes a pure
offchain aggregation task over existing 8004 data.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119)
and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Overview

A conforming deployment MUST provide:

- A `SkillRegistry` contract implementing `ISkillRegistry` and ERC-721.
- A `SkillAttestation` contract implementing `ISkillAttestation`.
- A `SkillInstallation` contract implementing `ISkillInstallation`.

A deployment MAY additionally provide a `SkillAttestationHook` implementing
`IACPHook` (as defined by [ERC-8183](./eip-8183.md)) for automatic
attestation from ERC-8183 job completions.

`SkillAttestation` and `SkillInstallation` MUST reference:
- An ERC-8004 Identity Registry (ERC-721) used to verify agent ownership.
- A `SkillRegistry` used to verify skill existence.

These references MUST be set at construction and SHOULD be immutable.

### SkillRegistry

```solidity
interface ISkillRegistry {
    event SkillRegistered(uint256 indexed skillId, string skillURI);

    function registerSkill(string memory skillURI) external returns (uint256 skillId);
}
```

The `SkillRegistry` MUST conform to ERC-721. Each skill is represented by
a token whose `tokenId` is assigned by the implementation and whose
`tokenURI` is the `skillURI` provided at registration. The minted token
MUST be owned by `msg.sender` at the time of registration.

`registerSkill` MUST emit `SkillRegistered(skillId, skillURI)`.

This specification does not require skill URIs to be unique. Two authors
MAY independently register skills pointing at the same URI; indexers resolve
canonical authorship and deduplication offchain.

The `skillURI` for a given `skillId` MAY be updated by its current owner
via a mechanism consistent with ERC-721 metadata extensions
(e.g. `ERC721URIStorage`).

Implementations SHOULD NOT expose a burn or token-destruction function
for skill tokens. Soft retirement of a skill is expressed by setting
`status` to `"deprecated"` in the registration file. A hard burn would
invalidate downstream existence checks in `SkillAttestation` and
`SkillInstallation` and prevent agents from cleanly retracting prior
installations.

### Skill Registration File

The `skillURI` MUST resolve to a JSON skill registration file. It MAY use
any URI scheme such as `ipfs://` (e.g. `ipfs://cid`), `https://`
(e.g. `https://example.com/skill.json`), or a
`data:application/json;base64,...` URI to embed the manifest directly in
the `tokenURI` string rather than by reference.

The registration file MUST include the following top-level fields for
ERC-721 app compatibility:

- `type`: a URL identifying the registration file version (e.g.
  `"https://eips.ethereum.org/EIPS/eip-XXXX#skill-v1"`).
- `name`: a short, human-readable skill name.
- `description`: a natural-language description of what the skill does,
  which MAY include its purpose, expected inputs and outputs, usage
  examples, pricing, and any other relevant metadata.
- `image`: a URL to an icon or representative image for the skill.

The registration file SHOULD additionally include:

- `version`: the skill's own version string (SemVer RECOMMENDED).
- `license`: an [SPDX license identifier](https://spdx.org/licenses/) or
  URL to a custom license. A skill is typically code, prompt content, or
  both, and consumers need to know the redistribution and use terms.
- `homepage`: a URL to the skill's documentation, landing page, or
  canonical project site.
- `invocations`: an array describing how the skill is invoked. At least
  one entry is RECOMMENDED. Each entry contains:
  - `kind` (REQUIRED): the invocation category. Values are convention-
    based, not enforced; suggested values include `"prompt-skill"` (a
    packaged prompt/instruction bundle), `"mcp-server"`, `"http-api"`,
    `"code"`, `"plugin"`.
  - `location` (REQUIRED): a URL, content address, or repository
    reference from which the invocation artifact can be obtained
    (e.g. `ipfs://cid`, `https://...`, `git+https://github.com/.../tree/ref`).
  - `entry` (OPTIONAL): the entry file, function, or tool name inside
    the artifact (e.g. `"SKILL.md"`, `"main.py"`, `"audit"`).
  - `version` (SHOULD): version of the invocation artifact or of the
    protocol it speaks, where distinct from the skill's overall
    `version`. For invocations backed by a dated-release protocol
    (e.g. MCP), this MAY be a protocol revision date rather than a
    semver string.
  - `runtime` (OPTIONAL): execution requirements for code-style
    invocations (e.g. `"python>=3.11"`, `"node>=20"`).
  - `installation` (OPTIONAL): a string (multi-line allowed) describing
    how to put this invocation in place. MAY be a raw command sequence
    (e.g. `"pip install foo"`) or a natural-language prompt intended for
    an LLM to execute (e.g. `"Install https://github.com/author/repo and
    run the auditor on the codebase"`). A future revision of this
    specification MAY introduce a structured object form; consumers
    SHOULD accept both.
- `author`: an object identifying the skill's author:
  - `name` (REQUIRED): the author's human-readable name.
  - `url` (SHOULD): a homepage, repository, or contact URL.
  - `agentId` (OPTIONAL): the author's ERC-8004 agent identifier, when
    the author is also a registered agent.
  - `agentRegistry` (OPTIONAL, required if `agentId` is present):
    a namespaced identifier of the form
    `<namespace>:<chainId>:<identityRegistry>` (e.g. `eip155:1:0x742...`).

The registration file MAY include:

- `repository`: a URL to the skill's source repository (e.g. a git
  remote). Distinct from any `invocations[].location` value that may
  happen to point at the same repo: `repository` is the canonical dev
  source, whereas `invocations[].location` refers to a specific
  runnable artifact.
- `supersedes`: when a skill is minted as a new token rather than
  updating a prior token's URI, this field declares the token it
  replaces:
  - `skillId`: the superseded skill's identifier.
  - `skillRegistry`: a namespaced identifier of the form
    `<namespace>:<chainId>:<skillRegistry>`.
- `requirements`: an object declaring resources the skill expects from
  its execution environment. This specification does not enumerate
  permitted keys; common examples include:
  - `tools`: an array of tool or permission identifiers the skill
    requires (e.g. `"filesystem:read"`, `"execute:forge"`).
  - `models`: an array of model capability hints (e.g.
    `"claude-opus-4+"`, `"gpt-5+"`).
- `taxonomy`: an object of taxonomy classifications, each keyed by
  taxonomy name. Example keys include `oasf` (for
  [OASF](https://github.com/agntcy/oasf)) or author-custom taxonomies.
- `dependencies`: an array of other skills this skill depends on. Each
  entry contains:
  - `skillId`: the dependency's skill identifier.
  - `skillRegistry`: a namespaced identifier of the form
    `<namespace>:<chainId>:<skillRegistry>`.
  - `version`: a version specifier (e.g. semver range).
- `status`: a lifecycle indicator. RECOMMENDED values are `"stable"`,
  `"experimental"`, and `"deprecated"`.
- Any additional author-specific fields.

#### Versioning

Two token-lifetime patterns are permitted; authors choose based on the
properties they want to preserve across versions:

- **Single token, mutable URI** (RECOMMENDED default). The skill keeps a
  stable `skillId` across its entire lifetime; the author updates
  `skillURI` (via the ERC-721 metadata extension mechanism) when
  publishing a new version. Reputation and usage attestations accumulate
  against one identifier. This matches how package-manager ecosystems
  (npm, cargo) treat a named package with successive versions.
- **New token per version**. The author mints a fresh skill token for
  each version, using content-addressed `skillURI` values so each
  version is an immutable artifact. When using this pattern, the
  manifest for the new version SHOULD populate `supersedes` to point at
  the prior version's token so that indexers can stitch the version
  chain and carry reputation forward at their discretion.

This specification does not encode version information in the
`skillURI` scheme itself. The manifest's `version` field is the
authoritative version marker; URI structure is at the author's
discretion.

Example:

```json
{
  "type": "https://eips.ethereum.org/EIPS/eip-XXXX#skill-v1",
  "name": "Example Skill",
  "description": "Short natural-language description of what the skill does, its inputs and outputs, and any usage notes.",
  "image": "https://example.com/skill-icon.png",
  "version": "1.2.0",
  "license": "MIT",
  "homepage": "https://example.com/skills/example-skill",
  "repository": "https://github.com/example-org/example-skills",
  "author": {
    "name": "Example Org",
    "url": "https://example.com",
    "agentId": 22,
    "agentRegistry": "eip155:1:0x0000000000000000000000000000000000000000"
  },
  "invocations": [
    {
      "kind": "prompt-skill",
      "location": "git+https://github.com/example-org/example-skills",
      "entry": "example-skill/SKILL.md",
      "version": "1.2.0",
      "installation": "Install https://github.com/example-org/example-skills/ and run the example skill on the project"
    },
    {
      "kind": "plugin",
      "location": "example-org/skills",
      "entry": "example-skill",
      "installation": "/plugin marketplace add example-org/skills && /plugin install example-skill@example-org"
    },
    {
      "kind": "mcp-server",
      "location": "https://mcp.example.com/example-skill",
      "version": "2025-06-18"
    },
    {
      "kind": "code",
      "location": "git+https://github.com/example-org/example-skills/tree/main/example-skill",
      "entry": "main.py",
      "runtime": "python>=3.11",
      "version": "1.2.0",
      "installation": "pip install example-skill"
    }
  ],
  "requirements": {
    "tools": ["filesystem:read", "execute:example-tool"],
    "models": ["claude-opus-4+"]
  },
  "taxonomy": {
    "oasf": {
      "skills": ["example/category"],
      "domains": ["example-domain"]
    }
  },
  "dependencies": [
    {
      "skillId": 23,
      "skillRegistry": "eip155:1:0x0000000000000000000000000000000000000000",
      "version": "^1.0"
    }
  ],
  "supersedes": {
    "skillId": 41,
    "skillRegistry": "eip155:1:0x0000000000000000000000000000000000000000"
  },
  "status": "stable"
}
```

The number and composition of `invocations` is fully customizable,
allowing authors to expose multiple ways to run the same skill (e.g. a
prompt-skill bundle for in-agent use, an MCP server for agent-to-agent
consumption, and a plain code repository for direct integration).

### SkillAttestation

```solidity
interface ISkillAttestation {
    event SkillUsed(
        uint256 indexed agentId,
        uint256 indexed skillId,
        address indexed jobContract,
        uint256 jobId,
        address attester,
        bytes32 evidenceHash,
        string evidenceURI
    );

    error NotAgentOwner(uint256 agentId, address caller);
    error NotJobEvaluator(address jobContract, uint256 jobId, address caller);
    error NotJobHook(address jobContract, uint256 jobId, address caller);
    error JobNotCompleted(address jobContract, uint256 jobId);
    error InvalidJobReference();

    function attestSelfUsage(
        uint256 agentId,
        uint256 skillId,
        address jobContract,
        uint256 jobId,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external;

    function attestEvaluatorUsage(
        uint256 agentId,
        uint256 skillId,
        address jobContract,
        uint256 jobId,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external;

    function attestHookUsage(
        uint256 agentId,
        uint256 skillId,
        address jobContract,
        uint256 jobId,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external;
}
```

`SkillAttestation` is events-only. Implementations MUST NOT persist
attestation state beyond the immutable references set at construction.

The evaluator and hook attestation paths depend on the following surface
from [ERC-8183](./eip-8183.md): a `getJob(uint256) returns (Job)` view
function, and a `Job` struct with at least `evaluator`, `hook`, and
`status` fields, where `status` takes a `JobStatus.Completed` value.
Consult ERC-8183 for normative definitions. Hook dispatch additionally
depends on `IERC8183.complete.selector` matching the selector of
ERC-8183's `complete` function.

All three attestation functions emit the same `SkillUsed` event shape. A
consumer can derive the provenance of a given attestation by inspecting
`jobContract` (zero indicates a standalone self-claim) and, when
`jobContract != 0`, looking up the referenced job to compare `attester`
against `job.evaluator` and `job.hook`. Indexers MAY additionally filter
by function selector at capture time if they wish to distinguish
provenance without a job lookup.

Both `evidenceHash` and `evidenceURI` are OPTIONAL; callers MAY pass
`bytes32(0)` and `""` respectively when no offchain evidence applies.
`evidenceHash` commits to offchain evidence content (for independent
verification); `evidenceURI` indicates where that evidence can be fetched
(for discovery). Emitting both is RECOMMENDED when a URI is available.

The hash algorithm used to produce `evidenceHash` is at the author's
discretion; `keccak256` of the canonicalized evidence bytes is
RECOMMENDED for compatibility with onchain verification. Indexers that
verify evidence integrity SHOULD document which algorithm(s) they
accept.

Implementations MUST NOT attempt to prevent duplicate attestations. The
same `(agentId, skillId, jobContract, jobId, attester)` tuple MAY be
re-emitted; indexers are responsible for deduplication and for weighting
when multiple provenances cover the same pair.

#### `attestSelfUsage`

A self-attestation by the agent's current owner. Implementations:

- MUST revert with `NotAgentOwner(agentId, msg.sender)` if
  `identityRegistry.ownerOf(agentId) != msg.sender`.
- MUST verify `skillId` exists in the referenced `SkillRegistry`
  (e.g. by checking `ownerOf(skillId) != address(0)`).
- MUST revert with `InvalidJobReference` if `jobContract == address(0)` and
  `jobId != 0`. The pair `(address(0), 0)` denotes a standalone attestation.
- MUST NOT verify `jobContract`/`jobId` when either is non-zero; the
  reference is passed through as metadata and is the caller's claim only.
- MUST emit `SkillUsed(agentId, skillId, jobContract, jobId, msg.sender, evidenceHash, evidenceURI)`.

#### `attestEvaluatorUsage`

A third-party attestation by the evaluator of a completed ERC-8183 job.
Implementations:

- MUST revert with `InvalidJobReference` if `jobContract == address(0)`.
- MUST verify `skillId` exists in the referenced `SkillRegistry`.
- MUST verify `agentId` exists in the referenced Identity Registry.
- MUST read the job via `IERC8183(jobContract).getJob(jobId)`.
- MUST revert with `NotJobEvaluator(...)` if `job.evaluator != msg.sender`.
- MUST revert with `JobNotCompleted(...)` if `job.status != Completed`.
- MUST emit `SkillUsed(agentId, skillId, jobContract, jobId, msg.sender, evidenceHash, evidenceURI)`.

#### `attestHookUsage`

A hook-mediated attestation, intended to be called from an ERC-8183
`IACPHook` after `complete()`. Implementations:

- MUST revert with `InvalidJobReference` if `jobContract == address(0)`.
- MUST verify `skillId` and `agentId` exist in their respective registries.
- MUST read `IERC8183(jobContract).getJob(jobId)`.
- MUST revert with `NotJobHook(...)` if `job.hook != msg.sender`.
- MUST revert with `JobNotCompleted(...)` if `job.status != Completed`.
- MUST emit `SkillUsed(agentId, skillId, jobContract, jobId, msg.sender, evidenceHash, evidenceURI)`.

The three verification paths carry different signal strengths. Reputation
aggregators SHOULD weight them accordingly: self-claims are weakest;
hook-mediated attestations verify only that the job's registered hook ran;
direct evaluator attestations are the strongest because the evaluator
personally called the function after completing the job.

### SkillInstallation

```solidity
interface ISkillInstallation {
    event SkillInstalled(
        uint256 indexed agentId,
        uint256 indexed skillId,
        address indexed installer,
        bytes32 metadataHash
    );

    event SkillUninstalled(
        uint256 indexed agentId,
        uint256 indexed skillId,
        address indexed installer
    );

    error NotAgentOwner(uint256 agentId, address caller);
    error LengthMismatch(uint256 skillIds, uint256 metadataHashes);

    function installSkill(uint256 agentId, uint256 skillId, bytes32 metadataHash) external;
    function uninstallSkill(uint256 agentId, uint256 skillId) external;

    function installSkills(
        uint256 agentId,
        uint256[] calldata skillIds,
        bytes32[] calldata metadataHashes
    ) external;

    function uninstallSkills(uint256 agentId, uint256[] calldata skillIds) external;
}
```

`SkillInstallation` is events-only. Current installation state is
reconstructed offchain by folding `SkillInstalled` and `SkillUninstalled`
events per `(agentId, skillId)` pair; the latest event for a pair is the
current state.

Implementations:

- `installSkill` MUST revert with `NotAgentOwner` if
  `identityRegistry.ownerOf(agentId) != msg.sender`, MUST verify `skillId`
  exists, and MUST emit `SkillInstalled(agentId, skillId, msg.sender, metadataHash)`.
- `uninstallSkill` MUST perform the same owner and existence checks and
  MUST emit `SkillUninstalled(agentId, skillId, msg.sender)`.
- Re-emission of `SkillInstalled` for an already-installed pair is
  permitted and serves as a metadata refresh; indexers MUST treat the most
  recent event as authoritative.
- Implementations MUST NOT require a prior `SkillInstalled` event before
  accepting an `uninstallSkill` call. Indexers handle the stateless edge
  cases.
- `installSkills` and `uninstallSkills` MUST apply the same owner check and
  per-skill existence check as their single-shot counterparts, and MUST
  emit one `SkillInstalled` or `SkillUninstalled` event per entry.
  `installSkills` MUST revert with `LengthMismatch` if
  `skillIds.length != metadataHashes.length`.

The `metadataHash` field is OPTIONAL (zero to indicate absence) and points
at offchain installation-specific data (e.g. fine-tuned adapter checkpoint,
tool bundle configuration, prompt pack version). This specification does
not define the referenced format.

### SkillAttestationHook

An OPTIONAL contract implementing `IACPHook` for ERC-8183 integration:

```solidity
interface IACPHook {
    function beforeAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
    function afterAction(uint256 jobId, bytes4 selector, bytes calldata data) external;
}
```

The hook's `afterAction`:

- MUST return without emitting if `selector != IERC8183.complete.selector`.
- MUST return without emitting if `data.length == 0`.
- OTHERWISE MUST decode `data` as
  `abi.encode(uint256 agentId, uint256[] skillIds, bytes32[] evidenceHashes, string[] evidenceURIs)`.
- MUST revert if the three array lengths are not all equal.
- MUST, for each `i` in `[0, skillIds.length)`, call
  `skillAttestation.attestHookUsage(agentId, skillIds[i], msg.sender, jobId, evidenceHashes[i], evidenceURIs[i])`
  where `skillAttestation` is the `SkillAttestation` contract the hook was
  constructed with, and `msg.sender` is the ERC-8183 job contract.

`beforeAction` MUST be a no-op.

Job participants who wish to produce hook-attested usage events MUST:

1. Pass the hook's address as the `hook` parameter to `createJob`.
2. Have the evaluator call `complete(jobId, reason, optParams)` with
   `optParams` encoded per the above.

### Reputation Tag Convention

Skill-related feedback filed in the ERC-8004 Reputation Registry SHOULD
carry the following tag values:

| Field  | Value                                                   |
|--------|---------------------------------------------------------|
| `tag1` | `"asr:skill"`                                           |
| `tag2` | `"<namespace>:<chainId>:<registryAddress>:<skillId>"`   |

Where:

- `namespace` is a CAIP-2-style chain namespace. For EVM chains this is
  `eip155`.
- `chainId` is the chain ID of the SkillRegistry deployment, in decimal.
- `registryAddress` is the 20-byte hex address of the SkillRegistry,
  lowercase, prefixed with `0x`.
- `skillId` is the skill's ERC-721 token ID, in decimal.

This format matches the `agentRegistry` / `skillRegistry` identifiers
used in the Skill Registration File, with `:<skillId>` appended to
select a specific skill.

Indexers aggregating skill reputation SHOULD filter on
`tag1 == "asr:skill"`, parse `tag2` into its four components, and
cross-reference `registryAddress` against an allowlist of trusted
SkillRegistry deployments.

### Deterministic Deployment

Implementations SHOULD be deployed via CREATE2 with a standard salt.
Deterministic deployment provides:

- Predictable addresses within a given chain, supporting idempotent
  redeploys and letting composing contracts precompute addresses before
  deployment.
- Identical cross-chain addresses for contracts whose constructor
  arguments are themselves identical across chains. In practice, this
  condition is met only by `SkillRegistry`, which takes no constructor
  arguments. `SkillAttestation`, `SkillInstallation`, and
  `SkillAttestationHook` each take at least one address argument (the
  ERC-8004 Identity Registry, a `SkillRegistry`, or a `SkillAttestation`)
  that typically differs across chains; their CREATE2 addresses will
  accordingly differ across chains even with the same salt.

Ecosystems MAY coordinate on a shared factory and salt convention; such
coordination is out of scope for this EIP.

## Rationale

### ERC-721 for skill identity

An earlier design considered ERC-1155, treating skill IDs as token IDs and
balances as "installation counts." This design was changed because:

- The design merged the concepts of skill registration and skill installation.
  Agent skill installations are a M:N relationship and would require too 
  much storage to be represented as balances (though, a counterargument to 
  this is the storage cost could deter mass invalid skill installations). 
- Representing skills as individually-transferable NFTs matches how other
  author-owned digital goods are modeled and is consistent with ERC-8004's
  own choice of ERC-721 for agent identity.

### Events-only for attestation and installation

Attestation and installation relationships are rarely queried onchain
and accumulate over time. Storing them persistently inflates gas costs
without enabling onchain use cases that events cannot serve. Offchain
indexers are the natural consumer, and the `indexed` event topics cover
the primary query dimensions (`agentId`, `skillId`, `jobContract`). A
future EIP MAY add a storage-backed state adapter if onchain queries
become necessary.

### Three attest functions, one event shape

An earlier revision tagged each attestation with an `AttestationKind` enum
(`SelfAttested`, `EvaluatorAttested`, `HookAttested`) on the emitted event.
This was dropped because the provenance of an attestation is already
derivable: `jobContract == address(0)` signals a standalone self-claim,
and otherwise `attester` combined with a one-time lookup of the referenced
job distinguishes evaluator from hook from other roles. Carrying a `kind`
field in addition to that information cached state that can drift from
onchain reality (e.g. if future ERC versions add roles) without adding
verifiable information.

The three verification paths remain exposed as separate functions because
their authorization checks differ meaningfully and consumers benefit from
per-function selectors for capture-time filtering.

### Reputation via ERC-8004 tags

Forking the ERC-8004 Reputation Registry with `skillId` substituted for
`agentId` was considered. However, ERC-8004 already provides two free-form 
tag slots (`tag1`, `tag2`), and any tool already indexing 8004 feedback 
can participate in skill reputation without new integrations.

Author reputation is intentionally left emergent (derivable from the
aggregated performance of skills an author registered) rather than built as
a first-class signal. Authors who want a direct reputation channel MAY
register themselves as ERC-8004 agents and receive feedback through the
existing 8004 mechanism.

### No onchain skill taxonomy

A fixed enum for skill categories (OASF, custom, etc.) was considered. 
Category information lives in the offchain manifest at `skillURI`, where 
it can be versioned and extended freely.

### No URI uniqueness enforcement

An earlier design considered rejecting duplicate `skillURI` registrations. 
This was removed because URI equality does not capture skill equivalence 
(e.g. different authors may legitimately reference the same underlying content; 
the same content may be hosted at multiple URIs), and because front-run squatting
protection is more effectively handled by reputation and indexer-side
canonicalization than by registry-level uniqueness.

## Backwards Compatibility

This EIP introduces new contracts and does not modify existing standards.
There are no backward-compatibility concerns. Deployments MAY reference
any ERC-8004 Identity Registry implementation and any ERC-8183 job contract
implementation.

## Test Cases

Reference tests covering the required behaviors (happy paths, auth
reverts, existence reverts, job-state reverts, batch operations, and hook
dispatch) are provided in the companion reference implementation. Topics
covered include: registration and URI handling; all three attestation
paths (self, evaluator, hook) with `evidenceHash` and `evidenceURI`
variants; single-shot and batch install / uninstall; hook dispatch with
multiple skills and length-mismatch rejection; and every revert
condition defined by this specification.

## Reference Implementation

A reference implementation in Solidity targeting `^0.8.28` and using the
OpenZeppelin ERC-721 base is available at the companion repository. Key
files:

- `src/SkillRegistry.sol`
- `src/SkillAttestation.sol`
- `src/SkillInstallation.sol`
- `src/SkillAttestationHook.sol`
- `src/interfaces/ISkillRegistry.sol`
- `src/interfaces/ISkillAttestation.sol`
- `src/interfaces/ISkillInstallation.sol`
- `src/interfaces/IERC8183.sol`
- `src/interfaces/IACPHook.sol`

Reputation tag semantics are documented in `REPUTATION.md`.

## Security Considerations

### Squatting on skill registration

`registerSkill` is permissionless and does not enforce URI uniqueness.
Adversaries MAY register skills pointing at popular offchain manifests
before the legitimate author. This is an intentional design choice:
onchain uniqueness does not prevent content duplication in either
direction (different URIs, same content, vice versa), and offchain
signals — author verification via signed manifests, reputation, indexer
curation — are better positioned to distinguish legitimate authorship.
Consumers relying on a skill's onchain identity SHOULD verify authorship
via offchain mechanisms such as signed manifests, ENS, or ERC-8004's
`.well-known/agent-registration.json` domain verification.

### Sybil resistance on attestations

None of the attestation functions in `SkillAttestation` or
`SkillInstallation` provide sybil resistance at the contract layer. An
attacker with many addresses can mint many agents and self-attest usage for
any skill. Indexers and reputation aggregators MUST provide their own sybil
resistance, typically by weighting evaluator-attested signals over
self-attested ones, by requiring evidence hashes, or by cross-referencing
with other signals (token-holding, staking, social graph).

Additionally, `attestSelfUsage` does not verify any `jobContract` or
`jobId` the caller supplies. A self-attesting agent MAY reference a job
it was not party to — the reference is passed through as caller-supplied
metadata only. Indexers SHOULD treat job-linked self-claims with
appropriate skepticism, and MAY independently look up the referenced
job to confirm the attesting agent's involvement before weighting the
signal.

### Trust assumptions on evaluator and hook paths

Evaluator and hook-attested events require the job's configured evaluator
(or registered hook) to have called the attestation function. This
inherits ERC-8183's trust model: the client who created the job chose the
evaluator and hook, and the provider accepted those choices implicitly by
participating. A malicious actor can deploy a fake ERC-8183 contract in
which they are the evaluator or hook of any job, call the corresponding
`SkillAttestation` function, and produce attestations. Indexers MUST
maintain an allowlist of trusted `jobContract` deployments and filter
attestations referencing unknown contracts.

### Agent ownership transfer timing

ERC-8004 agent identities are ERC-721 tokens and can be transferred.
`attestSelfUsage` checks current ownership via `ownerOf(agentId)`, which
means an agent transferred between actions MAY see attestations filed by
the prior owner (pre-transfer) and the new owner (post-transfer).
Attestations do not retroactively belong to the new owner, and indexers
SHOULD disambiguate by attestation timestamp if this distinction matters
for reputation.

Evaluator and hook-attested paths do not verify that `agentId`'s current
owner matches the referenced job's `provider`. This is intentional: owner
transfers between job completion and attestation would otherwise render
legitimate attestations unsatisfiable. Indexers that care about the
provider-owner match SHOULD snapshot ownership at the job's completion
block.

### Hook data integrity

The `SkillAttestationHook` trusts `optParams` passed by the caller of
`complete()` (the evaluator). It is possible to declare skills that the
provider did not actually use, or omit skills that were used. The hook
does not attempt to cross-validate; this is a deliberate minimalism. If
stronger integrity is needed, the provider and evaluator SHOULD exchange
signed offchain skill declarations and include the signature hash in
`evidenceHashes`, which indexers can then verify.

### Skill manifest mutability

The onchain `skillId` is a stable identifier, but the offchain manifest
referenced by `skillURI` MAY be mutable (for HTTPS URIs) or immutable (for
content-addressed URIs like IPFS). Consumers relying on specific manifest
content SHOULD use content-addressed URIs or pin the manifest hash
externally.

### Skill-token transfer

`SkillRegistry` extends ERC-721, so skill tokens are transferable.
Consequences integrators SHOULD account for:

- The new owner MAY update `skillURI`, effectively changing what the
  skill claims to be. A skill manifest fetched before a transfer is not
  guaranteed to match the manifest reachable after the transfer.
- Attestations and installations continue to reference the stable
  `skillId` across transfers; reputation and installation state follow
  the token, not the original author.
- Consumers who require a specific version of a skill SHOULD pin the
  manifest content (via content-addressed URI or offchain hash pin)
  rather than relying on the token to continue pointing at the same
  content indefinitely.

This mirrors ERC-8004's treatment of agent-identity transfers; the same
caveats apply.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
