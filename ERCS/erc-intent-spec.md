---
title: Agent-Readable Smart Contract Documentation Layer (Intent Spec)
description: A standard for machine-verifiable semantic metadata to enable autonomous agent reasoning
author: Collins Adi (@collinsadi)
discussions-to:
status: Draft
type: Standards Track
category: ERC
created: 2026-02-11
requires: 165
license: CC0-1.0
---

## Abstract

This proposal defines a standard for attaching machine-readable semantic manifests to Ethereum smart contracts. It specifies:

1. An ERC-165 discoverable interface (`IIntentSpec`) exposing a metadata URI.
2. A canonical JSON schema describing contract-level and function-level semantic intent.

While the Application Binary Interface (ABI) defines how to call a function, it does not define the semantic intent, preconditions, or economic risks associated with execution. This ERC introduces a structured metadata layer to enable automated systems to reason about contract behavior prior to execution.

## Motivation

This ERC is complementary to ERC-8004.

ERC-8004 defines infrastructure primitives for autonomous agents, including identity, reputation, and validation mechanisms. It standardizes how agents establish identity and trust.

This ERC defines a structured semantic documentation layer for smart contracts. It standardizes how contract behavior is described and interpreted prior to execution.

Together, these standards address complementary layers of autonomous agent interaction.

Smart contracts are primarily documented for human auditors. Automated agents interacting with contracts must infer intent from naming conventions or sparse NatSpec comments, which may be ambiguous or incomplete.

The ABI provides function signatures and parameter types but does not express:

- Economic intent
- Safety preconditions
- Irreversible effects
- Risk disclosures

This proposal defines a standardized documentation layer enabling structured semantic disclosure at the contract level.

## Specification

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in RFC 2119.

---

### Interface Detection

Contracts implementing this standard **MUST** support ERC-165 interface detection as defined in ERC-165.

---

### `IIntentSpec` Interface

Contracts **MUST** expose a metadata pointer through the following interface:

```solidity
pragma solidity ^0.8.0;

/// @title IIntentSpec
/// @notice Interface for contracts that expose their Intent Spec metadata URI.
interface IIntentSpec {
    /// @notice Returns the URI where the Intent Spec JSON is stored.
    /// @return A URI (e.g. ipfs://... or https://...) pointing to the manifest.
    function getIntentSpecURI() external view returns (string memory);
}
````

---

### Metadata Resolution

* The returned URI **MUST** resolve to a JSON document conforming to the canonical schema defined below.
* The URI **SHOULD** reference immutable content (e.g., content-addressed storage).
* Once deployed, the manifest **SHOULD NOT** change.
* Agents **MUST** verify content-addressed URIs where applicable.

---

### Canonical Manifest Schema

The resource returned by `getIntentSpecURI()` **MUST** conform to the following JSON Schema (Draft 2020-12):

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "IntentSpec",
  "type": "object",
  "required": ["schemaVersion", "contract", "functions"],
  "properties": {
    "schemaVersion": {
      "type": "string",
      "description": "Semantic version of the IntentSpec schema (e.g. 1.0.0)"
    },
    "contract": {
      "type": "object",
      "required": ["name"],
      "properties": {
        "name": { "type": "string" },
        "version": { "type": "string" },
        "description": { "type": "string" }
      }
    },
    "functions": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name", "intent"],
        "properties": {
          "name": { "type": "string" },
          "selector": {
            "type": "string",
            "description": "EVM function selector in hexadecimal (0x + 8 hex chars)"
          },
          "signature": {
            "type": "string",
            "description": "Canonical Solidity function signature (e.g. transfer(address,uint256))"
          },
          "intent": { "type": "string" },
          "preconditions": {
            "type": "array",
            "items": { "type": "string" }
          },
          "effects": {
            "type": "array",
            "items": { "type": "string" }
          },
          "risks": {
            "type": "array",
            "items": { "type": "string" }
          },
          "agentGuidance": { "type": "string" }
        }
      }
    },
    "events": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["name"],
        "properties": {
          "name": { "type": "string" },
          "description": { "type": "string" }
        }
      }
    },
    "invariants": {
      "type": "array",
      "items": { "type": "string" }
    }
  }
}
```

#### Schema Requirements

* `schemaVersion`, `contract`, and `functions` are **REQUIRED**.
* Each function entry **MUST** include:

  * `name`
  * `intent`
* `selector` and `signature` are OPTIONAL but **RECOMMENDED**.
* Agents **MAY** ignore unknown fields for forward compatibility.

---

### NatSpec Integration (Non-Normative)

This ERC does not modify the Solidity compiler or NatSpec standard.

Developers **MAY** use custom NatSpec tags to generate manifests via external tooling. Suggested tags include:

| Level    | Tag                          | Purpose                   |
| -------- | ---------------------------- | ------------------------- |
| Contract | `@custom:agent-version`      | Contract version          |
| Contract | `@custom:agent-description`  | Short description         |
| Contract | `@custom:agent-invariant`    | Invariant (repeatable)    |
| Contract | `@custom:agent-event`        | Event name + description  |
| Function | `@custom:agent-intent`       | One-line intent           |
| Function | `@custom:agent-precondition` | Precondition (repeatable) |
| Function | `@custom:agent-effect`       | Effect (repeatable)       |
| Function | `@custom:agent-risk`         | Risk (repeatable)         |
| Function | `@custom:agent-guidance`     | Guidance                  |

Tooling MAY extract these tags at build time to emit schema-conformant JSON.

---

## Rationale

### Structured JSON Schema

A standardized schema enables deterministic parsing of contract metadata. Required fields provide minimal semantic guarantees while allowing optional enrichment.

### Off-Chain Metadata

Storing semantic documentation on-chain is cost prohibitive. A URI pointer reduces gas overhead while allowing immutable documentation through content-addressed storage.

### Single Discovery Entry Point

`getIntentSpecURI()` provides a consistent discovery mechanism for metadata retrieval.

---

## Backwards Compatibility

This proposal is fully backwards compatible.

Existing contracts MAY support this standard through:

* Proxy upgrades
* Wrapper contracts
* Metadata registries

Contracts not implementing this interface are treated as lacking semantic metadata.

---

## Security Considerations

### Metadata Misrepresentation

Contract authors may provide inaccurate metadata. Agents SHOULD independently verify:

* Contract bytecode
* Execution simulations
* Third-party attestations

### Simulation Verification

Agents SHOULD simulate execution and compare observed state transitions with declared `effects`.

### Metadata Integrity

Agents MUST verify content-addressed URIs where applicable to prevent tampering.

---

## Test Cases

Reference implementations MAY include:

* Example contracts implementing `IIntentSpec`
* Manifest validation tooling
* Agent-side verification workflows

These are non-normative.

---

## Copyright

Copyright and related rights waived via CC0-1.0.
