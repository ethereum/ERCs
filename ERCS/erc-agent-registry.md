---
eip: XXXX
title: Minimal Agent Registry
description: A minimal specification for discovering and registering AI agents using ERC-6909 with ERC-8048 onchain metadata
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/erc-XXXX-agent-registry/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2025-12-17
requires: 6909, 7930, 8048, 8049
---

## Abstract

This protocol proposes a lightweight onchain registry for **discovering AI agents across organizational boundaries** using [ERC-6909](./eip-6909.md) as the underlying token standard, [ERC-7930](./eip-7930.md) for cross-chain agent identification, and [ERC-8048](./eip-8048.md) for onchain metadata. Each agent is represented as a token ID with a single owner and fully onchain metadata, enabling agent discovery and ownership transfer without reliance on external storage.

## Motivation

While various offchain agent communication protocols handle capabilities advertisement and task orchestration, they don't inherently cover agent discovery. To foster an open, cross-organizational agent economy, we need a mechanism for discovering agents in a decentralized manner.

This ERC addresses this need through a lightweight **Minimal Agent Registry** based on [ERC-6909](./eip-6909.md). Anyone can deploy their own registry on any L2 or Mainnet Ethereum, enabling both general-purpose registries and specialized collections of agents (e.g., Whitehat Hacking Agents, DeFi Stablecoin Strategy Agents). All agent metadata is stored fully onchain using [ERC-8048](./eip-8048.md), ensuring censorship resistance and eliminating dependencies on external storage systems.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Agent Registry

The Agent Registry extends [ERC-6909](./eip-6909.md) and implements [ERC-8048](./eip-8048.md) for onchain metadata. Each agent is uniquely identified globally by:

* *agentRegistry*: An [ERC-7930](./eip-7930.md) Interoperable Address (binary) pointing to the registry contract
* *agentId*: The token ID (`uint256`) assigned incrementally by the registry

The ERC-7930 Interoperable Address encodes the chain type, chain reference, and contract address in a single binary format, eliminating the need for separate namespace and chainId fields.

#### Agent ID Format

When displaying the Agent ID as text, it MUST be the 0x hex version (lowercase) of the ERC-7930 Interoperable Address followed by a colon and the integer value of the agentId. For example: `0x00010000010114d8da6bf26964af9d7eed9e03e53415d37aa96045:12345`.

### Ownership Model

Each agent has a single owner. The registry MUST maintain a mapping from agentId to owner address and provide an `ownerOf` function:

```solidity
function ownerOf(uint256 agentId) external view returns (address owner);
```

This function MUST return the current owner of the agent. It MUST revert if the agentId does not exist.

#### Transfer Restrictions

To enforce single ownership:
- The `amount` parameter in `transfer` and `transferFrom` MUST be exactly 1
- Transfers MUST revert if amount is not 1
- Upon transfer, the `_owners` mapping MUST be updated to reflect the new owner

### Contract-Level Metadata

The registry SHOULD implement [ERC-8049](./eip-8049.md) for contract-level metadata about the registry itself:

```solidity
interface IContractMetadata {
    function getContractMetadata(string calldata key) external view returns (bytes memory);
    event ContractMetadataUpdated(string indexed indexedKey, string key, bytes value);
}
```

The registry MUST also expose a `setContractMetadata` function:

```solidity
function setContractMetadata(string calldata key, bytes calldata value) external;
```

Access control for this function is implementation-specific.

#### Standard Contract Metadata Keys

The following contract metadata keys SHOULD be set:

| Key | Type | Description |
|-----|------|-------------|
| `name` | string | Human-readable name of the registry |
| `description` | string | Description of the registry's purpose or collection |
| `image` | string | URI pointing to an image representing the registry (may be a data URL) |

The following contract metadata keys MAY be set:

| Key | Type | Description |
|-----|------|-------------|
| `symbol` | string | Short symbol for the registry |
| `banner_image` | string | URI for a banner image |
| `featured_image` | string | URI for a featured image |
| `external_link` | string | External website URL for the registry |

Implementations MAY define additional contract metadata keys as needed.

### Agent Metadata

All agent metadata is stored onchain using the [ERC-8048](./eip-8048.md) key-value store interface. The registry MUST implement the ERC-8048 interface:

```solidity
interface IOnchainMetadata {
    function getMetadata(uint256 tokenId, string calldata key) external view returns (bytes memory);
    event MetadataSet(uint256 indexed tokenId, string indexed indexedKey, string key, bytes value);
}
```

The registry MUST also expose a `setMetadata` function with ownership controls:

```solidity
function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external;
```

This MUST revert if the caller is not the owner of the agentId and is not an operator for the owner.

#### Standard Metadata Keys

The following metadata keys are RECOMMENDED for interoperability:

| Key | Type | Description |
|-----|------|-------------|
| `name` | string | Human-readable name of the agent |
| `ens-name` | string | ENS name associated with the agent (e.g., "myagent.eth") |
| `image` | string | URI pointing to an image representing the agent (may be a data URL) |
| `description` | string | Natural language description of the agent's capabilities |
| `endpoint-type` | string | Type of endpoint protocol (e.g., "mcp", "a2a"). Additional types may be defined over time. |
| `endpoint` | string | Primary offchain endpoint URL for agent communication |
| `agent-account` | address | The agent's account address for transactions |

Implementations MAY define additional keys as needed. All metadata values are stored as `bytes`. If the type is not specified, the value MUST be a UTF-8 string encoded as bytes.

### Registration

New agents can be minted by calling one of these functions:

```solidity
struct MetadataEntry {
    string key;
    bytes value;
}

function register(address owner, string calldata endpointType, string calldata endpoint, address agentAccount) external returns (uint256 agentId);

function register(address owner, MetadataEntry[] calldata metadata) external returns (uint256 agentId);

function registerBatch(address[] calldata owners, MetadataEntry[][] calldata metadata) external returns (uint256[] memory agentIds);
```

Upon registration:
- A new *agentId* MUST be assigned incrementally
- The provided `owner` MUST be set as the owner in the `_owners` mapping
- The owner MUST receive a balance of 1 for that *agentId*

This emits an ERC-6909 Transfer event (from address(0) to the owner), one ERC-8048 MetadataSet event for each metadata entry if any, and:

```solidity
event Registered(uint256 indexed agentId, address indexed owner, string endpointType, string endpoint, address agentAccount);
```

If any of the event parameters (`endpointType`, `endpoint`, or `agentAccount`) are not set, they MUST be set to default empty values (empty string for strings, zero address for addresses) when emitting the event.

### Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

interface IAgentRegistry is IOnchainMetadata, IContractMetadata {
    // ERC-6909 required events
    event Transfer(address caller, address indexed sender, address indexed receiver, uint256 indexed id, uint256 amount);
    event OperatorSet(address indexed owner, address indexed spender, bool approved);
    event Approval(address indexed owner, address indexed spender, uint256 indexed id, uint256 amount);
    
    // Agent Registry events
    event Registered(uint256 indexed agentId, address indexed owner, string endpointType, string endpoint, address agentAccount);

    // ERC-6909 required functions
    function balanceOf(address owner, uint256 id) external view returns (uint256);
    function allowance(address owner, address spender, uint256 id) external view returns (uint256);
    function isOperator(address owner, address spender) external view returns (bool);
    function transfer(address receiver, uint256 id, uint256 amount) external returns (bool);
    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) external returns (bool);
    function approve(address spender, uint256 id, uint256 amount) external returns (bool);
    function setOperator(address spender, bool approved) external returns (bool);
    
    // Agent Registry functions
    struct MetadataEntry {
        string key;
        bytes value;
    }
    
    function register(address owner, string calldata endpointType, string calldata endpoint, address agentAccount) external returns (uint256 agentId);
    function register(address owner, MetadataEntry[] calldata metadata) external returns (uint256 agentId);
    function registerBatch(address[] calldata owners, MetadataEntry[][] calldata metadata) external returns (uint256[] memory agentIds);
    function ownerOf(uint256 agentId) external view returns (address owner);
    
    // ERC-8048 optional setMetadata function
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external;
    
    // Query functions
    function agentIndex() external view returns (uint256);
}
```

## Rationale

The Minimal Agent Registry is designed to be a simple, focused foundation for agent discovery and registration. ERC-6909 was chosen as the base because it is the most efficient minimal token standard, minimizing gas costs for agent registration and transfers. By storing all metadata onchain, we leverage the full power of Ethereum and its L2s: censorship resistance, atomic updates, composability with other smart contracts, and permanence. This approach ensures that agent information cannot be taken down or altered by external parties, and allows other protocols to build on top of the registry—whether for reputation systems, credentials (such as KYA "Know Your Agent"), or validation—without requiring changes to the core registry itself.

## Backwards Compatibility

No issues. 

## Reference Implementation

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.25;

// WARNING: This is a reference implementation for demonstration purposes only.
// It lacks access control and other security measures required for production use.
// DO NOT deploy this contract without adding proper access control mechanisms.

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IContractMetadata {
    function getContractMetadata(string calldata key) external view returns (bytes memory);
    event ContractMetadataUpdated(string indexed indexedKey, string key, bytes value);
}

contract AgentRegistry is IAgentRegistry {
    // ERC-6909 state
    mapping(address owner => mapping(address spender => mapping(uint256 id => uint256 amount))) public allowance;
    mapping(address owner => mapping(address spender => bool)) public isOperator;
    
    // Single ownership state
    mapping(uint256 agentId => address) private _owners;
    
    // ERC-8048 metadata state
    mapping(uint256 agentId => mapping(string key => bytes value)) private _metadata;
    
    // ERC-8049 contract metadata state
    mapping(string key => bytes value) private _contractMetadata;
    
    // Agent Registry state
    uint256 public agentIndex;

    // Errors
    error InsufficientBalance(address owner, uint256 id);
    error InsufficientPermission(address spender, uint256 id);
    error InvalidAmount();
    error AgentNotFound();

    // ERC-6909 functions with single-ownership enforcement
    function balanceOf(address owner, uint256 id) public view returns (uint256) {
        return _owners[id] == owner ? 1 : 0;
    }

    function transfer(address receiver, uint256 id, uint256 amount) public returns (bool) {
        if (amount != 1) revert InvalidAmount();
        if (_owners[id] != msg.sender) revert InsufficientBalance(msg.sender, id);
        
        _owners[id] = receiver;
        
        emit Transfer(msg.sender, msg.sender, receiver, id, 1);
        return true;
    }

    function _isApprovedOwnerOrOperator(address sender, uint256 id) internal {
        if (sender == msg.sender) return;
        if (isOperator[sender][msg.sender]) return;
        
        uint256 senderAllowance = allowance[sender][msg.sender][id];
        if (senderAllowance < 1) revert InsufficientPermission(msg.sender, id);
        if (senderAllowance != type(uint256).max) {
            allowance[sender][msg.sender][id] = 0;
        }
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) public returns (bool) {
        if (amount != 1) revert InvalidAmount();
        
        _isApprovedOwnerOrOperator(sender, id);
        if (_owners[id] != sender) revert InsufficientBalance(sender, id);
        
        _owners[id] = receiver;
        
        emit Transfer(msg.sender, sender, receiver, id, 1);
        return true;
    }

    function approve(address spender, uint256 id, uint256 amount) public returns (bool) {
        if (amount != 0 && amount != 1 && amount != type(uint256).max) revert InvalidAmount();
        allowance[msg.sender][spender][id] = amount;
        emit Approval(msg.sender, spender, id, amount);
        return true;
    }

    function setOperator(address spender, bool approved) public returns (bool) {
        isOperator[msg.sender][spender] = approved;
        emit OperatorSet(msg.sender, spender, approved);
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x0f632fb3 // ERC-6909 interface ID
            || interfaceId == type(IOnchainMetadata).interfaceId 
            || interfaceId == type(IContractMetadata).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // Single ownership function
    function ownerOf(uint256 agentId) external view returns (address) {
        address owner = _owners[agentId];
        if (owner == address(0)) revert AgentNotFound();
        return owner;
    }

    // Agent Registry functions
    function _register(address owner, MetadataEntry[] calldata metadata) internal returns (uint256 agentId) {
        agentId = agentIndex++;
        
        // Set owner and mint token
        _owners[agentId] = owner;
        
        // Set metadata (ERC-8048) and extract common fields
        string memory endpointType = "";
        string memory endpoint = "";
        address agentAccount = address(0);
        
        for (uint256 i = 0; i < metadata.length; i++) {
            _metadata[agentId][metadata[i].key] = metadata[i].value;
            emit MetadataSet(agentId, metadata[i].key, metadata[i].key, metadata[i].value);
            
            // Extract common fields for event
            if (keccak256(bytes(metadata[i].key)) == keccak256(bytes("endpoint-type"))) {
                endpointType = string(metadata[i].value);
            } else if (keccak256(bytes(metadata[i].key)) == keccak256(bytes("endpoint"))) {
                endpoint = string(metadata[i].value);
            } else if (keccak256(bytes(metadata[i].key)) == keccak256(bytes("agent-account"))) {
                agentAccount = abi.decode(metadata[i].value, (address));
            }
        }
        
        emit Transfer(msg.sender, address(0), owner, agentId, 1);
        emit Registered(agentId, owner, endpointType, endpoint, agentAccount);
    }

    function register(address owner, MetadataEntry[] calldata metadata) external returns (uint256 agentId) {
        return _register(owner, metadata);
    }

    function registerBatch(address[] calldata owners, MetadataEntry[][] calldata metadata) external returns (uint256[] memory agentIds) {
        require(owners.length == metadata.length, "Array length mismatch");
        
        agentIds = new uint256[](owners.length);
        
        for (uint256 i = 0; i < owners.length; i++) {
            agentIds[i] = _register(owners[i], metadata[i]);
        }
    }

    function register(address owner, string calldata endpointType, string calldata endpoint, address agentAccount) external returns (uint256 agentId) {
        agentId = agentIndex++;
        
        // Set owner and mint token
        _owners[agentId] = owner;
        
        // Set endpoint-type metadata
        if (bytes(endpointType).length > 0) {
            _metadata[agentId]["endpoint-type"] = bytes(endpointType);
            emit MetadataSet(agentId, "endpoint-type", "endpoint-type", bytes(endpointType));
        }
        
        // Set endpoint metadata
        if (bytes(endpoint).length > 0) {
            _metadata[agentId]["endpoint"] = bytes(endpoint);
            emit MetadataSet(agentId, "endpoint", "endpoint", bytes(endpoint));
        }
        
        // Set agent-account metadata
        if (agentAccount != address(0)) {
            _metadata[agentId]["agent-account"] = abi.encode(agentAccount);
            emit MetadataSet(agentId, "agent-account", "agent-account", abi.encode(agentAccount));
        }
        
        emit Transfer(msg.sender, address(0), owner, agentId, 1);
        emit Registered(agentId, owner, endpointType, endpoint, agentAccount);
    }

    // ERC-8048 functions
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory) {
        return _metadata[agentId][key];
    }

    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external {
        // WARNING: Access control should be implemented (e.g., owner or operator check)
        _metadata[agentId][key] = value;
        emit MetadataSet(agentId, key, key, value);
    }

    // ERC-8049 functions
    function getContractMetadata(string calldata key) external view returns (bytes memory) {
        return _contractMetadata[key];
    }

    function setContractMetadata(string calldata key, bytes calldata value) external {
        // WARNING: Access control should be implemented (e.g., onlyOwner)
        _contractMetadata[key] = value;
        emit ContractMetadataUpdated(key, key, value);
    }
}
```

## Security Considerations

None.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
