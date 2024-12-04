---
eip: xxxx
title: ERC721 Sustainable Collections
description: A standard for managing NFTs with dynamic fees and donation-based engagement.
author: Gustavo Lobo (@gflobo)
status: Draft
type: Standards Track
category: ERC
created: 2024-12-04
requires: 721
---

### Abstract  
This EIP defines a standard for economically sustainable NFTs using features derived from the ERC721 standard. It integrates dynamic minting fees, role-based access control, and donation-based engagement. These mechanisms align tokenomics with principles of scarcity and value attribution while enabling creators to foster community engagement through contributions. Additionally, the standard supports optional features like token raffles to further incentivize community participation.

---

### Motivation  
NFT systems often face issues like inflationary supply and lack of mechanisms to incentivize meaningful engagement between creators and contributors. This EIP addresses these gaps by introducing:  
- **Dynamic Minting Fees**: To align token costs with user activity and ownership.  
- **Donation-Based Engagement**: Encouraging contributions to creators.  
- **Role-Based Access**: Empowering creators while ensuring transparent governance.  
- **Optional Raffles**: Providing a mechanism for creators to reward contributors in a gamified manner.

---

### Specification  

#### Core Functionalities  

1. **Dynamic Minting Fees:**  
   Minting fees increase dynamically based on the number of tokens owned by the user. This discourages hoarding and promotes equitable token distribution.  
   - Formula:  
     ```solidity
     function mintFee() public view returns (uint256) {
        if (hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) return 0;
        uint256 baseFee = mintBaseFee;
        uint256 incrementPercentage = mintRateIncrementPercentage;
        uint256 userTokenCount = balanceOf(msg.sender);
        return baseFee * (1 + incrementPercentage / 100) ** userTokenCount;
      }
     ```  

2. **Donation System:**  
   Contributors can support creators by donating ETH. Upon donation, users may receive the **Contributor Role**, granting them special access to features like raffles or exclusive minting rights.  
   - Function:  
     ```solidity
     function donate(address creator) external payable;
     ```

3. **Role-Based Access:**  
   - **Creator Role:** Enables minting and managing collections. Users can acquire this role by paying a creator signature fee.  
   - **Contributor Role:** Granted to users who donate ETH to creators, enabling participation in additional features.  

4. **Administrative Controls:**  
   - **Pause/Unpause:** Allows administrators to halt or resume contract operations during emergencies.  
   - **Withdraw:** Administrators can withdraw ETH from the contract with complete transparency.  

#### Optional Raffle Mechanism (Extra Feature)  

Creators can optionally organize raffles to reward contributors. Raffles encourage engagement by allowing contributors to compete for ownership of specific tokens.  
- **Creating a Raffle:**  
  - Creators specify the token ID, expected donation amount, and participant limits.  
  - Example function:  
    ```solidity
    function createRaffle(uint256 tokenId, uint256 expectedAmount) external;
    ```

- **Joining a Raffle:**  
  - Contributors can join active raffles by donating ETH to the creator. If the donation pool reaches the expected amount, a winner is randomly selected.  
  - Example function:  
    ```solidity
    function joinRaffle(uint256 tokenId) external payable;
    ```

- **Random Winner Selection:**  
  - Winners are selected using a random mechanism based on on-chain factors like block timestamp and randomness (`block.prevrandao`).  

---

### Roles and Permissions  

- **Administrator:**  
  - Grants roles, updates contract parameters, and manages withdrawals.  
- **Creator:**  
  - Mints tokens and creates raffles (optional feature).  
- **Contributor:**  
  - Gains access to exclusive features after donating to creators.  

---

### Security Considerations  

- **Reentrancy Protection:**  
  Implements `ReentrancyGuard` to prevent recursive call vulnerabilities in donation and raffle functions.  
- **Access Management:**  
  Utilizes OpenZeppelin's `AccessControl` to enforce role-based restrictions.  
- **Raffle Transparency:**  
  Raffle mechanics use auditable and on-chain randomness for fairness.  
- **Paused State:**  
  Allows administrators to pause the contract in emergencies, ensuring safety during unexpected events.  

---

### Test Cases  

- Validate dynamic minting fees with varying ownership levels.  
- Verify role-based access control for minting and donations.  
- Ensure proper donation flow and ETH transfer to creators.  
- Test contract pause and unpause functionalities.  
- Simulate raffle creation, participation, and winner selection scenarios.  
- Simulate unauthorized access attempts and validate security safeguards.  

---

### Reference Implementation  

The reference implementation is provided at [Collectible](https://github.com/gfLobo/Collectible). It includes all specified functionalities, including dynamic fees, donation systems, role-based access, and optional raffle mechanisms.

---

### Backwards Compatibility  

This EIP is fully compatible with ERC721. Extensions like dynamic minting fees, donation systems, and optional raffles are modular and do not impact existing ERC721 token functionalities.

---

### Copyright Waiver  
Copyright and related rights waived via [CC0](../LICENSE.md).
