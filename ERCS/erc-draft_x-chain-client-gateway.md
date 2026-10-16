---
title: Cross-Chain Client Gateway for CCIP-Read
description: An extension of CCIP-Read where the client itself performs a cross-chain read named by an x-chain URL
author: Prem Makeig (@nxt3d)
discussions-to:
status: Draft
type: Standards Track
category: ERC
created: 2026-10-16
requires: 3668, 7930
---

## Abstract

This ERC extends [ERC-3668](./eip-3668.md) so a contract can ask the client to read another contract directly, on another chain or the same chain, instead of relying on an offchain gateway. The client returns the same result a gateway would, using its own trusted connection to that chain, so no third party is involved. Contracts can also detect clients that do not support this ERC.

## Motivation

An [ERC-3668](./eip-3668.md) gateway must either be trusted or return a proof that the contract verifies on the original chain. In many cases a valid proof cannot be produced. That does not make the read unsafe. A client that already trusts its RPC connection to the destination chain can make the call itself.

This ERC lets the client act as the gateway. The contract names the chain and contract to read, and the client answers using its own trusted RPC, so no third party is involved.

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

The callback MUST treat a one byte `0xff` response as a client without support for this ERC, never as a remote result.

### Client behavior

A client that supports this ERC MUST use the first `x-chain` URL in `urls` and ignore all other URLs.

The client alone decides whether it can safely make the call on the destination chain. This includes knowing the chain, having a trusted RPC endpoint for it, and supporting its virtual machine. The client MUST use its own RPC endpoints and MUST NOT take endpoints or chain metadata from the contract. Support for one EVM chain does not imply support for another. If the client cannot make the call, or the URL is malformed, it MUST fail the call, the same outcome as a gateway HTTP 4xx response.

The client calls the target contract on the destination chain with `callData`, at the selected block. The destination chain MAY be the same chain.

- On success, the client invokes the callback with the return data exactly as `eth_call` returns it.
- On a revert, the client MUST fail the call and SHOULD surface the revert data.
- On an `OffchainLookup` revert from the target contract, the client handles it as a normal [ERC-3668](./eip-3668.md) lookup on the destination chain. If that lookup includes an `x-chain` URL, the client MUST fail the call, so one `x-chain` read never starts another.

Lookups on the destination chain count toward the client's ERC-3668 lookup limit for the original call.

## Rationale

[ERC-3668](./eip-3668.md) does not require a gateway to be an HTTP service, and allows URLs of any scheme. The client already trusts its own RPC connections, so it can answer a cross-chain read without adding a third party. A client that supports this ERC ignores all other URLs, so it never sends the request to a third-party gateway. It returns exactly what `eth_call` returns, so callbacks work as they do with any ERC-3668 gateway. Nested `x-chain` URLs are not followed, which limits each call to one cross-chain hop and prevents loops between chains.

The fallback is a `data:` URL because the client resolves it itself, without contacting anyone. Deployed CCIP-Read clients skip unsupported URL schemes, and most accept `data:` URLs, so the callback receives `0xff`. Clients that cannot read `data:` URLs fail the lookup with an error, which is safe. No ABI encoded result is a single byte, so `0xff` cannot be mistaken for a real result. The `block` parameter uses the standard `eth_call` block tags, and `latest-N` keeps a fixed number of blocks behind the head, which is a different span of time on each chain.

## Backwards Compatibility

This ERC adds a URL scheme to the ERC-3668 `urls` list and changes no interfaces. Clients without support skip the `x-chain` URL and return `0xff` from the `data:` URL. Clients that cannot read `data:` URLs fail the lookup with an error and never return a wrong result.

## Test Cases

### Chain identifier vectors

The ERC-7930 Chain Identifier for Ethereum mainnet, chain id 1, is `0x00010000010100`. The Chain Identifier for Base, chain id 8453, is `0x0001000002210500`. Chain Identifiers have a zero-length address and are therefore not valid in `x-chain` URLs, which require a target address.

### Valid URLs

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

### Invalid URLs

Each of the following MUST be treated as unsupported.

| URL | Defect |
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

Client algorithm, in the style of [ERC-3668](./eip-3668.md). `lookups` is the shared counter bounding the entire resolution, and `LIMIT` is the client's ERC-3668 lookup limit.

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

The result is as trustworthy as the client's RPC connection to the destination chain. The contract cannot verify it onchain. Contracts that need onchain guarantees should use proofs instead.

Clients use only their own RPC endpoints, so a contract cannot direct a client to an endpoint of its choosing. A chain the client does not recognize makes the call fail.

Refusing nested `x-chain` URLs prevents cross-chain loops, and the client's lookup limit bounds the remaining lookups.

All calls under this ERC are reads. They move no assets and cannot reenter the calling contract.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
