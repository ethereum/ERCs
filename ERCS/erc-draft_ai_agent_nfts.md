---
title: AI Agent NFTs
description: A specification for NFTs that represent AI Agents.
author: Greg Marlin (@0marleymarl)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2024-03-26
requires: 721
---

## Abstract

This proposal introduces a standard for AI agent NFTs. In order for AI Agents to be created and traded as NFTs it doesn't make sense to put the prompts in the token metada, therefore it requires a standard custom struct. It also needs doesn't make sense to store the prompts directly onchain as they can be quite large, therefore this standard proposes they be stored as decentralized storage URLs. This standard also proposes two options on how this data should be made private to the owner of the NFT, with the favored implementation option being encrypting the data using custom contract parameters for decryption that decrypt only to the owner of the NFT. 

## Motivation

The creation and trading of AI Agent NFTs are a natural fit and offer the potential for an entirely new and vibrant onchain market. This requires some custom data to be embedded in the NFT through a custom struct and this needs to be standardized so that any marketplace or AI Agent management product, among others, know how to create and parse AI Agent NFTs. 


## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### AI Agent NFTs Interface

All ERC-XXXX compliant contracts MUST implemet the IERC721 and AgentInfo struct

```solidity
   

```


## Rationale

This standard provides a unified way to create and parse AI Agent NFTs. 

### AI Agent Parameters

This standard codifies the necessary parameters of Name, Description, Model, User Prompt, and System Prompt for creating and using AI Agent NFTs. 

### Addressing The Privacy In Open Blockchain Problem

It doesn't make practical sense to store the user and system prompts in an existing ERC721 as the only place to put would be in the token metadata that is open for anyone to access the prompts without owning the NfT. By storing the prompts in a custom AgentInfo struct, there is the options to restrict access to the struct info to the holder of the NFT, or, since this still exposes the prompt URls to the public, encrypting the prompts onchain and tying the decryption of the URLs to the holder of the NFT, using onchain services such as Lit Protocol. 



### Metadata

It makes sense to add the recommended data addition to the ERC-721 standard that makse it easy for e.g. NFT Marketplaces to display data about the AI Agent NFT, i.e. Model, which in turn reveals the platform that is used for the agent, e.g. OpenAI in the case of gpt-4-0125-preview or Anthropic in the case of claude-3-opus-20240229. The standard name and description can be used to display the Agent Name and Agent Description. 

## Backwards Compatibility

The AI Agents NFT standard introduces additional features and data to the standard ERC-721 protocol, aimed at addressing the practical requirements of using NFTs to store, trade and use AI Agents. It is designed to be fully backward-compatible with the original ERC-721 standard.  All existing ERC-721 functions (such as transferFrom, approve, and balanceOf) retain their original functionality and interfaces. Our extension does not modify these core behaviors, ensuring that any ERC-721 compliant wallet or service can interact with these tokens without modifications.

### Reference Implementation

This is being implemented in the upcoming CEO.ai product for creating, managing and using AI Agents Onchain through a DApp interface. In this implementation, Lit Protocol is being used to encrypt the prompts using custom EVMContractParameters that only decrypt for the holder of the NFT and using Arweave to store the URLs of this encrypted data. 

## Security Considerations


## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).