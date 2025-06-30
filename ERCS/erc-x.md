---
eip: TBD
title: Decentralized Gateway URLs for ERC-3668
description: Extends ERC-3668 (CCIP-Read) gateway URLs to support decentralized storage (IPFS, IPNS, Arweave, Swarm) and erc-4804 Web3 URLs
author: 0xc0fe4c0ffee (@0xc0de4c0ffee),
discussions-to: <LINK>
status: Draft
type: Standards Track
category: ERC
created: 2025-06-30
requires: 3668, 4804
---

## Abstract
This ERC defines how clients should handle decentralized storage URLs (ipfs://, ipns://, ar://, bzz://) and Web3 URLs (web3://) in ERC-3668 gateway arrays, enabling contracts to use multiple data sources while maintaining the same fallback behavior.

## Motivation
Current ERC-3668 implementations only support HTTPS gateways, limiting contracts to centralized data sources. This extension enables contracts to leverage decentralized storage networks and direct L2/EVM calls, providing better availability, censorship resistance, and cost efficiency while maintaining backward compatibility.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

### Protocol Support

This extension adds the following protocols to ERC-3668's `urls` parameter:

1. `ipfs://` - Immutable IPFS/IPLD (CIDv1/v0)
2. `ipns://` - Mutable IPNS/dnslink (CIDv1/v0)
3. `ar://` - Arweave and ARNS
4. `bzz://` - Swarm content
5. `web3://` - ERC-4804 L2/EVM call message

### Client Requirements

Clients implementing this extension MUST:

1. For decentralized storage protocols (IPFS, IPNS, Arweave, Swarm):
   - Use appropriate gateway APIs to resolve content
   - Gateways MUST return JSON `{"data": "0x..."}` as per ERC-3668

2. For Web3 protocol:
   - Resolve Web3 URLs according to ERC-4804 specification
   - Use returned raw bytes in CCIP-Read callback if successful
   - Handle reverts by trying next fallback gateway

### Examples

#### ENS Resolution
```solidity
string[4] gateways = [
    "ipfs://bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi/ens/{data}",
    "ar://sub_domain/ens/{data}",
    "web3://base.ens.eth:8453/resolve/{data}?returns=(bytes)",
    "https://ccip.gateway.eth/ens/{data}"
]
```

#### Token Balance
```solidity
string[3] gateways = [
    "web3://base.usdc.eth:8453/balanceOf/{data}?returns=(uint256)",
    "https://api.usdc.xyz/base/balanceOf/{data}",
    "data:application/json,{\"data\":\"0x0404\"}"
]
```

## Rationale
This extension adds support for decentralized storage and Web3 URLs while maintaining compatibility with ERC-3668.

## Backwards Compatibility
This extension is backwards compatible with ERC-3668 through HTTPS fallbacks.

## Security Considerations
- Protocol-specific security considerations apply (IPFS CID verification, Arweave transaction verification, etc.)
- Gateway trust and fallback mechanisms follow ERC-3668 security guidelines

## Copyright
Copyright and related rights waived via [CC0](../LICENSE.md). 