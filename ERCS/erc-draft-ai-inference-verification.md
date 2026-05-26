---
eip: XXXX
title: Standard Interfaces for AI Inference Proof Verification
description: Minimal abstract interfaces for AI inference proof backends (IProofVerifier) and consuming contracts (IVerificationMethod), structured around Input, Computation, and Output
author: JimmyShi22 (@JimmyShi22) <jimmyshixiang22@gmail.com>
discussions-to: https://ethereum-magicians.org/t/draft-erc-universal-ai-inference-verification-registry/28083
status: Draft
type: Standards Track
category: ERC
created: 2026-05-26
requires: 165
---

## Abstract

This ERC defines two minimal abstract interfaces for on-chain AI inference proof verification:

- `IProofVerifier` — the interface that proof backends (zkML, opML, TEE, oracle, multisig, etc.) implement
- `IVerificationMethod` — the interface that consuming contracts implement to declare which verifier they use

A complete on-chain AI inference event is decomposed into three auditable components:

| Component | What it captures |
|-----------|-----------------|
| **Input** | What data entered the model, and how it was preprocessed |
| **Computation** | Who ran the model, which model was used, and how execution is verified |
| **Output** | What the model produced |

Each component has a corresponding struct. `IProofVerifier.verify()` accepts all three, making the full inference lifecycle verifiable end-to-end.

This standard is designed to compose with:
- **ERC-8004** for on-chain agent identity (`agentId` in `InferenceComputation`)
- **ERC-8263** for on-chain proof commitment (`anchor()`)
- **OCP (Observation Commitment Protocol)** for system-independent digest verification

## Motivation

On-chain AI inference involves multiple competing proof systems — zkML, opML, TEE enclaves, oracle-based attestation, and multisig — each with distinct interfaces, trust assumptions, and deployment patterns. ERCs that consume AI inference results currently face an N×M integration problem: each consumer must write separate integration code for each proof backend it wishes to support.

Existing work addresses adjacent layers but leaves a gap at the interface level:

- **ERC-8004** establishes agent identity but does not define verification interfaces
- **ERC-8263** defines `anchor()` for on-chain proof commitment but not how commitments are verified across backends
- **OCP** defines a system-independent verification primitive but not consumer-facing or backend-facing interfaces

Beyond the N×M problem, a flat `verify(modelHash, inputHash, outputHash, proof)` signature obscures an important question: **how was `inputHash` computed?** On-chain AI agents read data from ENS records, NFT metadata, and contract return values before hashing. Without committing to the preprocessing step, a consumer cannot determine whether the input was sanitised, and under what rules.

This ERC introduces `sanitizationPipelineHash` as a first-class field in `InferenceInput`, directly addressing the interoperability point raised in the discussion thread (see post #8). The three-struct decomposition makes every part of the inference lifecycle independently auditable.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Data Structures

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @notice Captures what data entered the model and how it was preprocessed.
struct InferenceInput {
    /// @dev SHA-256 of the raw on-chain source data, before any preprocessing.
    ///      Set to bytes32(0) if raw input provenance is not tracked.
    bytes32 rawInputHash;

    /// @dev SHA-256 of the canonical serialisation of the sanitisation pipeline spec.
    ///      MUST equal IDENTITY_SENTINEL if no preprocessing was applied:
    ///      0x8116eec29078e8f57c07077d5e8080a35bde73036581df3abb93755d1b1a16ea
    bytes32 sanitizationPipelineHash;

    /// @dev SHA-256 of the sanitised input as presented to the model.
    ///      Equals rawInputHash when sanitizationPipelineHash == IDENTITY_SENTINEL.
    ///      This value MUST match the proofHash used in ERC-8263 anchor().
    bytes32 inputHash;
}

/// @notice Captures who ran the model, which model was used, and the execution proof.
struct InferenceComputation {
    /// @dev On-chain agent identifier, resolved via ERC-8004 getAgentWallet().
    ///      Set to bytes32(0) if agent identity is not required.
    bytes32 agentId;

    /// @dev SHA-256 of the model weights or configuration.
    bytes32 modelHash;

    /// @dev Backend-specific proof bytes.
    ///      For zkML: the validity proof.
    ///      For TEE: the remote attestation report.
    ///      For opML: the optimistic challenge window reference.
    ///      For oracle/multisig: the signature bundle.
    bytes proof;
}

/// @notice Captures what the model produced.
struct InferenceOutput {
    /// @dev SHA-256 of the model output.
    bytes32 outputHash;
}
```

### IProofVerifier

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./InferenceStructs.sol";

/// @title IProofVerifier
/// @notice Interface for AI inference proof verification backends.
interface IProofVerifier {
    /// @notice Verify an AI inference proof.
    /// @param input       The input component: raw data hash, preprocessing commitment, sanitised input hash
    /// @param computation The computation component: agent identity, model hash, backend proof
    /// @param output      The output component: model output hash
    /// @return            True if the proof is valid for the given input/computation/output
    function verify(
        InferenceInput calldata input,
        InferenceComputation calldata computation,
        InferenceOutput calldata output
    ) external view returns (bool);

    /// @notice Human-readable identifier for this proof backend.
    /// RECOMMENDED format: "{system}/{version}"
    /// Examples: "risc0-zkml/1", "opml-optimistic/1", "tee-nitro/1", "oracle-multisig/1"
    function backendId() external view returns (string memory);
}
```

### IVerificationMethod

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IProofVerifier.sol";

/// @title IVerificationMethod
/// @notice Interface for contracts that declare which proof verifier they use.
interface IVerificationMethod {
    /// @notice Returns the proof verifier used by this contract.
    function getVerifier() external view returns (IProofVerifier);

    /// @notice MUST be emitted when the verifier address changes.
    event VerifierUpdated(
        address indexed previousVerifier,
        address indexed newVerifier
    );
}
```

### IDENTITY_SENTINEL

When no sanitisation pipeline is applied, `InferenceInput.sanitizationPipelineHash` MUST be set to the IDENTITY_SENTINEL constant:

```
0x8116eec29078e8f57c07077d5e8080a35bde73036581df3abb93755d1b1a16ea
```

This is the SHA-256 of the canonical identity pipeline spec, as defined by OCP. Verifiers MUST implement the following branch:

- `sanitizationPipelineHash == IDENTITY_SENTINEL` → `inputHash == rawInputHash`, skip preprocessing verification
- `sanitizationPipelineHash != IDENTITY_SENTINEL` → `inputHash != rawInputHash`, verify the transformation

### Composition with the AI Agent Proof Stack

```
Layer 1  ERC-8004        Agent on-chain identity  →  InferenceComputation.agentId
Layer 2  Input trust     Sanitisation commitments  →  InferenceInput (all three fields)
Layer 3  OCP             Portable digest verification  →  OCP.record(inputHash)
Layer 4  ERC-8263        On-chain commitment  →  anchor(agentIdScheme, agentId, inputHash)
Layer 5  This ERC        IProofVerifier / IVerificationMethod
```

**Write path:**

```
1. rawInputHash              = SHA-256(raw_on_chain_data)
2. sanitizationPipelineHash  = SHA-256(pipeline_spec)   // or IDENTITY_SENTINEL
3. inputHash                 = SHA-256(sanitised_input)
4. outputHash                = SHA-256(output)
5. ERC-8263.anchor(scheme, agentId, inputHash)          // L4
6. OCP.record(inputHash)                                // L3
```

**Read path:**

```
1. verifier = consumer.getVerifier()
2. valid    = verifier.verify(input, computation, output)
3. Independently verify inputHash via OCP               // L3 floor
```

### Semantic Alignment with ERC-8263

`InferenceInput.inputHash` MUST equal the `proofHash` used in the corresponding `ERC-8263.anchor()` call for the same inference event. Both refer to the SHA-256 of the sanitised model input.

### OCP Anchoring

Implementations of `IProofVerifier` SHOULD anchor `input.inputHash` via OCP before or after `verify()` returns. This ensures the input commitment survives the proof system going offline and remains independently verifiable. Anchoring MAY be asynchronous and is not required to be synchronous with the `verify()` call.

### ERC-165 Support

Implementations SHOULD support ERC-165:

```solidity
function supportsInterface(bytes4 interfaceId)
    external view returns (bool)
{
    return interfaceId == type(IProofVerifier).interfaceId
        || interfaceId == type(IERC165).interfaceId;
}
```

## Rationale

### Three-struct decomposition

A single flat function signature `verify(modelHash, inputHash, outputHash, proof)` conflates three distinct concerns:

1. **Input** — What data was used and how was it prepared? `rawInputHash` and `sanitizationPipelineHash` make preprocessing auditable. Without them, a consumer cannot distinguish "clean input, no preprocessing" from "missing provenance."
2. **Computation** — Who ran it and how was it verified? `agentId` links to on-chain identity (ERC-8004); `modelHash` pins the model; `proof` carries the backend-specific execution certificate.
3. **Output** — What was produced? `outputHash` is the only output field; richer output semantics belong in application-layer ERCs.

Separating these into structs makes each component independently extensible. An application that does not require agent identity tracking can pass `agentId = bytes32(0)` without changing the interface.

### Why `sanitizationPipelineHash` is not optional

Making `sanitizationPipelineHash` a required field with a defined sentinel value (rather than an optional parameter) avoids ambiguity. A missing field can mean "no preprocessing" or "preprocessing not tracked." The IDENTITY_SENTINEL makes intent explicit and enables verifiers to implement a single deterministic branch.

### Abstract interfaces over a central registry

A central coordinator contract introduces an unnecessary trust assumption. Abstract interfaces leave the choice of verifier to each consumer, consistent with OCP's principle of minimising trust dependencies.

### Why `proof` is opaque bytes

Proof formats are backend-specific and evolve independently. Encoding requirements belong in backend-specific ERCs, not in this interface layer.

## Backwards Compatibility

No backwards compatibility issues. This ERC introduces new interfaces and does not modify any existing standard.

## Reference Implementation

> To be contributed. Anticipated backend implementations:
> - zkML (RISC Zero / Bonsai)
> - opML optimistic
> - TEE (AWS Nitro / Intel TDX)
> - Oracle / multisig

Live L1–L4 reference: `gateway.ensub.org` (TMerlini / dinamic.eth). L5 integration pending.

## Open Questions

**Q1: Should OCP anchoring be SHOULD or MUST? (for @Damonzwicker)**

Current draft: SHOULD. Argument for MUST: without L3 anchoring the portability guarantee is absent. Argument against: async anchoring (as in the live implementation) complicates a synchronous MUST. What is the right normative level?

**Q2: Formal L2 composition section (for @TMerlini)**

The triple-hash scheme and IDENTITY_SENTINEL are the most concretely verified pieces of this stack. A formal section describing how L2 output maps to `InferenceInput` fields would strengthen both ERCs. Invitation to co-author, with `gateway.ensub.org` as the reference implementation.

**Q3: proofHash / inputHash alignment note (for @VincentWu)**

`InferenceInput.inputHash` and `ERC-8263.anchor(proofHash)` refer to the same value. This should be a cross-reference in both specs. Invitation to align wording for ERC-8263 v0.2.

**Q4: rawInputHash optionality**

`rawInputHash = bytes32(0)` signals "not tracked." Should there be a stronger requirement — e.g., SHOULD be provided when the agent reads on-chain data sources?

**Q5: backendId namespace**

Informally self-assigned vs. a lightweight off-chain registry (like EIP-155 chain IDs)? Open for discussion.

## Security Considerations

**Input provenance**

`verify()` confirms a proof is valid for a given input. It does not confirm the input was trustworthy. Consumers SHOULD check `sanitizationPipelineHash` or require a trusted L2 implementation.

**Opaque proof bytes**

Consumers MUST NOT assume structural compatibility of `proof` bytes across different `IProofVerifier` implementations.

**Verifier mutability**

`getVerifier()` MAY return different addresses over time. High-value consumers SHOULD monitor `VerifierUpdated` events.

**No execution guarantee**

`verify()` is a `view` function. It provides no liveness guarantee for the underlying proof system.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
