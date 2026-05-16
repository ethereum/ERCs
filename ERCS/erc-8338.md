---
eip: TBD
title: Zero-Knowledge Compliance Oracle
description: On-chain ZK compliance verification without revealing transaction data
author: DROO (@DROOdotFOO), Bloo (@bloo-berries), Merkle Bonsai (@Jabher)
discussions-to: https://ethereum-magicians.org/t/erc-zero-knowledge-compliance-oracle/28543
status: Draft
type: Standards Track
category: ERC
created: 2026-04-07
requires: 165
---

## Abstract

A standard interface for on-chain verification of regulatory compliance (AML, sanctions screening, anti-structuring) using zero-knowledge proofs. Users generate proofs client-side that attest to compliance with jurisdiction-specific thresholds without revealing transaction amounts, counterparty identities, or screening details. Verifiers confirm proof validity on-chain. No trusted third party or TEE is required.

## Motivation

Public blockchains force a binary choice between transparency and privacy. Transparent execution (Uniswap, CoW Protocol) exposes trades to billions in cumulative MEV extraction. Privacy tools (Tornado Cash) have been sanctioned for lacking compliance mechanisms.

Existing approaches to compliant privacy fall short:

- **View keys** (Railgun, Panther): Trade privately, then reveal raw transaction data to auditors on request. This leaks the data: it is delayed transparency.
- **TEE-based compliance** (various): Rely on hardware trust assumptions that have been broken repeatedly (SGX side channels, key extraction).
- **Compliance-by-exclusion** (Privacy Pools): Prove you're NOT in a bad set. Doesn't prove you ARE compliant with specific jurisdiction rules.

This ERC defines a standard where compliance is proven cryptographically at transaction time. The proof commits to screening results, jurisdiction thresholds, and provider attestations. Regulators verify a proof. They never see the underlying data.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

### Terminology

- **providerSetHash**: A commitment to the specific set of screening providers and their weights used for a particular compliance proof. Included in each attestation for retroactive verification.
- **providerConfigHash**: A hash of the global provider weight configuration published by the oracle administrator. Versioned on-chain; weight changes push a new entry to the config history.
- **attestation TTL**: The duration (in seconds) for which a compliance attestation remains valid after on-chain recording. Expired attestations remain queryable via `getHistoricalProof()` but are not considered valid by `checkCompliance()`.

### Proof Types

Implementations MUST support the following proof types. Each type corresponds to a separate ZK circuit with its own verification key.

All proof types include `submitter` as a public input; implementations MUST enforce
`submitter == msg.sender` at submission time.

| Type ID | Name              | Circuit           | Public inputs                                                                                                                                    | Private inputs                                                                                             |
| ------- | ----------------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| 0x01    | Compliance        | compliance        | jurisdiction_id, provider_set_hash, config_hash, timestamp, meets_threshold, submitter                                                           | signals, weights, weight_sum, provider_ids, num_providers                                                  |
| 0x02    | Risk Score        | risk_score        | proof_type (threshold/range), direction, bound_lower, bound_upper, result, config_hash, provider_set_hash, submitter                             | signals, weights, weight_sum, provider_ids, num_providers                                                  |
| 0x03    | Pattern           | pattern           | analysis_type, result, reporting_threshold, time_window, tx_set_hash, submitter, settlement_root                                                 | amounts, timestamps, num_transactions                                                                      |
| 0x04    | Attestation       | attestation       | provider_id, credential_type, is_valid, credential_root, current_timestamp, submitter                                                            | credential_attribute, expiry_timestamp, merkle_index, merkle_path                                          |
| 0x05    | Membership        | membership        | merkle_root, set_id, timestamp, is_member, submitter                                                                                             | subject_salt, merkle_index, merkle_path                                                                    |
| 0x06    | Non-membership    | non_membership    | merkle_root, set_id, timestamp, is_non_member, submitter                                                                                         | low_leaf, low_leaf_salt, low_index, low_path, high_leaf, high_leaf_salt, high_index, high_path             |
| 0x07    | Compliance Signed | compliance_signed | jurisdiction_id, provider_set_hash, config_hash, timestamp, meets_threshold, signer_pubkey_hash, chain_id, oracle_address, submitter             | signals, weights, weight_sum, provider_ids, num_providers, signature, pubkey_x, pubkey_y                   |
| 0x08    | Risk Score Signed | risk_score_signed | proof_type, direction, bound_lower, bound_upper, result, config_hash, provider_set_hash, signer_pubkey_hash, chain_id, oracle_address, submitter | signals, weights, weight_sum, provider_ids, num_providers, signature, pubkey_x, pubkey_y, signed_timestamp |
| 0x09    | Compliance Multi-Signed | compliance_multi_signed | jurisdiction_id, provider_set_hash, config_hash, timestamp, meets_threshold, threshold_m, signer_pubkey_hash_0..4, chain_id, oracle_address, submitter | per-slot signals/weights/weight_sums/pubkey_x/pubkey_y/signature (5 slots each)                            |

Notes on the proof type semantics:

- **Attestation (0x04).** The leaf in the per-provider credentials Merkle tree is `leaf_hash_value(credential_hash)`, where `credential_hash = H(DOMAIN_CREDENTIAL, provider_id, submitter, credential_type, credential_attribute, expiry_timestamp)`. The hash binds the credential to a specific submitter at issuance time; cross-submitter forgery is not possible without breaking Pedersen preimage resistance. `credential_root` references a per-provider tree registered via `publishCredentialRoot`; the on-chain `providerId` recorded against the root must match the `provider_id` in the proof's public inputs.

- **Membership (0x05) and Non-membership (0x06).** The leaf is `leaf_hash_subject(value, set_id, salt)`. For membership, `value` is the submitter's address (the leaf is computed from the public `submitter` input + private `subject_salt`). For non-membership, `value` is the bracketing tree entry (`low_leaf` / `high_leaf`), and the proof asserts `low_leaf < submitter < high_leaf` using full-width Field comparison (no u64 ceiling). Tree publishers MUST sort leaves by `value`; the circuit additionally requires `high_index == low_index + 1` to prevent an attacker from skipping a real intermediate entry.

- **Pattern (0x03).** The `analysis_type` field selects the analysis kind: 1 = anti-structuring, 2 = velocity, 3 = round-amounts. Implementations that depend on a specific analysis (e.g., a settlement registry requiring anti-structuring) MUST verify the `analysis_type` field; storing only the `result` boolean is insufficient. The `settlement_root` public input is opaque to the circuit (set to 0 for standalone use, or to a downstream consumer's declarative binding value). Consumers that need to bind a pattern proof to a specific downstream state (e.g., the sub-settlements of a particular trade) MUST recompute the expected `settlement_root` from their own state and assert equality, and SHOULD mark each consumed pattern proof to prevent reuse across multiple bound contexts.

- **Risk Score (0x02).** Validators MUST reject trivially-true claims (`bound_lower = 0` for direction GT, `bound_lower >= MAX_RISK_SCORE_BPS` for direction LT, full-domain ranges). The `meetsThreshold` boolean stored on the attestation reflects only the cryptographic `result` field; integrators querying RISK_SCORE attestations should also verify the bounds match their integration's expectations.

- **Provider-signed variants (0x07 Compliance Signed, 0x08 Risk Score Signed).** Identical semantics to their unsigned siblings, plus an in-circuit secp256k1 ECDSA verification of a Pedersen digest committing to `(chain_id, oracle_address, provider_set_hash, signals, weights, timestamp, submitter)`. The provider's pubkey commitment is exposed as `signer_pubkey_hash`; implementations MUST validate it against an on-chain registry. The `chain_id` and `oracle_address` public inputs MUST match `block.chainid` and the consuming Oracle's address: this binds a single provider signature to one deployment so the same signed payload cannot mint attestations across chains or against alternate Oracle deployments. Strict-mode jurisdictions (e.g. US BSA, Singapore) reject the unsigned siblings entirely; permissive jurisdictions accept either form.

- **Compliance Multi-Signed (0x09).** Extends the signed model to M-of-N. The circuit bundles up to five parallel signer slots; a slot is active iff its public `signer_pubkey_hash` is non-zero. Each active slot independently verifies a secp256k1 signature over a slot-specific Pedersen digest carrying its own `slot_index` (under a distinct `DOMAIN_MULTI_SIGNED_SIGNALS` tag) and independently asserts the per-provider risk score is below the jurisdiction high-risk floor. The Oracle MUST validate each non-zero slot's `signer_pubkey_hash` against the registry, MUST reject duplicate hashes across active slots, MUST enforce `chain_id == block.chainid` and `oracle_address == address(this)`, and MUST enforce `threshold_m >= JurisdictionConfig.minMultiProviderThreshold(jurisdictionId)` (e.g., US BSA and Singapore require M >= 2; permissive jurisdictions accept M >= 1). Forging an attestation under 0x09 requires compromising at least M of the N registered signing keys simultaneously.

### Verifier Interface

The verifier routes proof verification to per-proof-type verification contracts. Each circuit produces a separate verifier via the ZK backend (e.g., `bb write_solidity_verifier` for Barretenberg's UltraHonk).

```solidity
interface IXochiZKPVerifier {
    /// @notice Verify a zero-knowledge compliance proof
    /// @param proofType The type of proof (0x01-0x09)
    /// @param proof The encoded proof data
    /// @param publicInputs The public inputs to the verification circuit (packed bytes32 values)
    /// @return valid Whether the proof is valid
    function verifyProof(
        uint8 proofType,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external view returns (bool valid);

    /// @notice Verify a batch of proofs atomically
    /// @param proofTypes Array of proof types
    /// @param proofs Array of encoded proofs
    /// @param publicInputs Array of public input sets
    /// @return valid Whether ALL proofs are valid
    function verifyProofBatch(
        uint8[] calldata proofTypes,
        bytes[] calldata proofs,
        bytes[] calldata publicInputs
    ) external view returns (bool valid);

    /// @notice Get the current verifier address for a proof type
    /// @param proofType The proof type (0x01-0x09)
    /// @return verifier The verifier contract address (address(0) if not set)
    function getVerifier(uint8 proofType) external view returns (address verifier);

    /// @notice Verify a proof against a specific historical verifier version
    /// @dev Required for retroactive verification: a proof generated under a prior
    ///      verifier version must remain checkable after the current verifier has
    ///      been upgraded. Revoked versions (see Verifier Versioning) MUST revert.
    /// @param proofType The proof type (0x01-0x09)
    /// @param version The 1-indexed verifier version
    /// @param proof The encoded proof data
    /// @param publicInputs The public inputs
    /// @return valid Whether the proof is valid
    function verifyProofAtVersion(
        uint8 proofType,
        uint256 version,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external view returns (bool valid);

    /// @notice Get the verifier address for a specific historical version
    /// @param proofType The proof type (0x01-0x09)
    /// @param version The 1-indexed verifier version
    /// @return verifier The verifier contract address
    function getVerifierAtVersion(uint8 proofType, uint256 version) external view returns (address verifier);

    /// @notice Get the current verifier version for a proof type
    /// @param proofType The proof type (0x01-0x09)
    /// @return version The current version (0 if no verifier set)
    function getVerifierVersion(uint8 proofType) external view returns (uint256 version);
}
```

Implementations MUST also implement [ERC-165](./eip-165.md). `supportsInterface(bytes4)` MUST return `true` for `type(IXochiZKPVerifier).interfaceId` and for `type(IERC165).interfaceId`, and `false` for `0xffffffff`.

### Oracle Interface

```solidity
interface IXochiZKPOracle {
    struct ComplianceAttestation {
        address subject;          // address that proved compliance (msg.sender at submission)
        uint8 jurisdictionId;     // jurisdiction (0=EU, 1=US, 2=UK, 3=SG)
        uint8 proofType;          // which proof type produced this attestation (0x01-0x09)
        bool meetsThreshold;      // whether the rule was satisfied
        uint256 timestamp;        // block.timestamp at submission
        uint256 expiresAt;        // block.timestamp + attestationTTL
        bytes32 proofHash;        // keccak256(proof, proofType, chainId, oracleAddr) -- see Proof Hash Computation
        bytes32 providerSetHash;  // hash of providers + weights (COMPLIANCE/COMPLIANCE_SIGNED only; bytes32(0) otherwise)
        bytes32 publicInputsHash; // keccak256(publicInputs)
        address verifierUsed;     // verifier contract address at submission time (TOCTOU-safe)
    }

    event ComplianceVerified(
        address indexed subject,
        uint8 indexed jurisdictionId,
        bool meetsThreshold,
        bytes32 indexed proofHash,
        uint256 expiresAt,
        uint256 previousExpiresAt
    );

    event ProviderWeightsUpdated(
        bytes32 indexed configHash,
        uint256 timestamp,
        string metadataURI
    );

    event AttestationTTLUpdated(uint256 oldTTL, uint256 newTTL);
    event ConfigRevoked(bytes32 indexed configHash);
    event MerkleRootRegistered(bytes32 indexed merkleRoot);
    event MerkleRootRevoked(bytes32 indexed merkleRoot);
    event ReportingThresholdRegistered(bytes32 indexed threshold);
    event ReportingThresholdRevoked(bytes32 indexed threshold);

    /// @notice Submit a compliance proof and record the attestation
    /// @param jurisdictionId Target jurisdiction (0=EU, 1=US, 2=UK, 3=SG)
    /// @param proofType The proof type for verifier routing (0x01-0x09)
    /// @param proof The ZK proof data
    /// @param publicInputs Public inputs matching the circuit's pub parameters
    /// @param providerSetHash Hash of provider IDs and weights used for screening
    /// @return attestation The recorded compliance attestation
    function submitCompliance(
        uint8 jurisdictionId,
        uint8 proofType,
        bytes calldata proof,
        bytes calldata publicInputs,
        bytes32 providerSetHash
    ) external returns (ComplianceAttestation memory attestation);

    /// @notice Submit a batch of compliance proofs atomically
    /// @dev All entries share `jurisdictionId`. The batch reverts if ANY entry fails
    ///      verification, validation, or replay checks. Implementations MUST cap the
    ///      batch size (see Batch verification limits).
    /// @param jurisdictionId Target jurisdiction for all entries (0=EU, 1=US, 2=UK, 3=SG)
    /// @param proofTypes Proof type for each entry (0x01-0x09)
    /// @param proofs ZK proof data for each entry
    /// @param publicInputs Public inputs for each entry
    /// @param providerSetHashes Provider set hash for each entry
    /// @return attestations The recorded compliance attestations, in input order
    function submitComplianceBatch(
        uint8 jurisdictionId,
        uint8[] calldata proofTypes,
        bytes[] calldata proofs,
        bytes[] calldata publicInputs,
        bytes32[] calldata providerSetHashes
    ) external returns (ComplianceAttestation[] memory attestations);

    /// @notice Check if an address has a valid (non-expired) compliance attestation
    /// @param subject The address to check
    /// @param jurisdictionId The jurisdiction to check against
    /// @return valid Whether a valid, non-expired attestation exists
    /// @return attestation The attestation if valid
    function checkCompliance(
        address subject,
        uint8 jurisdictionId
    ) external view returns (bool valid, ComplianceAttestation memory attestation);

    /// @notice Check compliance filtered by proof type
    /// @dev Integrators that require a specific proof family (e.g. only signed variants,
    ///      or only ATTESTATION-backed) MUST use this rather than `checkCompliance()`,
    ///      since the latest attestation per (subject, jurisdiction) may have been
    ///      produced by any supported proof type.
    /// @param subject The address to check
    /// @param jurisdictionId The jurisdiction
    /// @param proofType The required proof type (0x01-0x09)
    /// @return valid Whether a valid attestation of the specified type exists
    /// @return attestation The attestation if valid
    function checkComplianceByType(
        address subject,
        uint8 jurisdictionId,
        uint8 proofType
    ) external view returns (bool valid, ComplianceAttestation memory attestation);

    /// @notice Retrieve a proof for retroactive verification (proof-of-innocence)
    /// @param proofHash The hash of the original compliance proof
    /// @return attestation The original attestation record
    function getHistoricalProof(
        bytes32 proofHash
    ) external view returns (ComplianceAttestation memory attestation);

    /// @notice Get the proof type that produced an attestation
    /// @dev Equivalent to `getHistoricalProof(proofHash).proofType` but cheaper.
    /// @param proofHash The hash of the original proof
    /// @return proofType The proof type identifier (0x01-0x09)
    function getProofType(bytes32 proofHash) external view returns (uint8 proofType);

    /// @notice Get all attestation hashes for a subject in a jurisdiction
    /// @dev Returns an unbounded array. Implementations SHOULD also expose a
    ///      paginated variant for subjects with large histories.
    /// @param subject The address to query
    /// @param jurisdictionId The jurisdiction
    /// @return proofHashes Array of proof hashes for historical lookup
    function getAttestationHistory(
        address subject,
        uint8 jurisdictionId
    ) external view returns (bytes32[] memory proofHashes);

    /// @notice Get the current provider weight configuration hash
    /// @return configHash Hash of current provider weights
    function providerConfigHash() external view returns (bytes32 configHash);

    /// @notice Get the current attestation time-to-live
    /// @return ttl Duration in seconds that attestations remain valid
    function attestationTTL() external view returns (uint256 ttl);
}
```

Implementations MUST also implement [ERC-165](./eip-165.md). `supportsInterface(bytes4)` MUST return `true` for `type(IXochiZKPOracle).interfaceId` and for `type(IERC165).interfaceId`, and `false` for `0xffffffff`.

### Jurisdiction Configuration

Implementations MUST publish jurisdiction thresholds openly. Risk scores are expressed in basis points (0-10000 = 0.00%-100.00%).

| ID  | Jurisdiction | Low (bps) | Medium (bps) | High / Filing trigger (bps) |
| --- | ------------ | --------- | ------------ | --------------------------- |
| 0   | EU (AMLD6)   | 0-3099    | 3100-7099    | >=7100                      |
| 1   | US (BSA)     | 0-2599    | 2600-6599    | >=6600                      |
| 2   | UK (MLR)     | 0-3099    | 3100-7099    | >=7100                      |
| 3   | Singapore    | 0-3599    | 3600-7599    | >=7600                      |

### Attestation Lifecycle

Compliance attestations have a configurable time-to-live (TTL):

- Default TTL: 24 hours
- Minimum TTL: 1 hour
- Maximum TTL: 30 days
- `expiresAt = block.timestamp + attestationTTL` at submission time

`checkCompliance()` MUST return `false` for expired attestations. Expired attestations MUST remain retrievable via `getHistoricalProof()` for proof-of-innocence purposes. The TTL is updatable by the oracle administrator via `updateAttestationTTL()`.

### Provider Weight Publication

Implementations SHOULD publish provider weights as an on-chain configuration hash. Weight changes MUST emit `ProviderWeightsUpdated` with the new configuration hash, timestamp, and an optional `metadataURI` pointing to the full configuration (e.g., on IPFS or Arweave).

Provider configuration MUST be versioned. Implementations SHOULD maintain a history of configuration hashes to support retroactive verification: determining which weights were active when a particular proof was generated. Implementations SHOULD support revoking historical configuration hashes when a configuration is discovered to be flawed. The currently active configuration MUST NOT be revocable.

### Proof Type Routing

Implementations MUST maintain a registry mapping each proof type to a per-circuit verifier contract. Each ZK circuit (compiled separately) produces its own verification key and verifier contract. The main verifier contract acts as a router:

1. Caller specifies `proofType` (0x01-0x09)
2. Router looks up the registered verifier for that type
3. Public inputs are decoded from packed `bytes` to `bytes32[]`
4. The per-circuit verifier's `verify(bytes, bytes32[])` is called

Verifier addresses are updatable to allow circuit upgrades. Implementations SHOULD use a two-step ownership transfer pattern for administrative operations.

### Verifier Versioning

Verifier upgrades MUST NOT invalidate proofs that were valid under a prior verifier. An on-chain attestation produced under version $v_n$ records `verifierUsed` at submission time, but a counterparty months later may need to re-run the verification — for example, to recompute proof-of-innocence after a discovered circuit bug or to independently audit a historical attestation. This is impossible if the contract retains only the latest verifier address.

Implementations MUST maintain an append-only version history per proof type and expose three operations:

- `getVerifierVersion(proofType)` returns the current version count (1-indexed).
- `getVerifierAtVersion(proofType, version)` returns the verifier contract address at that version.
- `verifyProofAtVersion(proofType, version, proof, publicInputs)` re-runs verification through the historical verifier.

Implementations MUST support revoking a specific historical version when a verifier is discovered to be unsound. Revocation MUST NOT delete the entry from history (the address remains recoverable via `getVerifierAtVersion`), but `verifyProofAtVersion` against a revoked version MUST revert. Revoking the current (latest) version MUST be forbidden — current revocation must instead proceed by proposing a replacement verifier through the upgrade timelock and then revoking the prior version.

Revocation MAY have two paths: a delayed path (default) and an immediate path gated behind the GUARDIAN role for cases where a paused proof type needs the revocation locked in before the timelock elapses. The reference implementation uses a 6 h delay for the routine path.

### Public Input Validation

Implementations MUST validate public inputs semantically for each proof type before forwarding to the per-circuit verifier. The ZK proof guarantees internal consistency (e.g., that the score was correctly computed from the committed inputs), but the oracle MUST verify that those committed inputs match the expected context (e.g., that the config hash is a known configuration, that the merkle root belongs to a registered set). Without this validation, a valid proof generated for one context can be replayed in a different context.

Public inputs MUST be 32-byte aligned. Implementations MUST reject `publicInputs` where `length % 32 != 0`.

The following validation MUST be performed per proof type:

| Proof Type        | Validated Fields                                                                                                                                 | Registry                                    |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------- |
| COMPLIANCE        | jurisdiction_id, provider_set_hash, config_hash, meets_threshold                                                                                 | Config hash registry                        |
| RISK_SCORE        | result, config_hash, provider_set_hash                                                                                                           | Config hash registry                        |
| PATTERN           | result, reporting_threshold, tx_set_hash != 0                                                                                                    | Reporting threshold registry                |
| ATTESTATION       | is_valid, credential_root, provider_id                                                                                                           | Credential root registry (per-provider)     |
| MEMBERSHIP        | merkle_root, is_member                                                                                                                           | Merkle root registry                        |
| NON_MEMBERSHIP    | merkle_root, is_non_member                                                                                                                       | Merkle root registry                        |
| COMPLIANCE_SIGNED | jurisdiction_id, provider_set_hash, config_hash, meets_threshold, signer_pubkey_hash, chain_id == block.chainid, oracle_address == address(this) | Config hash + signer-pubkey-hash registries |
| RISK_SCORE_SIGNED | result, config_hash, provider_set_hash, semantic-bound checks, signer_pubkey_hash, chain_id == block.chainid, oracle_address == address(this)    | Config hash + signer-pubkey-hash registries |

### Proof Result Validation

Each proof type includes a boolean result field (`meets_threshold`, `result`, `is_valid`, `is_member`, `is_non_member`) in its public inputs. A valid ZK proof with a false result means the prover proved they do NOT satisfy the condition (e.g., non-compliant, not a member). Implementations MUST reject proofs where the result field is not `true` (encoded as `bytes32(uint256(1))`). Without this check, a user could submit a cryptographically valid proof of non-compliance and receive a compliant attestation.

The `providerSetHash` parameter in `submitCompliance()` is semantically meaningful for COMPLIANCE proofs, which include it as a caller-supplied public input. RISK_SCORE proofs also commit to a `provider_set_hash` in their circuit public inputs, but this value is embedded in the proof itself and does not come from the caller parameter. For all non-COMPLIANCE proof types, implementations MUST ignore the caller-supplied `providerSetHash` and store `bytes32(0)` in the attestation to prevent injection of arbitrary values.

### Validation Registries

Implementations MUST maintain on-chain registries for values that public inputs are validated against. These registries prevent context-spoofing attacks where a proof generated for one context is submitted in a different context.

**Config hash registry.** Tracks valid provider weight configuration hashes. New hashes are added when the administrator updates the configuration. Historical hashes SHOULD be revocable (see Provider Weight Publication). The currently active configuration MUST NOT be revocable. Implementations MUST permanently retain revocation status: a previously-revoked config hash MUST NOT be re-registrable, to prevent silent un-revocation.

**Merkle root registry.** Tracks valid merkle roots for MEMBERSHIP and NON_MEMBERSHIP proofs (typically managed sets such as sanctions lists or whitelists). Roots MUST be registered by the administrator before proofs referencing them can be accepted. Roots SHOULD be revocable when the underlying set is superseded or compromised.

**Credential root registry (per-provider).** Tracks valid credentials Merkle roots for ATTESTATION proofs, keyed by `provider_id`. Each provider has an authorized publisher EOA, set by the administrator via a separate registration step. The publisher SHOULD publish new credential roots periodically (replacing prior ones). Roots SHOULD have a finite TTL window during which they are accepted; this window allows users with paths against an outgoing root to continue submitting proofs while a new root propagates. Implementations MUST verify the proof's `provider_id` matches the registered `providerId` for the credential root being referenced; otherwise an attacker could reuse another provider's root with a forged `provider_id`.

**Reporting threshold registry.** Tracks valid reporting thresholds for PATTERN (anti-structuring) proofs. Each jurisdiction defines its own reporting threshold (e.g., $10,000 for US BSA). Thresholds MUST be registered before proofs referencing them can be accepted.

### Risk Score Computation

The risk score formula MUST be deterministic and publicly verifiable:

$$\text{RiskScore}_{\text{bps}} = \frac{\displaystyle\sum_{i=1}^{N} \text{signal}_i \cdot \text{weight}_i}{W} \times 100$$

where $\text{signal}_i \in [0, 100]$ are provider screening results, $\text{weight}_i$ are published provider weights, $W = \sum_{i=1}^{N} \text{weight}_i$ is the weight sum, and $N \leq 8$ is the number of active providers. The result is in basis points ($0$-$10000$, i.e., $0.00\%$-$100.00\%$).

Circuits that accept `weight_sum` as a private input MUST constrain it to equal the actual sum of the `weights` array. Without this constraint, a malicious prover could pass an arbitrary denominator to inflate or deflate the computed score.

The ZK proof commits to:

- Signal values (hidden)
- Weights used (public via config_hash, must match published config)
- Resulting score (hidden)
- Whether jurisdiction threshold was crossed (revealed as boolean)

### Hash Function Requirements

Circuits MUST use a collision-resistant hash function for all commitments (provider set hashes, config hashes, Merkle trees, credential hashes). The reference implementation uses Pedersen hash, which is efficient in ZK circuits and available in the Noir standard library.

Pedersen commitments are additively homomorphic over the underlying elliptic curve. This is safe provided:

1. Hash outputs are used only as opaque commitments compared via equality.
2. No circuit composes hash outputs arithmetically (e.g., `H(x) + H(y)`).
3. All hash calls use fixed-arity inputs to prevent length-extension reinterpretation.

Implementations MAY migrate to Poseidon2 when high-level APIs stabilize in the circuit language, as Poseidon2 provides stronger random-oracle properties.

### Merkle Tree Domain Separation

Implementations MUST use distinct domain tags for leaf and internal-node hashes to prevent the second-preimage attack where an attacker crafts a leaf whose hash collides with an internal node. The reference implementation uses three explicit tags: one for internal nodes, one for set-style leaves bound to `(element, set_id)`, and one for value-style leaves committing a single value (e.g., `credential_hash` in the attestation circuit).

The fixed-arity Pedersen hash used in the reference implementation does NOT achieve domain separation by input arity alone (e.g., `H([a, b, 0]) == H([a, b])` for the standard pedersen_hash without an explicit length tag). Implementations MUST therefore include an explicit domain tag in the input array.

### Non-Membership Proof Security

The non-membership circuit proves that the SUBMITTER is NOT in a sorted Merkle tree by demonstrating adjacency: there exist two consecutive leaves $l$ and $h$ in the tree such that $l < \text{submitter} < h$ AND $\text{high\_index} = \text{low\_index} + 1$.

The adjacency requirement is critical. Without it, an attacker could pick two non-adjacent tree entries that bracket the submitter, hiding any real intermediate entry that contains the submitter's address. Tree publishers MUST sort leaves by their raw value (the `value` argument to `leaf_hash_subject`). Implementations SHOULD insert sentinel boundary leaves at $0$ and $p-1$ (BN254 prime minus 1) so every submitter has well-defined neighbors.

Comparison MUST be performed over the full Field range using bit-decomposition (Noir's `Field::lt`). Earlier designs that cast to `u64` and compared as fixed-width integers required additional range checks on all values; the reference implementation uses Field-level comparison to support arbitrary-width identifiers (Ethereum addresses, hashes, etc.) without truncation risk.

### Submitter Binding

Implementations MUST bind every proof to its submitter. Each proof type includes `submitter` as a public input that the on-chain validator enforces equal to `msg.sender`. For proofs that prove a fact about a specific party (membership, non-membership, attestation), the proof's leaf format MUST also bind to `submitter` in-circuit so the proof is meaningful only for that submitter:

- Membership / non-membership: `leaf_hash_subject(value, set_id, salt)` where `value` derives from the relevant party (e.g., `submitter` for membership; the bracketing tree entries for non-membership ordering).
- Attestation: `credential_hash = H(DOMAIN_CREDENTIAL, provider_id, submitter, credential_type, credential_attribute, expiry_timestamp)`, then `leaf_hash_value(credential_hash)`.

Without this binding, an unauthorized party could submit a proof asserting facts about an arbitrary value and claim the resulting attestation as their own.

### Retroactive Flagging

Each compliance proof MUST commit to:

1. Provider IDs used for screening (committed via providerSetHash)
2. Results returned by each provider at proof time (hidden)
3. The oracle's clearing decision (revealed as meetsThreshold boolean)
4. A timestamp binding the proof to a specific block

This enables proof-of-innocence: counterparties to retroactively flagged addresses can present the original attestation (retrieved via `getHistoricalProof()`) demonstrating the address was clean at transaction time. The on-chain record is immutable and independently verifiable.

## Rationale

**Why client-side computation?** Server-side or TEE-based compliance creates a trusted party that can be coerced, compromised, or surveilled. Client-side ZK proof generation means the raw data never leaves the user's device. The verifier learns only the boolean result.

**Why published weights?** "Black box" compliance algorithms invite regulatory skepticism and legal challenge. Publishing weights and thresholds makes the system auditable without compromising individual privacy. When enforcement data reveals a provider consistently misses bad actors, the weight adjustment is transparent.

**Why on-chain attestations?** Off-chain attestations can be forged, lost, or denied. On-chain records are immutable, timestamped, and independently verifiable. This is critical for proof-of-innocence: the proof must be retrievable months or years after the original transaction.

**Why not Privacy Pools inclusion/exclusion proofs?** Privacy Pools prove set membership ("I'm not in the OFAC set"). This ERC proves compliance with specific rules ("my risk score under jurisdiction X is below threshold Y using providers A, B, C"). Set membership is a subset of what's needed for regulatory compliance.

**Why attestation TTL?** Compliance status is not permanent. A user who was compliant yesterday may not be compliant today. Screening providers update their data continuously. The TTL forces periodic re-attestation while keeping the window configurable per deployment context.

**Why nine proof types?** Each proof type maps to a separate ZK circuit with distinct constraint logic. Compliance handles the core risk score check. Risk Score provides standalone threshold/range proofs. Pattern detects structuring behaviors. Attestation verifies credentials from authorized providers. Membership proves inclusion in an authorized set (whitelist). Non-membership proves exclusion from a sanctions list via sorted Merkle tree adjacency. The two single-signer `_signed` variants (Compliance Signed, Risk Score Signed) shadow their unsigned siblings but additionally verify one provider's secp256k1 ECDSA signature over the screening payload in-circuit and bind to (`chain_id`, `oracle_address`). The Compliance Multi-Signed variant (0x09) extends this further to M-of-N: up to five parallel signer slots, each independently signature- and floor-checked, with a runtime `threshold_m` and a per-jurisdiction floor for M. They are separate circuits rather than an oracle-side flag because the signature check materially changes the constraint set: an unsigned proof has no provenance for its `signals[]` private witness, while a signed proof cryptographically attests them. Strict-mode jurisdictions (US BSA, Singapore) accept only the signed forms. This separation keeps individual circuits small and auditable, and lets unsigned-tolerant jurisdictions deploy without paying the signature-verification gas overhead.

### What this standard does NOT prove

The single most important caveat for adopters: the cryptographic guarantees in this ERC are about _correct computation_, not about _honest inputs_. Three trust tiers exist across the proof types, and integrators MUST pick the tier that matches their threat model.

| Tier                | Proof types                           | Who attests the screening signals?                                                         |
| ------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------ |
| Self-attested       | COMPLIANCE, RISK_SCORE                | The submitter. The circuit accepts `signals[]` as a private witness with no signature.     |
| Provider-attested   | COMPLIANCE_SIGNED, RISK_SCORE_SIGNED  | A registered provider, via in-circuit secp256k1 ECDSA over the screening payload.          |
| Credential-attested | ATTESTATION (composed with the above) | A registered credential-tree publisher EOA, via Merkle inclusion against a published root. |

The self-attested tier is useful for jurisdictions that explicitly permit user-asserted compliance (some EU and UK contexts), for fast-path flows where a downstream system performs the honest-signal check, and as a building block in larger composed proofs. A user submitting a self-attested COMPLIANCE proof could in principle pass `signals = [0, ...]` and produce a valid "low-risk" proof regardless of their true screening result; `provider_set_hash` and `config_hash` commit to _which_ providers and weights were used, not to _what_ those providers returned. This is documented as an explicit design tradeoff, not a bug.

Strict-mode jurisdictions (US BSA, Singapore) MUST reject the self-attested tier — the reference enforces this via `JurisdictionConfig.requireSignedSignals(uint8)`. Permissive jurisdictions MAY accept either tier. Integrators whose threat model includes a dishonest user but a trusted provider MUST require the signed variants. Integrators whose threat model includes a compromised provider key MUST additionally require an ATTESTATION proof against an independently-published credential tree, ideally with an in-circuit signature over the credential root (out of scope for this specification, tracked as future work).

Implementations SHOULD prominently document this trust model in deployment-facing materials.

### Related Work

Several existing and emerging standards address compliance, privacy, or on-chain ZK verification. This ERC differs from each in scope, architecture, or trust model.

**[ERC-3643](./eip-3643.md) (T-REX).** The ratified compliance token standard for regulated securities, with $32B+ in tokenized assets. ERC-3643 requires identity revelation via ONCHAINID claims verified by trusted issuers. This ERC proves compliance without revealing identity data, provider signals, or transaction amounts. The two standards are complementary: this ERC could serve as a ZK-enhanced identity provider within an ERC-3643 deployment.

**Privacy Pools (0xbow).** Live on Ethereum mainnet since March 2025. Users prove their withdrawal originates from a "clean" deposit set using ZK proofs, with Association Set Providers (ASPs) maintaining approved deposit lists. The Privacy Pools protocol validates the "prove compliance without revealing data" model. However, set membership is a subset of what regulatory compliance requires. This ERC extends the approach to multi-dimensional compliance: risk scoring, anti-structuring detection, credential verification, and membership/non-membership proofs.

**[EIP-7963](./eip-7963.md).** An oracle-permissioned [ERC-20](./eip-20.md) that validates token transfers via ZK proofs against off-chain payment instructions (ISO 20022 format), using RISC Zero as the proof system. EIP-7963 gates a single token's transfers through a single oracle with a single proof type. This ERC provides standalone compliance attestations with nine proof types, usable by any contract, and is not gated to token operations.

**VOSA-RWA.** A compliance-gated privacy token for real-world assets (Draft, 2026). Every token operation requires dual ZK proofs: a compliance attestation (Groth16/BN254, Poseidon hashing) and a transaction conservation proof. VOSA-RWA and this ERC share the "ZK proof for compliance, no PII on-chain" design, but VOSA-RWA embeds compliance into a specific token standard. This ERC is a standalone oracle whose attestations are reusable across protocols.

**[ERC-7812](./eip-7812.md).** A ZK identity registry using a singleton Sparse Merkle Tree (80-level, Poseidon on BN128) with custom registrars for business logic. Deployed on Ethereum mainnet. ERC-7812 provides a general-purpose private statement registry. This ERC could operate as a compliance-specific registrar within ERC-7812, storing compliance commitments in its Merkle tree.

**[ERC-8039](./eip-8039.md).** A proof-system-agnostic ZK verification interface for smart accounts (`verifyProof(bytes,bytes) returns (bytes4)`). ERC-8039 standardizes per-relation verifier contracts with a non-reverting return pattern (following [ERC-1271](./eip-1271.md)). This ERC's per-proof-type verifier routing serves a similar verification role but with domain-specific semantics (proof type routing, batch verification, version history). Each generated UltraHonk verifier in this ERC could be wrapped behind an ERC-8039 adapter for smart account integration.

**[EIP-7702](./eip-7702.md).** Account abstraction via temporary delegation: an EOA can authorize a contract to execute code on its behalf for a single transaction. EIP-7702 interacts with the `submitter == msg.sender` rule in two ways. First, when a 7702-delegated EOA calls `submitCompliance`, `msg.sender` is the EOA address (not the delegated contract), so the attestation correctly binds to the EOA and the `submitter` public input must equal that EOA. Second, a smart-account batcher (using 7702 to wrap multiple operations) can call `submitComplianceBatch` provided every entry's `submitter` public input equals the delegating EOA. Account-abstraction wallets MUST surface the bound `submitter` address to the user before submission, since a malicious dApp could otherwise solicit proofs bound to the wrong address. The same considerations apply to [ERC-4337](./eip-4337.md) paymasters and ERC-1271 contract signers when used as compliance subjects.

**[ERC-8035](./eip-8035.md) / [ERC-8036](./eip-8036.md) (MultiTrust Credential).** Non-transferable credential anchors with ZK presentation via fixed Groth16 ABI, supporting predicate proofs ("score >= threshold") without revealing raw data. The predicate-proving pattern parallels this ERC's RISK_SCORE proof type. MultiTrust focuses on credential issuance and presentation; this ERC focuses on compliance attestation and retroactive verification.

**[ERC-1922](./eip-1922.md).** The original zk-SNARK verifier standard (2019, stagnant). ERC-1922 defines a generic interface for on-chain ZK verification with dynamic arrays for cross-scheme compatibility. This ERC supersedes ERC-1922's approach with per-proof-type routing, UltraHonk support, and domain-specific input validation.

## Backwards Compatibility

This ERC introduces new interfaces and does not modify existing standards. It is designed to complement [ERC-5564](./eip-5564.md) (stealth addresses) and [ERC-6538](./eip-6538.md) (stealth meta-address registry) for privacy-preserving settlement, but does not depend on them.

## Test Cases

The reference implementation includes binary proof fixtures in `test/fixtures/` for the six unsigned proof types. Static fixtures are not provided for the three signed variants (COMPLIANCE_SIGNED, RISK_SCORE_SIGNED, COMPLIANCE_MULTI_SIGNED) because each requires a fresh secp256k1 ECDSA witness; those are exercised end-to-end in the TypeScript SDK consumer tests instead. Each unsigned fixture contains:

- `proof`: the raw UltraHonk proof bytes (8640 bytes each)
- `public_inputs`: the packed bytes32 public inputs

| Proof Type     | Public Inputs Size   | Logical Public Inputs                                                                              |
| -------------- | -------------------- | -------------------------------------------------------------------------------------------------- |
| COMPLIANCE     | 192 bytes (6 inputs) | jurisdiction_id, provider_set_hash, config_hash, timestamp, meets_threshold, submitter             |
| RISK_SCORE     | 256 bytes (8 inputs) | proof_type, direction, bound_lower, bound_upper, result, config_hash, provider_set_hash, submitter |
| PATTERN        | 224 bytes (7 inputs) | analysis_type, result, reporting_threshold, time_window, tx_set_hash, submitter, settlement_root   |
| ATTESTATION    | 192 bytes (6 inputs) | provider_id, credential_type, is_valid, credential_root, current_timestamp, submitter              |
| MEMBERSHIP     | 160 bytes (5 inputs) | merkle_root, set_id, timestamp, is_member, submitter                                               |
| NON_MEMBERSHIP | 160 bytes (5 inputs) | merkle_root, set_id, timestamp, is_non_member, submitter                                           |

All fixtures use Pedersen hash (Noir stdlib) for in-circuit commitments and Merkle tree construction. Fixtures can be regenerated via `scripts/generate-fixtures.sh`.

### Witness Annex

The exact Prover.toml inputs used to produce the binary fixtures are reproduced below so other implementations can cross-validate against the same witness. All `submitter` values are `0xdead` and all `timestamp` values are `1700000000` (UNIX seconds, 2023-11-14). Address-style values are packed as field elements; Pedersen hashes on BN254 are reproduced verbatim.

```toml
# circuits/compliance/Prover.toml
signals           = [20, 0, 0, 0, 0, 0, 0, 0]
weights           = [100, 0, 0, 0, 0, 0, 0, 0]
weight_sum        = 100
provider_ids      = ["1", "0", "0", "0", "0", "0", "0", "0"]
num_providers     = 1
jurisdiction_id   = 0     # EU
provider_set_hash = "0x14b6becf762f80a24078e62fc9a7eca246b8e406d19962dda817b173f30a94b2"
config_hash       = "0x18574f427f33c6c77af53be06544bd749c9a1db855599d950af61ea613df8405"
timestamp         = "1700000000"
meets_threshold   = true
submitter         = "0xdead"
# Derived risk score: 20 * 100 / 100 * 100 = 2000 bps (below EU 7100 trigger).
```

```toml
# circuits/risk_score/Prover.toml
signals           = [60, 0, 0, 0, 0, 0, 0, 0]
weights           = [100, 0, 0, 0, 0, 0, 0, 0]
weight_sum        = 100
provider_ids      = ["1", "0", "0", "0", "0", "0", "0", "0"]
num_providers     = 1
proof_type        = 1     # threshold
direction         = 1     # GT
bound_lower       = 5000  # asserts score > 5000 bps
bound_upper       = 0
result            = true
config_hash       = "0x18574f427f33c6c77af53be06544bd749c9a1db855599d950af61ea613df8405"
provider_set_hash = "0x14b6becf762f80a24078e62fc9a7eca246b8e406d19962dda817b173f30a94b2"
submitter         = "0xdead"
# Derived risk score: 60 * 100 / 100 * 100 = 6000 bps > 5000 -> result=true.
```

```toml
# circuits/pattern/Prover.toml (clean anti-structuring)
amounts             = [500, 1200, 3000, 7500, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
timestamps          = [1700000000, 1700001000, 1700002000, 1700003000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
num_transactions    = 4
analysis_type       = 1            # anti-structuring
result              = true         # clean
reporting_threshold = 10000        # USD-equivalent, US BSA-style
time_window         = 3600
tx_set_hash         = "0x2231d26d52515af30cbb6e91834cdb9e3d1d36575f160cbb4f6ebbb3c3dd8dad"
submitter           = "0xdead"
settlement_root     = "0"          # 0 = standalone use (no downstream binding)
```

```toml
# circuits/attestation/Prover.toml (KYC credential)
credential_attribute = "999"
expiry_timestamp     = 2000000000
merkle_index         = "0"
merkle_path          = ["0", "0", "0", "0", "0", "0", "0", "0", "0", "0",
                        "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"]  # 20 levels
provider_id          = "42"
credential_type      = 1           # KYC basic
is_valid             = true
credential_root      = "0x24ce58f9ed6ca066d25f66b15b0eb1dccebe6e457f5aa0fcd353d82d539f5ed5"
current_timestamp    = 1700000000  # < expiry
submitter            = "0xdead"
# credential_hash = H(DOMAIN_CREDENTIAL, provider_id=42, submitter=0xdead,
#                     credential_type=1, credential_attribute=999, expiry=2000000000)
```

```toml
# circuits/membership/Prover.toml (submitter is a member of set 1)
subject_salt = "0"                # 0 = public set
merkle_index = "0"
merkle_path  = ["0", "0", "0", "0", "0", "0", "0", "0", "0", "0",
                "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"]
merkle_root  = "0x1d7de002251083fdc312a329d46abde0680cbccc27935c33815c18b1beb3da8c"
set_id       = "1"
timestamp    = "1700000000"
is_member    = true
submitter    = "0xdead"
# leaf = leaf_hash_subject(submitter=0xdead, set_id=1, salt=0)
```

```toml
# circuits/non_membership/Prover.toml (submitter NOT in set {0x100, 0x10000})
low_leaf       = "0x100"
low_leaf_salt  = "0"
low_index      = "0"
low_path       = ["0x2e3a62a21fa1706df17be5649ad62e45a4dbdbe9a9ce3923058d940cdc6b929d",
                  "0", "0", "0", "0", "0", "0", "0", "0", "0",
                  "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"]
high_leaf      = "0x10000"
high_leaf_salt = "0"
high_index     = "1"             # adjacent to low_index
high_path      = ["0x0c57a3ac2ba9abef99b6ab714e307311687782f270b6517717e181e5cd50cce5",
                  "0", "0", "0", "0", "0", "0", "0", "0", "0",
                  "0", "0", "0", "0", "0", "0", "0", "0", "0", "0"]
merkle_root    = "0x138f818fd4f2eec91e4fd93e14bcc47bc06a3ba333e5a2e7795d0beb752d247c"
set_id         = "1"
timestamp      = "1700000000"
is_non_member  = true
submitter      = "0xdead"
# Adjacency check: low_leaf (0x100) < submitter (0xdead) < high_leaf (0x10000)
#                  AND high_index == low_index + 1.
```

Signed-variant witnesses (COMPLIANCE_SIGNED, RISK_SCORE_SIGNED) are identical to their unsigned siblings in the screening payload, plus `pubkey_x`, `pubkey_y`, `signature`, `signer_pubkey_hash`, `chain_id`, and `oracle_address`. The signature is computed off-chain by the provider over `H_pedersen(chain_id, oracle_address, provider_set_hash, signals, weights, timestamp, submitter)`. COMPLIANCE_MULTI_SIGNED (0x09) extends this to five parallel signer slots: each active slot supplies its own `(signals, weights, weight_sum, pubkey_x, pubkey_y, signature)` and a non-zero `signer_pubkey_hash`, where each signature commits to a slot-specific Pedersen digest under the `DOMAIN_MULTI_SIGNED_SIGNALS` tag (with embedded `slot_index`). Implementations producing fresh fixtures MUST sample fresh nonces — the reference implementation does this in `test/sdk/` rather than committing a static witness.

## Reference Implementation

A reference implementation accompanies this ERC. It consists of:

- **Solidity contracts**: `src/XochiZKPVerifier.sol`, `src/XochiZKPOracle.sol`, `src/SettlementRegistry.sol`, `src/XochiTimelock.sol` (Foundry, Solidity 0.8.28, Cancun EVM)
- **Noir circuits**: `circuits/` (one per proof type, pinned to nargo 1.0.0-beta.20 via `.tool-versions`)
- **Generated verifiers**: `src/generated/` (UltraHonk verifiers generated by Barretenberg, pinned to bb 4.0.0-nightly.20260120)
- **Test suite**: Solidity tests (unit, fuzz, invariant, integration with real proofs for the 6 unsigned proof types) and circuit tests across all 9 circuits. The signed variants (0x07, 0x08, 0x09) are exercised in the TypeScript SDK consumer tests (`test/sdk/`) which generate a fresh ECDSA witness per run.

Thanks to Merkle Bonsai (@Jabher) for reviewing the generated UltraHonk verifiers and identifying that the `pairing()` free function could be rewritten in inline Yul to bring all nine per-proof-type verifiers under the [EIP-170](./eip-170.md) 24,576-byte runtime size limit. The reference implementation incorporates the rewrite in `scripts/patch-pairing-yul.sh`, saving ~186 bytes per verifier (and ~800 gas per `verifyProof` call as a bonus) while staying byte-identical to the `bb`-generated semantics on the pairing precompile (`address(0x08)`) input layout.

## Security Considerations

**Proof soundness.** The security of the system depends on the ZK proof system used. Implementations MUST use a proof system with at least 128-bit security. Groth16, PLONK, and UltraHonk (Noir/Aztec) are acceptable.

**Provider collusion.** If all screening providers collude, they could issue false clean signals. Implementations SHOULD require attestations from multiple independent providers and weight them based on enforcement track record.

**Timestamp manipulation.** Proofs commit to block timestamps. Block proposers control the timestamp, constrained only to be >= the parent block's timestamp. This is acceptable for compliance windows measured in days. Circuits MUST enforce realistic timestamp bounds (e.g., after 2021-01-01 and before year ~36000) to reject obviously invalid values. This applies to both public timestamp inputs (compliance, membership, non-membership) and private transaction timestamps (pattern).

**Regulatory acceptance.** This standard provides a technical mechanism for ZK compliance. Whether specific jurisdictions accept ZK proofs as sufficient compliance evidence is a legal question, not a technical one. The VARA (Dubai) definition of "anonymity-enhanced crypto" excludes assets with "mitigating technologies" for traceability. This standard provides exactly that technology.

**Front-running the oracle.** Compliance proofs are generated before settlement. An adversary who observes a proof submission could infer a trade is about to occur. Implementations SHOULD batch proof submissions or submit them as part of the settlement transaction to minimize information leakage.

**Administrative operations.** Verifier contract updates and provider weight changes are privileged operations. Implementations SHOULD use a two-step ownership transfer pattern (transferOwnership + acceptOwnership) to prevent accidental transfer to an incorrect address. Critical operations (verifier replacement, TTL changes) SHOULD be timelocked in production deployments. Implementations SHOULD further split administrative authority into role classes with bounded blast radius -- for example, a pause-only "guardian" role distinct from registry-mutating and config-mutating roles -- so that a single compromised key cannot both pause and rewrite registries. The reference implementation uses a three-role split (GUARDIAN, REGISTRAR, CONFIG) under a 2-tier selector-gated timelock; see `docs/THREAT_MODEL.md` for the full per-role capability matrix and the timelock-tier mapping.

**Public input validation.** Implementations MUST validate public inputs for every proof type, not just the primary compliance proof. Without validation, a prover can generate a proof for one context (e.g., a lenient jurisdiction's reporting threshold) and submit it for a different context. Specifically:

- ALL proof types MUST validate their boolean result field (`meets_threshold`, `result`, `is_valid`, `is_member`, `is_non_member`) equals `bytes32(uint256(1))`. A valid proof with a false result proves non-compliance; accepting it would record a compliant attestation for a non-compliant subject.
- ALL proof types MUST enforce `submitter == msg.sender` to prevent submission front-running.
- COMPLIANCE and RISK_SCORE proofs MUST validate `config_hash` against a registry of known configurations.
- COMPLIANCE proofs MUST validate `jurisdiction_id` and `provider_set_hash` against caller-supplied parameters.
- RISK_SCORE proofs commit to `provider_set_hash` as a public input, binding the proof to a specific set of screening providers. This prevents a prover from fabricating signals from unverified providers.
- RISK_SCORE proofs MUST validate the semantic public inputs (`proof_type ∈ {threshold, range}`, `direction ∈ {GT, LT}`, and bounds) to reject trivially-true claims. For example, a THRESHOLD/GT proof with `bound_lower = 0` proves only that the score is greater than zero, which is uninformative. Validators MUST reject such proofs.
- PATTERN (anti-structuring) proofs MUST validate `reporting_threshold` against a per-jurisdiction registry, enforce `time_window >= MIN_TIME_WINDOW`, and validate that `analysis_type` is one of the supported analyses. Implementations that depend on a specific analysis type (e.g., a settlement registry requiring anti-structuring) MUST verify the `analysis_type` field separately, since the result boolean alone is insufficient.
- ATTESTATION proofs MUST validate `credential_root` against the per-provider credential root registry AND verify the registry's recorded `providerId` matches the proof's `provider_id` public input. Without this cross-check, a proof for one provider's tree could be replayed against another provider's registration.
- MEMBERSHIP and NON_MEMBERSHIP proofs MUST validate `merkle_root` against the generic merkle root registry.
- COMPLIANCE_SIGNED and RISK_SCORE_SIGNED proofs MUST validate `signer_pubkey_hash` against an on-chain registry of authorized provider signing keys, AND MUST validate `chain_id == block.chainid` and `oracle_address == address(this)`. Without the chain/oracle binding, a single provider signature could mint attestations across alternate Oracle deployments (different chain, or a forked Oracle on the same chain).
- Strict-mode jurisdictions SHOULD reject the unsigned siblings entirely and accept only the signed variants. The reference implementation enforces this for US (BSA) and Singapore via `JurisdictionConfig.requireSignedSignals(uint8)`.
- Unknown proof types (outside 0x01-0x09) MUST be rejected.

**Proof replay prevention.** Proof hashes MUST be keyed on the proof bytes, the proof type, and the deployment context: `keccak256(abi.encodePacked(proof, proofType, block.chainid, address(this)))`. Including `proofType` scopes uniqueness per proof type (identical proof bytes submitted for different proof types are treated as distinct proofs); including `block.chainid` and `address(this)` prevents replay-into-storage from a forked or alternate Oracle deployment on the same or different chain, even if the underlying ZK proof is chain-agnostic. Note this is the on-chain replay guard only; see "Cross-chain replay" below for in-circuit chain binding (relevant to the signed variants).

**Config and root revocation.** Provider configuration hashes and merkle roots SHOULD be revocable. Without revocation, a discovered-to-be-flawed configuration or a compromised merkle tree remains accepted forever. Implementations MUST NOT allow revoking the currently active provider configuration. Provider configuration history SHOULD be bounded to prevent unbounded storage growth (e.g., 256 entries).

**Verifier TOCTOU.** Implementations MUST resolve the verifier address once per submission and use it for both proof verification and attestation recording. A time-of-check/time-of-use gap between address resolution and proof verification could allow the recorded `verifierUsed` to diverge from the actual verifier if a verifier upgrade occurs mid-transaction.

**Batch verification limits.** Implementations MUST enforce a maximum batch size for `verifyProofBatch()` to prevent unbounded gas consumption. The reference implementation uses a limit of 10 proofs per batch, sized to fit comfortably under a 30M-gas mainnet block ceiling (approximately 24M gas at the maximum batch size, with ~5M gas of headroom). Implementations targeting chains with different block-gas budgets SHOULD recalibrate the limit accordingly.

**Expected gas costs.** UltraHonk verification dominates total transaction cost. The following figures are measured against the reference implementation on the Cancun EVM with real proofs (see `test/GasBenchmark.t.sol`); other proof systems and circuit revisions will differ.

| Operation                                             | Approx. gas |
| ----------------------------------------------------- | ----------- |
| `verifyProof` (any of the 6 unsigned types)           | ~2.43M      |
| `submitCompliance` (any of the 6 unsigned types)      | ~2.83-2.90M |
| `verifyProofBatch` / `submitComplianceBatch`, 1 entry | ~2.88M      |
| ... 2 entries                                         | ~4.84M      |
| ... 5 entries                                         | ~12.05M     |
| ... 10 entries (max batch)                            | ~24.08M     |

Signed-variant gas (COMPLIANCE_SIGNED, RISK_SCORE_SIGNED) is dominated by in-circuit ECDSA-secp256k1 verification, which roughly doubles proving time off-chain but only modestly increases the verifier byte size; on-chain `verifyProof` for the signed variants is in the same order of magnitude as the unsigned variants. Implementations that target L2s (typical block target 30M-60M gas) MAY raise `MAX_BATCH_SIZE` proportionally. Implementations on chains with lower block-gas budgets MUST lower it.

Submission overhead beyond verification (~400-470k gas per attestation) covers public-input validation, registry lookups, replay-guard SSTORE, attestation storage, and the `ComplianceVerified` event. Integrators submitting many attestations per user can amortize the per-entry fixed cost via `submitComplianceBatch`.

**Registry idempotency.** Registry operations (registering merkle roots, reporting thresholds) SHOULD be idempotent-safe: re-registering an already-registered value SHOULD revert to prevent accidental double-registration. Similarly, revoking a value that is not registered SHOULD revert.

**Emergency circuit break.** Implementations SHOULD include a pause mechanism that can halt proof submissions (and optionally, verifications) in case of a discovered vulnerability in a ZK circuit or verifier contract. Pausing MUST NOT prevent read access to existing attestations, as these are needed for retroactive verification (proof-of-innocence). Implementations SHOULD support per-proof-type pause for surgical incident response without halting unrelated proof types.

**Trust model and signal honesty.** See [What this standard does NOT prove](#what-this-standard-does-not-prove) in Rationale for the full discussion. In short: the unsigned variants (COMPLIANCE, RISK_SCORE) are self-attested — the circuit verifies the score formula but not the screening signals themselves. Strict-mode jurisdictions MUST reject the unsigned variants; integrators in permissive jurisdictions that require signal honesty MUST require COMPLIANCE_SIGNED / RISK_SCORE_SIGNED, optionally composed with ATTESTATION proofs.

**ATTESTATION authority root.** ATTESTATION proofs verify Merkle inclusion of a credential leaf in a per-provider credentials tree. The leaf is `H(DOMAIN_CREDENTIAL, provider_id, submitter, type, attribute, expiry)`, which binds the credential to the submitter cryptographically; a forged credential leaf cannot be constructed without breaking Pedersen preimage resistance. However, the circuit does NOT verify a provider signature over the credential leaf or root in-circuit. Authority resolves to the registered publisher EOA: the Oracle records each `credentialRoot` against `(providerId, publisherEOA)`, with a 48 h root TTL and an owner-rotatable publisher. A compromised publisher EOA can publish a tree containing arbitrary `(submitter, attribute)` pairs until the owner rotates the publisher (`setProviderPublisher`, 6 h timelock) or revokes the root (`revokeCredentialRoot`, instant). Implementations whose threat model includes a compromised publisher key SHOULD layer an in-circuit signature scheme over the credential root or credential leaf; this is tracked as future work and is intentionally NOT required by this specification.

**Cross-chain replay.** The unsigned proof types (COMPLIANCE, RISK_SCORE, PATTERN, ATTESTATION, MEMBERSHIP, NON_MEMBERSHIP) do NOT include a chain identifier as a circuit public input. The same proof bytes may be replayed against the same Oracle on a different chain (or against an alternate Oracle deployment on the same chain), producing independent attestations on each. The on-chain `proofHash = keccak256(proof, proofType, block.chainid, address(this))` and the `_usedProofs[proofHash]` guard prevent replay-into-storage _within_ a given (chain, Oracle) pair, but provide no in-circuit binding. Implementations whose threat model includes cross-deployment replay of unsigned proofs MUST add `chainId` and the verifying contract address as circuit public inputs.

The signed variants (COMPLIANCE_SIGNED, RISK_SCORE_SIGNED) close this gap mathematically: their in-circuit Pedersen digest commits to (`chain_id`, `oracle_address`, `provider_set_hash`, `signals`, `weights`, `timestamp`, `submitter`), and the secp256k1 ECDSA verification of the provider's signature happens over that digest. Replaying a signed proof against a different chain or Oracle requires forging a new ECDSA signature over the new (chain_id, oracle_address) pair under the registered provider's key. Implementations MUST validate `chain_id == block.chainid` and `oracle_address == address(this)` on every signed-variant submission.

**Verifier-layer reentrancy.** The `IUltraVerifier.verify(...)` interface MUST be declared `view` so that the EVM uses STATICCALL when invoking the verifier. STATICCALL prevents a malicious or compromised verifier from mutating state in the calling contract via reentrant calls. Implementations MUST NOT call verifiers via interfaces that omit the `view` modifier.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
