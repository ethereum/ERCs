---
eip: unsigned
title: Inter dapp tracking standard inferface
description: Share an inter-dapp tracking standard inferface for dapp interactions and support for more complicated business logics
author: wart (@wartstone)
discussions-to: https://ethereum-magicians.org/t/any-eip-erc-related-with-airdrop-status-existing/16976
status: Draft
type: Standards Track
category: ERC
created: 2023-12-13
---

## Abstract

This proposal aims to establish an inter-dapp tracking standard inferface for dapp interactions and support for more complicated business logics.

As dapps shows their values and more dapps are coming onto chain,there's plenty of requirements for interactions between dapps. For one like, we have two entities holding their respective contracts: contract A and contract B. Then A targets on those users who did some key moves(commit specific functions) in contract B and would like to give bonus/airdrop to these users. Sure B would also get incentives in the meanwhile. To connect all these dots, B needs to identity these users, verify they're coming for the A's bonus. Hence, we need a track mechanism to facilitate such business.

This track mechanism try to offer a neaty and convenient interface for contracts to interact with each other.

## Motivation

The internet is flooded with fresh content every day, but with the traditional IP infrastructure, IP registration and licensing is a headache for digital creators. The rapid creation of content has eclipsed the slower pace of IP registration, leaving much of this content unprotected. This means digital creators can't fairly earn from their work's spread.  

||Traditional IP Infrastructure|Open IP Infrastructure|
|-|-|-|
|IP Registration|Long waits, heaps of paperwork, and tedious back-and-forths.|An NFT represents intellectual property; the owner of the NFT holds the rights to the IP.|
|IP Licensing|Lengthy discussions, legal jargon, and case-by-case agreements.|A one-stop global IP licensing market that supports various licensing agreements.|  

With this backdrop, we're passionate about building an Open IP ecosystem tailored for today's digital creators. Here, with just a few clicks, creators can register, license, and monetize their content globally, without geographical or linguistic barriers. 

Currently, for dapp interaction tracking scenarios, we don't have a shared standard solution. Such standard interface would facilitate the effiency and booms the above use cases, specially in social and game realms. We can expect it thriving later and turn into promotion/ads, a web3 promotions/ads solution.

## Specification

The keywords “MUST,” “MUST NOT,” “REQUIRED,” “SHALL,” “SHALL NOT,” “SHOULD,” “SHOULD NOT,” “RECOMMENDED,” “MAY,” and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

**Interface**

This protocol standardizes how to remix multiple existing NFTs and create a new NFT derivative work (known as a combo), while their relationships can be traced on the blockchain. It contains three core modules, remix module, network module, and license module.

### Remix Module

This module extends the ERC-721 standard and enables users to create a new NFT by remixing multiple existing NFTs, whether they’re ERC-721 or [ERC-1155](./eip-1155.md). 

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.10;

interface IERCXXX {
    // Events

    /// @dev Emits when track starts.
    /// @param track_id track id
    /// @param contract_address the address of tracking contract
    /// @param function_hash the hash of tracking function
    event onTrackStartRecorded(uint256 track_id, address contract_address, bytes32 function_hash);

    /// @dev Emits when track ends.
    /// @param owner The owner address of the newly minted combo
    /// @param comboId The newly minted combo identifier
    event onTrackStartRecorded(uint256 track_id, address contract_address, bytes32 function_hash);

    // Functions

    /// @dev Track a specified contract function start move.
    /// @param track_id track id
    /// @param contract_address the address of tracking contract
    /// @param function_hash the hash of tracking function
    function onTrackStart(uint256 track_id, address contract_address, bytes32 function_hash) external;

    /// @dev Track a specified contract function end move.
    /// @param track_id track id
    /// @param contract_address the address of tracking contract
    /// @param function_hash the hash of tracking function
    function onTrackEnd(uint256 track_id, address contract_address, bytes32 function_hash);

    // TODO: may need more
}
```


## Rationale

The core mechanism for this proposal is to provide a shared track interface standard for inter dapps, to improve the efficiency and fulfile the required tracking business. We provide two neaty interface functions onTrackStart and onTrackEnd to fill the basic required info and connect the necessary dots. Sure there're more demands for more functions and it would be updated later.

<!-- TODO: add reference implementation -->

## Backwards Compatibility

This proposal is fully backwards compatible with earlier standard, extending the standard with new functions that do not affect the core functionality.

<!-- TODO: add reference implementation -->

## Security Considerations

<!-- TODO: add reference implementation --> 

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
