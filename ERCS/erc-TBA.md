---
title: Soulbound Degradable Governance
description:
  DAO governance where voting power is non-transferable and decays over time without
  active contributions.
author: Guilherme Neves (@0xneves) Rafael Castaneda (@castacrypto)
discussions-to: https://ethereum-magicians.org/t/soulbounded-degradable-governance-sdg-a-new-approach-to-dao-power-structures/21326
status: Draft
type: Standards Track
category: ERC
created: 2024-10-15
requires:
---

## Abstract

This proposal introduces the Soulbound Degradable Governance (SDG) standard, where governance power should be granted as non-transferable tokens that decay over time unless renewed through participation. SDG enables young DAOs to implement merit-based governance by detaching governance power from economic power while on early stages of development.

## Motivation

Traditional DAO governance models rely heavily on economic tokens, where voting power is proportional to token holdings. While effective for some use cases, this model risks concentrating power among wealthy members, leading to plutocracy and discouraging participation from smaller stakeholders. Furthermore, it fosters a treasury-centric culture that attracts contributors primarily focused on financial gain, rather than long-term governance or community well-being. 

Young DAOs, in particular, need governance models that incentivize active contributions without relying on economic power. This proposal addresses these issues by detaching governance power from economic power and ensuring political power decays if not maintained through ongoing participation. This approach creates a merit-based structure that reflects continuous involvement and reduces the risk of early-stage centralization or dependent on heavy inflationary policies.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT",
"RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as
described in RFC 2119 and RFC 8174.

This system MUST operate with two distinct tokens, one representing **political power** and another representing **economic power**:  

1. The political power token is non-transferable, decays over time and MUST implement SDG. 

2. The economic power token supports liquidity and trade, providing the financial utility needed for the DAO’s operations and is RECOMMENDED to be a standard ERC-20 token.

The implementer of this standard MUST:

1. Override the `transfer(...)` function on derived contracts for the governance token to prevent transfers between addresses. 

2. Create a decay mechanism by overriding the `getVotes(...)` function on parent contract, reducing the token’s voting power over time. This is RECOMMENDED to be a linear or exponential decay formula.

3. Utilize the `_setVotingUnits(...)` internal function of SDG on the parent contract to set the voting power of addresses when minting, burning or other applying other format of distribution/destruction.

4. Create the respectives **Event** emissions on the parent contract for minting, burning or other functions that affect the voting power of addresses.

### **Contract Methods:**

```solidity
/**
 * @dev This contract implements a governance system where voting units decays over time if not actively 
 * maintained and MUST be implemented by a Soulbounded Token contract.
 */
abstract contract SDG {
  // Mapping of addresses to their voting units
  mapping(address => uint256) private _votingUnits;

  // Mapping of addresses to the last time their voting units was updated
  mapping(address => uint256) private _lastUpdates;
  
  /**
   * @dev Returns the grace period duration before the voting units begins decaying. This period is
   * fixed to 90 days. But it can be overridden in derived contracts.
   * @return The duration of the grace period in seconds.
   */
  function gracePeriod() public view virtual returns (uint256);

  /**
   * @dev Returns the duration of the decay period during which the voting units decreases. This
   * period is fixed to 90 days. But it can be overridden in derived contracts.
   * @return The duration of the decay period in seconds.
   */
  function decayPeriod() public view virtual returns (uint256);

  /**
   * @dev Should be implemented by derived contracts to return the current voting units of an account.
   * This function calculates the voting units based on the last time it was updated and decays it
   * over time.
   * @param account The address to check for voting units.
   * @return The current voting units of the account.
   */
  function getVotes(address account) public view virtual returns (uint256);

  /**
   * @dev Returns the voting units of an account without decaying it.
   * @param account The address of the account to query.
   * @return The current voting units of the account.
   */
  function _votingUnitsOf(address account) internal view virtual returns (uint256);

  /**
   * @dev Returns the timestamp of the last update to an account's voting units.
   * @param account The address of the account to query.
   * @return The timestamp of the last voting units update for the account.
   */
  function _lastUpdateOf(address account) internal view virtual returns (uint256);

  /**
   * @dev Sets the voting units of an account and updates the timestamp.
   * @param account The address of the account receiving additional voting units.
   * @param amount The amount of additional voting units to grant.
   */
  function _setVotingUnits(address account, uint256 amount) internal virtual;
}

```

## Rationale

The SDG standard ensures flexibility by not being tied to any specific token type, allowing DAOs to implement it with **ERC-20**, **ERC-721**, **ERC-1155**, or other future token standards. This decision maximizes the compatibility and adaptability of the framework across different governance models.

The choice to **decouple governance power from economic power** aims to provide a practical governance model for young DAOs seeking to prevent early centralization while fostering active participation. Non-transferable governance tokens ensure that only engaged members retain influence, as political power decays over time if not renewed through contributions. 

We deliberately avoided incorporating mechanisms like "Game Master mode" for early stages or fixed decayment strategy within the standard to keep the specification **minimal and modular**. These governance structures should be implemented by individual DAOs if needed, without burdening the core SDG standard with additional complexity. The goal is to provide DAOs with the essential tools to build sustainable, merit-based governance, while leaving room for experimentation and customization at the implementation level.

The inclusion of **grace periods** and **decay periods** balances fairness with fluidity, incentivizing active participation while preventing governance stagnation. These mechanics ensure that governance power reflects recent contributions, phasing out inactive members naturally, and maintaining a dynamic, merit-based structure.

## Backwards Compatibility

No backward compatibility issues found.

## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
