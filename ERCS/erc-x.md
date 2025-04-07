---
title: Non-Fungible PermaLink Asset Bound Token Standard
description: An interface for Non-Fungible PermaLink Asset Bound Tokens, also known as a NFABT.
author: Mihai Onila (@MihaiORO), Nick Zeman (@NickZCZ), Narcis Cotaie (@NarcisCRO)
discussions-to: <[URL](https://ethereum-magicians.org/t/non-fungible-asset-bound-token/23175)>
status: Draft
type: Standards Track
category: <Core, Networking, Interface, or ERC> # Only required for Standards Track. Otherwise, remove this field.
created: <date created on, in ISO 8601 (yyyy-mm-dd) format>
requires: <EIP number(s)> # Only required when you reference an EIP in the `Specification` section. Otherwise, remove this field.
---

<!--
  READ EIP-1 (https://eips.ethereum.org/EIPS/eip-1) BEFORE USING THIS TEMPLATE!

  This is the suggested template for new EIPs. After you have filled in the requisite fields, please delete these comments.

  Note that an EIP number will be assigned by an editor. When opening a pull request to submit your EIP, please use an abbreviated title in the filename, `eip-draft_title_abbrev.md`.

  The title should be 44 characters or less. It should not repeat the EIP number in title, irrespective of the category.

  TODO: Remove this comment before submitting
-->

## Abstract

A standard interface for Non-Fungible PermaLink Asset Bound Tokens (PermaLink-ABT/s), a subset of the more general Asset Bound Tokens (ABT/s).

The following standard allows for the implementation of a standard API for tokens within smart contracts and provides mirrored information of a specific smart contract through the ‘assetBoundContract’ function. Mirrored information consists of ‘ownerOf’, ‘tokenID’, ‘totalSupply’, as well as ‘balanceOf’. This in conjunction with blocking the ability to use basic transfer and approve functionality makes 2 tokens from different smart contracts interlocked. As the asset cannot be transferred in the traditional sense, being bound to a specific asset within a specific contract and maintaining corresponding information and movements creates an ABT. 

As the asset is bound to another asset having specified mirrored information, a ‘reveal’ function replaces the mint function commonly seen. The total supply of all the tokens from the ABT smart contract already exists.

We considered ABTs being used by every individual who wishes to link an additional non-fungible asset to an already existing non-fungible asset. ABTs allow an infinite amount of tokens to be bound together, allowing them to work symbiotically rather than splintering and separating. Remaining interlocked and asset bound removes the idea that 2 smart contracts released by the same or different creators at the same or different times are competing with one another.

<!--
  The Abstract is a multi-sentence (short paragraph) technical summary. This should be a very terse and human-readable version of the specification section. Someone should be able to read only the abstract to get the gist of what this specification does.

  TODO: Remove this comment before submitting
-->

## Motivation

Currently, there is a limitation to traditional ownership models as only wallets or addresses can own blockchain assets. As digital identities, real-world assets (RWAs), and digital collectibles continue to grow, one common denominator emerges: smart contracts. While these contracts serve as the foundation for on-chain innovation, they are inherently static. Once deployed, they cannot be modified to accommodate evolving ideas, unforeseen use cases, or new integrations.

During the development process, multiple use cases where a new ownership model would be beneficial were established;

1. **The Case for On-Chain Identity:** Digital identity issuance is already taking shape worldwide, with nations like China, India, and Singapore leading the way. The EU, US, and others are also exploring digital passports, state IDs, and blockchain-based social security numbers. These identity frameworks require seamless linking to healthcare, driver's licenses, bank accounts, and voting registries.
If each ID or registry exists as an isolated smart contract, users must manually track and transfer numerous tokens and credentials—a process prone to human error. A universal on-chain identity should enable assets to be bound together, allowing them to move as a unit rather than requiring manual migration. Asset Bound Tokens (ABTs) provide a framework for this, ensuring that identity-linked assets remain interconnected and dynamic.

2. **Real-World Assets and Ownership Structure**: RWAs are gaining traction, from tokenized commodities like gold (e.g., BRICS-backed gold currency) to entire corporations and their underlying assets. Unlike static collectibles, companies actively buy, sell, and manage assets. A farming company acquiring new land or upgrading machinery, or an IT firm merging with another and inheriting IP, necessitates an ownership structure that reflects these changes.
Currently, assets locked within smart contracts cannot be seamlessly transferred across contracts. ABTs address this by enabling hierarchical ownership structures where assets within a contract can be linked and updated as ownership evolves. This ensures businesses can efficiently manage assets on-chain without the constraints of rigid smart contracts.

3. **Manufacturing and Inventory Management:** Manufacturing supply chains involve complex hierarchies: products are packed into boxes, which are placed on pallets, which are stored in containers. Each step requires precise tracking, from raw materials to final products reaching consumers. Immutable records on blockchain offer transparency, but the current model—creating individual smart contracts or repeatedly minting new tokens—is costly and inefficient.
ABTs streamline inventory management by allowing dynamic asset binding. Instead of creating redundant smart contracts, manufacturers can link tokens representing various stages of the supply chain, maintaining historical data while ensuring seamless tracking and updates.

4. **Addressing NFT Fragmentation:** NFTs have traditionally been associated with digital collectibles and art. However, many projects deploy secondary smart contracts to evolve their collections, inadvertently causing liquidity fragmentation. Owners often sell assets from the original collection to acquire newer ones, leading to value dilution and lower overall market confidence.
ABTs solve this by allowing secondary collections to complement rather than compete with the original. Bound assets enhance the primary asset’s value without necessitating a separate, competing ecosystem. This structure retains liquidity within the original collection and sustains its market metrics, benefiting both creators and collectors.

5. **New Opprutunites for Creators:** ABTs empower both asset owners and creators by enabling an open secondary market for existing tokens. Artists, for instance, can create and bind assets to existing NFTs without requiring permission from the original contract owner. This facilitates new revenue streams, such as artists being paid on consignment for augmenting or adding onto existing assets. Owners benefit as well, as additional assets increase the inherent value of their holdings, especially in instances of collaboration between established projects or reputable artists.

In general, the concept of ABTs establishes a token standard where one token is bound to another by linking rather than direct ownership. If the binding token moves, all bound assets update accordingly, preserving structure without requiring manual transfers. This approach transforms smart contracts into dynamic, evolving repositories, ensuring long-term viability for digital identities, RWAs, and NFTs alike.

Whether enhancing identity systems, optimizing supply chains, or fostering NFT innovation, ABTs introduce a flexible, future-proof ownership model that aligns with the ever-evolving nature of blockchain ecosystems. In the case of **PermaLink-ABTs**, these specifically focus on a permanent link between the ABT either another ABT or an NFT. This results in the supposed increase in the value of the binding token due to the addition of a new asset bound to it. This ABT version also helps if a user would like to move a whole portfolio of ABTs at once, reducing gas fees, as only the binding token has to be moved in order for all of the PermaLink ABTs to move with it.







<!--
  This section is optional.

  The motivation section should include a description of any nontrivial problems the EIP solves. It should not describe how the EIP solves those problems, unless it is not immediately obvious. It should not describe why the EIP should be made into a standard, unless it is not immediately obvious.

  With a few exceptions, external links are not allowed. If you feel that a particular resource would demonstrate a compelling case for your EIP, then save it as a printer-friendly PDF, put it in the assets folder, and link to that copy.

  TODO: Remove this comment before submitting
-->

## Specification

<!--
  The Specification section should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for any of the current Ethereum platforms (besu, erigon, ethereumjs, go-ethereum, nethermind, or others).

  It is recommended to follow RFC 2119 and RFC 8170. Do not remove the key word definitions if RFC 2119 and RFC 8170 are followed.

  TODO: Remove this comment before submitting
-->

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

## Rationale

<!--
  The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

TBD

## Backwards Compatibility

<!--

  This section is optional.

  All EIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The EIP must explain how the author proposes to deal with these incompatibilities. EIP submissions without a sufficient backwards compatibility treatise may be rejected outright.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

No backward compatibility issues found.

## Test Cases

<!--
  This section is optional for non-Core EIPs.

  The Test Cases section should include expected input/output pairs, but may include a succinct set of executable tests. It should not include project build files. No new requirements may be introduced here (meaning an implementation following only the Specification section should pass all tests here.)
  If the test suite is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`. External links will not be allowed

  TODO: Remove this comment before submitting
-->

## Reference Implementation

<!--
  This section is optional.

  The Reference Implementation section should include a minimal implementation that assists in understanding or implementing this specification. It should not include project build files. The reference implementation is not a replacement for the Specification section, and the proposal should still be understandable without it.
  If the reference implementation is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`. External links will not be allowed.

  TODO: Remove this comment before submitting
-->

## Security Considerations

PermaLink-ABTs are linked to another non-fungible token. If an individual loses access to this token, what we call the binding token, they also lose access to all PermaLink-ABTs that have been bound to it. This is why we strongly recommend utilizing a standard such ERC-6809, a Non-Fungible Key Bound Token, because this token standard provides on-chain 2FA. This would secure all of the PermaLink-ABTs bound to the ERC-6809, and also allow a way to retrieve all of the tokens in case access to the wallet is lost or you’ve connected to a malicious site. In essence, as all of ERC-6809s security functionality carry of to all of the PermaLink-ABTs bound to it.

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
