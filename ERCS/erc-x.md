---
ERC: XXXX
eip: XXXX
title: Shadow Logs Standard
author: [Author Name] <[contact information]>, [Co-Author Name] <[contact information]>
type: Standards Track
category: ERC
status: Draft
created: [creation date]
---


# Simple Summary
A standard for Shadow Logs in Ethereum smart contracts, enabling enhanced on-chain analytics and reduced gas costs through an off-chain logging mechanism.

This draft is a starting point for discussion and refinement. It aims to lay the foundation for a standard that could be implemented across the Ethereum ecosystem, enhancing the capabilities of smart contracts while maintaining efficiency and security.

# Abstract
This standard proposes a system for Shadow Logs, which are logs that are emitted off-chain in a shadow fork of the Ethereum mainnet. These logs are intended to provide developers with a way to emit detailed event data without incurring the gas costs associated with on-chain event logging. Shadow Logs would be emitted by shadow contracts in a shadow fork environment and would be accessible via RPC calls and potentially indexed into SQL tables or other databases for analytics.

# Motivation
The motivation for Shadow Logs is twofold:
* **Gas Efficiency:** By allowing protocols to emit logs off-chain, smart contracts can reduce their on-chain footprint, leading to lower gas costs.
* **Richer Analytics:** Shadow Logs enable the emission of detailed data that would be prohibitively expensive to emit on-chain, thus providing developers and analysts with deeper insights into contract interactions.

# Specification

## Shadow Log Emission
Shadow Logs are emitted by shadow contracts within a shadow fork. These logs are not part of the mainnet state and are emitted in response to transactions that are replayed in the shadow fork environment.

**Syntax for Shadow Log Emission**

Shadow Logs can be specified using annotated comments within the Solidity source code. These comments follow a specific syntax that allows shadow fork tooling to recognize and process them.

```solidity
/* #shadow-log
* emit LogEventName(param1, param2, param3);
*/
```

## Accessing Shadow Logs

Shadow Logs can be accessed via the same RPC calls as `eth_getLogs`. The RPC service would need to support Shadow Logs under the hood.

## Integration with Tools and Services
For Shadow Logs to be useful, they need to be integrated with existing Ethereum infrastructure tools such as block explorers, analytics platforms, and event decoders.

## Standard API Endpoints
Standard API endpoints should be defined for:
* Fetching Shadow Logs
* Decoding Shadow Logs
* Indexing Shadow Logs into searchable databases

## Discovery Mechanism
A discovery mechanism should be established to allow indexing services and block explorers to identify and index Shadow Logs.

**Example Discovery Mechanism**

A standard field in the contract's metadata (e.g., within the Solidity source code or the contract's JSON ABI) could specify the location and structure of Shadow Logs.

```json
{
  "shadowLogs": {
    "source": "https://example.com/shadow-logs/contract123.json",
    "events": [
      {
        "name": "LogEventName",
        "params": ["param1", "param2", "param3"]
      }
    ]
  }
}
```

## Rationale
The proposed standard for Shadow Logs aims to balance the need for rich on-chain data with the constraints of blockchain resource costs. By establishing a standard, we can ensure that Shadow Logs are emitted and accessed in a consistent manner, facilitating broader adoption and integration with existing tools.

## Backwards Compatibility
Shadow Logs are fully backwards compatible as they do not affect the execution or the state of the mainnet contracts. They are an off-chain addition that can be adopted incrementally by the community.

# Implementation
The implementation of Shadow Logs would require:

* Modifications to the Solidity compiler to recognize Shadow Log annotations.
* Development of shadow fork tooling to emit and index Shadow Logs.
* Updates to block explorers and analytics platforms to read and display Shadow Logs.

# Security Considerations
While Shadow Logs do not affect on-chain state, care must be taken to ensure that the off-chain infrastructure for emitting and accessing Shadow Logs is secure and reliable. Additionally, developers must ensure that the reliance on Shadow Logs does not introduce centralization or trust issues.

# Copyright
Copyright and related rights waived via CC0.
