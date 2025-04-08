---
title: Smart Creative Commons Zero (SCC0) License for public dAIpps and dApps
description: This standard introduces a structured way for smart contracts to declare SCC0 compliance, enabling automated on-chain verification and governance integration.
author: DD Zhou (https://daism.io/en/smartcommons/actor/0xDD@daism.io), Changchun Chen (https://daism.io/smartcommons/actor/0xfeng@daism.io), Aranna (https://daism.io/smartcommons/actor/0xDD%40daism.io)
discussions-to: https://ethereum-magicians.org/t/scc0-smart-creative-commons-zero-a-license-for-public-decentralized-applications/22958
status: Draft
type: Standards Track
category: ERC
created: 2025-02-22
---

## Abstract

SCC0 (Smart Creative Commons Zero) is the first public goods license tailored for decentralized public applications (Smart Commons), including dApps, dAIpps(AIs). This standard introduces a structured way for smart contracts to declare SCC0 compliance, enabling automated on-chain verification and governance integration.

Two versions of SCC0 have been deployed by DAism, and anyone can deploy additional versions to further expand its applications. The declaration of any dApp/dAIpp is as simple as:

```solidity
address public constant LICENSE = contract_address;
```

## Motivation

To ensure that dApps and dAIpps can transparently declare their compliance with SCC0, we propose a standardized way to embed license-related variables in smart contracts. This allows for:

- On-chain verification of SCC0 adherence.
- Automated interaction checks between contracts.
- A reward mechanism that enables a specific public governance fund to distribute anonymous rewards to contributors.

## Specification

### SCC0 v1 Declaration

SCC0 v1 has been deployed by DAism, and any dApp/dAIpp adhering to it must:

1. Include the following declaration:

```solidity
address public constant LICENSE = 0xdFBF69B7E5366FB3001C9a214dd85c5FE3f90bAe;
```

1. Interact with DAism's smart contract `0xdFBF69B7E5366FB3001C9a214dd85c5FE3f90bAe`. Or go to [DAism](https://daism.io/zh/smartcommons) to mint a smart common.

```solidity
address public constant GOVERNANCE = 0xe40b05570d2760102c59bf4ffc9b47f921b67a1F;
```

1. DAism has defined the Smart Common structure:

```solidity
struct SCInfo {
    string name;        // Name of the smart common
    string symbol;      // Symbol of the smart common
    string desc;        // Description of the smart common
    address manager;    // Address of the smart common manager
    uint16 version;     // Version number of the smart common
    string SCType;      // Type of the smart common
}
```

Additional mappings and governance structures are included for community interactions:

```solidity
mapping(address => Object.Member) public memberInfos; // Stores Smart Common members and their dividend ratios
uint32 public proposalLifetime; // Validity period of Smart Common proposals
uint32 public proposalCoolingPeriod; // Cooling period for Smart Common proposals
uint16 public strategy; // Pass rate for Smart Common proposals
mapping(uint => File) public logoStorages; // Storage for Smart Common logos
```

### SCC0 v2 Declaration

1. SCC0 v2 extends the original standard and requires the following declarations in your dApp/dAIpp:

```solidity
address public constant LICENSE = 0xaCb910db73473944B2D23D37A0e46F57a43c6a49;

// Recommended declarations for better interaction:
address public owner;   // Address for rewards
string public scName;   // Smart Common name
string public scType;   // Smart Common type
```

For any upgradeable dApp/dAIpp , we strongly recommend to set owner with a multi-sig address, so as to pass the control to some dAIpps (AIs) in the future.

1. SCC0 Compliance Contract which is deployed by DAism:

```solidity
contract SCC0License {
    string public constant LICENSENAME = "SCC0";
    uint8 public constant VERSION = 2;
    bool public constant SELFISSUEDTOKEN = false;
    bool public constant NORIGHTSEXCEPTREWARDS = true;
    bool public constant NOLIABILITY = true;
    bool public constant ANONYMITYENSURED = true;
    address public constant GOVERNANCE = 0xe40b05570d2760102c59bf4ffc9b47f921b67a1F;
}
```

### Reward Distribution Mechanism

To support SCC0-compliant projects, an upgradeable reward distribution system is introduced by SSC0 V1:

1. Maintain an array to store external accounts eligible for rewards and their allocation percentages.
2. Rewards are not directly sent to external accounts. Instead, they are deposited into the public governance contract.
3. External accounts can withdraw funds any time.

```solidity
mapping(address => Object.Member) public memberInfos; // Stores smart common members and their dividend ratios
uint32 public proposalLifetime; // Validity period of smart common proposals
uint32 public proposalCoolingPeriod; // Cooling period for smart common proposals
uint16 public strategy; // Pass rate for smart common proposals
mapping(uint => File) public logoStorages; // Storage for smart common logos 
```

The reason why neither SSC0 V1 nor SSC0 V2 has introduced "detailed reward rules from Satoshi UTO Fund for smart commons" is that we can neither implement such measures through any centralized review panel approach, nor determine reward amounts through community voting using wallet addresses. The latter approach is even worse - it constitutes a pseudo-decentralized method that would only be employed by self-deceivers or even scammers. We expect some dAIpp take this work in the future, from valuation to prize management.

### Modifier for SCC0 Verification

To ensure compliance with SCC0 before interaction, we define the `onlySCC0` modifier:

```solidity
modifier onlySCC0() {
    require(keccak256(abi.encodePacked(LICENSE)) == keccak256(abi.encodePacked("SCC0")), "Not SCC0 licensed");
    _;
}
```


The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

## Rationale

1. **License Compliance (`LICENSE`, `LICENSENAME`)**: Ensures smart contracts transparently declare SCC0 adherence.
2. **No Self-Issued Token (`SELFISSUEDTOKEN`)**: Prevents misleading token issuance claims or any scams.
3. **No Liability (`NOLIABILITY`)**: Ensures no legal responsibility for SCC0 interactions.
4. **Anonymity Assurance (`ANONYMITYENSURED`)**: Reinforces that neither ownership nor control can be publicly verified.
5. **No Rights Except Rewards (`NORIGHTSEXCEPTREWARDS`)**: Confirms no legal claims beyond anonymous rewards.
6. **Version Control (`VERSION`)**: Allows future iterations of SCC0 compliance to be referenced.
7. **Governance Declaration (`GOVERNANCE`)**: Defines public governance fund integration.
8. **Enforceability (`onlySCC0` Modifier)**: Ensures SCC0 validation before contract interactions.

## Backwards Compatibility

This EIP does not introduce breaking changes but provides an opt-in mechanism for projects adopting SCC0. Legacy contracts must be redeployed to comply with the new standard.

## Security Considerations

- SCC0-compliant contracts disclaim liability, requiring users to acknowledge legal limitations.
- We believe none of upgradeable dApp/dAIpp should be controled by any person(s) ，so multi-sig address is a good way to pass the control to some dAIpps (AIs) in the future. It would be fantastic if we can find a universal solution with some dApp in day one.
- Developers must ensure contract logic aligns with SCC0's principles.
- The `onlySCC0` modifier enforces compliance in automated contract interactions.

Some dAIpp will enforce the security by auditing every dApp/dAIpp once it's minted a smart common (SCC0 v1) or deployed on-chain(SCC0 v2).

## Copyright

Copyright and related rights waived via [SCC0](https://github.com/DAism2019/SCC0).
