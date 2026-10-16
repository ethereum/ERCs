---
title: Cross-Chain Client Gateway for CCIP-Read
description: An extension of CCIP-Read where the client itself performs a cross-chain read named by an x-chain URL
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/
status: Draft
type: Standards Track
category: ERC
created: 2026-10-16
requires: 3668, 7930
---

## Abstract

This ERC extends [ERC-3668](./eip-3668.md) CCIP-Read with a URL scheme, `x-chain`, that names a contract on a specific chain using an [ERC-7930](./eip-7930.md) Interoperable Address. When a contract reverts with `OffchainLookup` and the URL list contains an `x-chain` URL, a client that supports this ERC performs the read itself on the named chain, in place of an HTTP gateway, and passes the result to the callback exactly as `eth_call` returns it. A contract can include a `data:` URL after the `x-chain` URL so that a client that does not support this ERC falls through to it and delivers the single byte `0xff` to the callback, signaling that the client is unaware of this ERC.

## Motivation

[ERC-3668](./eip-3668.md) lets a contract defer a read to an offchain gateway, and in practice many gateways do nothing more than call a contract on another chain and relay the answer. Every such deployment requires an HTTP service that someone must run, pay for, and keep available, and the client must trust its availability even when the client already operates RPC connections to the destination chain. This ERC removes the middleman for that case. The client is the gateway, the contract states only which chain and contract to read, and the read inherits whatever RPC trust the client already has. The design goal is that the result is safe from the client's perspective. The client answers using its own trusted RPC endpoints and no third party enters the path, which is why the only fallback this ERC defines is a `data:` URL that the client resolves locally.

A second problem is discoverability. A contract cannot ask the client whether it supports a new URL scheme. This ERC uses the existing ERC-3668 fallback behavior as the signal. Clients that support this ERC answer from the named chain and try no other URL. Clients that do not support it skip the unknown scheme and reach the next URL, so a `data:` URL returning `0xff` tells the callback that the client is unaware, and the contract can act on that, for example by reverting with a clear error.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### The x-chain URL

An `x-chain` URL has the following form.

```
x-chain:0x<interoperable-address>[?block=<block>]
```

`<interoperable-address>` is the lowercase hexadecimal encoding of a version 1 [ERC-7930](./eip-7930.md) Interoperable Address containing both a chain reference and a target address. The `AddressLength` field MUST NOT be zero. The hexadecimal string MUST be lowercase and MUST contain no bytes beyond the end of the Interoperable Address.

For example, the following URL names the contract `0x833589fcd6edb6e08f4c7c32d4f71b54bda02913` on Base, chain id 8453.

```
x-chain:0x0001000002210514833589fcd6edb6e08f4c7c32d4f71b54bda02913
```

A URL that is not well formed under this section is unsupported. A client that supports this ERC handles an unsupported `x-chain` URL as defined under Client behavior.

#### The block parameter

The OPTIONAL `block` query parameter selects the block at which the call is made. The following values are defined.

- `latest`. The latest block. This is the default when the parameter is absent.
- `safe`. The safe block.
- `finalized`. The finalized block.
- A `0x`-prefixed hexadecimal block number. The call is made at exactly that block.
- `latest-N`, where `N` is a decimal count of blocks. The client reads the head block number once, subtracts `N`, and makes the call at exactly that number. `latest-0` equals the head block.

If `N` is larger than the head block number, or the client cannot serve the selected block, for example on a pruned node, the call MUST fail. The client MUST NOT substitute another block. A `block` value not matching one of the forms above makes the URL unsupported.

The callback does not learn which block was used, because the result is identical to the result of `eth_call`. A contract that needs the block number MUST have the remote function return it.

### Contract behavior

A contract requests a cross-chain read by reverting with the `OffchainLookup` error defined in [ERC-3668](./eip-3668.md), with the `x-chain` URL in `urls` and with `callData` set to the plain call data for the target contract. No wrapping or envelope is applied to `callData`.

The contract SHOULD place a `data:` URL after the `x-chain` URL. Only clients without support for this ERC reach it, and they deliver the single byte `0xff` to the callback. A client that supports this ERC never uses it.

```
data:application/json,{"data":"0xff"}
```

The callback MUST NOT treat a one byte `0xff` response as a valid remote result. ABI encoded return values and standard revert payloads can never be the single byte `0xff`, so the value is unambiguous as a signal. The callback SHOULD handle `0xff` explicitly, for example by reverting with an error that names the missing capability.

### Client behavior

#### Accepting an x-chain URL

A client that supports this ERC and finds an `x-chain` URL in `urls` MUST ignore every other URL in the list, whatever the outcome of the call. It never falls back to the `data:` URL or to any other URL, so only unaware clients reach the fallback. If the list contains more than one `x-chain` URL, the client MUST use the first one and ignore the rest.

The URI format accepts any ERC-7930 chain type. The client alone decides whether it can safely and correctly make the call on the destination chain. That judgment covers at least whether the client knows the chain, has a trusted RPC endpoint for it, and supports its virtual machine and call semantics. If the client is not confident on all counts, or the URL is unsupported, it MUST fail the call with an error, the same outcome as a gateway HTTP 4xx response, and MUST NOT attempt a best effort call.

This section defines call semantics for `eip155` chains, where the read is an `eth_call`. EVM chains are a family of different virtual machines, including zkEVMs, chains missing newer opcodes such as `PUSH0`, and chains with different precompiles and gas rules, so support for one `eip155` chain does not imply support for another. Call semantics for other chain types, for example Solana, are left to clients or to a later ERC.

The chain named in the URL MAY equal the chain the original call was made on. Same-chain reads are valid uses of this ERC.

#### Performing the call

The client makes the call on the destination chain with `to` set to the address from the Interoperable Address, `data` set to `callData` from the `OffchainLookup` error, and the block selected by the `block` parameter. The client MUST give results identical to the results of a valid ERC-3668 gateway.

- On success, the client invokes the callback with `response` set to the raw return data exactly as `eth_call` returns it, and `extraData` unmodified, per [ERC-3668](./eip-3668.md).
- If the remote call reverts with an error other than `OffchainLookup`, the client MUST NOT invoke the callback and MUST fail the overall call, the same outcome as a gateway HTTP 4xx response. The client SHOULD surface the remote revert data to its caller where it can. The JSON-RPC representation of revert data is not uniform across providers, so the quality of the surfaced error may vary.
- If the remote call reverts with `OffchainLookup`, the client proceeds as described under Nested lookups.

#### Nested lookups

While serving an `x-chain` call, the client acts as a normal ERC-3668 client on the remote chain. It validates the nested `sender`, fetches from the nested gateway URLs, and invokes the nested callback on the remote chain via `eth_call`, repeating as needed.

If a nested lookup's URL list contains an `x-chain` URL, the client MUST fail the entire call with an error, the same outcome as a gateway HTTP 4xx response. Nested `x-chain` URLs are never followed and never skipped.

One shared lookup limit bounds the entire resolution, counting the outer lookup and every nested lookup together. The limit MUST be at least 4.

## Rationale

### The client is the gateway

A gateway under [ERC-3668](./eip-3668.md) is whatever answers the lookup, and nothing in that ERC requires it to be an HTTP service. The client already holds trusted RPC connections to the chains it serves, so it is the one party that can answer a cross-chain read without adding a trusted party. Making the client the gateway removes the service that someone must run, pay for, and keep available, and removes that service from the trust base of the read. The exclusivity rule follows from the same goal, a supporting client ignores every other URL so that it never consults a third party, and the outcome of a lookup depends only on the client's own connections. ERC-3668 states that URLs may be of any schema while defining handling only for HTTPS, so a new scheme is a conforming extension point.

### The fallback signal works with deployed clients

A survey of deployed CCIP-Read clients found that none fail hard at the sight of an unknown scheme, all of them record the failure and move to the next URL. Widely used clients also parse a `data:application/json` URL carrying a `data` field as a valid gateway response, so with those clients the callback receives `0xff` exactly as designed. Some clients cannot fetch `data:` URLs, and with those the whole lookup fails with an error rather than delivering `0xff`, a safe failure, though not a graceful one. The signal byte `0xff` was chosen because no ABI encoded return value and no standard revert payload is a single byte, so it cannot collide with a genuine remote result. An aware client never reaches the fallback, which keeps the signal unambiguous, `0xff` always means the client is unaware of this ERC. If an aware client that could not serve a chain fell back to the `data:` URL instead, the callback could not tell an unaware client from an aware client missing one chain, so the aware client fails the call with an error instead, matching how a gateway HTTP 4xx ends a lookup.

### The fallback is a data: URL only

The purpose of this ERC is that the result is safe from the client's perspective, answered by the client's own trusted RPC and nothing else. Listing an ordinary HTTPS gateway as a fallback would reintroduce exactly the trusted third party this ERC exists to remove, so the fallback is a `data:` URL, which the client resolves locally without contacting anyone. The `0xff` it carries tells the callback that no supporting client was present, and the contract decides what to do with that fact.

### No envelope

The client passes through exactly what `eth_call` returns, and a remote revert fails the call rather than being delivered in a wrapper. This keeps callback code identical to callback code written against a trusted ERC-3668 gateway, keeps the client logic small, and avoids inventing a serialization for errors whose JSON-RPC shape is already inconsistent across providers. Contracts that want remote revert details can expose a remote function that returns status information instead of reverting.

### Nested x-chain URLs are not followed

Allowing an `x-chain` call to spawn further `x-chain` calls makes loops easy, a contract on chain A can point at chain B and the contract on chain B can point back at chain A, and each hop multiplies RPC work across chains. Failing the call when a nested `x-chain` URL appears bounds the resolution to one cross-chain hop, while the shared lookup limit of at least 4 still leaves room for ordinary nested gateway lookups on the remote chain.

### Same-chain reads are allowed

Requiring the named chain to differ from the current chain would forbid three useful patterns. A contract can read its own chain at `safe` or `finalized` to act only on settled state. A contract can have the client resolve another local contract whose answer depends on that contract's own `OffchainLookup`. A contract can route around the [ERC-3668](./eip-3668.md) rule that a nested `OffchainLookup` is only valid when its `sender` equals the called contract, because the client issues a fresh top-level call to the target.

### The block parameter

`latest`, `safe`, and `finalized` are the block tags clients already pass to `eth_call`, and `safe` and `finalized` are the stronger choice when the goal is settled state on rollups. `latest-N` covers contracts that want a fixed reorg buffer. The count is resolved to an exact number once, so repeated URL fetches cannot drift, and the call fails rather than silently landing on a different block. `N` blocks is a different span of time on each chain, so contracts choose `N` per chain.

## Backwards Compatibility

This ERC changes no contract interfaces and no gateway interfaces. It only adds meaning to a URL scheme inside the existing [ERC-3668](./eip-3668.md) `urls` list. Contracts using this ERC remain valid ERC-3668 contracts. Clients without support for this ERC skip the `x-chain` URL and reach the `data:` fallback, so the callback receives `0xff` and can respond with a clear error. Clients that do not support `data:` URLs fail the lookup safely with an error and never give a wrong result.

## Test Cases

### Chain identifier vectors

The ERC-7930 Chain Identifier for Ethereum mainnet, chain id 1, is `0x00010000010100`. The Chain Identifier for Base, chain id 8453, is `0x0001000002210500`. Chain Identifiers have a zero-length address and are therefore not valid in `x-chain` URLs, which require a target address.

### Valid URIs

USDC on Base, chain id 8453, contract `0x833589fcd6edb6e08f4c7c32d4f71b54bda02913`.

```
x-chain:0x0001000002210514833589fcd6edb6e08f4c7c32d4f71b54bda02913
```

The ENS registry on Ethereum mainnet, chain id 1, contract `0x00000000000c2e074ec69a0dfb2997ba6c7d2e1e`.

```
x-chain:0x0001000001011400000000000c2e074ec69a0dfb2997ba6c7d2e1e
```

The same targets with a block parameter.

```
x-chain:0x0001000002210514833589fcd6edb6e08f4c7c32d4f71b54bda02913?block=finalized
x-chain:0x0001000001011400000000000c2e074ec69a0dfb2997ba6c7d2e1e?block=latest-128
```

### Invalid URIs

Each of the following MUST be treated as unsupported.

| URI | Defect |
| --- | --- |
| `x-chain:0x0002000002210514833589fcd6edb6e08f4c7c32d4f71b54bda02913` | version is not `0x0001` |
| `x-chain:0x0001000002210514833589FCD6EDB6E08F4C7C32D4F71B54BDA02913` | uppercase hexadecimal |
| `x-chain:0x0001000002210500` | zero-length address, a Chain Identifier only |
| `x-chain:0x0001000002210514833589fcd6edb6e08f4c7c32d4f71b54bda02913ff` | trailing bytes after the Interoperable Address |
| `x-chain:8453` | not an ERC-7930 Interoperable Address |

### Block parameter vectors

| `block` value | Valid | Meaning |
| --- | --- | --- |
| absent | yes | `latest`, the default |
| `latest` | yes | call at the latest block |
| `safe` | yes | call at the safe block |
| `finalized` | yes | call at the finalized block |
| `0x1538f70` | yes | call at exactly block 22253424, fails if the client cannot serve it |
| `latest-128` | yes | head read once, minus 128, call at that exact number |
| `latest-0` | yes | equals the head block |
| `latest-99999999999` | parses | fails when `N` exceeds the head, no substitute block |
| `latest-` | no | `N` missing |
| `latest-abc` | no | `N` not decimal |
| `latest--5` | no | negative `N` |
| `-5` | no | not a tag, not `0x` hexadecimal |
| `22253424` | no | decimal block numbers are not a defined form |
| `0x` | no | empty hexadecimal number |
| `earliest` | no | not a defined value |
| `pending` | no | not a defined value |

### The 0xff signal

A contract reverts with `OffchainLookup` where `urls[0]` is an `x-chain` URL and `urls[1]` is `data:application/json,{"data":"0xff"}`. A client without support for this ERC skips `urls[0]`, fetches `urls[1]`, and invokes the callback with `response` equal to the single byte `0xff`. The reference callback in the Reference Implementation reverts with `XChainUnsupported()` on that input.

### Nested lookup

While serving an `x-chain` call, the remote contract reverts with `OffchainLookup` where `urls[0]` is an `x-chain` URL and `urls[1]` is `data:application/json,{"data":"0xff"}`. The client MUST fail the entire call. It does not follow the nested `x-chain` URL and it does not use the `data:` URL.

### Multiple x-chain URLs

A contract reverts with `OffchainLookup` where `urls` contains two `x-chain` URLs followed by a `data:` URL. A supporting client uses the first `x-chain` URL and ignores every other URL in the list.

### Unsupported chain

A contract reverts with `OffchainLookup` where `urls[0]` is an `x-chain` URL naming a chain the client has no trusted RPC endpoint for and `urls[1]` is the `data:` fallback. A supporting client fails the call with an error and does not use the `data:` URL. A client unaware of this ERC skips `urls[0]` and delivers `0xff`.

### Same chain

A contract on Base reverts with `OffchainLookup` naming a contract on Base, chain id 8453, with `?block=finalized`. A supporting client performs the call on Base at the finalized block and invokes the callback with the raw return data.

## Reference Implementation

A contract that reads `totalSupply()` from USDC on Base.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

contract RemoteSupplyReader {
    error OffchainLookup(
        address sender,
        string[] urls,
        bytes callData,
        bytes4 callbackFunction,
        bytes extraData
    );
    error XChainUnsupported();

    string constant REMOTE_URL =
        "x-chain:0x0001000002210514833589fcd6edb6e08f4c7c32d4f71b54bda02913?block=finalized";
    string constant FALLBACK_URL = "data:application/json,{\"data\":\"0xff\"}";

    function remoteTotalSupply() external view returns (uint256) {
        string[] memory urls = new string[](2);
        urls[0] = REMOTE_URL;
        urls[1] = FALLBACK_URL;
        revert OffchainLookup(
            address(this),
            urls,
            abi.encodeWithSignature("totalSupply()"),
            this.remoteTotalSupplyCallback.selector,
            ""
        );
    }

    function remoteTotalSupplyCallback(
        bytes calldata response,
        bytes calldata
    ) external pure returns (uint256) {
        if (response.length == 1 && response[0] == 0xff) {
            revert XChainUnsupported();
        }
        return abi.decode(response, (uint256));
    }
}
```

Client algorithm, in the style of [ERC-3668](./eip-3668.md). `lookups` is the shared counter bounding the entire resolution, with a limit of at least 4.

```
resolve(chain, target, data, lookups, nested):
 1. Set result to the result of eth_call with to = target and
    input = data on chain.
 2. If the call succeeded, return result.
 3. If the call reverted with an error other than OffchainLookup,
    fail and surface the revert data where possible. At the top
    level, return the revert to the caller.
 4. Decode sender, urls, callData, callbackFunction, and extraData
    from the OffchainLookup error. If sender != target, fail.
 5. If lookups >= LIMIT, fail. Increment lookups.
 6. If urls contains an x-chain URL, ignore every other url and
    use only the first x-chain url:
    a. If nested, fail.
    b. If the url is not well formed, or the client cannot safely
       and correctly make the call on the named chain under
       "Accepting an x-chain URL", fail.
    c. Parse the Interoperable Address into (remoteChain,
       remoteTarget), resolve the block parameter, and set
       response to
       resolve(remoteChain, remoteTarget, callData, lookups, true)
       at the resolved block. If that resolution fails, fail.
 7. Otherwise, for each url in urls, in order, handle url per
    ERC-3668, continuing to the next url on failure. If no url
    produced a response, fail.
 8. Set data to callbackFunction ++ abi.encode(response, extraData)
    and go to step 1.
```

## Security Considerations

The callback MUST treat the client's answer as untrusted, exactly as it would treat the answer of any ERC-3668 gateway. A contract that needs guarantees verifies the response with proofs or signatures, or treats it as a hint.

Clients use their own RPC endpoints and MUST NOT accept RPC endpoints or chain metadata from the contract. The URL names a chain only through its ERC-7930 chain identifier. A chain identifier the client does not recognize makes the URL unsupported, so a contract cannot direct a client to an arbitrary endpoint. This ERC defines no HTTPS gateway fallback because a gateway would add another trusted party, the client's own RPC endpoints remain the only external dependency of the read.

The shared lookup limit bounds the work a single call can trigger. Without the nested restriction, cross-chain hops would make loops easy, a contract on chain A pointing to chain B whose contract points back to chain A, and each hop would multiply RPC load. Nested `x-chain` URLs are therefore never followed, and the shared limit of at least 4 caps the remaining gateway lookups.

All calls made under this ERC are reads. They move no assets, carry no spend authority, and create no reentrancy into the calling contract.

A client that has seen an `x-chain` URL MUST NOT fall back to any other URL, so a transient RPC failure surfaces as a failed call rather than silently resolving through another URL, and the `data:` fallback keeps a single meaning, the client is unaware of this ERC.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
