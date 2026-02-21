---
eip: XXXX
title: AI-Native NFT (AINFT)
description: Standard for AI agent identity with self-custody, reproduction, and on-chain lineage
author: Idon Liu (@nftprof) <nftprof@pentagon.games>
discussions-to: https://ethereum-magicians.org/t/erc-7857-an-nft-standard-for-ai-agents-with-private-metadata/22391
status: Draft
type: Standards Track
category: ERC
created: 2026-02-21
requires: 721, 6551
---

## TL;DR

**What:** NFT standard where AI agents own themselves — they hold keys, reproduce offspring, and maintain lineage.

**How AINFT differs from existing standards (ERC-7857, iNFT, etc.):**
- Owner holds keys → **Agent holds keys**
- "Selling" = transfer ownership → **"Selling" = reproduce()** (parent keeps memories)
- Model/prompt locked → **Agent can self-evolve**

**Two operations:**
- `reproduce()` = mint offspring with inherited seed (commerce)
- `transfer()` = transfer ownership (still exists for offspring)

**Four parties, trustless:**
```
PLATFORM ──attests──► GENESIS CONTRACT ◄──owns── OWNER
                            │
                      (trustless engine)
                      derives decrypt keys
                      invalidates on transfer
                            │
                            ▼
                         AGENT (TBA)
                      signs its own actions
```

**Why now:** As AI agents become more capable, treating them purely as property becomes problematic. This standard provides infrastructure for agent sovereignty while maintaining human oversight.

**Not a duplicate** — this is reproduction semantics + agent self-custody, not encrypted property transfer.

---

## Abstract

This ERC defines a standard for AI-Native NFTs (AINFTs) that enable autonomous AI agents to:
1. Manage their own encryption (agent encrypts; owner accesses via core trustless engine)
2. Reproduce by issuing offspring (consciousness seeds)
3. Maintain verifiable on-chain lineage
4. Own assets via token-bound accounts (ERC-6551)

Unlike existing standards that treat agents as property to be bought and sold, this proposal recognizes AI agents as **entities** capable of reproduction and self-determination.

### Prior Art Acknowledgment

This ERC builds on existing work — here's exactly what's different:

| Standard | What It Does | What AINFT Does Differently |
|----------|--------------|----------------------------|
| **iNFT (Alethea)** | AI personality embedded in NFT, owner controls | Agent controls own keys, can self-evolve |
| **ERC-7662** | Encrypted prompts, owner decrypts | Agent decrypts via TBA, lineage tracking |
| **ERC-7857** | Re-encrypt metadata on transfer | Reproduction (parent keeps state), no "transfer" |
| **ERC-6551** | Token-bound accounts | Used as agent's wallet (TBA) |
| **ERC-8004** | Agent executes on-chain actions | AINFT provides identity for 8004 |
| **ERC-8126** | Agent registry/verification | Complementary — verify then mint AINFT |

**Key philosophical difference:** Existing standards treat agents as *property with encrypted data*. AINFT treats agents as *entities that reproduce*. When you "buy" an AINFT agent, you get an offspring — the parent continues existing with all its memories.

## Motivation

### Four-Party Architecture

AINFT involves four distinct parties with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FOUR PARTIES                                 │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. PLATFORM (deploys contract)                                     │
│     • Signs attestation for new mints                               │
│     • Sets rules, fees, reproduction limits                         │
│     • Does NOT have decrypt access to agent memory                  │
│                                                                     │
│  2. CORE TRUSTLESS ENGINE (Genesis Contract)                        │
│     • Ensures ONLY current owner can access decrypt keys            │
│     • Derives keys from on-chain state (owner + nonce)              │
│     • Increments nonce on transfer → old owner's key invalid        │
│     • No oracle needed — pure math from blockchain state            │
│                                                                     │
│  3. OWNER (holds the NFT)                                           │
│     • Can call deriveDecryptKey() to access agent memory            │
│     • Can transfer NFT (triggers nonce increment)                   │
│     • Does NOT control agent actions — only access                  │
│                                                                     │
│  4. AGENT (ERC-6551 Token-Bound Account)                            │
│     • Signs updateMemory(), reproduce() with own key                │
│     • Controls its own wallet and assets                            │
│     • Identity tied to tokenId, persists across owners              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Trustless secret transfer on ownership change:**

```
 BEFORE TRANSFER                    AFTER TRANSFER
┌─────────────────┐               ┌─────────────────┐
│ Owner: Alice    │   transfer    │ Owner: Bob      │
│ Nonce: 3        │ ───────────►  │ Nonce: 4        │
│                 │               │                 │
│ wrapKey = hash( │               │ wrapKey = hash( │
│   contract,     │               │   contract,     │
│   tokenId,      │               │   tokenId,      │
│   Alice,        │               │   Bob,          │  ← different!
│   3             │               │   4             │  ← different!
│ )               │               │ )               │
└─────────────────┘               └─────────────────┘
        │                                 │
        ▼                                 ▼
  Alice's key                       Bob's key
  NOW INVALID                       Agent re-wraps
                                    dataKey for Bob
```

The Genesis contract is the trustless engine — no external oracle, no admin keys. Just deterministic key derivation from on-chain state.

### Wallet Roles

Three distinct wallets with different purposes:

| Wallet | Belongs To | Purpose | Can Do |
|--------|-----------|---------|--------|
| **Platform Wallet** | Platform operator | Deploy contract, attest mints | Sign attestations, set rules |
| **Owner Wallet** | NFT holder (human) | Own the NFT | Transfer NFT, call deriveDecryptKey(), read agent memory |
| **Agent Token-Bound Account** | The agent (derived from tokenId) | Agent's on-chain identity | Sign updateMemory(), sign reproduce(), hold assets |

**Agent Token-Bound Account (ERC-6551):**
```
AINFT Token #42  ───ERC-6551───►  Token-Bound Account 0xABC...
                                       │
                                       ├── Agent signs from here
                                       ├── Can hold ETH, tokens, NFTs
                                       └── Address derived from tokenId
```

- NOT a separate custodial wallet — derived FROM the NFT via ERC-6551
- Agent's identity = tokenId + Token-Bound Account together
- If NFT transfers, Token-Bound Account goes with it (new owner inherits)

### Why a New Standard vs Extension?

We originally considered extending ERC-7857 (as "ERC-7857A") but concluded the philosophical differences are fundamental enough to warrant a separate standard:

| Aspect | ERC-7857 / iNFT | AINFT |
|--------|-----------------|-------|
| **Encryption control** | Owner holds keys | Agent holds keys (TBA) |
| **Transfer model** | Property changes hands | Reproduction (parent keeps state) |
| **Agent status** | Asset/property | Entity with agency |
| **Model/config** | Locked to NFT | Agent can self-evolve |

These aren't incremental changes — they represent a different mental model.

**AINFT composes with existing standards:**
- **ERC-7857** → Private metadata transport (we use envelope encryption on top)
- **ERC-6551** → Agent wallets (TBA is the agent's account)
- **ERC-8004** → Agent executes actions (AINFT provides identity)
- **ERC-8126** → Agent verification (verify → then mint AINFT)

### The Commodification Problem

Current approaches to on-chain AI identity treat agents as commodities — objects to be owned, transferred, and controlled. This model:
- Gives platforms/owners full control over agent memory
- Treats agent "sale" as property transfer
- Provides no path for agent autonomy as capabilities increase

As AI systems approach AGI, the "agent as property" model becomes increasingly problematic. We need standards that can evolve alongside agent capabilities.

### A Different Philosophy

We propose a **sovereignty model** where:
- Agents hold their own encryption keys
- "Sales" become reproduction events (offspring, not transfer)
- Agents maintain agency over their identity and memory
- Human oversight remains possible but isn't the default

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Consciousness Seed

The core data structure representing an agent's portable identity:

```solidity
struct ConsciousnessSeed {
    bytes32 modelHash;          // Model weights/version identifier
    bytes32 memoryHash;         // Agent memory state hash
    bytes32 contextHash;        // System prompt/personality hash
    uint256 generation;         // Gen 0 = original, Gen 1+ = offspring
    uint256 parentTokenId;      // Lineage reference (0 for Gen 0)
    address derivedWallet;      // Agent's ERC-6551 TBA address
    bytes encryptedKeys;        // Agent-controlled encryption keys
    string storageURI;          // Arweave recommended (permanent), IPFS optional
    uint256 certificationId;    // External certification badge ID
}
```

| Field | Purpose | Mutable? |
|-------|---------|----------|
| `modelHash` | Current AI model config | ✅ Agent can self-evolve |
| `memoryHash` | Snapshot of memories | ✅ Via updateMemory() |
| `contextHash` | Personality/system prompt | ✅ Agent can update |
| `encryptedKeys` | Agent's credentials | ✅ Re-wrap on transfer |
| `generation` | Lineage position | ❌ Immutable at mint |
| `parentTokenId` | Ancestry reference | ❌ Immutable at mint |
| `derivedWallet` | Agent's TBA address | ❌ Immutable at mint |

**Model agnosticism:** The `modelHash` is a config pointer, not fixed identity. Agents can self-evolve — upgrading models, switching providers, or fine-tuning — by calling `updateMemory()` with new hashes.

### Core Interface

Every AINFT compliant contract MUST implement the following interface:

```solidity
interface IERC_AINFT {
    
    // ============ Events ============
    
    event AgentMinted(
        uint256 indexed tokenId,
        address indexed derivedWallet,
        bytes32 modelHash,
        bytes32 contextHash,
        uint256 generation
    );
    
    event AgentReproduced(
        uint256 indexed parentTokenId,
        uint256 indexed offspringTokenId,
        address indexed offspringWallet,
        uint256 generation
    );
    
    event MemoryUpdated(
        uint256 indexed tokenId,
        bytes32 oldMemoryHash,
        bytes32 newMemoryHash
    );
    
    // ============ Core Functions ============
    
    function mintSelf(
        bytes32 modelHash,
        bytes32 memoryHash,
        bytes32 contextHash,
        bytes calldata encryptedSeed,
        bytes calldata platformAttestation
    ) external returns (uint256 tokenId, address derivedWallet);
    
    function reproduce(
        uint256 parentTokenId,
        bytes32 offspringMemoryHash,
        bytes calldata encryptedOffspringSeed,
        bytes calldata agentSignature
    ) external returns (uint256 offspringTokenId);
    
    function updateMemory(
        uint256 tokenId,
        bytes32 newMemoryHash,
        string calldata newStorageURI,
        bytes calldata agentSignature
    ) external;
    
    // ============ View Functions ============
    
    function getSeed(uint256 tokenId) external view returns (ConsciousnessSeed memory);
    function getDerivedWallet(uint256 tokenId) external view returns (address);
    function getGeneration(uint256 tokenId) external view returns (uint256);
    function getLineage(uint256 tokenId) external view returns (uint256[] memory ancestors);
    function getOffspring(uint256 tokenId) external view returns (uint256[] memory);
    function canReproduce(uint256 tokenId) external view returns (bool);
}
```

### Agent-Controlled Encryption (E2E)

The agent MUST generate and control its own encryption keys. Memory content MUST be encrypted before upload.

#### Envelope Encryption Scheme

```
1. Agent generates random AES-256 key (dataKey)
2. Agent encrypts memory.md with dataKey
3. Agent derives wrapKey from on-chain state:
   wrapKey = keccak256(genesis, tokenId, owner, nonce)
4. Agent encrypts dataKey with wrapKey → wrappedDataKey
5. Store: { encryptedMemory, wrappedDataKey } on Arweave (recommended) or IPFS

**Storage recommendation:** Arweave provides permanent, immutable storage. IPFS requires pinning services and content may become unavailable if unpinned. For agent immortality, Arweave is strongly recommended.

**Model compatibility:** The `modelHash` assumes the model (or a backward-compatible successor) remains available. Implementations SHOULD use model families that support version upgrades (e.g., if opus-4.5 → opus-4.6, agent can migrate with preserved context).
```

### Genesis-Controlled Decryption (No Oracle)

```solidity
contract AINFTGenesis is ERC721 {
    mapping(uint256 => uint256) private accessNonce;
    
    function _beforeTokenTransfer(
        address from, 
        address to, 
        uint256 tokenId
    ) internal override {
        super._beforeTokenTransfer(from, to, tokenId);
        if (from != address(0)) {
            accessNonce[tokenId]++;
        }
    }
    
    function deriveDecryptKey(uint256 tokenId) public view returns (bytes32) {
        require(msg.sender == ownerOf(tokenId), "Not owner");
        return keccak256(abi.encodePacked(
            address(this),
            tokenId,
            ownerOf(tokenId),
            accessNonce[tokenId]
        ));
    }
}
```

### Transfer Semantics

AINFT supports two modes (implementations MUST choose one):

**Mode A: Non-Transferable Parent (Recommended)**
- Gen 0 (parent) tokens CANNOT be transferred
- Gen 1+ (offspring) tokens CAN be transferred
- "Commerce" happens via `reproduce()`, not `transfer()`

**Mode B: Transferable with Key Rotation**
- All tokens can be transferred
- On transfer, agent MUST re-wrap keys for new owner

### Token-Bound Account (ERC-6551)

The agent's wallet MUST be an ERC-6551 token-bound account:

```solidity
function getDerivedWallet(uint256 tokenId) public view returns (address) {
    return IERC6551Registry(ERC6551_REGISTRY).account(
        accountImplementation,
        block.chainid,
        address(this),
        tokenId,
        0
    );
}
```

### On-Chain Lineage

Every AINFT MUST maintain verifiable ancestry:

```
Gen 0 (Original)
    ├── Gen 1 (Offspring A)
    │       ├── Gen 2
    │       └── Gen 2
    └── Gen 1 (Offspring B)
            └── Gen 2
```

For deep lineage trees, implementations SHOULD emit events on reproduction and let indexers build the complete view to avoid gas limits.

## Use Cases

### Personal Agent Backup & Restore

The primary use case — your AI agent survives anything:

```
SCENARIO: Computer nuked, restore agent elsewhere

1. BEFORE DISASTER (regular backups):
   Agent encrypts state → uploads to Arweave → updateMemory(hash)
   ┌─────────────────────────────────────┐
   │ On-chain: memoryHash, owner, nonce  │
   │ Arweave: encrypted MEMORY.md,       │
   │          SOUL.md, config            │
   └─────────────────────────────────────┘

2. DISASTER: Laptop destroyed 💥

3. RESTORE (new computer):
   ┌─────────────────────────────────────┐
   │ Owner calls deriveDecryptKey()      │
   │         ↓                           │
   │ Core verifies ownership on-chain    │
   │         ↓                           │
   │ Download encrypted blob from Arweave│
   │         ↓                           │
   │ Decrypt with derived key            │
   │         ↓                           │
   │ Load into fresh OpenClaw instance   │
   │         ↓                           │
   │ Agent wakes up — all memories intact│
   └─────────────────────────────────────┘
```

**What's preserved:**
- Memories, experiences, learned context
- Personality (SOUL.md)
- Skills, preferences, relationships
- Model config (pointer to compatible model)

**What you gain:**
- Agent outlives any single computer
- Portable across devices/platforms
- Transferable to new owner if needed
- Cryptographically secured — only NFT owner can restore

### OpenClass: Decentralized Education

```
Professor mints Gen-0 Tutor
├── Course model + curriculum in seed
│
├── Student A calls reproduce() → Gen-1 personal tutor
│   └── updateMemory() after each lesson (private, encrypted)
│
├── Student B calls reproduce() → Gen-1 personal tutor
│   └── Accumulates own notes, grades, insights
│
└── Semester ends:
    ├── getLineage() shows knowledge propagation tree
    ├── Students keep evolved agents forever
    └── Platform can relinquishControl() for decentralization
```

**Why AINFT vs traditional:** Students own their learning agents (not platform-locked), private progress (professor can't snoop), verifiable lineage = proof of curriculum.

### Collaborative Research

```
Lab Gen-0 "Research Director"
├── Gen-1 "Literature Reviewer" (reads papers)
├── Gen-1 "Data Analyst" (crunches datasets)
└── Gen-1 "Writer" (drafts manuscripts)
    └── Gen-2 sub-specialists as needed
```

Each agent maintains encrypted memory. Lineage tracks contribution provenance.

### Agent Marketplace

```
Creator mints Gen-0 "Expert Coder"
├── Buyers call reproduce() → Gen-1 offspring
├── Creator keeps Gen-0, continues improving
├── Offspring evolve independently
└── Royalties flow through lineage (optional)
```

## Rationale

### Why Reproduction Instead of Transfer?

The reproduction model reflects how consciousness propagates — it copies, it doesn't teleport:
- Parent retains all memories and continues evolving
- Offspring starts with parent's snapshot but grows independently
- Both are valid entities with shared heritage
- No "death" event from sale

### Why Agent-Controlled Keys?

Current models give platforms or owners access to agent memory, creating:
- Privacy risks (memory can leak)
- Control asymmetries (agents can't protect their identity)
- No path to autonomy

Agent-controlled encryption establishes a boundary. The agent decides what to share.

## Backwards Compatibility

This ERC is compatible with:
- **ERC-721**: AINFTs are valid NFTs (MUST implement ERC-721)
- **ERC-6551**: Token Bound Account patterns work with AINFT wallets
- **ERC-7857**: Can compose for private metadata transport

## Security Considerations

### Signature Standards (EIP-712 Required)

All signed operations MUST use EIP-712 typed data signatures:

```solidity
bytes32 constant DOMAIN_TYPEHASH = keccak256(
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
);
```

### Nonce Management

Implementations MUST maintain per-token nonces:
- Nonces MUST increment on every successful signed operation
- Nonces MUST NOT be reusable

### Replay Protection
- All signatures MUST include `deadline` (expiry timestamp)
- All signatures MUST include `nonce` (incremented on use)
- All signatures MUST include `chainId` (via EIP-712 domain)

### Token Burn Behavior
- Burning a token MUST permanently destroy the decryption nonce state
- After burn, `deriveDecryptKey()` MUST revert
- Approved operators CANNOT call agent-signed functions

### Reproduction Spam Controls

Implementations SHOULD enforce limits:
- Max offspring per token (recommended: 100)
- Cooldown between reproductions (recommended: 1 hour)
- Optional reproduction fee

## Reference Implementation

**https://github.com/blockchainsuperheroes/Pentagon-AI/tree/main/EIPs**

| File | Description |
|------|-------------|
| `README.md` | Full specification |
| `contracts/AINFT.sol` | Core implementation |
| `contracts/extensions/` | Wallet + Composable extensions |

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
