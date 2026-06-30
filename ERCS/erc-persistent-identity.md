---
eip: TBD
title: Persistent Identity Token
description: A standard for persistent, human-readable identity tokens mapped to EVM addresses with support for resolution, lifecycle management, URL records, and policy-controlled governance.
author: Idon Liu (@nftprof)
discussions-to: https://ethereum-magicians.org/t/erc-persistent-identity-token-pip-on-chain-identity-with-bind-to-lock-model/28641
status: Draft
type: Standards Track
category: ERC
created: 2026-04-30
requires: 721, 165
---

## Abstract

This ERC defines a standard interface for **Persistent Identity Tokens** — ERC-721 tokens that represent human-readable, on-chain identities bound to EVM addresses. A Persistent Identity Token can represent a username, account identity, application handle, game identity, brand identity, or agent identity.

The standard introduces three interface layers:

1. **Identity Layer** (`IPersistentIdentity`) — name registration, address binding, URL records, and soulbound locking
2. **Resolution Layer** (`IPersistentIdentityResolver`) — convenience functions for resolving names to addresses and identity records
3. **Policy Layer** (`IPersistentIdentityPolicy`) — governance actions including pricing, renaming, unbinding, and namespace rules

## Motivation

Web2 usernames are platform-controlled database entries. They are not owned by users, cannot interoperate across applications, and are vulnerable to deletion, impersonation, recycling, and bot creation.

Web3 addresses are user-owned but not human-readable. They are difficult to use as social or login identities. Existing on-chain naming services (e.g., ENS) provide name resolution but do not address identity persistence, lifecycle governance, login system compatibility, or economic spam resistance.

This standard introduces a bridge between both models by defining persistent on-chain identity objects that:

- Map human-readable names to EVM addresses
- Become soulbound when bound (preventing unauthorized transfers of active identities)
- Support governance-controlled unbinding for legitimate transfers
- Store URL records on-chain for canonical forwarding
- Enable applications to use on-chain identities as login credentials
- Provide economic spam resistance through configurable pricing
- Support namespace-specific policy rules without modifying the core identity interface

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

### Identity Layer (`IPersistentIdentity`)

A compliant contract MUST implement `IPersistentIdentity` and MUST be an ERC-721 token.

#### Name Registration

- Each token MUST be associated with exactly one human-readable name string.
- Each name string MUST map to at most one token ID.
- Names MUST be unique within a namespace (contract instance).

```solidity
function nameRegistered(string calldata name) external view returns (bool);
function tokenOfName(string calldata name) external view returns (uint256);
function nameOf(uint256 tokenId) external view returns (string memory);
```

#### Address Binding

- Token owners MAY bind their token to an EVM address.
- The `bind` function MUST set the bound address to `msg.sender`.
- Binding MUST lock the token, preventing transfers.
- A bound token MUST NOT be transferable until explicitly unbound by the policy layer.

```solidity
function boundAddress(uint256 tokenId) external view returns (address);
function isBound(uint256 tokenId) external view returns (bool);
function bind(uint256 tokenId) external;
```

#### URL Record

- Bound tokens MAY have an associated URL record.
- The `setUrlRecord` function MUST require the token to be bound.
- URL records MUST be clearable by the policy layer on unbind.

```solidity
function urlRecord(uint256 tokenId) external view returns (string memory);
function setUrlRecord(uint256 tokenId, string calldata url) external;
```

#### Tier Classification

- Tokens MAY have a tier classification (e.g., Reserved, Standard, Basic).
- Tier determines tradability rules. Reserved tier tokens MAY be permanently non-transferable.

```solidity
function tierOf(uint256 tokenId) external view returns (Tier);
```

#### Transfer Restrictions

- If a token is bound (`isBound` returns true), the `_update` function (ERC-721 transfer hook) MUST revert.
- Reserved tier tokens MUST NOT be transferable unless explicitly unlocked by the contract owner.
- When a token is successfully transferred, the bound address and URL record MUST be cleared.

### Resolution Layer (`IPersistentIdentityResolver`)

A compliant contract SHOULD implement `IPersistentIdentityResolver` for convenience.

```solidity
function resolveAddress(string calldata name) external view returns (address);
function resolveUrl(string calldata name) external view returns (string memory);
function resolveIdentity(string calldata name) external view returns (
    uint256 tokenId, address owner, address boundAddr, bool bound, string memory url, uint8 tier
);
```

### Policy Layer (`IPersistentIdentityPolicy`)

A compliant contract MAY implement `IPersistentIdentityPolicy` for governance.

- `unbind` MUST clear the bound address, URL record, and lock status.
- `rename` MUST update the name-to-token and token-to-name mappings.
- `purchaseMint` MUST verify `msg.value` matches the on-chain price and mint to `msg.sender`.

### Events

All state changes MUST emit the corresponding events defined in the interfaces.

### Metadata

Token metadata returned by `tokenURI` SHOULD follow the standard ERC-721 metadata JSON schema and SHOULD include:

- `name`: The human-readable identity name
- `description`: Identity description including tier
- `image`: Visual representation of the identity
- `attributes`: Array including at minimum `Name`, `Tier`, and `Score` (if applicable)

Implementations MAY include additional classification metadata (e.g., AI-driven rarity signals, cultural significance indicators, domain availability data) as extended attributes.

## Rationale

### Separation of Identity and Policy

The standard separates the identity layer from the policy layer. The identity layer defines the minimum interface for persistent identity objects. The policy layer is namespace-specific and may include pricing, reclaim rules, reserved names, moderator controls, transferability rules, and dispute resolution.

This separation allows different applications and communities to adopt the same identity standard while applying their own governance models.

### Bind-to-Lock Model

Unlike traditional SBTs (ERC-5192) which are non-transferable from mint, Persistent Identity Tokens are transferable when unbound. This enables a secondary market for unclaimed identities while protecting active identities from unauthorized transfer.

The bind-to-lock model provides:
- Users can trade unbound names freely
- Once bound, the identity cannot be sold from under the user
- Governance-controlled unbinding provides a safety mechanism

### Economic Spam Resistance

By supporting on-chain pricing through the policy layer, namespace operators can introduce controlled economic friction. This provides natural bot resistance without relying solely on centralized moderation.

### URL Record vs DNS

On-chain URL records provide a censorship-resistant forwarding mechanism. Unlike traditional DNS forwarding, the identity record does not depend on a DNS registrar. Access layers (websites, wallets, apps, resolver APIs) read from the on-chain source of truth.

## Backwards Compatibility

This standard is compatible with:

- **ERC-721**: Persistent Identity Tokens are valid ERC-721 tokens.
- **ERC-165**: Implementations SHOULD register support for `IPersistentIdentity` via ERC-165.
- **ERC-5192**: The bind-to-lock behavior is philosophically related but distinct. ERC-5192 defines permanently non-transferable tokens; this standard defines conditionally non-transferable tokens based on binding state.
- **ENS**: This standard operates at the identity/username layer rather than the naming/DNS layer. Implementations MAY coexist with ENS.
- **ERC-6551**: Token Bound Accounts are complementary. A Persistent Identity Token MAY have an associated TBA for agent execution or wallet capabilities.
- **ERC-4337**: Account abstraction is compatible. Persistent Identity resolution can be used in smart account contexts.

## Security Considerations

Implementers should consider:

- **Impersonation risk**: Names are first-come-first-serve within a namespace. Policy layers SHOULD implement reserved name lists and moderation capabilities.
- **Premium name disputes**: Governance rename capability provides a mechanism for resolving trademark and IP disputes.
- **Moderator abuse**: Unbind and rename capabilities should be restricted to clearly defined governance roles with transparent event logging.
- **Private key compromise**: If a user's key is compromised, the bound identity cannot be transferred (protecting the identity), but the attacker could unbind if they have governance access.
- **Resolver poisoning**: External resolvers should validate on-chain data directly rather than relying on cached intermediaries.
- **Malicious URL forwarding**: Applications displaying URL records should warn users before redirecting to external URLs.
- **Bot registration**: Economic pricing through the policy layer provides spam resistance. Implementations SHOULD enforce minimum pricing for all registrations.
- **Namespace squatting**: Policy layers SHOULD implement mechanisms to prevent or mitigate squatting of culturally significant names.

## Reference Implementation

PEG ID at [id.peg.gg](https://id.peg.gg) is the first reference implementation of the Persistent Identity Protocol, deployed on Pentagon Chain (chain ID 3344) at `0xf97EB9f8293D1FD5587a809Eb74518c300738d07`.

The reference implementation includes:
- Full `IPersistentIdentity` compliance
- Policy layer with role-based access (Owner, Moderator)
- Three-tier classification system (Reserved/SBT, Standard, Basic)
- On-chain pricing with AI-driven classification
- URL forwarding with on-chain records
- Login system integration with existing Web2 authentication
- Metadata API with dynamic SVG generation

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
