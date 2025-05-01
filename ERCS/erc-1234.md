---
eip: 1234
title: uRWA - Universal Real World Asset Interface
description: A minimal interface for regulated assets, targeting the broad spectrum of RWAs.
author: Dario Lo Buglio (@xaler5)
discussions-to: https://ethereum-magicians.org/t/erc-universal-rwa-interface/23972
status: Draft
type: Standards Track
category: ERC
created: 2025-05-01
requires: 165
---

## Abstract

This EIP proposes "Universal RWA" (uRWA) standard, a minimal interface for all common tokens like [ERC-20](./eip-20.md), [ERC-721](./eip-721.md) or [ERC-1155](./eip-1155.md) based tokens, meant to be the primitive for the different classes of Real World Assets. It defines essential functions and events for regulatory compliance and enforcement actions common to RWAs. It also extends from [ERC-165](./eip-165.md) for introspection.

## Motivation

The tokenization of Real World Assets introduces requirements often absent in purely digital assets, such as regulatory compliance checks, nuanced transfer controls, and potential enforcement actions. Existing token standards, primarily [ERC-20](./eip-20.md), [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md), lack the inherent structure to address these needs directly within the standard itself.

Attempts at defining universal RWA standards historically imposed unnecessary complexity and gas overhead for simpler use cases that do not require the full spectrum of features like granular role-based access control, mandatory on-chain whitelisting, specific on-chain identity solutions or metadata handling solutions mandated by the standard.

The broad spectrum of RWA classes inherently suggests the need to move away from a one-size-fits-all solution. With the purpose in mind of defining an EIP for it, a minimalistic approach, unopinionated features list and maximally compatible design should be kept in mind.

The uRWA standard seeks a more refined balance by defining an essential interface, establishing a common ground for interaction regarding compliance and control, without dictating the underlying implementation mechanisms. This allows core token implementations to remain lean while providing standard functions for RWA-specific interactions.

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
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount seized.
    event Recalled(address indexed from, address indexed to, uint256 tokenId, uint256 amount);

    /// @notice Error reverted when a user is not allowed to interact.
    /// @param account The address of the user which is not allowed for interactions.
    error UserNotAllowed(address account);

    /// @notice Error reverted when a transfer is not allowed due to restrictions in place.
    /// @param from The address from which tokens are being transferred.
    /// @param to The address to which tokens are being transferred.
    /// @param tokenId The ID of the token being transferred. 
    /// @param amount The amount being transferred.
    error TransferNotAllowed(address from, address to, uint256 tokenId, uint256 amount);

    /// @notice Takes tokens from one address and transfers them to another.
    /// @dev Requires specific authorization. Used for regulatory compliance or recovery scenarios.
    /// @param from The address from which `amount` is taken.
    /// @param to The address that receives `amount`.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount to recall.
    function recall(address from, address to, uint256 tokenId, uint256 amount) external;

    /// @notice Checks if a transfer is currently possible according to token rules and registered plugins.
    /// @dev This may involve checks like allowlists, blocklists, transfer limits, etc.
    /// @param from The address sending tokens.
    /// @param to The address receiving tokens.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount being transferred.
    /// @return allowed True if the transfer is allowed, false otherwise.
    function isTransferAllowed(address from, address to, uint256 tokenId, uint256 amount) external view returns (bool allowed);

    /// @notice Checks if a specific user is allowed to interact with the token.
    /// @dev This is often used for allowlist/KYC checks.
    /// @param user The address to check.
    /// @return allowed True if the user is allowed, false otherwise.
    function isUserAllowed(address user) external view returns (bool allowed);

    /// Derived from EIP-165
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
    - MUST emit both the standard `Transfer` event (from the base standard) and the `Recalled` event. 
    - SHOULD bypass standard transfer validation logic, including checks enforced by `isTransferAllowed` and `isUserAllowed`.

Given the agnostic nature of the standard on the specific base token standard being used the implementation SHOULD use `tokenId = 0` for [ERC-20](./eip-20.md) based implementations, and `amount = 1` for [ERC-721](./eip-721.md) based implementations on `Recalled` event, `TransferNotAllowed` error and `recall` / `isTransferAllowed` functions. Integrators MAY decide to not enforce this, however the standard discourages it. This is considered a little tradeoff for having a unique standard interface for different token standards without overlapping syntaxes.

Implementations of this interface MUST implement the necessary functions of their chosen base standard (e.g., [ERC-20](./eip-20.md), [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md) functionalities) and MUST also restrict access to sensitive functions like `recall` using an appropriate access control mechanism (e.g., `onlyOwner`, Role-Based Access Control). The specific mechanism is NOT mandated by this interface standard.

Integrators MUST ensure their internal transfer logic (e.g., within `_update`, `_transfer`, `_mint`, `_burn`) respects the boolean outcomes of `isUserAllowed` and `isTransferAllowed`. Transfers, mints, or burns MUST NOT proceed and instead MUST revert with `UserNotAllowed` or `TransferNotAllowed` if and only if these checks indicate the action is disallowed according to the contract's specific policy.

## Rationale

*   **Minimalism:** Defines only the essential functions (`recall`, `isUserAllowed`, `isTransferAllowed`) and associated events/errors needed for common RWA compliance and control patterns, avoiding mandated complexity or opinionated features.
*   **Flexibility:** Provides standard view functions (`isUserAllowed`, `isTransferAllowed`) for compliance checks without dictating *how* those checks are implemented internally by the token contract. This allows diverse compliance strategies.
*   **Compatibility:** Designed as an interface layer compatible with existing base standards like [ERC-20](./eip-20.md), [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md). Implementations extend from `IuRWA` alongside their base standard interface.
*   **RWA Essential:** Includes `recall` as a standard function, acknowledging its importance for regulatory enforcement in the RWA space, distinct from standard transfers. Mandates access control for this sensitive function.
*   **[ERC-165](./eip-165.md):** Ensures implementing contracts can signal support for this interface.

As an example, a Uniswap v4 pool can integrate with uRWA [ERC-20](./eip-20.md) tokens by calling `isUserAllowed` or `isTransferAllowed` within its before/after hooks to handle these assets in a compliant manner. Users can then expand these tokens with additional features to fit the specific needs of individual asset types, either with on-chain identity systems, historical balances tracking for dividend distributions, semi-fungibility with tokens metadata, etc.

## Backwards Compatibility

This EIP defines a new interface standard and does not alter existing ones like [ERC-20](./eip-20.md), [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md). Standard wallets and explorers can interact with the base token functionality of implementing contracts, subject to the rules enforced by that contract's implementation of `isUserAllowed` and `isTransferAllowed`. Full support for the `IuRWA` functions requires explicit integration.

## Reference Implementation

Examples of basic implementation for [ERC-20](./eip-20.md), [ERC-721](./eip-721.md) and [ERC-1155](./eip-1155.md) which includes a basic whitelist for users and an enumerable role based access control:

### [ERC-20](./eip-20.md) Example

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/* required imports ... */

contract uRWA20 is Context, ERC20, AccessControlEnumerable, IuRWA {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant RECALL_ROLE = keccak256("RECALL_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    mapping(address user => bool whitelisted) public isWhitelisted;

    event Whitelisted(address indexed account, bool status);
    error NotZeroAddress();

    constructor(string memory name, string memory symbol, address initialAdmin) ERC20(name, symbol) {
        /* give initialAdmin necessary roles ...*/
    }

    function changeWhitelist(address account, bool status) external onlyRole(WHITELIST_ROLE) {
        require(account != address(0), NotZeroAddress());
        isWhitelisted[account] = status;
        emit Whitelisted(account, status);
    }

    /* standard mint and burn functions with access control ...*/ 

    function recall(address from, address to, uint256, uint256 amount) public onlyRole(RECALL_ROLE) {
        require(isUserAllowed(to), UserNotAllowed(to));
        // Directly update balances, bypassing overridden _update
        super._update(from, to, amount);
        emit Recalled(from, to, 0, amount);
    }

    function isTransferAllowed(address from, address to, uint256, uint256 amount) public virtual view returns (bool allowed) {
        if (balanceOf(from) < amount) return false;
        if (!isUserAllowed(from) || !isUserAllowed(to)) return false;

        return true;
    }

    function isUserAllowed(address user) public virtual view returns (bool allowed) {
        if (!isWhitelisted[user]) return false;
        
        return true;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && to != address(0)) { // Transfer
            require(isTransferAllowed(from, to, 0, value), TransferNotAllowed(from, to, 0, value));
        } else if (from == address(0)) { // Mint
            require(isUserAllowed(to), UserNotAllowed(to));
        } else { // Burn
            require(isUserAllowed(from), UserNotAllowed(from));
        }

        super._update(from, to, value);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, IERC165) returns (bool) {
        return interfaceId == type(IuRWA).interfaceId ||
            interfaceId == type(IERC20).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
```

### [ERC-721](./eip-721.md) Example

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/* required imports ... */

contract uRWA721 is Context, ERC721, AccessControlEnumerable, IuRWA {
    /* same roles definitions, constructor and changeWhitelist function as before ...*/

    /* standard mint and burn functions with access control ...*/ 

    function recall(address from, address to, uint256 tokenId, uint256) public virtual override onlyRole(RECALL_ROLE) {
        require(to != address(0), ERC721InvalidReceiver(address(0)));
        address previousOwner = super._update(to, tokenId, address(0)); // Skip _update override
        require(previousOwner != address(0), ERC721NonexistentToken(tokenId));
        require(previousOwner == from, ERC721IncorrectOwner(from, tokenId, previousOwner));
        
        ERC721Utils.checkOnERC721Received(_msgSender(), from, to, tokenId, "");
        emit Recalled(from, to, tokenId, 1);
    }

    function isUserAllowed(address user) public view virtual override returns (bool allowed) {
        return isWhitelisted[user];
    }

    function isTransferAllowed(address from, address to, uint256 tokenId, uint256) public view virtual override returns (bool allowed) {
        if (_ownerOf(tokenId) != from || _ownerOf(tokenId) == address(0)) return false; // Use internal function to avoid reverting for non existing tokenIds
        if (!isUserAllowed(from) || !isUserAllowed(to)) return false;
        return true;
    }

    function _update(address to, uint256 value, address auth) internal virtual override returns(address) {
        address from = _ownerOf(value);

        if (auth != address(0)) {
            _checkAuthorized(from, auth, value);
        }

        if (from != address(0) && to != address(0)) { // Transfer
            require(isTransferAllowed(from, to, value, 1), TransferNotAllowed(from, to, value, 1));
        } else if (from == address(0)) { // Mint
            require(isUserAllowed(to), UserNotAllowed(to));
        } else { // Burn
            require(isUserAllowed(from), UserNotAllowed(from));
        } 

        return super._update(to, value, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC721, IERC165) returns (bool) {
        return interfaceId == type(IuRWA).interfaceId ||
               super.supportsInterface(interfaceId);
    }
}
```

### [ERC-1155](./eip-1155.md) Example

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/* required imports ... */

contract uRWA1155 is Context, ERC1155, AccessControlEnumerable, IuRWA {
    /* same roles definitions, constructor and changeWhitelist function as before ...*/

    /* standard mint and burn functions with access control ...*/ 

    function recall(address from, address to, uint256 tokenId, uint256 amount) public onlyRole(RECALL_ROLE) {
        require(isUserAllowed(to), UserNotAllowed(to));
        _safeTransferFrom(from, to, tokenId, amount, "");
        emit Recalled(from, to, tokenId, amount);
    }

    function isTransferAllowed(address from, address to, uint256 tokenId, uint256 amount) public view virtual override returns (bool allowed) {
        if (balanceOf(from, tokenId) < amount) return false;
        if (!isUserAllowed(from) || !isUserAllowed(to)) return false;

        return true;
    }

    function isUserAllowed(address user) public view virtual override returns (bool allowed) {
        return isWhitelisted[user];
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {
        if (ids.length != values.length) {
            revert ERC1155InvalidArrayLength(ids.length, values.length);
        }

        for (uint256 i = 0; i < ids.length; ++i) {
            if (from != address(0) && to != address(0)) { // Transfer
                require(isTransferAllowed(from, to, ids[i], values[i]), TransferNotAllowed(from, to, ids[i], values[i]));
            }
        }

        if (from == address(0)) { // Mint
            require(isUserAllowed(to), UserNotAllowed(to));
        } else if (to == address(0)) { // Burn
            require(isUserAllowed(from), UserNotAllowed(from));
        }

        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, ERC1155, IERC165) returns (bool) {
        return interfaceId == type(IuRWA).interfaceId ||
               super.supportsInterface(interfaceId);
    }
}
```

## Security Considerations

*   **Access Control for `recall`:** The security of the mechanism chosen by the implementer to restrict access to the `recall` function is paramount. Unauthorized access could lead to asset theft. Secure patterns (multisig, timelocks) are highly recommended.
*   **Implementation Logic:** The security and correctness of the *implementation* behind `isUserAllowed` and `isTransferAllowed` are critical. Flaws in this logic could bypass intended transfer restrictions or incorrectly block valid transfers.
*   **Standard Contract Security:** Implementations MUST adhere to general smart contract security best practices (reentrancy guards where applicable, checks-effects-interactions, etc.).

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).