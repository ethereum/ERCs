---
eip: ____
title: Solana storage handler for CCIP-Write
description: Cross-chain write deferral protocol incorporating storage handler for Solana
author: Avneet Singh (@sshmatrix), 0xc0de4c0ffee (@0xc0de4c0ffee)
discussions-to: https://ethereum-magicians.org/t/_/_
status: Draft
type: Standards Track
category: ERC
created: 2024-04-18
---

## Abstract
The following standard is an extension to the cross-chain write deferral protocol introducing storage handler for Solana.

## Motivation
[EIP-5559](./eip-5559) introduces two external handlers for deferring write operations to L2s and databases. This document extends that specification by introducing a third storage handler targeting Solana as the storage provider. 

L2s and databases both have centralising catalysts in their stack. For L2s, this centralising agent is the shared security with Ethereum mainnet. In case of databases, the centralising agent is trivial; it is the physical server hosting the database. In light of this, a storage provider that relies on its own independent consensus mechanism is preferred. This specification instructs how the clients should treat write deferrals made to the Solana handler.

Solana is a cheap L1 solution that is fairly popular among Ethereum community and is widely supported alongside Ethereum by almost all wallet providers. There are several chain-agnostic protocols on Ethereum which could benefit from direct access to Solana blockspace; ENS is one such example where it can serve users of Solana via its chain-agnostic properties while also using Solana's own native storage. This development will surely encourage more cross-chain functionalities between Ethereum and Solana at core. 

## Specification
A Solana storage handler `StorageHandledBySolana()` requires the hex-encoded `programId` and the manager `account` on the Solana blockchain. `programId` is equivalent to a contract address on Solana while `account` is the manager wallet on Solana handling write operations on behalf of `msg.sender`. Since Solana natively uses `base58` encoding in its virtual machine setup, `programId` values are hex-encoded according to EIP-2308 for usage on Ethereum. These hex-encoded values must be decoded to `base58` for usage on Solana. 

```solidity
// Revert handling Solana storage handler
error StorageHandledBySolana(
    bytes32 programId,
    bytes32 account,
    bytes32 sender
);

// Generic function in a contract
function setValue(
    bytes32 node,
    bytes32 key,
    bytes32 value
) external {
    // Get metadata from on-chain sources
    (
        bytes32 programId, // Program (= contract) address on Solana; hex-encoded
        bytes32 account // Manager account on Solana; hex-encoded
    ) = getMetadata(node); // Arbitrary code
    // programId = 0x37868885bbaf236c5d2e7a38952f709e796a1c99d6c9d142a1a41755d7660de3
    // account = 0xe853e0dcc1e57656bd760325679ea960d958a0a704274a5a12330208ba0f428f
    // Parse sender as bytes32 type
    bytes32 sender = bytes32(msg.sender)
    // Defer write call to L2 handler
    revert StorageHandledBySolana( 
        programId,
        account,
        sender
    );
};
```

Clients implementing the Solana handler must call the Solana `programId` using a Solana wallet that is connected to `account` using the precise calldata that it originally received. 

```js
/* Pseudo-code to write to Solana program (= contract) */
// Instantiate program interface on Solana
const program = new program(programId, rpcProvider);
// Connect to Solana wallet
const wallet = useWallet();
// Cast sender to base58
const sender = base58(sender);
// Call the Solana program using connected wallet with initial calldata
// [!] Only approved manager in the Solana program should call
if (wallet.publicKey === account === program.isManagerFor(account, sender)) {
    await program(wallet).setValue(node, key, value);
}
```

In the above example, `programId`, `account` and `msg.sender` are `base58` encoded. Solana handler requires a one-time transaction on Solana during initial setup for each user to set the local manager. This call in form of pseudo-code is simply 

```js 
/* Initial one-time setup */
// Cast sender to base58
const sender = base58(sender);
// Set manager on-chain
await program(wallet).setManagerFor(account, sender)
```

## Backwards Compatibility
None.

## Security Considerations
None.

## Copyright
Copyright and related rights waived via [`CC0`](../LICENSE.md).
