---
title: <ERC-XXXX: Perpetual Contract NFTs as Collateral for Liquidity Provision>
description: A standard for representing locked financial assets as Non-Fungible Tokens (NFTs), enabling these NFTs to be used as collateral for borrowing funds in Decentralized Finance (DeFi). This ERC also integrates the concept of rentable NFTs (via ERC-4907) to facilitate liquidity provision.

author: hyougnsung@keti.re.kr
discussions-to: {Will be replaced after uploading to Fellowship of Ethereum Magicians (FEM) forum}
status: Draft
type: Standards Track
category: ERC
created: date created on, 2023-11-27
requires: 721, 4907
---

<!--
  READ EIP-1 (https://eips.ethereum.org/EIPS/eip-1) BEFORE USING THIS TEMPLATE!

  This is the suggested template for new EIPs. After you have filled in the requisite fields, please delete these comments.

  Note that an EIP number will be assigned by an editor. When opening a pull request to submit your EIP, please use an abbreviated title in the filename, `eip-draft_title_abbrev.md`.

  The title should be 44 characters or less. It should not repeat the EIP number in title, irrespective of the category.

  TODO: Remove this comment before submitting
-->

## Abstract
This ERC proposes a mechanism where a person (referred to as the "Asset Owner") can collateralize NFTs that represent locked deposits or assets, to borrow funds against them. These NFTs represent the right to claim the underlying assets, along with any accrued benefits, after a predefined maturity period. For an academic article, please visit [IEEE Xplore](https://ieeexplore.ieee.org/document/9967987/.)


## Motivation
The rapidly evolving landscape of DeFi has introduced various mechanisms for asset locking, offering benefits like interest and voting rights. However, one of the significant challenges in this space is maintaining liquidity while these assets are locked. This ERC addresses this challenge by proposing a method to generate profit from locked assets using ERC-721 and ERC-4907.

In DeFi services, such as Uniswap v3, liquidity providers contribute assets to pools and receive NFTs representing their stake. These NFTs denote the rights to the assets and the associated benefits, but they also lock the assets in the pool, often causing liquidity challenges for the providers. The current practice requires providers to withdraw their assets for urgent liquidity needs, adversely affecting the pool's liquidity and potentially increasing slippage during asset swaps.

Our proposal allows these NFTs, representing locked assets in liquidity pools, to be used as collateral. This approach enables liquidity providers to gain temporary liquidity without withdrawing their assets, maintaining the pool's liquidity levels. Furthermore, it extends to a broader range of DeFi services, including lending and trading, where asset locking is prevalent. By allowing the collateralization of locked asset representations through NFTs, our approach aims to provide versatile liquidity solutions across DeFi services, benefitting a diverse user base within the ecosystem.

The concept of perpetual contract NFTs, which we introduce, exploits the idea of perpetual futures contracts in the cryptocurrency derivatives market. These NFTs represent the rights to the perpetual contract and its collateral, enabling them to be used effectively as collateral for DeFi composability. The perpetual contract NFT offers a new form of NFT that enhances the utility of locked assets, providing a significant advantage in DeFi applications by offering liquidity while retaining the benefits of asset locking.

## Specification
The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.


### Contract Interface
Solidity interface.

```solidity
interface IPerpetualContractNFT {

    // Logged when an NFT is used as collateral for a loan
    event Collateralized(uint256 indexed tokenId, address indexed owner, uint256 loanAmount, uint256 interestRate, uint256 loanDuration);

    // Logged when a loan against an NFT is repaid and the NFT is released from collateral
    event LoanRepaid(uint256 indexed tokenId, address indexed owner);

    // Logged when a loan defaults and the NFT is transferred to the lender
    event Defaulted(uint256 indexed tokenId, address indexed lender);

    // Allows an NFT owner to use their NFT as collateral to receive a loan
    // @param tokenId The NFT to be used as collateral
    // @param loanAmount The amount of funds to be borrowed
    // @param interestRate The interest rate for the loan
    // @param loanDuration The duration of the loan
    function collateralize(uint256 tokenId, uint256 loanAmount, uint256 interestRate, uint256 loanDuration) external;

    // Allows an NFT owner to repay their loan and reclaim their NFT
    // @param tokenId The NFT that was used as collateral
    function repayLoan(uint256 tokenId) external;

    // Allows querying the loan terms for a given NFT
    // @param tokenId The NFT used as collateral
    // @return loanAmount, interestRate, loanDuration, and loanDueDate
    function getLoanTerms(uint256 tokenId) external view returns (uint256 loanAmount, uint256 interestRate, uint256 loanDuration, uint256 loanDueDate);

    // Allows querying the current owner of the NFT
    // @param tokenId The NFT in question
    // @return The address of the current owner
    function currentOwner(uint256 tokenId) external view returns (address);
}
```

Event `Collateralized`:
- Implementation Suggestion: MUST be emitted when the collateralize function is successfully executed.
- Usage: Logs the event of an NFT being used as collateral for a loan, capturing essential details like the loan amount, interest rate, and loan duration.


Event `LoanRepaid`:
- Implementation Suggestion: MUST be emitted when the repayLoan function is successfully executed.
- Usage: Logs the event of a loan being repaid and the corresponding NFT being released from collateral.


Event `Defaulted`:
- Implementation Suggestion: MUST be emitted in scenarios where the loan defaults and the NFT is transferred to the lender.
- Usage: Used to log the event of a loan default and the transfer of the NFT to the lender.

Function `collateralize`:
- Implementation Suggestion: SHOULD be implemented as `external`.
- Usage: Allows an NFT owner to collateralize their NFT to receive a loan.

Function `repayLoan`:
- Implementation Suggestion: SHOULD be implemented as `external`.
- Usage: Enables an NFT owner to repay their loan and reclaim their NFT.
  
Function `getLoanTerms`:
- Implementation Suggestion: MAY be implemented as `external` `view`.
- Usage: Allows querying the loan terms for a given NFT.

Function `currentOwner`:
- Implementation Suggestion: MAY be implemented as `external` `view`.
- Usage: Enables querying the current owner of a specific NFT.
  
## Rationale

<!--
  The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

### Motivation 
The design of this standard is motivated by the need to address specific challenges in the DeFi sector, particularly around the liquidity and management of assets locked as collateral. Traditional mechanisms in DeFi often require asset holders to lock up their assets for participation in lending, staking, or yield farming, resulting in a loss of liquidity. This standard aims to introduce a more flexible approach, allowing asset holders to retain some liquidity while their assets are locked, thereby enhancing the utility and appeal of DeFi products.

### Design Decision
- Dual-Role System (Owner and User/DeFi Platform): The standard introduces a distinct division between the NFT owner (the asset holder) and the user or DeFi platform utilizing the NFT as collateral. This clear distinction is intended to streamline rights and responsibilities, reducing potential disputes and enhancing transaction clarity.

- Automated Loan and Collateral Management: The integration of automated features for managing the terms and conditions of the collateralized NFT is a deliberate choice to minimize transaction costs and complexity, essential in the blockchain context where efficiency is paramount.

- DeFi Composability: The strategic emphasis on DeFi composability, particularly the integration between asset-locking and collateralizing services, is pivotal for this standard. This approach aims to streamline the adoption of the standard across diverse DeFi platforms and services. By fostering seamless connections within the DeFi ecosystem.

### Alternate Designs and Related Work
- Comparison with ERC-4907: While ERC-4907 also introduces a dual-role model for NFTs (owner and user), our standard focuses specifically on the use of NFTs for collateralization in financial transactions, diverging from ERC-4907’s rental-oriented approach.

- Traditional Collateralization Mechanisms: The standard offers an alternative to traditional DeFi collateralization, which typically requires complete asset lock-up. It proposes a more dynamic model, allowing for continued liquidity and flexibility.


## Backwards Compatibility

Fully compatible with ERC-721 and integrates with ERC-4907 for renting NFTs.

## Test Cases

<!--
  This section is optional for non-Core EIPs.

  The Test Cases section should include expected input/output pairs, but may include a succinct set of executable tests. It should not include project build files. No new requirements may be be introduced here (meaning an implementation following only the Specification section should pass all tests here.)
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

<!--
  All EIPs must contain a section that discusses the security implications/considerations relevant to the proposed change. Include information that might be important for security discussions, surfaces risks and can be used throughout the life cycle of the proposal. For example, include security-relevant design decisions, concerns, important discussions, implementation-specific guidance and pitfalls, an outline of threats and risks and how they are being addressed. EIP submissions missing the "Security Considerations" section will be rejected. An EIP cannot proceed to status "Final" without a Security Considerations discussion deemed sufficient by the reviewers.

  The current placeholder is acceptable for a draft.

  TODO: Remove this comment before submitting
-->

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
