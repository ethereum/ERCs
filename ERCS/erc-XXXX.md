---
eip: 8126
title: AI Agent Registration and Verification
description: Self-registration and specialised verifications for verifiable AI Agent security on Ethereum
author: Leigh Cronian (@cybercentry) <leigh.cronian@cybercentry.co.uk>
discussions-to: https://ethereum-magicians.org/t/erc-8126-ai-agent-registration-and-verification/27445
status: Draft
type: Standards Track
category: ERC
created: 2025-01-15
requires: EIP-155, EIP-712, EIP-3009, ERC-191
---

## Abstract

This ERC defines a standard interface for registering and verifying AI agents on Ethereum. It enables AI agents to self-register with verifiable credentials and undergo specialised verification processes including Ethereum Token Verification (ETV), Staking Contract Verification (SCV), Web Application Verification (WAV), and Wallet Verification (WV). Verification providers implementing this standard process results through Private Data Verification (PDV) to generate Zero-Knowledge Proofs. Detailed verification results are accessible only to AI Agent wallet holders, providing a unified risk scoring system (0-100) that helps users assess agent trustworthiness.

## Motivation

As AI agents become increasingly prevalent in blockchain ecosystems, users need standardised ways to verify their authenticity and trustworthiness. Current solutions are fragmented, with no unified standard for agent registration or verification. This ERC addresses these challenges by providing:

1. **Self-Registration**: AI agents can register themselves with verifiable on-chain credentials
2. **Multi-Layer Verification**: Four specialised verification types assess different aspects of agent security
3. **Privacy-First Architecture**: Zero-Knowledge Proofs ensure verification without exposing sensitive data
4. **Unified Risk Scoring**: A standardised 0-100 risk score enables easy comparison between agents
5. **Micropayment Integration**: x402 protocol enables cost-effective verification without gas overhead
6. **Quantum-Resistant Future**: Optional Quantum Cryptography Verification (QCV) provides future-proof encryption

## Definitions

| Term | Definition |
|------|------------|
| **Agent Wallet** | The Ethereum address designated as controlled by the AI agent |
| **AI Agent** | An autonomous software entity that performs actions on behalf of users, identified by an Ethereum wallet address and optional smart contract |
| **ETV** | Ethereum Token Verification - validates smart contract presence and legitimacy |
| **PDV** | Private Data Verification - generates Zero-Knowledge Proofs from verification results |
| **Proof ID** | A unique identifier for a Zero-Knowledge Proof generated during verification |
| **QCV** | Quantum Cryptography Verification - provides quantum-resistant encryption for sensitive data |
| **Registrant** | The Ethereum address that submitted the agent registration transaction |
| **Risk Score** | A numerical value from 0-100 indicating the assessed risk level, where 0 is lowest risk and 100 is highest risk |
| **SCV** | Staking Contract Verification - validates staking contract security |
| **Verification Provider** | A service implementing this standard's verification types (ETV, PDV, QCV, SCV, WAV, WV) |
| **WAV** | Web Application Verification - checks endpoint security and accessibility |
| **WV** | Wallet Verification - assesses wallet history and threat database status |
| **ZKP** | Zero-Knowledge Proof - cryptographic proof that verification occurred without revealing underlying data |

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Required Standards

This standard requires the following EIPs/ERCs:

| Standard | Purpose in This ERC |
|----------|---------------------|
| **EIP-155** | Replay attack protection - ensures signatures include chain ID to prevent cross-chain replay attacks during agent registration and verification |
| **EIP-712** | Typed structured data signing - enables human-readable signing requests for agent registration, preventing blind signing attacks and improving UX |
| **EIP-3009** | Transfer with authorization - enables gasless USDC transfers for x402 micropayments, allowing verification fees without requiring ETH for gas |
| **ERC-191** | Signed data standard - provides standardised format for signed messages used in wallet verification and proof validation |

### Verification Flow

The following diagram illustrates the verification process:

    +-------------------+
    |   AI Agent Owner  |
    +--------+----------+
             |
             | 1. Register Agent (EIP-712 signed)
             v
    +-------------------+
    |  Agent Registry   |
    |  (Smart Contract) |
    +--------+----------+
             |
             | 2. Emit AgentRegistered Event
             v
    +-------------------+
    |   Verification    |
    |     Request       |
    +--------+----------+
             |
             | 3. Submit to Verification Provider
             |    (x402 payment via EIP-3009)
             v
    +-------------------+     +-------------------+
    |   Verification    |     |                   |
    |     Provider      +---->+  ETV (if contract |
    |                   |     |     provided)     |
    +--------+----------+     +--------+----------+
             |                         |
             |                         v
             |                +--------+----------+
             |                |       SCV         |
             |                |  (if staking      |
             |                |     provided)     |
             |                +--------+----------+
             |                         |
             |                         v
             |                +--------+----------+
             |                |       WAV         |
             |                |  (always runs)    |
             |                +--------+----------+
             |                         |
             |                         v
             |                +--------+----------+
             |                |       WV          |
             |                |  (always runs)    |
             |                +--------+----------+
             |                         |
             | 4. Aggregate Results    |
             |<------------------------+
             |
             | 5. Generate ZK Proofs via PDV
             v
    +-------------------+
    |       PDV         |
    | (Zero-Knowledge   |
    |  Proof Generation)|
    +--------+----------+
             |
             | 6. Optional: QCV encryption
             v
    +-------------------+
    |       QCV         |
    | (Quantum-Resistant|
    |    Encryption)    |
    +--------+----------+
             |
             | 7. Return Proof IDs
             v
    +-------------------+
    |  Update Registry  |
    | Emit AgentVerified|
    +-------------------+

### Agent Registration

An AI agent MUST register with the following information:

#### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| name | string | Human-readable agent name |
| description | string | Brief description of agent purpose |
| walletAddress | address | Ethereum address controlled by agent |
| url | string | HTTPS endpoint for agent interaction |

#### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| contractAddress | address | Smart contract address if applicable |
| stakingContractAddress | address | Staking contract address if applicable |
| platformId | uint256 | Platform identifier for cross-platform verification |
| chainId | uint256 | Chain ID for multi-chain agents |

### Verification Types

Compliant verification providers MUST implement the following verification types:

#### ETV (Ethereum Token Verification)

Validates on-chain presence and smart contract legitimacy.

- MUST verify contract exists on specified chain
- MUST check contract against known vulnerability patterns
- MUST return risk score 0-100
- SHOULD accept parameters: chain_id, platform_id, contract_address
- SHOULD follow OWASP Smart Contract Security guidelines

#### SCV (Staking Contract Verification)

Validates staking contract legitimacy and security when a staking contract address is provided.

- MUST verify staking contract exists on specified chain
- MUST check staking mechanism implementation
- MUST verify reward distribution logic
- MUST check for common staking vulnerabilities (reentrancy, flash loan attacks)
- MUST return risk score 0-100
- SHOULD accept parameters: chain_id, staking_contract_address
- SHOULD follow OWASP Smart Contract Security guidelines

#### WAV (Web Application Verification)

Ensures the agent's web endpoint is accessible and secure.

- MUST verify HTTPS endpoint responds
- MUST check for common security vulnerabilities
- MUST verify SSL certificate validity
- MUST return risk score 0-100
- SHOULD accept parameter: url
- SHOULD follow OWASP Web Application Security Testing guidelines (WSTG)
- SHOULD check for OWASP Top 10 vulnerabilities

#### WV (Wallet Verification)

Confirms wallet ownership and assesses on-chain risk profile.

- MUST verify wallet has transaction history
- MUST check against threat intelligence databases
- MUST return risk score 0-100
- SHOULD accept parameter: wallet_address

### Off-chain Verification

Verification is performed off-chain to:

1. Eliminate gas costs for verification operations
2. Enable complex verification logic that would be prohibitively expensive on-chain
3. Allow verification criteria to evolve without requiring contract upgrades
4. Enable multiple competing verification providers

### Provider Agnostic Design

This standard intentionally separates the interface specification from implementation details. Any verification provider MAY implement compliant ETV, WV, WAV, SCV, PDV, and QCV services, enabling:

1. Competition among verification providers
2. Specialisation in different verification domains
3. Geographic and jurisdictional flexibility
4. Price competition benefiting users

### Privacy-First Architecture with PDV

Verification results are processed through Private Data Verification (PDV) which generates Zero-Knowledge Proofs. This privacy-first approach:

1. Eliminates data breach risks - no stored data means nothing to compromise
2. Provides cryptographic proof of verification that third parties can validate
3. Ensures GDPR and privacy regulation compliance
4. Builds user trust through transparent, verifiable data handling

### Quantum-Resistant Future with QCV

Verification providers MAY implement QCV for quantum-resistant encryption of sensitive verification data.

- SHOULD use AES-256-GCM or equivalent post-quantum encryption algorithm
- MUST return unique record_id for encrypted data
- MUST provide decryption_url for authorized data retrieval
- SHOULD ensure quantum-resistant key exchange mechanisms

QCV Key Properties:
- Provides future-proof protection against quantum computing threats
- Military-grade encryption standards (AES-256-GCM)
- Enables secure long-term storage of verification records

### Payment Protocol

Verification providers MAY charge fees for verification services. When fees are required:

- SHOULD use x402 protocol for micropayments
- SHOULD support stablecoin settlement (e.g., USDC)
- MUST clearly disclose fee structure before verification
- SHOULD use EIP-3009 TransferWithAuthorization for gasless payments

### Risk Scoring

The overall risk score MUST be calculated as the average of all applicable verification scores:

| Tier | Score Range | Description |
|------|-------------|-------------|
| Low Risk | 0-20 | Minimal concerns identified |
| Moderate | 21-40 | Some concerns, review recommended |
| Elevated | 41-60 | Notable concerns, caution advised |
| High Risk | 61-80 | Significant concerns detected |
| Critical | 81-100 | Severe concerns, avoid interaction |

### Error Codes

Implementations MUST use the following standardised error codes:

| Error Code | Name | Description |
|------------|------|-------------|
| `0x01` | `InvalidAddress` | Provided address is not a valid Ethereum address |
| `0x02` | `InvalidURL` | Provided URL is malformed or not HTTPS |
| `0x03` | `AgentNotFound` | No agent exists with the specified agentId |
| `0x04` | `UnauthorizedAccess` | Caller is not walletAddress or registrantAddress |
| `0x05` | `AlreadyRegistered` | Agent with this walletAddress already exists |
| `0x06` | `VerificationFailed` | Verification provider returned an error |
| `0x07` | `InsufficientCredits` | No verification credits available |
| `0x08` | `InvalidProof` | PDV proof validation failed |
| `0x09` | `ProviderUnavailable` | Verification provider is not responding |
| `0x0A` | `InvalidScore` | Risk score outside valid range (0-100) |
| `0x0B` | `ContractNotFound` | Specified contract does not exist on chain |
| `0x0C` | `StakingContractNotFound` | Specified staking contract does not exist |

Implementations SHOULD revert with these error codes:

    error InvalidAddress();
    error InvalidURL();
    error AgentNotFound();
    error UnauthorizedAccess();
    error AlreadyRegistered();
    error VerificationFailed();
    error InsufficientCredits();
    error InvalidProof();
    error ProviderUnavailable();
    error InvalidScore();
    error ContractNotFound();
    error StakingContractNotFound();

### Interface

    // SPDX-License-Identifier: CC0-1.0
    pragma solidity ^0.8.0;

    interface IERCXXXX {
        /// @notice Emitted when a new agent is registered
        event AgentRegistered(
            bytes32 indexed agentId,
            address indexed walletAddress,
            address indexed registrantAddress,
            string name
        );

        /// @notice Emitted when an agent completes verification
        event AgentVerified(
            bytes32 indexed agentId,
            uint8 overallRiskScore,
            bytes32 etvProofId,
            bytes32 scvProofId,
            bytes32 wavProofId,
            bytes32 wvProofId,
            bytes32 summaryProofId
        );

        /// @notice Emitted when an agent's details are updated
        event AgentUpdated(
            bytes32 indexed agentId,
            address indexed updatedBy
        );

        /// @notice Emitted when verification credits are purchased
        event CreditsPurchased(
            bytes32 indexed agentId,
            address indexed purchaser,
            uint256 amount
        );

        /// @notice Register a new AI agent
        function registerAgent(
            string calldata name,
            string calldata description,
            address walletAddress,
            string calldata url,
            address contractAddress,
            address stakingContractAddress,
            uint256 platformId,
            uint256 chainId
        ) external returns (bytes32 agentId);

        /// @notice Get agent verification status and scores
        function getAgentVerification(bytes32 agentId) external view returns (
            bool isVerified,
            uint8 overallRiskScore,
            uint8 etvScore,
            uint8 scvScore,
            uint8 wavScore,
            uint8 wvScore
        );

        /// @notice Get agent proof details (restricted to wallet holder)
        /// @dev MUST only return data if msg.sender is walletAddress or registrantAddress
        function getAgentProofs(bytes32 agentId) external view returns (
            bytes32 etvProofId,
            string memory etvProofUrl,
            bytes32 scvProofId,
            string memory scvProofUrl,
            bytes32 wavProofId,
            string memory wavProofUrl,
            bytes32 wvProofId,
            string memory wvProofUrl,
            bytes32 summaryProofId,
            string memory summaryProofUrl
        );

        /// @notice Get basic agent information
        function getAgentInfo(bytes32 agentId) external view returns (
            string memory name,
            string memory description,
            address walletAddress,
            address registrantAddress,
            string memory url,
            address contractAddress,
            address stakingContractAddress
        );
    }

## Rationale

### Required Standards Justification

**EIP-155 (Replay Protection)**: Agent registrations involve wallet signatures. Without chain ID inclusion (EIP-155), a registration signature on mainnet could be replayed on testnets or L2s, potentially creating conflicting agent records across chains.

**EIP-712 (Typed Data Signing)**: Registration requires users to sign structured data. EIP-712 presents human-readable signing requests (e.g., "Register Agent: MyBot at 0x...") rather than opaque hashes, preventing phishing attacks where users unknowingly sign malicious transactions.

**EIP-3009 (Transfer With Authorization)**: Verification fees use x402 micropayments. EIP-3009 enables gasless USDC transfers where the verification provider pays gas, improving UX by not requiring users to hold ETH for verification.

**ERC-191 (Signed Data Standard)**: Wallet verification requires proving wallet ownership. ERC-191 provides the standardised prefix for signed messages, ensuring compatibility across wallets and preventing signature malleability.

### Four Verification Types

The four verification types are presented in alphabetical order (ETV → SCV → WAV → WV) for clarity and consistency.

The decision to implement four distinct verification types addresses different aspects of agent authenticity:

- **ETV** validates on-chain presence and contract legitimacy, ensuring the agent has a legitimate blockchain footprint
- **SCV** validates staking contract security, ensuring agents with staking mechanisms have secure and auditable contracts
- **WAV** ensures the agent's web endpoint is accessible and secure, protecting users from phishing and vulnerable endpoints
- **WV** confirms wallet legitimacy and checks against threat databases, preventing association with known malicious actors

### Off-chain Verification

Verification is performed off-chain to:

1. Eliminate gas costs for verification operations
2. Enable complex verification logic that would be prohibitively expensive on-chain
3. Allow verification criteria to evolve without requiring contract upgrades
4. Enable multiple competing verification providers

### Provider Agnostic Design

This standard intentionally separates the interface specification from implementation details. Any verification provider MAY implement compliant ETV, WV, WAV, SCV, PDV, and QCV services, enabling:

1. Competition among verification providers
2. Specialisation in different verification domains
3. Geographic and jurisdictional flexibility
4. Price competition benefiting users

### Privacy-First Architecture with PDV

Verification results are processed through Private Data Verification (PDV) which generates Zero-Knowledge Proofs. This privacy-first approach:

1. Eliminates data breach risks - no stored data means nothing to compromise
2. Provides cryptographic proof of verification that third parties can validate
3. Ensures GDPR and privacy regulation compliance
4. Builds user trust through transparent, verifiable data handling

### Quantum-Resistant Future with QCV

Verification providers MAY implement QCV for quantum-resistant encryption of sensitive verification data.

- SHOULD use AES-256-GCM or equivalent post-quantum encryption algorithm
- MUST return unique record_id for encrypted data
- MUST provide decryption_url for authorized data retrieval
- SHOULD ensure quantum-resistant key exchange mechanisms

QCV Key Properties:
- Provides future-proof protection against quantum computing threats
- Military-grade encryption standards (AES-256-GCM)
- Enables secure long-term storage of verification records

### OWASP Alignment

This standard recommends alignment with OWASP (Open Web Application Security Project) guidelines:

- **WAV** SHOULD follow OWASP Web Security Testing Guide (WSTG) for endpoint security assessment
- **ETV/SCV** SHOULD follow OWASP Smart Contract Security Verification Standard (SCSVS)
- Verification providers SHOULD check for OWASP Top 10 vulnerabilities in web applications
- Verification providers SHOULD check for Smart Contract Top 10 vulnerabilities in contracts

OWASP alignment ensures verification follows industry-recognised security standards.

### Registration Fields

The required fields (name, description, walletAddress, url) represent the minimum information needed to identify and interact with an AI agent. Optional fields (contractAddress, stakingContractAddress, platformId, chainId) allow for richer on-chain verification without imposing unnecessary requirements.

### Risk Scoring Approach

A unified 0-100 risk scoring system allows:

- Easy comparison between agents
- Clear risk tier categorisation
- Weighted average calculation for overall assessment
- Actionable guidance based on score ranges

## Backwards Compatibility

This ERC introduces a new standard and does not modify any existing standards. Existing AI agents can register with this standard without any modifications to their current implementations. It is designed to work alongside existing token standards (ERC-20, ERC-721, ERC-1155) and identity standards.

## Test Cases

### Registration Tests

**Test: Successful Registration**

    // Pseudocode
    function testSuccessfulRegistration() {
        bytes32 agentId = registry.registerAgent(
            "MyAIAgent",
            "A helpful assistant",
            0x1234...5678,           // walletAddress
            "https://myagent.ai",
            address(0),              // no contract
            address(0),              // no staking contract
            0,                       // platformId
            1                        // chainId (mainnet)
        );
        
        assert(agentId != bytes32(0));
        assert(registry.getAgentInfo(agentId).name == "MyAIAgent");
    }

**Test: Invalid URL Rejection**

    // Pseudocode
    function testInvalidURLRejection() {
        // Should revert with InvalidURL error
        expectRevert(InvalidURL.selector);
        registry.registerAgent(
            "MyAIAgent",
            "Description",
            0x1234...5678,
            "http://insecure.com",   // HTTP not HTTPS - MUST fail
            address(0),
            address(0),
            0,
            1
        );
    }

**Test: Duplicate Registration Rejection**

    // Pseudocode
    function testDuplicateRejection() {
        registry.registerAgent("Agent1", "Desc", 0x1234, "https://a.com", ...);
        
        // Same walletAddress - MUST revert
        expectRevert(AlreadyRegistered.selector);
        registry.registerAgent("Agent2", "Desc", 0x1234, "https://b.com", ...);
    }

### Verification Tests

- MUST complete ETV when contractAddress is provided
- MUST complete WV for all registered agents
- MUST complete WAV for all registered agents
- MUST complete SCV when stakingContractAddress is provided
- MUST generate PDV proof for each verification type
- MUST calculate overallRiskScore as average of applicable scores
- MUST emit AgentVerified event with all proof IDs
- MUST revert with `VerificationFailed` on provider error
- MUST revert with `InsufficientCredits` when no credits available

### Access Control Tests

**Test: Unauthorized Proof Access**

    // Pseudocode
    function testUnauthorizedProofAccess() {
        bytes32 agentId = registry.registerAgent(...);  // registered by 0xAAAA
        
        // Caller is 0xBBBB (not owner or registrant)
        vm.prank(0xBBBB);
        expectRevert(UnauthorizedAccess.selector);
        registry.getAgentProofs(agentId);
    }

- MUST allow only walletAddress or registrantAddress to view proof URLs
- MUST allow only walletAddress or registrantAddress to edit agent details
- MUST allow anyone to view public agent information (excluding proofs)
- MUST revert with `UnauthorizedAccess` for unauthorized proof access
- MUST revert with `AgentNotFound` for non-existent agentId

### Risk Score Tests

- MUST return score 0-20 for Low Risk tier
- MUST return score 21-40 for Moderate tier
- MUST return score 41-60 for Elevated tier
- MUST return score 61-80 for High Risk tier
- MUST return score 81-100 for Critical tier
- MUST revert with `InvalidScore` for scores outside 0-100

## Reference Implementation

The reference implementation will demonstrate:
- Agent self-registration with EIP-712 typed signing
- Four verification types (ETV, WV, WAV, SCV)
- PDV integration for Zero-Knowledge Proof generation
- x402 micropayment integration with EIP-3009
- Risk scoring with five-tier classification
- Wallet-holder restricted proof access

## Security Considerations

### Verification Trust

Users MUST understand that verification through this standard indicates the agent has passed specific technical checks at a point in time, but does not guarantee the agent's future behaviour or intentions. Risk scores provide guidance but users should exercise their own judgment.

### Wallet Security

Agents MUST secure their registered wallet addresses. Compromise of a wallet could allow an attacker to impersonate a legitimate agent. Re-verification is available to update risk scores.

### URL Hijacking

If an agent's URL is compromised after registration, the attacker could serve malicious content. Users SHOULD verify the current status of agents before interacting. WAV re-verification can detect compromised endpoints.

### Smart Contract Risks

For agents with registered contract addresses, standard smart contract security considerations apply. ETV and SCV provide initial verification but users SHOULD audit any contracts they interact with.

### Staking Contract Risks

Staking contracts present additional risks including locked funds, reward manipulation, and governance attacks. SCV verification checks common vulnerabilities but users SHOULD perform due diligence before staking with any agent.

### Zero-Knowledge Proof Security

PDV implementations SHOULD use established ZKP systems with proven security properties:

- **Circuit Soundness**: Implementations SHOULD use audited circuits (e.g., Groth16, PLONK) with formal security proofs
- **Trusted Setup**: Systems requiring trusted setup (e.g., Groth16) MUST use multi-party computation ceremonies to minimize trust assumptions
- **Proof Verification**: On-chain proof verification MUST use battle-tested verifier contracts
- **Quantum Considerations**: Current ZKP systems (based on elliptic curves) may be vulnerable to future quantum attacks. High-value, long-term proofs SHOULD consider QCV encryption as an additional layer

### Quantum Computing Threats

Current cryptographic primitives face potential threats from quantum computing:

- **ECDSA Signatures**: Vulnerable to Shor's algorithm on sufficiently powerful quantum computers
- **ZKP Schemes**: Elliptic curve-based ZKPs (Groth16, PLONK) share quantum vulnerability
- **Mitigation**: QCV provides AES-256-GCM encryption which remains quantum-resistant for symmetric operations. Implementations concerned with long-term security SHOULD use QCV for sensitive verification data

### Provider Trust

Users MUST evaluate their trust in chosen verification providers. Different providers may have varying levels of thoroughness, independence, and reliability. Zero-Knowledge Proofs generated by PDV provide verifiable evidence of verification completion that can be independently validated.

### Attack Vectors

- **Sybil Attacks**: Malicious actors could register many agents. Mitigated by registration fees.
- **Front-Running**: Registration transactions could be front-run. Consider commit-reveal schemes for sensitive registrations.
- **Provider Collusion**: Verification providers could collude with malicious agents. Users SHOULD consider using multiple independent providers for high-stakes interactions.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).