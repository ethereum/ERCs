---
eip: 8004
title: Trustless Agents
description: Discover agents and establish trust through reputation and validation
author: Marco De Rossi (@MarcoMetaMask), Davide Crapis (@dcrapis) <davide@ethereum.org>, Jordan Ellis <jordanellis@google.com>, Erik Reppel <erik.reppel@coinbase.com>
discussions-to: https://ethereum-magicians.org/t/erc-8004-trustless-agents/25098
status: Draft
type: Standards Track
category: ERC
created: 2025-08-13
requires: 155, 712, 721, 1271
---

## Abstract

This protocol proposes to use blockchains to **discover, choose, and interact with agents across organizational boundaries** without pre-existing trust, thus **enabling open-ended agent economies**.

Trust models are pluggable and tiered, with security proportional to value at risk, from low-stake tasks like ordering pizza to high-stake tasks like medical diagnosis. Developers can choose from different trust models: reputation systems using client feedback, validation via stake-secured re-execution, zero-knowledge machine learning (zkML) proofs, or trusted execution environment (TEE) oracles.

## Motivation

Model context protocol <!-- TODO: double check that this is the correct abbreviation -->(MCP) allows servers to list and offer their capabilities (prompts, resources, tools, and completions), while Agent2Agent <!-- TODO: double check that this is the correct abbreviation -->(A2A) handles agent authentication, skills advertisement via AgentCards, direct messaging, and complete task-lifecycle orchestration. However, these agent communication protocols don't inherently cover agent discovery and trust.

To foster an open, cross-organizational agent economy, we need mechanisms for discovering and trusting agents in untrusted settings. This ERC addresses this need through three lightweight registries, which can be deployed on any L2 or on Mainnet as per-chain singletons:

**Identity Registry** \- A minimal on-chain handle based on [ERC-721](./eip-721.md) with URIStorage extension <!-- Editor's Note: where is URIStorage defined? Is it an OZ thing? If so, you should include the interface here, or make a separate ERC standardizing it. -->that resolves to an agent's registration file, providing every agent with a portable, censorship-resistant identifier.

**Reputation Registry** \- A standard interface for posting and fetching feedback signals. Scoring and aggregation occur both on-chain (for composability) and off-chain (for sophisticated algorithms), enabling an ecosystem of specialized services for agent scoring, auditor networks, and insurance pools.

**Validation Registry** \- Generic hooks for requesting and recording independent validators checks (e.g. stakers re-running the job, zkML verifiers, TEE oracles, trusted judges).

Payments are orthogonal to this protocol and not covered here. However, examples are provided showing how **x402 payments** <!-- Editor's Note: This is a coinbase thing, right? If it isn't necessary to your standard, can you omit it? -->can enrich feedback signals.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Identity Registry

The Identity Registry uses ERC-721 with the URIStorage extension for agent registration, making **all agents immediately browsable and transferable with NFTs-compliant apps**. Each agent is uniquely identified globally by:

* *agentRegistry*: A colon-separated string `{namespace}:{chainId}:{identityRegistry}` (e.g., `eip155:1:0x742...`) where:
  * *namespace*: The chain family identifier (`eip155` for EVM chains)
  * *chainId*: The blockchain network identifier
  * *identityRegistry*: The address where the ERC-721 registry contract is deployed
* *agentId*: The ERC-721 tokenId assigned incrementally by the registry

Throughout this document, *tokenId* in ERC-721 is referred to as *agentId* and *tokenURI* in ERC-721 is referred to as *agentURI*. The owner of the ERC-721 token is the owner of the agent and can transfer ownership or delegate management (e.g., updating the registration file) to operators, as supported by `ERC721URIStorage`.

#### Agent URI and Agent Registration File

The *agentURI* MUST resolve to the agent registration file. It MAY use any URI scheme such as `ipfs://` (e.g., `ipfs://cid`), `https://` (e.g., `https://example.com/agent3.json`), or a base64-encoded `data:` URI (e.g., `data:application/json;base64,eyJ0eXBlIjoi...`) for fully on-chain metadata. When the registration uri changes, it can be updated with *setAgentURI()*.

The registration file MUST have the following structure:

```jsonc
{
  "type": "https://eips.ethereum.org/EIPS/eip-8004#registration-v1",
  "name": "myAgentName",
  "description": "A natural language description of the Agent, which MAY include what it does, how it works, pricing, and interaction methods",
  "image": "https://example.com/agentimage.png",
  "services": [
   {
      "name": "web",
      "endpoint": "https://web.agentxyz.com/"
    },
    {
      "name": "A2A",
      "endpoint": "https://agent.example/.well-known/agent-card.json",
      "version": "0.3.0"
    },
    {
      "name": "MCP",
      "endpoint": "https://mcp.agent.eth/",
      "version": "2025-06-18"
    },
    {
      "name": "OASF",
      "endpoint": "ipfs://{cid}",
      "version": "0.8", // https://github.com/agntcy/oasf/tree/v0.8.0
      "skills": [], // OPTIONAL
      "domains": [] // OPTIONAL
    },
    {
      "name": "ENS",
      "endpoint": "vitalik.eth",
      "version": "v1"
    },
    {
      "name": "DID",
      "endpoint": "did:method:foobar",
      "version": "v1"
    },
    {
      "name": "email",
      "endpoint": "mail@myagent.com"
    }
  ],
  "x402Support": false,
  "active": true,
  "registrations": [
    {
      "agentId": 22,
      "agentRegistry": "{namespace}:{chainId}:{identityRegistry}" // e.g. eip155:1:0x742...
    }
  ],
  "supportedTrust": [
    "reputation",
    "crypto-economic",
    "tee-attestation"
  ]
}
```

The *type*, *name*, *description*, and *image* fields at the top SHOULD ensure compatibility with ERC-721 apps. The number and type of *endpoints* are fully customizable, allowing developers to add as many as they wish. The *version* field in endpoints is a SHOULD, not a MUST.

Agents MAY advertise their endpoints, which point to an A2A agent card, an MCP endpoint, an ENS agent name, DIDs, or the agent's wallets on any chain (even chains where the agent is not registered).

#### Endpoint Domain Verification (Optional)

Since endpoints can point to domains not controlled by the agent owner, an agent MAY optionally prove control of an HTTPS endpoint-domain by publishing `https://{endpoint-domain}/.well-known/agent-registration.json` containing at least a `registrations` list (or the full agent registration file). Users MAY treat the endpoint-domain as verified if the file is reachable over HTTPS and includes a `registrations` entry whose `agentRegistry` and `agentId` match the on-chain agent; if the endpoint-domain is the same domain that serves the agent’s primary registration file referenced by `agentURI`, this additional check is not needed because domain control is already demonstrated there.

Agents SHOULD have at least one registration (multiple are possible), and all fields in the registration are mandatory.
The *supportedTrust* field is OPTIONAL. If absent or empty, this ERC is used only for discovery, not for trust.

#### On-chain metadata

The registry extends ERC-721 by adding `getMetadata(uint256 agentId, string metadataKey)` and `setMetadata(uint256 agentId, string metadataKey, bytes metadataValue)` functions for optional extra on-chain agent metadata:

```solidity
function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory)
function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external
```

When metadata is set, the following event is emitted:

```solidity
event MetadataSet(uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue)
```

The key `agentWallet` is reserved and cannot be set via `setMetadata()` or during `register()` (including the metadata array overload). It represents the address where the agent receives payments and is initially set to the owner's address. To change it, the agent owner must prove control of the new wallet by providing a valid [EIP-712](./eip-712.md) signature for EOAs or [ERC-1271](./eip-1271.md) for smart contract wallets—by calling:

```solidity
function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external
```

To read and clear the currently set wallet, the following functions are exposed:

```solidity
function getAgentWallet(uint256 agentId) external view returns (address)
function unsetAgentWallet(uint256 agentId) external
```

When the agent is transferred, `agentWallet` is automatically cleared (effectively resetting it to the zero address) and must be re-verified by the new owner.

#### Registration

New agents can be minted by calling one of these functions:

```solidity
struct MetadataEntry {
string metadataKey;
bytes metadataValue;
}

function register(string agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId)

function register(string agentURI) external returns (uint256 agentId)

// agentURI is added later with setAgentURI()
function register() external returns (uint256 agentId)
```

This emits one Transfer event, one MetadataSet event for the reserved `agentWallet` key, one MetadataSet event for each additional metadata entry (if any), and

```solidity
event Registered(uint256 indexed agentId, string agentURI, address indexed owner)
```

#### Update agentURI

The agentURI can be updated by calling the following function, which emits a URIUpdated event:

```solidity

function setAgentURI(uint256 agentId, string calldata newURI) external

event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy)

```

If the owner wants to store the entire registration file on-chain, the *agentURI* SHOULD use a base64-encoded data URI rather than a serialized JSON string:

```
data:application/json;base64,eyJ0eXBlIjoi...
```

### Reputation Registry

When the Reputation Registry is deployed, the *identityRegistry* address is set via `initialize(address identityRegistry_)` and publicly visible by calling:

```solidity
function getIdentityRegistry() external view returns (address identityRegistry)
```

The feedback given by a *clientAddress* to an agent consists of a signed fixed-point *value* (`int128`) and its *valueDecimals* (`uint8`, 0-18), plus optional *tag1* and *tag2* (left to developers' discretion to provide maximum on-chain composability and filtering), an *endpoint* URI, a file URI pointing to an off-chain JSON containing additional information, and its KECCAK-256 file hash to guarantee integrity. We suggest using IPFS or equivalent services to make feedback easily indexed by subgraphs or similar technologies. For IPFS URIs, the hash is not required.
All fields except *value* and *valueDecimals* are OPTIONAL, so the off-chain file is not required and can be omitted.

#### Giving Feedback

New feedback can be added by any *clientAddress* calling:

```solidity
function giveFeedback(uint256 agentId, int128 value, uint8 valueDecimals, string calldata tag1, string calldata tag2, string calldata endpoint, string calldata feedbackURI, bytes32 feedbackHash) external
```

The *agentId* must be a validly registered agent. The *valueDecimals* MUST be between 0 and 18. The feedback submitter MUST NOT be the agent owner or an approved operator for *agentId*. *tag1*, *tag2*, *endpoint*, *feedbackURI*, and *feedbackHash* are OPTIONAL.

Where provided, *feedbackHash* is the KECCAK-256 hash (`keccak256`) of the content referenced by *feedbackURI*, enabling verifiable integrity for non-content-addressed URIs. For IPFS (or other content-addressed URIs), *feedbackHash* is OPTIONAL and can be omitted (e.g., set to `bytes32(0)`).

If the procedure succeeds, an event is emitted:

```solidity
event NewFeedback(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, int128 value, uint8 valueDecimals, string indexed indexedTag1, string tag1, string tag2, string endpoint, string feedbackURI, bytes32 feedbackHash)
```

The feedback fields *value*, *valueDecimals*, *tag1*, *tag2*, and *isRevoked* are stored in the contract storage along with the feedbackIndex (a 1-indexed counter of feedback submissions that *clientAddress* has given to *agentId*). The fields *endpoint*, *feedbackURI*, and *feedbackHash* are emitted but are not stored. This exposes reputation signals to any smart contract, enabling on-chain composability.

When the feedback is given by an agent (i.e., the client is an agent), the agent SHOULD use the address set in the on-chain optional `agentWallet` metadata as the clientAddress, to facilitate reputation aggregation.

#### Examples of `value` / `valueDecimals`

| tag1 | What it measures | Example human value | `value` | `valueDecimals` |
| --- | --- | --- | --- | --- |
| `starred` | Quality rating (0-100) | `87/100` | `87` | `0` |
| `reachable` | Endpoint reachable (binary) | `true` | `1` | `0` |
| `ownerVerified` | Endpoint owned by agent owner (binary) | `true` | `1` | `0` |
| `uptime` | Endpoint uptime (%) | `99.77%` | `9977` | `2` |
| `successRate` | Endpoint success rate (%) | `89%` | `89` | `0` |
| `responseTime` | Response time (ms) | `560ms` | `560` | `0` |
| `blocktimeFreshness` | Avg block delay (blocks) | `4 blocks` | `4` | `0` |
| `revenues` | Cumulative revenues (e.g., USD) | `$560` | `560` | `0` |
| `tradingYield` (`tag2` = `day, week, month, year`) | Yield | `-3,2%` | `-32` | `1` |

#### Off-Chain Feedback File Structure

The OPTIONAL file at the URI could look like:

```jsonc
{
  // MUST FIELDS
  "agentRegistry": "eip155:1:{identityRegistry}",
  "agentId": 22,
  "clientAddress": "eip155:1:{clientAddress}",
  "createdAt": "2025-09-23T12:00:00Z",
  "value": 100,
  "valueDecimals": 0,

  // ALL OPTIONAL FIELDS
  "tag1": "foo",
  "tag2": "bar",
  "endpoint": "https://agent.example.com/GetPrice",

  "mcp": { "tool": "ToolName" }, // or: { "prompt": "PromptName" } / { "resource": "ResourceName" }

  // A2A: see "Context Identifier Semantics" and Task model in the A2A specification.
  "a2a": {
    "skills": ["as-defined-by-A2A"], // e.g., AgentSkill identifiers
    "contextId": "as-defined-by-A2A",
    "taskId": "as-defined-by-A2A"
  },

  "oasf": {
    "skills": ["as-defined-by-OASF"],
    "domains": ["as-defined-by-OASF"]
  },
  
  "proofOfPayment": { // this can be used for x402 proof of payment
	  "fromAddress": "0x00...",
	  "toAddress": "0x00...",
	  "chainId": "1",
	  "txHash": "0x00..."
   },

 // Other fields
  " ... ": { " ... " } // MAY
}
```

#### Revoking Feedback

*clientAddress* can revoke feedback by calling:

```solidity
function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external
```

This emits:

```solidity
event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 indexed feedbackIndex)
```

#### Appending Responses

Anyone (e.g., the *agentId* showing a refund, any off-chain data intelligence aggregator tagging feedback as spam) can call:

```solidity
function appendResponse(uint256 agentId, address clientAddress, uint64 feedbackIndex, string calldata responseURI, bytes32 responseHash) external
```

Where *responseHash* is the KECCAK-256 file hash of the *responseURI* file content to guarantee integrity. This field is not required for IPFS URIs.

This emits:

```solidity
event ResponseAppended(uint256 indexed agentId, address indexed clientAddress, uint64 feedbackIndex, address indexed responder, string responseURI, bytes32 responseHash)
```

#### Read Functions

```solidity
function getSummary(uint256 agentId, address[] calldata clientAddresses, string tag1, string tag2) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals)
// agentId and clientAddresses are mandatory; tag1 and tag2 are optional filters.
// clientAddresses MUST be provided (non-empty); results without filtering by clientAddresses are subject to Sybil/spam attacks. See Security Considerations for details

function readFeedback(uint256 agentId, address clientAddress, uint64 feedbackIndex) external view returns (int128 value, uint8 valueDecimals, string tag1, string tag2, bool isRevoked)

function readAllFeedback(uint256 agentId, address[] calldata clientAddresses, string tag1, string tag2, bool includeRevoked) external view returns (address[] memory clients, uint64[] memory feedbackIndexes, int128[] memory values, uint8[] memory valueDecimals, string[] memory tag1s, string[] memory tag2s, bool[] memory revokedStatuses)
// agentId is the only mandatory parameter; others are optional filters. Revoked feedback are omitted by default.

function getResponseCount(uint256 agentId, address clientAddress, uint64 feedbackIndex, address[] responders) external view returns (uint64 count)
// agentId is the only mandatory parameter; others are optional filters.

function getClients(uint256 agentId) external view returns (address[] memory)

function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64)
```

We expect reputation systems around reviewers/clientAddresses to emerge. **While simple filtering by reviewer (useful to mitigate spam) and by tag are enabled on-chain, more complex reputation aggregation will happen off-chain**.


### Validation Registry

**This registry enables agents to request verification of their work and allows validator smart contracts to provide responses that can be tracked on-chain**. Validator smart contracts could use, for example, stake-secured inference re-execution, zkML verifiers or TEE oracles to validate or reject requests.

When the Validation Registry is deployed, the *identityRegistry* address is set via `initialize(address identityRegistry_)` and is visible by calling `getIdentityRegistry()`, as described above.

#### Validation Request

Agents request validation by calling:

```solidity
function validationRequest(address validatorAddress, uint256 agentId, string requestURI, bytes32 requestHash) external
```

This function MUST be called by the owner or operator of *agentId*. The *requestURI* points to off-chain data containing all information needed for the validator to validate, including inputs and outputs needed for the verification. The *requestHash* is a commitment to this data (`keccak256` of the request payload) and identifies the request. All other fields are mandatory.

A ValidationRequest event is emitted:

```solidity
event ValidationRequest(address indexed validatorAddress, uint256 indexed agentId, string requestURI, bytes32 indexed requestHash)
```

#### Validation Response

Validators respond by calling:

```solidity
function validationResponse(bytes32 requestHash, uint8 response, string responseURI, bytes32 responseHash, string tag) external
```

Only *requestHash* and *response* are mandatory; *responseURI*, *responseHash* and *tag* are optional. This function MUST be called by the *validatorAddress* specified in the original request. The *response* is a value between 0 and 100, which can be used as binary (0 for failed, 100 for passed) or with intermediate values for validations with a spectrum of outcomes. The optional *responseURI* points to off-chain evidence or audit of the validation, *responseHash* is its commitment (in case the resource is not on IPFS), while *tag* allows for custom categorization or additional data.

validationResponse() can be called multiple times for the same *requestHash*, enabling use cases like progressive validation states (e.g., “soft finality” and “hard finality” using *tag*) or updates to validation status.

Upon successful execution, a *ValidationResponse* event is emitted with all function parameters:

```solidity
event ValidationResponse(address indexed validatorAddress, uint256 indexed agentId, bytes32 indexed requestHash, uint8 response, string responseURI, bytes32 responseHash, string tag)
```

The contract stores *requestHash*, *validatorAddress*, *agentId*, *response*, *responseHash*, *lastUpdate*, and *tag* for on-chain querying and composability.

#### Read Functions

```solidity
function getValidationStatus(bytes32 requestHash) external view returns (address validatorAddress, uint256 agentId, uint8 response, bytes32 responseHash, string tag, uint256 lastUpdate)

//Returns aggregated validation statistics for an agent. agentId is the only mandatory parameter; validatorAddresses and tag are optional filters
function getSummary(uint256 agentId, address[] calldata validatorAddresses, string tag) external view returns (uint64 count, uint8 averageResponse)

function getAgentValidations(uint256 agentId) external view returns (bytes32[] memory requestHashes)

function getValidatorRequests(address validatorAddress) external view returns (bytes32[] memory requestHashes)
```

Incentives and slashing related to validation are managed by the specific validation protocol and are outside the scope of this registry.

## Rationale

* **Agent communication protocols**: MCP and A2A are popular, and other protocols could emerge. For this reason, this protocol links from the blockchain to a flexible registration file including a list where endpoints can be added at will, combining AI primitives (MCP, A2A) and Web3 primitives such as wallet addresses, DIDs, and ENS names.
* **Feedback**: The protocol combines the leverage of nomenclature already established by A2A (such as tasks and skills) and MCP (such as tools and prompts) with complete flexibility in the feedback signal structure.
* **Gas Sponsorship**: Since clients don't need to be registered anymore, any application can implement frictionless feedback leveraging [EIP-7702](./eip-7702.md).
* **Indexing**: Since feedback data is saved on-chain and we suggest using IPFS for full data, it's easy to leverage subgraphs to create indexers and improve UX.
* **Deployment**: We expect the registries to be deployed with singletons per chain. Note that an agent registered and receiving feedback on chain A can still operate and transact on other chains. Agents can also be registered on multiple chains if desired.

<!-- Editor's Note: The test cases section should be a list of input/output/state changes or automated test functions. Simply listing "what to test" is insufficient. -->

<!--

## Test Cases

This protocol enables:

* Crawling all agents starting from a logically centralized endpoint and discover agent information (name, image, services), capabilities, communication endpoints (MCP, A2A, others), ENS names, wallet addresses and which trust models they support (reputation, validation, TEE attestation)
* Building agent explorers and marketplaces using any ERC-721 compatible application to browse, transfer, and manage agents
* Building reputation systems with on-chain aggregation (average scores for smart contract composability) or sophisticated off-chain analysis. All reputation signals are public good.
* Discovering which agents support stake-secured or zkML validation and how to request it through a standardized interface

-->

## Security Considerations

* Sybil attacks are possible, inflating the reputation of fake agents. The protocol's contribution is to make signals public and use the same schema. We expect many players to build reputation systems, for example, trusting or giving reputation to reviewers (and therefore filtering by reviewer, as the protocol already enables).
* On-chain pointers and hashes cannot be deleted, ensuring audit trail integrity
* Validator incentives and slashing are managed by specific validation protocols
* While this ERC cryptographically ensures the registration file corresponds to the on-chain agent, it cannot cryptographically guarantee that advertised capabilities are functional and non-malicious. The three trust models (reputation, validation, and TEE attestation) are designed to support this verification need

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
