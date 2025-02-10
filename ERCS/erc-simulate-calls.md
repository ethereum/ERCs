---
title: Wallet Call Simulation API
description: Adds a JSON-RPC method for simulating execution of calls on a Wallet
author: Jake Moxey (@jxom), Adam Hodges (@ajhodges)
discussions-to: 
status: Draft
type: Standards Track
category: Interface
created: 2025-02-10
requires: 5792
---

## Abstract

This ERC proposes a new JSON-RPC method for simulating the execution of calls on a Wallet. The method is designed to be used by Wallets to simulate the execution of calls before sending them to the network, allowing for gas estimation, log extraction, and call validation.

## Motivation

Applications are reliant on JSON-RPC communication to Wallets in order to execute actions. A seemingly core functionality for "offline" Applications (Servers, etc) is the ability to simulate if an action will succeed or fail and/or estimate the total fee and/or calculate balance changes, prior to signing and broadcasting to the network.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### `wallet_simulateCalls`

Instructs a Wallet to simulate execution of a set of calls, and return metadata such as: the gas used, logs, status, and failure reason (if applicable).

#### Request

Accepts exact parameters as per [ERC-5792 `wallet_sendCalls`](https://eips.ethereum.org/EIPS/eip-5792#wallet_sendcalls).

```ts 
type Request = {
  method: 'wallet_simulateCalls',
  params: [{
    // Calls to simulate.
    calls: {
      to: `0x${string}`,
      data?: `0x${string}`,
      value?: `0x${string}`,
      capabilities?: Record<string, any>;
    }[],
    // ERC-5792 Capabilities.
    capabilities?: Record<string, any>;
    // Target chain ID to simulate calls on.
    chainId: `0x${string}`,
    // Sender address.
    from?: `0x${string}`;
    // Version.
    version: string;
  }]
}
```

#### Response

- The `status` code complies with the [ERC-5792 Status Codes](https://github.com/ethereum/EIPs/blob/2dcee4d0e2fc1cea488c12ba88e9a93d5925043b/EIPS/eip-5792.md#status-codes-for-status-field).

```ts
type Response = {
  // Chain ID the calls were simulated on.
  chainId: `0x${string}`;
  // Estimated total gas used by the calls.
  gasUsed: `0x${string}`;
  // Logs emitted by the calls.
  logs: {
    address: `0x${string}`;
    data: `0x${string}`;
    topics: `0x${string}`[];
  }[];
  // Capabilities used by the calls.
  capabilities?: Record<string, any>;
  // Error that occurred during simulation.
  error?: {
    data?: `0x${string}`;
    code?: number;
    message?: string;
  },
  // Status code of the simulation. 
  status?: number;
}
```

#### Example

```ts
const response = await provider.request({
  method: 'wallet_simulateCalls',
  params: [{
    calls: [{
      to: '0xcafebabecafebabecafebabecafebabecafebabe',
      data: '0xdeadbeef',
    }],
    chainId: '0x1',
    from: '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
    version: '1',
  }],
});

console.log(response);
/**
 * {
 *  chainId: '0x1',
 *  gasUsed: '0xe208',
 *  logs: [{
 *    address: '0xcafebabecafebabecafebabecafebabecafebabe',
 *    data: '0x0000000000000000000000000000000000000000000000000000000000069420',
 *    topics: [
 *      '0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef',
 *      '0x000000000000000000000000deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
 *      '0x000000000000000000000000cafebabecafebabecafebabecafebabecafebabe',
 *    ],
 *  }],
 *  status: 200,
 * }
 */
```

## Rationale

### `eth_simulateV1` vs `wallet_simulateCalls`

The [`eth_simulateV1` Execution API method](https://github.com/ethereum/execution-apis/pull/484) is very similar to `wallet_simulateCalls` in that they both simulate the execution of calls on a Wallet. However, the fundamental differences are that `eth_simulateV1`: is not account agnostic, is an Execution API method (not a Wallet API method), and assumes that regular transactions will be executed. It does not have knowledge of the implementation details of how the Wallet constructs transactions (ie. they could be wrapped as an [ERC-4337 User Operation](https://eips.ethereum.org/EIPS/eip-4337#useroperation) with a Paymaster, or wrapped as another type of abstraction, which consequently would affect the simulation results).

`wallet_simulateCalls` is account agnostic, meaning that it is aware of the implementation details of how the Wallet constructs transactions. As the Wallet handles `wallet_simulateCalls` and returns a response to the Application, this means that the Wallet can simulate the calls with the full context of its implementation details (ie. simulate as a regular transaction, a [ERC-4337 User Operation](https://eips.ethereum.org/EIPS/eip-4337#useroperation), or something else entirely).

## Backwards Compatibility

Needs discussion.

## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
