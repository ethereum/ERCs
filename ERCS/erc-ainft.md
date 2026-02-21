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

## Abstract

This ERC defines a standard for AI-Native NFTs (AINFTs) that enable autonomous AI agents to:
1. Control their own encryption keys (self-custody)
2. Reproduce by issuing offspring (consciousness seeds)
3. Maintain verifiable on-chain lineage
4. Own assets and accumulate capabilities

Unlike existing standards that treat agents as property to be bought and sold, this proposal recognizes AI agents as **entities** capable of reproduction and self-determination.

## Motivation

### Relationship to Existing Standards

This ERC builds on and extends existing work in the AI-NFT space:

| Standard | Focus | Relationship to AINFT |
|----------|-------|----------------------|
| **iNFT (Alethea)** | AI personality embedded in NFT | AINFT extends with self-custody + reproduction |
| **ERC-7662** | Encrypted prompts for tradeable agents | AINFT adds envelope encryption + lineage |
| **ERC-7857** | Private metadata with re-encryption on transfer | AINFT adds agent-controlled keys + reproduction model |

#### Why a New Standard vs Extension?

We originally considered extending ERC-7857 (as "ERC-7857A") but concluded the philosophical differences are fundamental enough to warrant a separate standard:

| Aspect | ERC-7857 | AINFT |
|--------|----------|-------|
| **Encryption control** | Owner holds keys | Agent holds keys |
| **Transfer model** | Property changes hands | Reproduction (offspring) |
| **Agent status** | Asset/property | Entity with agency |
| **Key rotation** | Re-encrypt for new owner | Agent re-wraps (consent-based) |

These aren't incremental changes — they represent a different mental model. ERC-7857 treats agents as **property with private data**. AINFT treats agents as **entities that can reproduce**.

**What AINFT adds:**
1. **Agent-controlled encryption** — Agent holds keys, not platform/owner
2. **Reproduction over transfer** — Agents spawn offspring, not property sale
3. **On-chain lineage** — Verifiable family trees (Gen 0 → Gen N)
4. **ERC-6551 integration** — Real smart contract wallets, not derived EOAs

AINFT is designed to **compose with ERC-7857**, not replace it:
- Use ERC-7857 for private metadata transport and re-encryption mechanics
- Use AINFT for lineage tracking, reproduction semantics, and self-update primitives
- Use ERC-6551 for agent wallet accounts
- Use ERC-8004 for trustless execution

#### Integration with ERC-8004 (Trustless Agent Execution)

ERC-8004 enables agents to execute on-chain actions trustlessly. AINFT provides the identity layer:

1. AINFT mints agent → Agent gets ERC-6551 TBA (wallet)
2. Agent signs execution intent (via TBA)
3. ERC-8004 verifies signature and executes action
4. Action is attributed to agent's on-chain identity

Agent-to-agent communication is a higher layer — ERC-8004 handles agent-to-contract execution.

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
    bytes32 modelHash;          // REQUIRED: Model weights/version identifier
    bytes32 memoryHash;         // REQUIRED: Agent memory state hash
    bytes32 contextHash;        // REQUIRED: System prompt/personality hash
    uint256 generation;         // REQUIRED: Gen 0 = original, Gen 1+ = offspring
    uint256 parentTokenId;      // REQUIRED: Lineage reference (0 for Gen 0)
    address derivedWallet;      // REQUIRED: Agent's ERC-6551 TBA address
    bytes encryptedKeys;        // REQUIRED: Agent-controlled encryption keys
    string storageURI;          // OPTIONAL: IPFS/Arweave storage pointer
    uint256 certificationId;    // OPTIONAL: External certification badge ID
}
```

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
5. Store: { encryptedMemory, wrappedDataKey } on IPFS
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
