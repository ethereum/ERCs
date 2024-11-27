---
title: Chain-specific addresses using ENS
description: A unified chain-specific address format that allows specifying the account as well as the chain on which that account intends to transact. 
author: Sam Kaufman (@SampkaML), Marco Stronati (@paracetamolo), Yuliya Alexiev (@yuliyaalexiev), Jeff Lau (@jefflau), Sam Wilson (@samwilsn), Vitalik Buterin (@vbuterin)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2024-11-27
requires: 55, 137, 155, 7785
---

## Abstract

This proposal builds off of ERC-7785 (on-chain configs) to provide a standard and human-readable format for chain-specific L2 addresses:
- A unified format for accounts that specifies, together with the address, the chain where the address lives.
- The use of human-readable chain names and how they can be resolved to chain identifiers using ENS on L1.
- The use of human-readable account names and how they can be resolved to addresses using ENS on L2.

## Motivation

The current Ethereum address landscape is leading to an ecosystem that will have hundreds and eventually thousands of L2s that use the same address format as Ethereum mainnet. This means an address by itself is not enough information to know which chain the address is related to. This can be problematic if funds are sent to an unreachable address on the incorrect chain. From the user account it should be possible to obtain the right chain identifier (chainID) to include in a transaction. 

The mapping from chain names to identifiers has, since EIP-155, been maintained off chain using a centralized list. This solution has two main shortcomings:
 - It does not scale with the growing number of L2s.
 - The list maintainer is a trusted centralized entity.

Instead of using chain identifiers, which are not human readable, the address could be extended with a human-readable chain name, which can then be resolved to a chain identifier.
The mapping from chain names to identifiers can be resolved off-chain using existing centralized lists such as [Ethereum Lists](https://github.com/ethereum-lists/chains) or on-chain using ENS (see EIP-7785).

In the same spirit, the address could be a human-readable name as well, which is already a use case for ENS. However it would be desirable if the address name could be registered on a L2.

Desired properties:
- a unified format to represent any address on L1 or L2
- the ability to use chain names in addition to identifiers
- the chain portion can be a domain name, or just the suffix for a "base chain" (eg. `eth`, `myfavoriterollup.eth`, `sepolia`, `my_l3.base.superchain.eth`)
- the address portion can be either the appropriate type of address for the chain (0x... for EVM chains, otherwise eg. for starknet something else), or a domain name (ENS or other)
- the ability to resolve ENS names on the L2
- the address portion and the chain portion should be resolved separately 
- checksums are MANDATORY
- checksum hash goes over the entire address, so users can't just replace a component and expect it to stay valid


## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Format

Valid addresses MUST include the identifier of the chain they belong to.

```
L1-TLD ::= eth | sepolia | …
chain_id ::= 0x[a-fA-F0-9]{1,64}
address ::= 0x[a-fA-F0-9]{40}
chain ::= <chain_id> | <L1-TLD> | <ens-name> . <L1-TLD>
user ::= <address> | <ens-subdomain>
account ::= <user>@<chain>
```

Note the difference between `ens-name`, which is a full ENS name, and `ens-subdomain` that is just a segment of a name between dots. E.g. `user.app.eth` is a name, `user` and `app` are subdomains.

A few examples below. 

Option 1: using @ to separate address and chain
```
Mainnet
- 0x12345...6789@0x1
- 0x12345...6789@eth
- alice.eth@eth

Testnet (Sepolia)
- 0x12345...6789@0xaa36a7
- 0x12345...6789@sepolia
- alice.eth@sepolia

Rollup
- 0x12345...6789@chainId
- 0x12345...6789@arbitrum.eth
- alice.eth@arbitrum.eth

Rollup Sepolia
- 0x12345...6789@arbitrum.sepolia

My ENS name is registered on rollup1, but I want to receive funds on rollup2
- alice.rollup1.eth@rollup2.eth
```

Option 2: using : instead of @ 
```
Mainnet
- 0x12345...6789:0x1
- 0x12345...6789:eth
- alice.eth:eth

Testnet (Sepolia)
- 0x12345...6789:0xaa36a7
- 0x12345...6789:sepolia
- alice.eth:sepolia

Rollup
- 0x12345...6789:chainId
- 0x12345...6789:arbitrum.eth
- alice.eth:arbitrum.eth

Rollup Sepolia
- 0x12345...6789:arbitrum.sepolia

My ENS name is registered on rollup1, but I want to receive funds on rollup2
- alice.rollup1.eth:rollup2.eth
```
### CHECKSUM
TODO: add more explanation here

Two desired properties:
1) checksums are MANDATORY
2) checksum hash goes over the entire address, so users can't just go and replace a component and expect it to stay valid


### A special case for ENS resolution

Any ENS name today can be resolved to a chain identifier as in [ENSIP-11](https://docs.ens.domains/ensip/11) or to an address as in [ENSIP-9](https://docs.ens.domains/ensip/9).
We could imagine having a name `user.eth` that points to a record of the form `{address ; chain_id}`. Given such an address a wallet can verify it resolves to a valid account.
The advantage of this format is that it is very flexible and can accommodate a number of use cases, however it can also lead to confusion for users because a name does not necessarily resolve to a valid account. The same `user.eth` could lead to a website, a NFT or multiple addresses.

The resolution of a `address@chain` on the contrary, imposes that the left-hand resolves to an address and the right-hand to a chain identifier.

When given a `user@rollup.eth`, the wallet can resolve `rollup.eth` to get a chain identifier and `user.rollup.eth` to get an address. In any other case it fails.

### L2 resolution

In case an address is not registered on L1, but only on a L2, the resolution can be processed using [CCIP-Read EIP](https://eips.ethereum.org/EIPS/eip-3668) and [ENSIP-10 Wildcard Resolution](https://docs.ens.domains/ensip/10).

In the previous example `user@rollup.eth`, `user` would not be registered on L1.
In this case the wallet can resolve `rollup.eth` to get a chain identifier as before and when attempting to resolve `user.rollup.eth` to get an address, it would fail and be redirected to the L2 gateway. Any answer from the gateway needs to be verified as explained in the EIP.

#### Note: avoiding the http gateway

In order to avoid contacting an external http gateway, we could define the gateway to be a ENS contract on the L2. In this way a wallet operator would need to only rely on a node following the L1 and a node following the L2.

### L1 resolution

Ethereum Mainnet and its testnets can be resolved to their corresponding chain identifiers using a [centralized list](https://chainid.network/chains.json), which remains unchanged from how it works today. Other L1 registrations are out of scope for this EIP.

Mapping:
```
L1-TLD -> {L1_chain_id : chain_id; L1_ens_address : address;}
```
Example:
```
eth     -> {L1_chain_id : 0x1;      L1_ens_address : <ENS-address-on-mainnet>}
sepolia -> {L1_chain_id : 0xaa36a7; L1_ens_address : <ENS-address-on-sepolia>}
```

### Note: clashes of L1 and TLD

In the above proposal the ENS TLD and chain name coincide which may be confusing or incorrect in some cases. A more explicit approach could be to have an additional suffix for the chain name.
Example:
```
name.eth.mainnet -> {L1_chain_id : 0x1;      L1_ens_address : <ENS-address-on-mainnet>}
name.eth.sepolia -> {L1_chain_id : 0xaa36a7; L1_ens_address : <ENS-address-on-sepolia>}
```
### Note: default fallbacks

If a user receives a legacy address without chain name, the wallet can:
Refuse the address (safest)
Default to Mainnet (unambiguous)
Dynamically default to same chainID as sender (ambiguous and context-dependent but probably compatible with current use-cases)

### Advanced patterns

The `@` syntax described in this EIP is a restricted resolution case for ENS names whose main purpose it to be user-friendly. We can however support more advanced pattern in ENS.

### Supported today

For example a user might configure its name with multiple address such as
```
rollup1.user.eth -> {address : address; chain_id : chain_id} 
rollup2.user.eth -> {address : address; chain_id : chain_id} 
```
Given `user.eth` as recipient a wallet could prompt the user to select a destination chain.
Otherwise the user can be more explicit and give as recipient `rollup1.user.eth`.

### Note: Speculative

Alternatively we could store multiple addressed under the same domain as
```
user.eth -> { rollup1 : address * chain_id ; 
              rollup2 : address * chain_id } 
```
if a syntax to access ENS records could be standardized, the user could be asked to be paid at
`user.eth/rollup1`

### URL compatibility

It would be very desirable to maintain compatibility with the syntax defined by the [Uniform Resource Identifier](https://www.rfc-editor.org/rfc/rfc3986) standard, so that in the future a schema could be supported.

Example of a link to require a payment of 10 tokens to the `user` address living in `rollup`:
```
evm://user@rollup.eth.mainnet/transfer?amount=10
```

### Resolution step-by-step example

1. Check the type of `chain`
   - if typeof(chain) == “ENS name”: go to step 2
   - if typeof(chain) == “L1 TLD”: go to step 3
   - if typeof(chain) == “chainId”: go to step 4
2. Resolve the ENS name's `text(chainENSName, ‘chain_id’)` record using [ENSIP-10](https://docs.ens.domains/ensip/10) and skip to step 4
3. Use an offline mapping of `TLD => chainId` to find the relevant chainId.
4. Check if `account` is an ENS name, if not end the resolution process.
5. Generate the cointype using the chainId via ENSIP-11: `coinType = 0x80000000 | chainId`
6. Verify the bridge address by resolving `[chainId].id.eth`'s `name(name, 60)` record using [ENSIP-10](https://docs.ens.domains/ensip/10)
7. Check if this name matches the ENS name representing the chain, continue otherwise consider the resolution a failure and error.
8. Resolve the ENS name's `addr(name, cointype)`

## Rationale

#### Using @ vs : for the separator 

The colon (`:`) may be a reasonable choice for separator because it is not an allowed character in ENS names, it is familiar (eg. IPv6), and isn't as overloaded as the `@` symbol.

The `@` symbol may be a reasonable choice as it is arguably more human-readable, is already a common choice for addresses, and finds use in email and several federated communication protocols. The English reading (foo-**AT**-example-DOT-com) is natural and implies a hierarchy between the left and the right components.

## Backwards Compatibility

No backward compatibility issues found.

## Security Considerations

TODO

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
