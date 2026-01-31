---
eip: TBD
title: Smart Credentials
description: A specification for blockchain-based credentials.
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/erc-smart-credentials/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2025-12-15
requires: 3668
---

## Abstract

This ERC defines Smart Credentials, a specification for blockchain-based credentials that are resolved via smart contracts.With the rise of AI agents, users on the internet will become increasingly indistinguishable from AI agents. We need provable onchain identities that allow real human users to prove their humanity, AI agents to prove who controls them, prove what capabilites they have, and to develop reputations and trust based on their work. Blockchains are well-positioned to provide provable identity because records can be broadcast publicly with provable ownership and provenance.  Smart Credentials provide a uniform method for resolving credentials for onchain identities including human users and AI agents. For the purposes of simplifying the langage of this specification, "users" refers to both human users and AI agents. Credentials are records "about" a user controlled by a smart credential issuer, as compared to records "by" a user that it controls directly.

Smart Credentials support fully onchain data, a mix of onchain and offchain data, or fully offchain data with onchain verification. They are designed to support credentials using Zero Knowledge Proofs (ZKPs), enabling privacy-preserving credentials where users can prove specific facts without revealing the underlying data (e.g., proving your age is over 18 without revealing a birthdate). 

## Motivation

Smart contracts, when using ERC-3668 already provide, a broad set of capabilites for credential issuers to issue credentials to be resolved via a blockchians, however, there is a need for a unified standard such that clients can discover and resolve credentials in a uniform way. 


### Identity and Credentials

 Unlike profile data that a user controls (e.g., name, avatar), credentials are records "about" a user, controlled by third-party credential issuers. They are verifiable facts that users cannot fabricate. Examples include:

- **Proof of Personhood**: Verify that a user is a human and not an AI agent
- **KYC**: Verify a user's identity from a trusted credential issuer
- **Reputation Systems**: Ratings for AI agents based on work and reviews
- **Privacy-Preserving Proofs**: ZKPs that prove facts without revealing underlying data

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.


Smart credentials must implement the following interface: 

```solidity
interface ISmartCredential {
    function getCredential(string calldata identifier) external view returns( bytes result);
}
```

The snart credential MUST return true when `supportsInterface()` is called on it with the interface's ID, `0x?????`.

Credential resolving clients will call `getCredential` with an identifier bytes value and a return a result as bytes.

Compliant clients MUST perform the following procedure when resolving a record:
 
1. Call the `getCredential` function, using ERC-3668 (Some libraries do not use ERC-3668 by default and it is necessary to make a special function call to use ERC-3668), with an identifier. The identifier MAY include a key using the ERC-8119 Key Paramaters format, shuch as `kyc: 0x123...234`. 

2. Resolve the return result and decode it according to the credential specificiaon, such as an ABI encoded string, or raw UTF-8 bytes. It is alos possible to decode arrays and structs using ABI encoding for example. 

### Pseudocode

```javascript

function getCredential(name, func, ...args) { . . . 
```

## Rationale

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).

## Backwards Compatibility

No issues.

## Security Considerations

None.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).

