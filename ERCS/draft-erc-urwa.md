---
title: uRWA - Universal Real World Asset Interface
description: A minimal standard interface for regulated assets, targeting the broad spectrum of RWAs.
author: Dario Lo Buglio (@xaler5)
discussions-to: <URL of forum discussion, GitHub issue, etc.>
status: Draft
type: Standards Track
category: ERC
created: 2025-04-27
requires: EIP-165
---

## Abstract

This EIP proposes "Universal RWA" (uRWA) standard, a minimal interface for all commond tokens like ERC-20 / ERC-721 or ERC-1155 based tokens, meant to be the primitive for the different classes of Real World Assets. It defines essential functions and events for regulatory compliance and enforcement actions common to RWAs.

## Motivation

The tokenization of Real World Assets introduces requirements often absent in purely digital assets, such as regulatory compliance checks, nuanced transfer controls, and potential enforcement actions. Existing token standards, primarily ERC-20, ERC-721 and ERC-1155, lack the inherent structure to address these needs directly within the standard itself.

Attempts at defining universal RWA standards historically imposed unnecessary complexity and gas overhead for simpler use cases that do not require the full spectrum of features like granular role-based access control, mandatory on-chain whitelisting, specific on-chain identity solutions or metadata handling solutions mandated by the standard.

The broad spectrum of RWA classes inherently suggests the need to move away from a one-size-fits-all solution. With the purpose in mind of defining an EIP for it, a minimalistic approach, unopinionated features list and maximally compatible design should be kept in mind.

The uRWA standard seeks a more refined balance by defining an essential interface, establishing a common ground for interaction regarding compliance and control, without dictating the underlying implementation mechanisms. This allows core token implementations (like ERC-20, ERC-721 or ERC-1155) to remain lean while providing standard functions for RWA-specific interactions.

The final goal is to build composable DeFi around RWAs, providing the same interface when dealing with compliance and regulation.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

**uRWA Interface**

The following defines the standard interface for an uRWA token contract.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Interface for the uRWA Token Interface
interface IuRWA {
    /// @notice Emitted when tokens are taken from one address and transferred to another.
    /// @param from The address from which tokens were taken.
    /// @param to The address to which seized tokens were transferred.
    /// @param amount The amount seized.
    /// @param tokenId The ID of the token being transferred.
    event Recalled(address indexed from, address indexed to, uint256 amount, uint256 tokenId);

    /// @notice Error reverted when a user is not allowed to interact.
    /// @param account The address of the user which is not allowed for interactions.
    error UserNotAllowed(address account);

    /// @notice Error reverted when a transfer is not allowed due to restrictions in place.
    /// @param from The address from which tokens are being transferred.
    /// @param to The address to which tokens are being transferred.
    /// @param amount The amount being transferred.
    /// @param tokenId The ID of the token being transferred. 
    error TransferNotAllowed(address from, address to, uint256 amount, uint256 tokenId);

    /// @notice Takes tokens from one address and transfers them to another.
    /// @dev Requires specific authorization. Used for regulatory compliance or recovery scenarios.
    /// @param from The address from which `amount` is taken.
    /// @param to The address that receives `amount`.
    /// @param amount The amount to recall.
    /// @param tokenId The ID of the token being transferred.
    function recall(address from, address to, uint256 amount, uint256 tokenId) external;

    /// @notice Checks if a transfer is currently possible according to token rules and registered plugins.
    /// @dev This may involve checks like allowlists, blocklists, transfer limits, etc.
    /// @param from The address sending tokens.
    /// @param to The address receiving tokens.
    /// @param amount The amount being transferred.
    /// @param tokenId The ID of the token being transferred.
    /// @return allowed True if the transfer is allowed, false otherwise.
    function isTransferAllowed(address from, address to, uint256 amount, uint256 tokenId) external view returns (bool allowed);

    /// @notice Checks if a specific user is allowed to interact with the token.
    /// @dev This is often used for allowlist/KYC checks.
    /// @param user The address to check.
    /// @return allowed True if the user is allowed, false otherwise.
    function isUserAllowed(address user) external view returns (bool allowed);

    /// Derived from ERC-165
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}
```
*   The `isUserAllowed` and `isTransferAllowed` functions provide views into the implementing contract's compliance and transfer policy logic. The exact implementation of these checks (e.g., internal allowlist, external calls, complex logic) is NOT mandated by this interface standard. However these two functions:
    - MUST NOT revert. 
    - MUST NOT change the storage of the contract. 
    - MAY depend on context (e.g., current timestamp or block.number).
*   The `recall` function provide a standard mechanism for forcing a transfer from a `from` to a `to` address. This is often known as either "confiscation" / "revocation" or even "recovery" which are all names related to the motivation being the feature itself. The name chose tries to abstract away the motivation and keep a general name. This function:
    - MUST directly manipulate balances or ownership to transfer the asset from `from` to `to` either by transfering or burning from `from` and minting to `to`. 
    - MUST perform necessary validation checks (e.g., sufficient balance/ownership of a specific token).
    - MUST emit both the standard `Transfer` event (from the base ERC standard) and the `Recalled` event. 
    - SHOULD bypass standard transfer validation logic, including checks enforced by `isTransferAllowed` and `isUserAllowed`.

Given the agnostic nature of the standard on the specific base token standard being used (ERC-20, ERC-721, ERC-1155), the implementation SHOULD use `tokenId = 0` for ERC-20 based implementations, and `amount = 1` for ERC-721 based implementations on `Recalled` event, `TransferNotAllowed` error and `recall` / `isTransferAllowed` functions. Integrators MAY decide to not enforce this, however the standard discourages it. This is considered a little tradeoff for having a unique standard interface for different token standards without overlapping syntaxes.

Implementations of this interface MUST implement the necessary functions of their chosen base standard (e.g., `ERC-20`, `ERC-721`, `ERC-1155` functionalities) and MUST also restrict access to sensitive functions like `recall` using an appropriate access control mechanism (e.g., `onlyOwner`, Role-Based Access Control). The specific mechanism is NOT mandated by this interface standard.

Integrators MUST ensure their internal transfer logic (e.g., within `_update`, `_transfer`, `_mint`, `_burn`) respects the boolean outcomes of `isUserAllowed` and `isTransferAllowed`. Transfers, mints, or burns MUST NOT proceed and instead MUST revert with `UserNotAllowed` or `TransferNotAllowed` if and only if these checks indicate the action is disallowed according to the contract's specific policy.

## Rationale

*   **Minimalism:** Defines only the essential functions (`recall`, `isUserAllowed`, `isTransferAllowed`) and associated events/errors needed for common RWA compliance and control patterns, avoiding mandated complexity or opinionated features.
*   **Flexibility:** Provides standard view functions (`isUserAllowed`, `isTransferAllowed`) for compliance checks without dictating *how* those checks are implemented internally by the token contract. This allows diverse compliance strategies.
*   **Compatibility:** Designed as an interface layer compatible with existing base standards like ERC-20, ERC-721 and ERC-1155. Implementations extend from `IuRWA` alongside their base standard interface.
*   **RWA Essential:** Includes `recall` as a standard function, acknowledging its importance for regulatory enforcement in the RWA space, distinct from standard transfers. Mandates access control for this sensitive function.
*   **EIP-165:** Ensures implementing contracts can signal support for this interface.

As an example, a Uniswap v4 pool can integrate with uRWA ERC-20 tokens by calling `isUserAllowed` or `isTransferAllowed` within its before/after hooks to handle these assets in a compliant manner. Users can then expand these tokens with additional features to fit the specific needs of individual asset types, either with on-chain identity systems, historical balances tracking for dividend distributions, semi-fungibility with tokens metadata, etc.

## Backwards Compatibility

This EIP defines a new interface standard and does not alter existing ones like ERC-20, ERC-721, ERC-1155. Standard wallets and explorers can interact with the base token functionality of implementing contracts, subject to the rules enforced by that contract's implementation of `isUserAllowed` and `isTransferAllowed`. Full support for the `IuRWA` functions requires explicit integration.

## Security Considerations

*   **Access Control for `recall`:** The security of the mechanism chosen by the implementer to restrict access to the `recall` function is paramount. Unauthorized access could lead to asset theft. Secure patterns (multisig, timelocks) are highly recommended.
*   **Implementation Logic:** The security and correctness of the *implementation* behind `isUserAllowed` and `isTransferAllowed` are critical. Flaws in this logic could bypass intended transfer restrictions or incorrectly block valid transfers.
*   **Standard Contract Security:** Implementations MUST adhere to general smart contract security best practices (reentrancy guards where applicable, checks-effects-interactions, etc.).

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).