---
title: Opaque Token
description: An opaque token standard with privacy support
author: Ivica Aračić (@ivica7), SWIAT
discussions-to: https://ethereum-magicians.org/t/erc-idea-opaque-token-a-token-standard-with-privacy-support-that-unifies-fungible-and-non-fungible-tokens
status: Draft
type: Standards Track
category: ERC
created: 2024-06-09
---

## Abstract

This ERC proposes a standard for an opaque token with built-in privacy support, integrating features of both fungible and non-fungible tokens. Privacy is achieved by offloading token position data records to off-chain storage, while on-chain ownership is represented through hashes of these position records. This approach ensures the confidentiality of token positions and simultaneously unifies fungible and non-fungible tokens as a byproduct.

## Motivation

In ERC-20, the position data of a token is transparent on-chain, with privacy being partially ensured through the use of pseudonyms for the sender and receiver. However, this transparency makes it challenging to work with smart contract accounts like Gnosis Safe or with well-defined identities holding claims, such as those defined in ERC-725/735. In regulated environments where KYC (Know Your Customer) procedures are required, revealing an identity would expose the entire portfolio of that identity from the on-chain data.

Without additional privacy mechanisms, the use of pseudonyms can only partially mask the sender's and receiver's identities. The chain of transactions remains visible on-chain, and once a pseudonym is de-masked, significant data and metadata about the holder's portfolio and business activities can be extracted. This transparency complicates the use of smart contract accounts and on-chain identities and claims, as they expose the entire portfolio of the associated identity.

This proposal makes token positions opaque on-chain, enabling the use of on-chain identities while maintaining a high level of privacy.

## Specification

### Opaque Positions

Positions are represented on-chain as hashes of the following form:

```
positionHash = keccak256(abi.encode(salt, value, additionalDataFp))
// where  salt bytes32              - random 32bytes to increase the entropy and make brute-forcing the hash impossible
//        value uint256             - the value of the position
//        additionalDataFp bytes32  - additional data attached to the position, e.g. for non-fungible tokens
```

### Token Interface

```
interface OpaqueToken {

    struct SIGNATURE {
      uint8 v; bytes32 r; bytes32 s;
    }

    struct CONFIG {
      uint8 minNumberOfOracles; // min. number of oracle signatures required for reorg
      bool fungible;            // can position be reorganized or are they non-fungible
      address[] oracles;        // valid oracles
    }
    
    event Create(address minter, bytes32[] positionHashes);

    event Reorg(address initiatedBy, bytes32[] positionHashesIn, bytes32[] positionHashesOut);

    event Transfer(address sender, address receiver, bytes32[] positionHashes, bytes32 ref);


    // returns the owner of a position hash
    function owner(bytes32 positionHash) external view returns (address);

    // returns the configuration for this token
    function config() external view returns (CONFIG memory);
    
    /*
    transfers a set of positionHashes to a new owner. If we look at position hashes as basket with a hidden 
    content, the transfer would be analogously to handing over this basket to the new owner.
    */
    function transfer(
        bytes32[] calldata positionHashes,
        address receiver,
        bytes32 ref
    ) external;

    /*
    reorganizes a set of position hashes (positionHashesIn) to a new set of hashes (positionHashesOut) 
    where the sum all values behind in and out remain the same. In order to ensure the integrity, we need 
    to rely on an external oracle service that would sign the reorg proposal requested by the position 
    owner. 

    Note that: if reorg is disabled, we disable the fungibility of the token and it becomes a NFT.
    See also CONFIG.fungible.
    */
    function reorg(
        SIGNATURE[] calldata reorgOracleSignatures,
        bytes32[] calldata positionHashesIn,
        bytes32[] calldata positionHashesOut
    ) external;
}
```

### Off-chain Data Endpoints

The design requires off-chain data management that is in the responsibility of the issuer of the token. so the issuer has the full source of the private data and will share the position data on need-to-know basis with all new and old position owners. (*authentication mechanism to be described. PUT/GET have diffferent requirements!*) Moreover, it is recommended that every position owner makes a copy of this data and store it in its own private data storage for the case that issuer's data storage is not available.

Off-Chain Data Endpoints for accessing the private data about a position:

```
  PUT position
  PostData: {
    positionHash: keccak256(abi.encode(salt, value, additionalDataFp))
    position: {
      salt: <bytes32>
      value: <uint256>
      additionalDataFp: <bytes32>
    }
  }

  GET position?position-hash=<bytes32>
  Response: {
    positionHash: keccak256(abi.encode(salt, value, additionalDataFp)),
    position: {
      salt: <bytes32>
      value: <uint256>
      additionalDataFp: <bytes32>
    }
  }
```

### reog Endpoint

In order to ensure the integrity of a position reorg, we rely on a set of oracles that will sign a reorg proposal if the sum of input values is equal the sum of all output values. This endpoint requires no further authentication and can be used by anyone without restrictions.

```
POST reorg
PostData: {
  in: [
    {
      positionHash: keccak256(abi.encode(salt, value, additionalDataFp)),
      position: {
        salt: <bytes32>
        value: <uint256>
        additionalDataFp: <bytes32>
      }
    },
    ...
  ],
  out: [
    {
      positionHash: keccak256(abi.encode(salt, value, additionalDataFp)),
      position: {
        salt: <bytes32>
        value: <uint256>
        additionalDataFp: <bytes32>
      }
    },
    ...
  ]
}

Response: {
    // hash is signed with oracles private key
    // positionHashesIn and positionHashesOut are bytes32[]
    signature: sign(keccak256(abi.encode(positionHashesIn, positionHashesOut)))
}
```

## Rationale

### Breaking the ERC-20 Compatibility

The transparency inherent in ERC-20 tokens presents a significant issue for reusable blockchain identities, such as smart contract accounts or those defined by ERC-725/735. To address this, we prioritize privacy over ERC-20 compatibility, ensuring that token positions remain confidential. 

### Reorg Oracles

To ensure the integrity of token entries and prevent accidental or fraudulent mints or burns, a set of oracles is required to confirm that the input set of position hashes in a reorganization has equal value to the output set of position hashes. This process is stateless, meaning no additional data is needed beyond what is provided in the request.

The trusted oracles and the minimum number of required signatures can be configured to achieve the desired level of decentralization.

The position owner proposes the input and output position hashes for the reorg, while the oracles are responsible for verifying that the sums of the values on both sides (input and output) are equal. This system allows for mutual control, ensuring that no single party can manipulate the process.

The fraudlent cases can be tracked back on-chain, i.e., the system ensures weak-integrity at minimum.

### Not using ZKP

It is also possible to use Zero-Knowledge Proofs (ZKP) to provide reorganization proofs (see "Future Work"). However, we have chosen to use oracles for reasons of efficiency.

### Off-chain Data Storage

We have chosen the issuer, or in some cases the token operator (aka registrar), as the initial source for off-chain data. This is acceptable, since they must know anyway which investor holds which positions to manage lifecycle events on the token. While this approach may not be suitable for every use case within the broader Ethereum ecosystem, it fits well the financial instruments in the regulated environment of the financial industry, which rely on strict KYC procedures between the issuer, registrar, and investors.

### Authentication Mechanism

The data provider will determine whether an entity can query the data based on the ownership of the position. To verify the requester's eligibility to access the data, the requester must sign the request using a key associated with the address to which the token is assigned. does not have to be the direct private key of the address, as we also aim to support smart contract accounts. *authentication mechanism is to be defined yet*

## Future Work

### ZKP as alterantive to Oracles

Instead of using oracles in the future, it would also be possible to apply zero knowledge proofs (ZKPs) to verify if a set of input hashes matches in the value a set of output hashes.

#### Differential Privacy

To further strengtehn the privacy and obscure who is transacting with whome, an additional layer of noise can be introduced through empty transfers and reorgs. For example, a position hash can be split into multiple hashes, some of which might have a value of 0. During a transfer, these empty positions can be sent to random receivers. This approach makes it more challenging to analyze and interpret metadata visible on-chain and also renders the knowledge of the sender on previous transfers less uselesse.

## Backwards Compatibility

No backward compatibility issues found.

## Reference Implementation

To be included as inline code or in `../assets/eip-####/`.

## Security Considerations

To be discussed.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
