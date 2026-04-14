---
eip: XXXX
title: Post-Quantum Key Registry
description: An interface for on-chain registration, rotation, and migration of post-quantum cryptographic keys.
author: Valisthea (@Valisthea)
discussions-to: https://ethereum-magicians.org/t/erc-post-quantum-key-registry-on-chain-management-of-crystals-kyber-dilithium-and-slh-dsa-keys/28235
status: Draft
type: Standards Track
category: ERC
created: 2026-04-14
requires: 165
---

## Abstract

This EIP defines an interface for **on-chain management of post-quantum cryptographic keys**. It provides a registry where accounts (EOAs, smart wallets, contracts) can register, rotate, revoke, and migrate lattice-based and hash-based key pairs that are resistant to quantum computing attacks.

The interface supports NIST-standardized post-quantum algorithms: **CRYSTALS-Kyber** (ML-KEM, FIPS 203) for key encapsulation, **CRYSTALS-Dilithium** (ML-DSA, FIPS 204) for digital signatures, and **SLH-DSA** (FIPS 205, formerly SPHINCS+) for stateless hash-based signatures. It defines a unified key lifecycle (REGISTERED → ACTIVE → ROTATED → REVOKED) and enables any on-chain protocol to query and verify post-quantum keys for an address.

This EIP does not replace Ethereum's native secp256k1 signature scheme. It provides a **parallel post-quantum identity layer** that contracts can opt into for quantum-resistant operations, preparing the ecosystem for the post-quantum transition without requiring a consensus-level hard fork.

## Motivation

Quantum computers capable of running Shor's algorithm will break every elliptic curve cryptographic system currently used in Ethereum: secp256k1 (transaction signatures), ECDH (key exchange), and BN254/BLS12-381 (ZK proof systems). This is not a question of "if" but "when."

1. **Harvest-now-decrypt-later** — Adversaries are already recording encrypted blockchain traffic and storing signed transactions. When quantum computers arrive, they can retroactively forge signatures, extract private keys from public keys, and break historical encryption. Data encrypted today with classical schemes is already compromised against a future quantum attacker.

2. **No standard key infrastructure** — Several projects have implemented ad-hoc post-quantum signatures (e.g., XMSS in Ethereum research, Dilithium in experimental wallets), but there is no standard way to register, discover, or verify post-quantum keys on-chain. Each project invents its own registry, breaking interoperability.

3. **Gradual migration** — The post-quantum transition cannot happen overnight. Ethereum cannot hard-fork to replace secp256k1 without breaking every existing wallet. A parallel key registry allows accounts to register PQ keys alongside their existing keys. Protocols that require quantum resistance can enforce PQ key verification today, while the rest of the ecosystem migrates gradually.

4. **FHE key management** — FHE schemes (TFHE, BFV, BGV) use lattice-based encryption that is believed quantum-resistant. But the key exchange to establish shared FHE keys often uses classical ECDH — a quantum-vulnerable step. This EIP provides quantum-resistant key encapsulation (ML-KEM) for FHE key distribution.

5. **Regulatory compliance** — NIST finalized post-quantum cryptographic standards in 2024 (FIPS 203, 204, 205). Government agencies (NSA CNSA 2.0, EU ENISA) are mandating PQ transition timelines. Financial institutions using blockchain infrastructure will need to demonstrate PQ readiness. A standard registry provides auditable proof of PQ key deployment.

### Why not wait for Ethereum to upgrade?

Ethereum core developers are researching PQ signature schemes for the protocol level. But consensus-level changes require years of research, testing, and coordination across all clients. This EIP provides application-level PQ key management today, without waiting for a hard fork. When Ethereum eventually migrates to PQ signatures at the protocol level, this registry provides the key infrastructure that the migration will need.

### Why a registry instead of just using PQ signatures directly?

PQ signatures are large. A Dilithium-3 signature is ~3.3 KB (vs 65 bytes for secp256k1). Storing PQ public keys and verifying PQ signatures on-chain is expensive. A registry amortizes the cost: register the key once, then reference it by ID in subsequent operations. Verification can happen off-chain with on-chain key lookup, or on-chain for critical operations.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **PQ Key**: A post-quantum cryptographic key pair. The public key is stored on-chain. The private key remains with the owner.
- **Algorithm**: The specific PQ algorithm and parameter set (e.g., ML-KEM-1024, ML-DSA-87, SLH-DSA-SHAKE-256f).
- **Key ID**: A unique on-chain identifier for a registered key, derived deterministically from its content and owner.
- **Key Lifecycle**: The progression of a key through states: REGISTERED → ACTIVE → ROTATED → REVOKED.
- **Migration**: The process of replacing a classical key with a PQ key, or upgrading a PQ key to a stronger parameter set.
- **Dual-Signing**: The practice of signing with both a classical key (secp256k1) and a PQ key (ML-DSA) during the transition period.

### Algorithm Registry

```solidity
// Key Encapsulation Mechanisms (FIPS 203 — ML-KEM)
bytes4 constant ALG_ML_KEM_512  = 0x4B454D31; // "KEM1" — NIST Level 1
bytes4 constant ALG_ML_KEM_768  = 0x4B454D33; // "KEM3" — NIST Level 3
bytes4 constant ALG_ML_KEM_1024 = 0x4B454D35; // "KEM5" — NIST Level 5

// Digital Signatures (FIPS 204 — ML-DSA)
bytes4 constant ALG_ML_DSA_44   = 0x44534132; // "DSA2" — NIST Level 2
bytes4 constant ALG_ML_DSA_65   = 0x44534133; // "DSA3" — NIST Level 3
bytes4 constant ALG_ML_DSA_87   = 0x44534135; // "DSA5" — NIST Level 5

// Hash-Based Signatures (FIPS 205 — SLH-DSA)
bytes4 constant ALG_SLH_DSA_128 = 0x534C4831; // "SLH1" — NIST Level 1
bytes4 constant ALG_SLH_DSA_192 = 0x534C4833; // "SLH3" — NIST Level 3
bytes4 constant ALG_SLH_DSA_256 = 0x534C4835; // "SLH5" — NIST Level 5
```

### Key Lifecycle

```
    ┌──────────────┐   activateKey()   ┌──────────┐
    │  REGISTERED  │ ────────────────► │  ACTIVE  │
    └──────────────┘                   └──────────┘
     registerPQKey()                        │
     registerPQKeyWithProof()        ┌──────┴──────┐
                              rotateKey()    revokeKey()
                                     │             │
                                     ▼             ▼
                               ┌──────────┐  ┌──────────┐
                               │ ROTATED  │  │ REVOKED  │
                               └──────────┘  └──────────┘
                                     │
                              (old key remains valid
                               for verification of
                               historical signatures)
```

### Core Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0;

interface IERCWWWW {

    enum KeyState { REGISTERED, ACTIVE, ROTATED, REVOKED }

    enum KeyPurpose { SIGNATURE, ENCAPSULATION, DUAL }

    enum RevocationReason {
        KEY_COMPROMISED,
        ALGORITHM_DEPRECATED,
        OWNER_REQUEST,
        GOVERNANCE_ACTION,
        SUPERSEDED
    }

    struct PQKeyInfo {
        bytes32 keyId;
        address owner;
        bytes4 algorithm;
        KeyPurpose purpose;
        KeyState state;
        uint256 registeredAt;
        uint256 activatedAt;
        uint256 rotatedAt;
        uint256 revokedAt;
        bytes32 rotatedTo;
        uint256 nistLevel;
        uint256 expiresAt;  // 0 = no expiration
    }

    error KeyAlreadyRegistered(bytes32 keyId);
    error KeyNotFound(bytes32 keyId);
    error KeyNotActive(bytes32 keyId, KeyState currentState);
    error KeyAlreadyRevoked(bytes32 keyId);
    error UnauthorizedKeyOwner(address caller, address owner);
    error UnsupportedAlgorithm(bytes4 algorithm);
    error InvalidPublicKeyFormat(bytes4 algorithm, uint256 expectedSize, uint256 actualSize);
    error AlgorithmPurposeMismatch(bytes4 algorithm, KeyPurpose purpose);
    error NistLevelTooLow(uint256 provided, uint256 minimum);
    error RotationTargetNotActive(bytes32 newKeyId);
    error InvalidProofOfPossession(bytes32 keyId);
    error MaxKeysReached(address owner, uint256 max);
    error KeyExpired(bytes32 keyId, uint256 expiresAt);

    event PQKeyRegistered(bytes32 indexed keyId, address indexed owner,
        bytes4 indexed algorithm, KeyPurpose purpose, uint256 nistLevel);
    event PQKeyActivated(bytes32 indexed keyId, address indexed owner);
    event PQKeyRotated(bytes32 indexed oldKeyId, bytes32 indexed newKeyId,
        address indexed owner);
    event PQKeyRevoked(bytes32 indexed keyId, address indexed owner,
        RevocationReason indexed reason);

    function registerPQKey(address owner, bytes4 algorithm, KeyPurpose purpose,
        bytes calldata publicKey, uint256 validityPeriod)
        external returns (bytes32 keyId);

    function registerPQKeyWithProof(address owner, bytes4 algorithm,
        KeyPurpose purpose, bytes calldata publicKey, uint256 validityPeriod,
        bytes calldata proofOfPossession) external returns (bytes32 keyId);

    function activateKey(bytes32 keyId) external;
    function rotateKey(bytes32 oldKeyId, bytes32 newKeyId) external;
    function revokeKey(bytes32 keyId, RevocationReason reason) external;

    function keyInfo(bytes32 keyId) external view returns (PQKeyInfo memory);
    function publicKeyOf(bytes32 keyId) external view returns (bytes memory);
    function activeKeyFor(address owner, bytes4 algorithm, KeyPurpose purpose)
        external view returns (bytes32 keyId);
    function keysOfPaginated(address owner, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory keys, uint256 total);
    function keyCountOf(address owner) external view returns (uint256);
    function rotationChain(bytes32 keyId) external view returns (bytes32[] memory);
    function isKeyUsable(bytes32 keyId) external view returns (bool);

    function minNistLevel() external view returns (uint256);
    function maxKeysPerOwner() external view returns (uint256);
    function supportedAlgorithms() external view returns (bytes4[] memory);
    function isAlgorithmSupported(bytes4 algorithm) external view returns (bool);
    function expectedKeySize(bytes4 algorithm) external view returns (uint256);
}
```

### Extension: Dual-Signing (OPTIONAL)

For the transition period where both classical and PQ signatures coexist. Both signatures MUST sign the same EIP-712 digest:

```
digest = keccak256(abi.encode("\x19\x01", DOMAIN_SEPARATOR, keccak256(message)))
```

Both the secp256k1 ECDSA signature and the PQ signature operate on `digest`. Implementations MUST NOT allow one scheme to sign the raw message while the other signs the hash.

```solidity
interface IERCWWWW_DualSign is IERCWWWW {
    function verifyDualSignature(bytes32 keyId, bytes calldata message,
        bytes calldata classicalSig, bytes calldata pqSig,
        address classicalSigner) external view returns (bool);
    function domainSeparator() external view returns (bytes32);
    function isDualSignReady(address account) external view returns (bool);
}
```

### Extension: On-Chain Verification (OPTIONAL)

On-chain PQ signature verification is expensive (ML-DSA-65: ~1.5M gas; SLH-DSA-256f: ~10M+ gas). This is an optional extension. The recommended flow for most protocols is off-chain verification with on-chain key lookup via `publicKeyOf()`.

```solidity
interface IERCWWWW_OnChainVerify is IERCWWWW {
    function verifyPQSignature(bytes32 keyId, bytes calldata message,
        bytes calldata signature) external view returns (bool);
    function estimatedVerificationGas(bytes4 algorithm)
        external pure returns (uint256);
}
```

### Extension: Key Attestation (OPTIONAL)

For enterprise environments requiring proof of key generation quality:

```solidity
interface IERCWWWW_Attestation is IERCWWWW {
    struct Attestation {
        bytes32 keyId;
        address attester;
        bytes4 attestationType;
        uint256 timestamp;
        bytes data;
    }
    bytes4 constant ATT_HSM_GENERATED  = 0x48534D47; // "HSMG"
    bytes4 constant ATT_FIPS_VALIDATED = 0x46495053; // "FIPS"
    bytes4 constant ATT_AUDITED        = 0x41554454; // "AUDT"
    bytes4 constant ATT_ENTROPY_PROOF  = 0x454E5450; // "ENTP"

    event KeyAttested(bytes32 indexed keyId, address indexed attester,
        bytes4 indexed attestationType);

    function attestKey(bytes32 keyId, bytes4 attestationType,
        bytes calldata data) external;
    function attestationsOf(bytes32 keyId)
        external view returns (Attestation[] memory);
    function hasAttestation(bytes32 keyId, bytes4 attestationType)
        external view returns (bool);
}
```

### Public Key Size Reference

| Algorithm | NIST Level | Public Key Size | Signature Size | Purpose |
|---|---|---|---|---|
| ML-KEM-512 | 1 | 800 bytes | N/A (KEM) | Encapsulation |
| ML-KEM-768 | 3 | 1,184 bytes | N/A (KEM) | Encapsulation |
| ML-KEM-1024 | 5 | 1,568 bytes | N/A (KEM) | Encapsulation |
| ML-DSA-44 | 2 | 1,312 bytes | 2,420 bytes | Signature |
| ML-DSA-65 | 3 | 1,952 bytes | 3,309 bytes | Signature |
| ML-DSA-87 | 5 | 2,592 bytes | 4,627 bytes | Signature |
| SLH-DSA-128f | 1 | 32 bytes | 17,088 bytes | Signature |
| SLH-DSA-192f | 3 | 48 bytes | 35,664 bytes | Signature |
| SLH-DSA-256f | 5 | 64 bytes | 49,856 bytes | Signature |

### Key ID Derivation

Key IDs MUST be computed deterministically on-chain:

```solidity
keyId = keccak256(abi.encode(
    block.chainid,           // Prevent cross-chain key collision
    address(this),           // Prevent cross-registry collision
    owner,                   // Key owner
    algorithm,               // Algorithm identifier
    keccak256(publicKey)     // Hash of public key (not full key, for gas)
));
```

## Rationale

### Why a registry instead of protocol-level PQ signatures?

Protocol-level changes (replacing secp256k1 with ML-DSA for transaction signatures) require a hard fork and years of coordination. This EIP provides PQ key management at the application level, deployable today. When the protocol eventually migrates, this registry serves as the existing key infrastructure.

### Why support multiple algorithms?

Different use cases need different PQ algorithms. ML-KEM for key exchange (FHE key distribution, encrypted messaging). ML-DSA for fast signatures (authentication, attestations). SLH-DSA for maximum conservative security (hash-based, no lattice assumptions — survives even if lattice problems are broken). A single-algorithm interface would force unnecessary tradeoffs.

### Why explicit key lifecycle states?

ROTATED keys remain valid for verifying historical signatures. A signature made with key K1 on Monday should still verify on Friday, even if K1 was rotated to K2 on Wednesday. Without the ROTATED state, key rotation would retroactively invalidate past signatures.

REVOKED is different: a revoked key means "this key may have been compromised." Historical signatures should be treated as suspect.

### Why keyId on-chain derivation?

Caller-provided key IDs are vulnerable to collision attacks and front-running. On-chain derivation with chainId, contract address, owner, and public key hash ensures uniqueness and prevents predictability.

### Why is on-chain verification optional?

ML-DSA-65 verification costs approximately 1.5M gas. SLH-DSA-256f verification costs approximately 10M+ gas. For most use cases, off-chain verification with on-chain key lookup is sufficient. On-chain verification is only necessary when the verification result must be trustless and a ZK proof of verification is unavailable.

### Why RevocationReason enum instead of string?

Strings in events are expensive (dynamic ABI encoding) and cannot be indexed by value in event filters. An enum maps to a uint8, is indexable, and allows callers to distinguish `KEY_COMPROMISED` (treat all historical signatures as suspect) from `OWNER_REQUEST` (historical signatures remain valid).

### Why proof of possession?

Without proof of possession, any account can register any byte sequence as a PQ public key, even one they do not control. This pollutes the registry with invalid keys, enables rogue-key attacks in multi-party protocols, and may cause on-chain verification to return incorrect results. `registerPQKeyWithProof()` provides a lightweight mitigation without requiring expensive full on-chain key validation.

### Why paginate keysOf()?

An unbounded `keysOf()` is a gas DoS vector: an adversary registers `maxKeysPerOwner()` keys for an address, making any caller that iterates all keys hit gas limits. Pagination with `keysOfPaginated()` decouples query cost from registration count.

### Why key expiration?

NIST and NSA CNSA 2.0 guidelines recommend key validity periods. A key registered today with NIST Level 3 parameters may have insufficient security margin in a decade due to cryptanalytic advances. Expiration forces periodic key hygiene without requiring a manual rotation or revocation action.

### Why a two-step REGISTERED → ACTIVE lifecycle?

The two-step model enables pre-staging use cases that a single-step "register and activate" cannot support:

1. **Key ceremony**: An organization registers a replacement key before the current active key is due for rotation. A governance vote approves the new key. On approval, `activateKey()` atomically rotates the old key to ROTATED and activates the new one.
2. **Scheduled rotation**: Register a new key N days before a planned rotation date, allowing time for audit and validation before activation.
3. **Disaster recovery**: Pre-register a cold-storage backup key that can be activated immediately if the active key is lost or compromised.

The REGISTERED state is NOT usable for new cryptographic operations — it is exclusively a staging area.

## Backwards Compatibility

This EIP introduces a new parallel key infrastructure alongside Ethereum's existing secp256k1 identity system. It does not modify, replace, or interfere with existing signature verification mechanisms.

Contracts that do not implement this EIP are unaffected. Contracts that want PQ key verification can query the registry via `activeKeyFor()` and the optional `IERCWWWW_OnChainVerify` extension.

The Dual-Signing extension explicitly supports the transition period where both classical and PQ signatures coexist.

This EIP requires [ERC-165](./eip-165.md) for interface detection.

## Reference Implementation

A reference implementation is provided in the STYX Protocol repository:

`Valisthea/styx-erc-pq-key-registry`

## Security Considerations

### Public Key Storage Cost

PQ public keys are large (up to 2,592 bytes for ML-DSA-87). Storing them on-chain costs approximately 80,000–100,000 gas per registration. This is a one-time cost per key. Implementations SHOULD store the public key directly (not just a hash) to enable on-chain verification without requiring the caller to re-supply the key each time.

### Key Derivation Front-Running

If an attacker knows a public key before registration, they could front-run the registration with a different `owner` for the same public key. The on-chain derivation includes `owner` in the keyId hash, so a front-run with a different owner produces a different keyId. In adversarial environments, implementations SHOULD use a commit-reveal scheme: commit `keccak256(owner, publicKey, salt)` in block N, reveal in block N+1.

### Algorithm Agility

New PQ algorithms may be standardized in the future. The algorithm registry uses `bytes4` identifiers that can be extended without modifying the interface. Implementations SHOULD allow governance to add new algorithm IDs.

### Revocation Propagation

Key revocation is only effective if all verifiers check revocation status on-chain. Cached keys not re-verified against the registry could be used after revocation. Verifiers SHOULD re-check key status for any signature older than their cache TTL.

### Quantum Threat to the Registry Itself

The registry contract's access control uses secp256k1 signatures (standard Ethereum transactions). A quantum attacker who breaks secp256k1 could impersonate any account and register, rotate, or revoke keys for addresses they do not own. The Dual-Signing extension allows governance operations on the registry to require both classical and PQ signatures, mitigating this risk.

### Cross-Chain Key Reuse

The same PQ key pair could be registered on multiple chains. This is not inherently dangerous, but revocation on one chain does not propagate to others. Implementations SHOULD document cross-chain revocation limitations.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
