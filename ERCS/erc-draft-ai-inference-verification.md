---
eip: XXXX
title: Standard Interfaces for AI Inference Proof Verification
description: Minimal abstract interfaces for AI inference proof backends (IProofVerifier) and consuming contracts (IVerificationMethod)
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

- `IProofVerifier` — the interface that proof backends (zkML, opML, TEE, oracle, multisig, etc.) implement to expose a uniform `verify()` entry point
- `IVerificationMethod` — the interface that consuming contracts implement to declare which verifier they use

These interfaces define how verification is called and composed across proof systems, not how it is implemented internally. They sit at the horizontal coordination layer of the AI agent proof stack, above proof-system-specific contracts and below application logic.

This standard is designed to compose with:
- **ERC-8004** for on-chain agent identity resolution
- **ERC-8263** for on-chain proof commitment (`anchor()`)
- **OCP (Observation Commitment Protocol)** for system-independent digest verification

## Motivation

On-chain AI inference involves multiple competing proof systems — zkML, opML, TEE enclaves, oracle-based attestation, and multisig — each with distinct interfaces, trust assumptions, and deployment patterns. ERCs that consume AI inference results (governance systems, DeFi protocols, autonomous agents) currently face an N×M integration problem: each consumer must write separate integration code for each proof backend it wishes to support.

Existing work addresses adjacent layers:

- **ERC-8004** establishes agent identity but does not define verification interfaces
- **ERC-8263** defines a minimal `anchor()` interface for on-chain proof commitment but does not define how that commitment is verified across backends
- **OCP** defines a system-independent verification primitive (`recompute → compare → confirm inclusion`) but does not define backend-facing or consumer-facing interfaces

The missing piece is a **common abstract interface** that lets proof backends be treated interchangeably by consumers, without requiring a central registry or coordinator contract. This ERC fills that gap.

A central registry was the original framing of this proposal (see discussion thread). The discussion in posts #2–#10 surfaced a cleaner approach: abstract interfaces with no coordinator contract, following the same pattern as ERC-20's `transfer()`. Each consumer holds a direct reference to whichever `IProofVerifier` implementation it chooses, with no hub in between.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### IProofVerifier

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IProofVerifier
/// @notice Interface for AI inference proof verification backends.
/// Implementations MAY support zkML, opML, TEE, oracle, multisig,
/// or any other proof system.
interface IProofVerifier {
    /// @notice Verify an AI inference proof.
    /// @param modelHash  SHA-256 digest of the model weights or configuration
    /// @param inputHash  SHA-256 digest of the model input after sanitisation.
    ///                   When no sanitisation pipeline is applied,
    ///                   the corresponding sanitization_pipeline_hash MUST equal
    ///                   the IDENTITY_SENTINEL defined in OCP:
    ///                   0x8116eec29078e8f57c07077d5e8080a35bde73036581df3abb93755d1b1a16ea
    /// @param outputHash SHA-256 digest of the model output
    /// @param proof      Backend-specific proof bytes (zkML proof, TEE attestation, etc.)
    /// @return           True if the proof is valid for the given hashes
    function verify(
        bytes32 modelHash,
        bytes32 inputHash,
        bytes32 outputHash,
        bytes calldata proof
    ) external view returns (bool);

    /// @notice Human-readable identifier for this proof backend.
    /// RECOMMENDED format: "{system}/{version}", e.g. "risc0-zkml/1", "opml-optimistic/1", "tee-nitro/1"
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
/// Consuming ERCs (governance, DeFi, agent systems) implement this to expose
/// their verification method in a discoverable, standardised way.
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

### Composition with the AI Agent Proof Stack

This ERC is designed to operate as Layer 5 of the following proof stack. Each layer is independently optional; the full attribution–commitment–verification chain requires all layers acting together.

```
Layer 1  ERC-8004        Agent on-chain identity
Layer 2  Input trust     Sanitisation commitments, triple-hash scheme
Layer 3  OCP             Portable, system-independent digest verification
Layer 4  ERC-8263        On-chain proof commitment via anchor()
Layer 5  This ERC        IProofVerifier / IVerificationMethod abstract interfaces
```

**Write path (executed by the agent):**

```
1. input_hash  = SHA-256(sanitised_input)          // L2 output
2. output_hash = SHA-256(output)
3. ERC-8263.anchor(agentIdScheme, agentId,          // L4 write
       proofHash)                                    // proofHash == input_hash
4. OCP.record(input_hash)                           // L3 commitment
```

**Read path (executed by the consumer):**

```
1. verifier = consumer.getVerifier()                // L5 interface
2. valid    = verifier.verify(                      // L5 interface
       modelHash, inputHash, outputHash, proof)
3. Independently verify input_hash via OCP          // L3 floor
```

### Semantic Alignment with ERC-8263

The `inputHash` parameter in `IProofVerifier.verify()` is semantically equivalent to the `proofHash` parameter in ERC-8263's `anchor()` function. Both refer to the SHA-256 digest of the sanitised model input (post-L2 processing).

Implementations that use both interfaces MUST ensure these values are identical for the same inference event.

### inputHash Requirements

- `inputHash` MUST be the SHA-256 digest of the input as it was presented to the model after any sanitisation processing.
- When no sanitisation pipeline was applied, implementations MUST set `sanitization_pipeline_hash` to the IDENTITY_SENTINEL defined by OCP:
  ```
  0x8116eec29078e8f57c07077d5e8080a35bde73036581df3abb93755d1b1a16ea
  ```
  In this case, `inputHash` equals `raw_input_hash`.

### OCP Anchoring

Implementations of `IProofVerifier` SHOULD call `OCP.record(inputHash)` internally before returning from `verify()`, or commit `inputHash` to an OCP-compatible ledger asynchronously after the call. This ensures that the input commitment survives the proof system going offline and remains independently verifiable by any party.

Whether this anchoring is synchronous or asynchronous, and on which chain, is implementation-defined. Cross-chain OCP compatibility (EVM and Solana) has been verified in practice (May 2026); the proof envelope schema requires no structural changes across chains.

### ERC-165 Support

Implementations SHOULD implement ERC-165 `supportsInterface()`:

```solidity
function supportsInterface(bytes4 interfaceId)
    external view returns (bool)
{
    return interfaceId == type(IProofVerifier).interfaceId
        || interfaceId == type(IERC165).interfaceId;
}
```

## Rationale

### Abstract interfaces over a central registry

A central coordinator contract introduces an unnecessary trust assumption: consumers must trust the registry itself has not been compromised. Abstract interfaces leave the choice of verifier to each consumer. Any contract can hold a reference to any `IProofVerifier` implementation directly — no hub required. This is consistent with OCP's design principle of minimising trust dependencies.

### Why `backendId()`

`backendId()` provides a human-readable identifier for off-chain tooling and on-chain event logs, allowing consumers to display "verified by zkML / TEE / opML" without parsing contract addresses. The `{system}/{version}` convention is recommended but not enforced; a formal registry of backend identifiers is left for a future ERC.

### Why `proof` is opaque bytes

Proof formats are intentionally backend-specific and evolve independently of this interface. Encoding format requirements belong in backend-specific ERCs or companion specifications, not in this interface layer.

### Relationship to `IVerificationMethod`

`IVerificationMethod` is a discovery interface. It allows indexers, wallets, and other contracts to determine which verifier a given contract uses without reading bytecode. The `VerifierUpdated` event provides an audit trail for verifier changes, which is security-relevant for consumers that hold significant value.

## Backwards Compatibility

No backwards compatibility issues. This ERC introduces new interfaces and does not modify any existing standard.

## Reference Implementation

> To be contributed. Reference implementations for the following backends are anticipated:
> - zkML backend (RISC Zero / Bonsai)
> - opML optimistic backend
> - TEE backend (AWS Nitro / Intel TDX)
> - Oracle / multisig backend

Live reference implementation of the full L1–L4 stack is available at `gateway.ensub.org` (ERC-8004 + input trust layer, by TMerlini / dinamic.eth). L5 integration is pending.

## Open Questions

The following questions are open for contributor input before this ERC is finalised. Contributors are welcome to open a PR against this draft or reply in the discussion thread.

**Q1: Should OCP anchoring be SHOULD or MUST? (for @Damonzwicker)**

The current draft uses SHOULD for `OCP.record(inputHash)`. Arguments for MUST: without it, the L3 portability guarantee is absent and the full stack is broken. Arguments against: async anchoring patterns (as demonstrated in the live implementation) complicate a synchronous MUST. Input requested on the right normative level and on whether a time-bound async commitment satisfies MUST semantics.

**Q2: Formal L2 composition section (for @TMerlini)**

The triple-hash scheme (`raw_input_hash` / `sanitization_pipeline_hash` / `input_hash`) and the IDENTITY_SENTINEL are the most concretely specified and independently verified pieces of this stack. A formal composition section describing how L2 output feeds into `IProofVerifier.verify()` would strengthen both ERCs. Invitation to co-author or contribute this section, with `gateway.ensub.org` as the normative reference implementation.

**Q3: proofHash / inputHash joint alignment note (for @VincentWu)**

The semantic equivalence between `IProofVerifier.verify(inputHash)` and `ERC-8263.anchor(proofHash)` should appear as a cross-reference in both specs. An "ERC-8263 compatibility" subsection here and a matching note in ERC-8263 v0.2 would make this explicit for implementors. Invitation to align wording jointly.

**Q4: backendId namespace**

Should `backendId` values be informally self-assigned, or is a lightweight off-chain registry (similar to EIP-155 chain IDs or CAIP network identifiers) desirable? Open for discussion.

## Security Considerations

**inputHash poisoning**

`verify()` confirms that an inference ran correctly on a given input. It does not confirm that the input itself was trustworthy. Input trustworthiness is the responsibility of Layer 2 (input trust layer). Consumers SHOULD verify `sanitization_pipeline_hash` before accepting a proof, or require that a trusted L2 implementation committed the input.

**Opaque proof bytes**

The `proof` parameter is backend-specific. Consumers MUST NOT assume structural compatibility of proof bytes across different `IProofVerifier` implementations.

**Verifier mutability**

`IVerificationMethod.getVerifier()` MAY return different addresses over time. High-value consumers SHOULD monitor `VerifierUpdated` events and treat verifier changes as security-relevant configuration changes.

**No execution guarantee**

This interface defines a `view` function. It provides no guarantee that the underlying proof system is live, that the model referred to by `modelHash` is available, or that the proof was generated honestly. These guarantees must come from the specific proof backend implementation and its associated trust model.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
