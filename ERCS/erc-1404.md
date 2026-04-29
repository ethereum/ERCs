---
eip: 1404
title: Simple Restricted Token
description: A token interface extension for enforcing transfer restrictions with machine-readable status codes.
author: Ron Gierlach (@rongierlach), James Poole (@pooleja), Mason Borda (@masonicgit), Lawson Baker (@lwsnbaker), Ryan Sauge (@rya-sge)
discussions-to: https://ethereum-magicians.org/t/erc-1404-simple-restricted-token-standard/1405
status: Draft
type: Standards Track
category: ERC
created: 2018-07-27
requires: 20
---

## Abstract

Current token standards have provided the community with a platform on which to develop a decentralized economy that is focused on building Ethereum applications for the real world. As these applications mature and face consumer adoption, they begin to interface with corporate governance requirements as well as regulations. They must not only be able to meet corporate and regulatory requirements but must also be able to integrate with technology platforms underpinning their associated businesses. What follows is a simple and extendable standard that seeks to ease the burden of integration for wallets, exchanges, and issuers.

## Motivation

Token issuers need a way to restrict transfers of [ERC-20](./eip-20.md) tokens to be compliant with securities laws and other contractual obligations. Current implementations do not address these requirements.

A few examples:

- Enforcing Token Lock-Up Periods
- Enforcing Passed AML/KYC Checks
- Private Real-Estate Investment Trusts
- Delaware General Corporations Law Shares

Furthermore, standards adoption amongst token issuers has the potential to evolve into a dynamic and interoperable landscape of automated compliance.

The following design gives greater freedom / upgradability to token issuers and simultaneously decreases the burden of integration for developers and exchanges.

Additionally, this standard provides a pattern by which human-readable messages may be returned when token transfers are reverted. Transparency as to _why_ a token's transfer was reverted is of equal importance to the successful enforcement of the transfer restriction itself.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHOULD", and "MAY" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

[ERC-1404](./eip-1404.md) extends [ERC-20](./eip-20.md). All [ERC-20](./eip-20.md) functions, events, and semantics remain unchanged; compliant tokens MUST additionally implement the following methods.

### Methods

- #### `detectTransferRestriction(address,address,uint256)`

  Returns a restriction code for the proposed transfer of `value` tokens from `from` to `to`, or `0` if the transfer is unrestricted. The restriction logic is defined by the issuer.

  MUST be called inside the token's `transfer` and `transferFrom` methods. When a non-zero code is returned, the transfer SHOULD fail consistently with [ERC-20](./eip-20.md) expectations; reverting is RECOMMENDED. Implementations MAY return `false` instead.

  ```solidity
  function detectTransferRestriction(address from, address to, uint256 value) external view returns (uint8);
  ```

- #### `messageForTransferRestriction(uint8)`

  Returns the human-readable message corresponding to `restrictionCode`.

  ```solidity
  function messageForTransferRestriction(uint8 restrictionCode) external view returns (string memory);
  ```

### Additional Specifications

- Implementations MAY add [ERC-165](./eip-165.md) interface detection support for [ERC-1404](./eip-1404.md). 

- Implementations MAY apply analogous restriction checks to token supply-changing operations (for example, mint and burn). Such checks are optional and are not required for [ERC-1404](./eip-1404.md) compliance.

- The [ERC-165](./eip-165.md) interface identifier for [ERC-1404](./eip-1404.md) is `0xab84a5c8`.

- Compliance-related contracts MAY implement [ERC-1404](./eip-1404.md) restriction interfaces without directly implementing the full [ERC-20](./eip-20.md) token interface. In such cases, this standard only defines the behavior of `detectTransferRestriction` and `messageForTransferRestriction`.

- Restriction checks SHOULD be deterministic for the same state and inputs, and SHOULD avoid reliance on manipulable off-chain data during execution.

- The string returned by `messageForTransferRestriction` SHOULD NOT be treated as an authorization primitive.

- Implementations SHOULD define and manage restriction code allocation carefully, because `uint8` limits the available code space to 256 values (`0` to `255`).

## Rationale

The standard proposes two functions on top of the [ERC-20](./eip-20.md) standard. The rationale for each is described below.

1. `detectTransferRestriction` - This function is where an issuer enforces the restriction logic of their token transfers. Some examples of this might include, checking if the token recipient is whitelisted, checking if a sender's tokens are frozen in a lock-up period, etc. Because implementation is up to the issuer, this function serves solely to standardize _where_ execution of such logic should be initiated. Additionally, 3rd parties may publicly call this function to check the expected outcome of a transfer. Because this function returns a `uint8` code rather than a boolean or just reverting, it allows the function caller to know the reason why a transfer might fail and report this to relevant counterparties.
2. `messageForTransferRestriction` - This function is effectively an accessor for the "message", a human-readable explanation as to _why_ a transaction is restricted. By standardizing message look-ups, we empower user interface builders to effectively report errors to users.
3. Optional [ERC-165](./eip-165.md) support - Implementations may expose [ERC-165](./eip-165.md) support for interface discovery.

## Backwards Compatibility

By design [ERC-1404](./eip-1404.md) is interface-compatible with [ERC-20](./eip-20.md), while transfer restrictions may introduce behavioral differences.

## Test Cases

The following table-driven cases SHOULD be verified for every implementation. The examples use a whitelist-based policy (code `0` = no restriction, `1` = sender not whitelisted, `2` = recipient not whitelisted) to keep the expected values concrete, but the same structure applies to any issuer-defined policy.

### `detectTransferRestriction`

| Scenario | Expected return |
|---|---|
| Both `from` and `to` satisfy the policy | `0` |
| `from` violates the policy | Non-zero restriction code |
| `to` violates the policy; `from` does not | Non-zero restriction code distinct from the sender case |
| Both `from` and `to` violate the policy | Non-zero code; the specific code returned depends on the implementation's evaluation order |

### `messageForTransferRestriction`

| Input | Expected output |
|---|---|
| `0` | A deterministic human-readable string indicating no restriction (e.g., `"No restriction"`) |
| Any known restriction code | The corresponding deterministic human-readable message |

### Transfer enforcement

| Scenario | Expected behavior for `transfer` and `transferFrom` |
|---|---|
| `detectTransferRestriction` returns `0` | Transfer succeeds |
| `detectTransferRestriction` returns a non-zero code | Transfer reverts (preferred) or returns `false` |

### ERC-165 interface detection (optional)

For implementations that expose [ERC-165](./eip-165.md) support:

| Input to `supportsInterface` | Expected return |
|---|---|
| `0xab84a5c8` ([ERC-1404](./eip-1404.md) interface identifier) | `true` |
| `0x01ffc9a7` ([ERC-165](./eip-165.md) interface identifier) | `true` |
| Any unrecognized selector | `false` |

A complete Foundry test suite covering all the cases above is available at [`test/ERC1404.t.sol`](../assets/eip-1404/test/ERC1404.t.sol).

## Reference Implementation

A complete reference implementation built with Foundry and OpenZeppelin Contracts v5 is provided in the assets folder:

| File | Description |
|------|-------------|
| [`src/IERC1404.sol`](../assets/eip-1404/src/IERC1404.sol) | Interface — extends `IERC20` with the two [ERC-1404](./eip-1404.md) functions |
| [`src/ERC1404.sol`](../assets/eip-1404/src/ERC1404.sol) | Concrete implementation — whitelist-based, with [ERC-165](./eip-165.md) support |
| [`test/ERC1404.t.sol`](../assets/eip-1404/test/ERC1404.t.sol) | Foundry test suite covering all mandatory behaviors |

The concrete implementation applies a whitelist policy and defines the following restriction codes. Note that codes `1` and `2` are specific to this implementation; [ERC-1404](./eip-1404.md) does not standardize restriction code values beyond reserving `0` as the "no restriction" sentinel.

| Code | Constant | Message |
|------|----------|---------|
| `0` | `TRANSFER_OK` | `"No restriction"` |
| `1` | `SENDER_NOT_WHITELISTED` | `"Sender not whitelisted"` |
| `2` | `RECIPIENT_NOT_WHITELISTED` | `"Recipient not whitelisted"` |

Notable design decisions in this implementation:

- `transfer` and `transferFrom` revert with a typed `TransferRestricted(uint8 code, string message)` error on non-zero codes, rather than returning `false`.
- `detectTransferRestriction` checks the sender before the recipient, so callers can distinguish the two failure cases with a single view call before submitting a transaction.
- `supportsInterface(0xab84a5c8)` returns `true`, enabling on-chain interface discovery.
- Mint and burn operations apply analogous restriction checks, as permitted by the specification.
- Implementations that also conform to [ERC-7943](./eip-7943.md) will likely revert with that standard's typed errors rather than `TransferRestricted(uint8 code, string message)`. Those errors do not carry a restriction code or human-readable message.

This example is provided for educational purposes only and has not been audited. Do not use in production without a thorough independent security review.

## Security Considerations

- Implementations are expected to encode policy in `detectTransferRestriction`, so mistakes in this logic can block valid transfers or allow restricted transfers.

- Restriction checks that are not deterministic for the same state and inputs can create inconsistent behavior, and reliance on manipulable off-chain data can undermine enforcement.

- Returning machine-readable codes improves integration, but the string returned by `messageForTransferRestriction` remains informational and is not an authorization primitive.

- Using `uint8` for restriction codes limits the available code space to 256 values (`0` to `255`), which can create ambiguity if code allocation is not managed carefully.

- [ERC-1404](./eip-1404.md) interface support alone is not evidence that a contract implements full [ERC-20](./eip-20.md) transfer behavior; a compliance-focused contract can expose [ERC-1404](./eip-1404.md) restriction interfaces and interface support while omitting parts of the [ERC-20](./eip-20.md) interface.

- The original [ERC-1404](./eip-1404.md) text did not require [ERC-165](./eip-165.md) signaling. Therefore, older implementations may still implement [ERC-1404](./eip-1404.md) while not returning `true` for the [ERC-165](./eip-165.md) interface identifier `0xab84a5c8`.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
