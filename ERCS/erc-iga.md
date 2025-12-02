---
eip: <to be assigned>
title: ERC-IGA: In-Ground Asset Tokenization Standard
author: Solomon Ashok J N <solomon@ingroundassets.com>
discussions-to: https://ethereum-magicians.org/c/standards/erc/
status: Draft
type: Standards Track
category: ERC
created: 2025-11-25
requires: 20, 721, 1155, 3643
---

# ERC-IGA: In-Ground Asset Tokenization Standard

## Simple Summary

ERC-IGA defines a standard interface and lifecycle model for tokenizing verified **in-ground geological assets** on Ethereum. It introduces primitives for geological provenance, reserve classification, dynamic extraction-linked supply, ESG and rehabilitation bonding, and regulated transfer control. ERC-IGA acts as the compliance and verification framework for representing *real-world mineral reserves* as secure digital assets.

---

## Abstract

The **In-Ground Asset Tokenization Standard (ERC-IGA)** provides a unified, machine-verifiable framework for representing natural resources (such as gold, copper, lithium, rare earths, aggregates, hydrocarbons, and other subsurface materials) on Ethereum. Unlike traditional fungible or non-fungible token standards, in-ground assets require:

- **Geological metadata structures** derived from technical reports (JORC, NI 43‑101, SAMREC, PERC, S‑K 1300)
- **Attestations and signatures from Competent Persons (CP/QP)** aligned with global reporting codes
- **Immutable resource statement anchoring**, with cryptographic versioning
- **Extraction-linked state updates**, enabling supply-aware tokens (burning, locking, or depletion indexing)
- **Jurisdictional and KYC gating**, similar to ERC‑3643, for regulated mineral markets
- **ESG, rehabilitation and bonding primitives**, for transparent environmental accountability
- **Integration with oracles** for production, depletion, and reserve reclassification events

ERC‑IGA establishes a programmable, compliance-aligned abstraction for in-ground assets that bridges **geoscience → regulation → digital asset issuance → institutional finance**. It enables safer, auditable, and regulator-ready tokenization for miners, royalty/streaming companies, banks, commodity funds, and sovereign entities.

---

## Motivation

The mining industry suffers from a lack of unified digital standards for geological provenance and compliance. Resource data is locked in PDFs (CPRs, JORC Reports, NI 43‑101 Technical Reports) and cannot be validated or consumed programmatically.

Tokenization attempts today are ad hoc and unsafe because:

- They lack CP/QP verification
- They cannot encode reserve categories
- They do not track extraction or depletion
- They have no jurisdictional transfer rules
- They fail to integrate ESG or rehabilitation obligations

ERC‑IGA introduces a blockchain-native framework for these missing primitives.

---

## Specification

### Core Metadata Objects

- **IRO** — In‑Ground Resource Object  
- **IGO** — Geology Object  
- **ICO** — Compliance Object  
- **ITO** — Tenure & Jurisdiction Object  
- **IEXO** — Extraction & Depletion Object  
- **IEO** — ESG & Rehabilitation Object  

All objects MUST be hashed (SHA‑256) and anchored on-chain.  
Full metadata MAY be stored off-chain (IPFS, Arweave, Filecoin, enterprise storage).

### Required Functions

```
getIGAMetadata(tokenId)
setIGAMetadata(tokenId, igaHash, cpAddress)
recordDepletion(tokenId, newRemaining)
```

### Optional Token Extensions

- **IGA‑T** — Fixed‑supply in‑ground reserve tokens  
- **IGA‑X** — Extraction-linked, dynamically adjusting supply  
- **IGA‑C** — ESG, credit, rehabilitation, or structured note modules  

---

## Rationale

ERC‑IGA fills a unique gap not solved by ERC‑20/721/1155 or ERC‑3643.  
In‑ground assets are regulated differently, rely on CP/QP verification, and depend on dynamic extraction and ESG obligations. ERC‑IGA enables:

- Machine-verifiable geological truth  
- Cross‑jurisdictional compliance mapping  
- Standardized reserve classification  
- Dynamic supply logic tied to real extraction  
- Safer institutional adoption of mineral-backed assets  

---

## Backwards Compatibility

ERC‑IGA is fully compatible with the following:

- **ERC‑20** for fungible reserve exposure  
- **ERC‑721** for single‑asset geological titles  
- **ERC‑1155** for multi‑commodity deposits  
- **ERC‑3643** for identity‑gated regulatory compliance  

Metadata and CP attestations are stored independently and do not break wallet compatibility.

---

## Reference Implementation

```solidity
// SPDX-License-Identifier: CC0
pragma solidity ^0.8.20;

interface IGAEvents {
    event MetadataUpdated(bytes32 indexed igaHash, address indexed cpAddress);
    event DepletionRecorded(uint256 indexed tokenId, uint256 newRemaining);
}

contract ERCIGA {
    struct IGAMetadata {
        bytes32 igaHash;          
        address cpAddress;        
        uint256 remainingInGround;
    }

    mapping(uint256 => IGAMetadata) public igaData;

    function setIGAMetadata(
        uint256 tokenId,
        bytes32 igaHash,
        address cpAddress
    ) external {
        igaData[tokenId].igaHash = igaHash;
        igaData[tokenId].cpAddress = cpAddress;
        emit MetadataUpdated(igaHash, cpAddress);
    }

    function recordDepletion(uint256 tokenId, uint256 newRemaining) external {
        igaData[tokenId].remainingInGround = newRemaining;
        emit DepletionRecorded(tokenId, newRemaining);
    }

    function getIGAMetadata(uint256 tokenId)
        external
        view
        returns (IGAMetadata memory)
    {
        return igaData[tokenId];
    }
}
```

---

## Security Considerations

- **CP Identity Fraud**: mitigated using DID or ERC‑735/780 identity attestations.  
- **Metadata Tampering**: prevented via SHA‑256 anchoring and versioned updates.  
- **Oracle Manipulation**: extraction data MUST use multi‑sig, CP, or decentralized oracle networks.  
- **Over‑Issuance Risk**: IGA‑X MUST enforce remainingInGround >= totalSupply.  
- **Jurisdiction Controls**: transfers MUST check on-chain regional restrictions.  
- **ESG Enforcement**: rehabilitation bonding MUST be unfreezable until obligations are met.  

---

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).

