---
eip: 8040
title: ESG Tokenization Protocol
description: ESG-compliant, AI-native asset tokenization with quantum auditability and lifecycle integrity.
author: Leandro Lemos (@agronetlabs) <leandro@agronet.io>
discussions-to: https://ethereum-magicians.org/t/erc-8040-esg-tokenization-protocol/25846
status: Draft
type: Standards Track
category: ERC
created: 2025-09-06
requires: 20, 721, 1155
---

## Abstract

This ERC defines an AI-native protocol for ESG-compliant asset tokenization, with quantum auditability, compliance-grade metadata, and lifecycle integrity.

## Specification

### Metadata Structure

Tokens MUST expose a metadata JSON with the following minimum fields:

json 

```
{ "standard": "ERC-ESG/1.0", "category": "carbon", "geo": "BR-RS", "carbon_value": 12.5, "cycle": "2025-Q3", "digest": "sha3-512:...", "physical_id": "seal:XYZ123", "attestation": { "atf_digest": "sha3-512:...", "signer": "did:atf:ai:..." }, "status": "issued|audited|retired", "evidence": "cid:Qm..." }
```

### Smart Contract Interface

Contracts implementing this standard MUST support the following interface:

solidity 

```
pragma solidity ^0.8.0; interface IERC8040 { struct Metadata { string standard; string category; string geo; uint256 carbon_value; string cycle; bytes32 digest; string physical_id; Attestation attestation; string status; string evidence; } struct Attestation { bytes32 atf_digest; string signer; } function mintESGToken(Metadata memory metadata) external returns (uint256 tokenId); function auditESGToken(uint256 tokenId, bytes32 auditDigest) external; function retireESGToken(uint256 tokenId, string memory reason) external; function esgURI(uint256 tokenId) external view returns (string memory); function getMetadata(uint256 tokenId) external view returns (Metadata memory); event Minted(uint256 indexed tokenId, string category, string geo); event Attested(uint256 indexed tokenId, bytes32 atfDigest, string esgURI); event Retired(uint256 indexed tokenId, uint256 timestamp, string reason); }
```

### Events

solidity

```
event Minted(uint256 indexed tokenId, string category, string geo); event Attested(uint256 indexed tokenId, bytes32 atfDigest, string esgURI); event Retired(uint256 indexed tokenId, uint256 timestamp, string reason);
```

### JSON-RPC Example

json 

```
{ "method": "eth_call", "params": [ { "to": "0xContractAddress", "data": "0x..." } ], "example_metadata": { "category": "carbon", "geo": "BR-RS", "carbon_value": 12.5, "digest": "sha3-512:abc123def456..." } }
```

### Mapping & Compatibility

- [ERC-20](./eip-20.md): Each unit represents a standardized fraction (e.g., 1e18 = 1 tCO2e).
- [ERC-721](./eip-721.md): Single credit with unique esgURI and immutable metadata.
- [ERC-1155](./eip-1155.md): Homogeneous batch with common URI, metadata, and fungible amounts.

## Rationale

- Deterministic flows: Lifecycle follows strict state transitions (issued → audited → retired).
- Immutable metadata: SHA3-512 digest ensures tamper-proof records.
- Machine-verifiable audit trails: ATF-AI validates compliance deterministically.
- Post-quantum readiness: Hash functions support quantum-resistant cryptography.

## Security Considerations

1. Metadata immutability: All metadata fields MUST be cryptographically sealed after minting.
2. Zero-trust validation: ATF-AI provides deterministic validation; all attestations are timestamped.
3. Digest integrity: SHA3-512 ensures audit-trail integrity.
4. Post-quantum cryptography: Hash functions and signature schemes MUST be quantum-resistant.
5. Irreversible retirement: Once retired, tokens cannot be reactivated.
6. Physical seal validation: On-chain digest MUST match physical seal cryptographic hash.
7. Input validation: All off-chain documents MUST be hashed and publicly referenced on-chain.

## Copyright

Copyright and related rights waived via CC0-1.0.
