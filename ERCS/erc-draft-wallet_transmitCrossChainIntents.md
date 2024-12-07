---
title: wallet_transmitCrossChainIntents Method
description: Standard Cross-Chain Intent Parsing Method For EVM Wallet
author: ZeroKPunk (@ZeroKPunk), 0xbbPizza (0xbbPizza)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC # Only required for Standards Track. Otherwise, remove this field.
created: 2024-12-03
requires: 7683 # Only required when you reference an EIP in the `Specification` section. Otherwise, remove this field.
---

## Abstract

This proposal adds a wallet-namespaced method: `wallet_transmitCrossChainIntents`: providing a standard interface for parsing the users' cross-chain intentions between EVM compatible networks(eg. EVM Rollups). By integrating this RPC method into wallets like MetaMask, users can initiate, broadcast, and track cross-chain transactions with minimal effort, improving cross-chain interoperability and user experience.

## Motivation

Cross-chain transactions are currently complex and require users to interact with multiple blockchains manually. This often involves switching networks, signing multiple transactions, and relying on third-party tools (e.g., bridges or relayers). While EIP-7683 provides a standardized approach for cross-chain intents, wallets currently lack native support for such workflows, leading to:

A poor user experience due to complex processes.
A lack of standardized wallet interfaces for cross-chain intent execution.
Fragmented cross-chain tooling that hinders interoperability.

### Goals:

Introduce a standardized RPC method for wallets to natively support [EIP-7683](https://eips.ethereum.org/EIPS/eip-7683) cross-chain intents.
Simplify the user experience by abstracting cross-chain complexities.
Enhance the adoption of cross-chain standards and drive interoperability between chains.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

This proposal defines a new wallet RPC method: `wallet_transmitCrossChainIntents`

### `wallet_transmitCrossChainIntents`

#### Parameter

The `wallet_transmitCrossChainIntents` method's input contains several parameters, which is defined as follows:

| Parameter Name      | Type        | Required | Description                                                                                                                                            |
| ------------------- | ----------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `originChainId`     | `uint256`   | Yes      | The chain ID of the originating blockchain where the user initiates the intent.                                                                        |
| `destinationChains` | `uint256[]` | Yes      | A list of target chain IDs where the intent will be executed.无                                                                                        |
| `orderData`         | `bytes`     | Yes      | The serialized cross-chain intent data (in compliance with EIP-7683). This includes token details, amounts, destination chains, and optional calldata. |
| `options`           | `object`    | No       | Additional options for the transaction, such as preferred fillers, gas settings, or execution constraints.                                             |

#### Return Value

The method returns a JSON object containing information about the transaction(s):

### Example Calls

#### Example Request

User initiates a cross-chain intent from Ethereum (chain ID: 1) to Polygon (chain ID: 137) and Optimism (chain ID: 10):

```json
{
  "jsonrpc": "2.0",
  "method": "wallet_transmitCrossChainIntents",
  "params": {
    "originChainId": 1,
    "destinationChains": [137, 10],
    "orderData": "0xabcdef123456...",
    "options": {
      "preferredFiller": "0xFILLER_ADDRESS",
      "gasLimit": 500000,
      "priorityFee": "high"
    }
  },
  "id": 1
}
```

#### Example Response

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "hashes": [
      "0xabc123...", // Origin chain transaction hash
      "0xdef456...", // Destination chain 1 transaction hash
      "0xghi789..." // Destination chain 2 transaction hash
    ],
    "status": "pending"
  }
}
```

#### Error response if the wallet fails to sign the transaction:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32602,
    "message": "Failed to sign the transaction."
  }
}
```

### WorkFlow

#### 1. User Interaction:

- The user initiates a cross-chain intent by selecting the origin chain, destination chain(s), and inputting transaction parameters (e.g., tokens, amounts, calldata).

#### 2. Wallet Processing:

- The wallet generates the cross-chain order (e.g., GaslessCrossChainOrder or OnchainCrossChainOrder as per EIP-7683).
- If GaslessCrossChainOrder is used, the wallet signs the intent offline and broadcasts it to fillers.
- If OnchainCrossChainOrder is used, the wallet submits the order to the origin chain settlement contract.

#### 3.Broadcast and Tracking:

- The wallet broadcasts the transaction on the origin chain and optionally tracks its progress on the destination chains.
- Users can monitor the transaction status directly within the wallet.

## Rationale

### Why a Wallet-Level RPC Interface?

- **User-Friendly Abstraction**: Wallets are the primary interface for blockchain users. By simplifying cross-chain workflows within wallets, users can interact with multiple chains without switching networks or relying on third-party tools.

- **Drive Standardization**: A wallet-level RPC interface aligned with EIP-7683 ensures consistent cross-chain support across different wallets and protocols.

- **Encourage Ecosystem Growth**: By natively integrating cross-chain standards, wallets can drive adoption of interoperable protocols and incentivize developers to build on these standards.

### Why JSON-RPC?

JSON-RPC is the de facto standard for wallet communication. Defining this interface as a JSON-RPC method ensures compatibility with existing wallet ecosystems like MetaMask while allowing easy integration into dApps and protocols.

## Backwards Compatibility

This proposal does not affect existing wallet functionality. It introduces a new, optional JSON-RPC method that is compatible with existing wallets and dApps.

## Test Cases

### Single Destination Chain:

A user submits a cross-chain intent with one destination chain. Verify that the wallet correctly generates the order and broadcasts it.

### Multiple Destination Chains:

A user submits a cross-chain intent with multiple destination chains. Verify that the wallet correctly tracks and returns transaction hashes for all chains.

### Invalid Parameters:

Test the wallet's response to invalid inputs (e.g., unsupported destination chains, malformed order data).

### Filler Network Interactions:

Verify that the wallet can interact with filler networks to broadcast gasless orders and resolve intents.

## Reference Implementation

<!--
  This section is optional.

  The Reference Implementation section should include a minimal implementation that assists in understanding or implementing this specification. It should not include project build files. The reference implementation is not a replacement for the Specification section, and the proposal should still be understandable without it.
  If the reference implementation is too large to reasonably be included inline, then consider adding it as one or more files in `../assets/eip-####/`. External links will not be allowed.

  TODO: Remove this comment before submitting
-->

## Security Considerations

### User Consent

- The wallet must prompt users to review and approve all transaction parameters before signing or broadcasting.

### Filler Trust

- Users should be warned of potential risks when interacting with unverified fillers. Wallets may implement reputation systems or filler whitelists for added security.

### Cross-Chain Failures:

- If a transaction fails on one of the destination chains, the wallet should provide clear error messages and rollback options (if applicable).

### Replay Protection:

- The wallet must ensure that cross-chain intents include nonces or other mechanisms to prevent replay attacks across chains.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
