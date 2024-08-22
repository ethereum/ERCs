---
eip:
title: JSON-RPC API for Account Abstraction Using the UserOperation Mempool
description: A set of JSON-RPC API methods that defines a communication between smart contract account wallets and bundlers
author: Vitalik Buterin (@vbuterin), Yoav Weiss (@yoavw), Dror Tirosh (@drortirosh), Shahaf Nacson (@shahafn), Alex Forshtat (@forshtat), Kristof Gazso (@kristofgazso), Tjaden Hess (@tjade273)
discussions-to:
status: Draft
type: Standards Track
category: ERC
created:
requires: 4337, 7562
---

## Abstract

## Motivation

## Specification

### RPC methods (eth namespace)

#### * eth_sendUserOperation

eth_sendUserOperation submits a User Operation object to the User Operation pool of the client. The client MUST validate the UserOperation, and return a result accordingly.

The result `SHOULD` be set to the **userOpHash** if and only if the request passed simulation and was accepted in the client's User Operation pool. If the validation, simulation, or User Operation pool inclusion fails, `result` `SHOULD NOT` be returned. Rather, the client `SHOULD` return the failure reason.

##### Parameters:

1. **UserOperation** a full user-operation struct. All fields MUST be set as hex values. empty `bytes` block (e.g. empty `initCode`) MUST be set to `"0x"`
2. **factory** and **factoryData** - either both exist, or none
3. paymaster fields (**paymaster**, **paymasterData**, **paymasterValidationGasLimit**, **paymasterPostOpGasLimit**) either all exist, or none.
4. **EntryPoint** the entrypoint address the request should be sent through. this MUST be one of the entry points returned by the `supportedEntryPoints` rpc call.

##### Return value:

* If the UserOperation is valid, the client MUST return the calculated **userOpHash** for it
* in case of failure, MUST return an `error` result object, with `code` and `message`. The error code and message SHOULD be set as follows:
  * **code: -32602** - invalid UserOperation struct/fields
  * **code: -32500** - transaction rejected by entryPoint's simulateValidation, during wallet creation or validation
    * The `message` field MUST be set to the FailedOp's "`AAxx`" error message from the EntryPoint
  * **code: -32501** - transaction rejected by paymaster's validatePaymasterUserOp
    * The `message` field SHOULD be set to the revert message from the paymaster
    * The `data` field MUST contain a `paymaster` value
  * **code: -32502** - transaction rejected because of opcode validation
  * **code: -32503** - UserOperation out of time-range: either wallet or paymaster returned a time-range, and it has already expired (or will expire soon)
    * The `data` field SHOULD contain the `validUntil` and `validAfter` values
    * The `data` field SHOULD contain a `paymaster` value, if this error was triggered by the paymaster
  * **code: -32504** - transaction rejected because paymaster is throttled/banned
    * The `data` field SHOULD contain a `paymaster` value, depending on the failed entity
  * **code: -32505** - transaction rejected because paymaster stake or unstake-delay is too low
    * The `data` field SHOULD contain a `paymaster` value, depending on the failed entity
    * The `data` field SHOULD contain a `minimumStake` and `minimumUnstakeDelay`
  * **code: -32507** - transaction rejected because of wallet signature check failed (or paymaster signature, if the paymaster uses its data as signature)
  * **code: -32508** - transaction rejected because paymaster balance can't cover all pending UserOperations.

##### Example:

Request:

```json=
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_sendUserOperation",
  "params": [
    {
      sender, // address
      nonce, // uint256
      factory, // address
      factoryData, // bytes
      callData, // bytes
      callGasLimit, // uint256
      verificationGasLimit, // uint256
      preVerificationGas, // uint256
      maxFeePerGas, // uint256
      maxPriorityFeePerGas, // uint256
      paymaster, // address
      paymasterVerificationGasLimit, // uint256
      paymasterPostOpGasLimit, // uint256
      paymasterData, // bytes
      signature // bytes
    },
    entryPoint // address
  ]
}

```

Response:

```
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0x1234...5678"
}
```

##### Example failure responses:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "message": "AA21 didn't pay prefund",
    "code": -32500
  }
}
```

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "message": "paymaster stake too low",
    "data": {
      "paymaster": "0x123456789012345678901234567890123456790",
      "minimumStake": "0xde0b6b3a7640000",
      "minimumUnstakeDelay": "0x15180"
    },
    "code": -32504
  }
}
```


#### * eth_estimateUserOperationGas

Estimate the gas values for a UserOperation.
Given UserOperation optionally without gas limits and gas prices, return the needed gas limits.
The signature field is ignored by the wallet, so that the operation will not require the user's approval.
Still, it might require putting a "semi-valid" signature (e.g. a signature in the right length)

**Parameters**:
* Same as `eth_sendUserOperation`\
  gas limits (and prices) parameters are optional, but are used if specified.
  `maxFeePerGas` and `maxPriorityFeePerGas` default to zero, so no payment is required by neither account nor paymaster.
* Optionally accepts the `State Override Set` to allow users to modify the state during the gas estimation.\
  This field as well as its behavior is equivalent to the ones defined for `eth_call` RPC method.


**Return Values:**

* **preVerificationGas** gas overhead of this UserOperation
* **verificationGasLimit** estimation of gas limit required by the validation of this UserOperation
* **paymasterVerificationGasLimit** estimation of gas limit required by the paymaster verification, if the
  UserOperation defines a Paymaster address
* **callGasLimit** estimation of gas limit required by the inner account execution

**Note:** actual `postOpGasLimit` cannot be reliably estimated. Paymasters should provide this value to account,
and require that specific value on-chain.

##### Error Codes:

Same as `eth_sendUserOperation`
This operation may also return an error if either the inner call to the account contract reverts,
or paymaster's `postOp` call reverts.

#### * eth_getUserOperationByHash

Return a UserOperation based on a hash (userOpHash) returned by `eth_sendUserOperation`

**Parameters**

* **hash** a userOpHash value returned by `eth_sendUserOperation`

**Return value**:

* If the UserOperation is included in a block:
  * Return a full UserOperation, with the addition of `entryPoint`, `blockNumber`, `blockHash` and `transactionHash`.

* Else if the UserOperation is pending in the bundler's mempool:
  *  MAY return `null`, or: a full UserOperation, with the addition of the `entryPoint` field and a `null` value for `blockNumber`, `blockHash` and `transactionHash`.

* Else:
  * Return `null`

#### * eth_getUserOperationReceipt

Return a UserOperation receipt based on a hash (userOpHash) returned by `eth_sendUserOperation`

**Parameters**

* **hash** a userOpHash value returned by `eth_sendUserOperation`

**Return value**:

`null` in case the UserOperation is not yet included in a block, or:

* **userOpHash** the request hash
* **entryPoint**
* **sender**
* **nonce**
* **paymaster** the paymaster used for this userOp (or empty)
* **actualGasCost** - the actual amount paid (by account or paymaster) for this UserOperation
* **actualGasUsed** - total gas used by this UserOperation (including preVerification, creation, validation and execution)
* **success** boolean - did this execution completed without a revert
* **reason** in case of revert, this is the revert reason
* **logs** the logs generated by this UserOperation (not including logs of other UserOperations in the same bundle)
* **receipt** the TransactionReceipt object.
  Note that the returned TransactionReceipt is for the entire bundle, not only for this UserOperation.

#### * eth_supportedEntryPoints

Returns an array of the entryPoint addresses supported by the client. The first element of the array `SHOULD` be the entryPoint addressed preferred by the client.

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_supportedEntryPoints",
  "params": []
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": [
    "0xcd01C8aa8995A59eB7B2627E69b40e0524B5ecf8",
    "0x7A0A0d159218E6a2f407B99173A2b12A6DDfC2a6"
  ]
}
```

#### * eth_chainId

Returns [EIP-155](./eip-155.md) Chain ID.

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "eth_chainId",
  "params": []
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0x1"
}
```

### RPC methods (debug Namespace)

This api must only be available in testing mode and is required by the compatibility test suite. In production, any `debug_*` rpc calls should be blocked.

#### * debug_bundler_clearState

Clears the bundler mempool and reputation data of paymasters/accounts/factories.

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "debug_bundler_clearState",
  "params": []
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "ok"
}
```

#### * debug_bundler_dumpMempool

Dumps the current UserOperations mempool

**Parameters:**

* **EntryPoint** the entrypoint used by eth_sendUserOperation

**Returns:**

`array` - Array of UserOperations currently in the mempool.

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "debug_bundler_dumpMempool",
  "params": ["0x1306b01bC3e4AD202612D3843387e94737673F53"]
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": [
    {
        sender, // address
        nonce, // uint256
        factory, // address
        factoryData, // bytes
        callData, // bytes
        callGasLimit, // uint256
        verificationGasLimit, // uint256
        preVerificationGas, // uint256
        maxFeePerGas, // uint256
        maxPriorityFeePerGas, // uint256
        signature // bytes
    }
  ]
}
```

#### * debug_bundler_sendBundleNow

Forces the bundler to build and execute a bundle from the mempool as `handleOps()` transaction.

Returns: `transactionHash`

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "debug_bundler_sendBundleNow",
  "params": []
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "0xdead9e43632ac70c46b4003434058b18db0ad809617bd29f3448d46ca9085576"
}
```

#### * debug_bundler_setBundlingMode

Sets bundling mode.

After setting mode to "manual", an explicit call to debug_bundler_sendBundleNow is required to send a bundle.

##### parameters:

`mode` - 'manual' | 'auto'

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "debug_bundler_setBundlingMode",
  "params": ["manual"]
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "ok"
}
```

#### * debug_bundler_setReputation

Sets the reputation of given addresses. parameters:

**Parameters:**

* An array of reputation entries to add/replace, with the fields:

  * `address` - The address to set the reputation for.
  * `opsSeen` - number of times a user operations with that entity was seen and added to the mempool
  * `opsIncluded` - number of times user operations that use this entity was included on-chain

* **EntryPoint** the entrypoint used by eth_sendUserOperation

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "debug_bundler_setReputation",
  "params": [
    [
      {
        "address": "0x7A0A0d159218E6a2f407B99173A2b12A6DDfC2a6",
        "opsSeen": "0x14",
        "opsIncluded": "0x0D"
      }
    ],
    "0x1306b01bC3e4AD202612D3843387e94737673F53"
  ]
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "ok"
}
```


#### * debug_bundler_dumpReputation

Returns the reputation data of all observed addresses.
Returns an array of reputation objects, each with the fields described above in `debug_bundler_setReputation` with the


**Parameters:**

* **EntryPoint** the entrypoint used by eth_sendUserOperation

**Return value:**

An array of reputation entries with the fields:

* `address` - The address to set the reputation for.
* `opsSeen` - number of times a user operations with that entity was seen and added to the mempool
* `opsIncluded` - number of times user operation that use this entity was included on-chain
* `status` - (string) The status of the address in the bundler 'ok' | 'throttled' | 'banned'.

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "debug_bundler_dumpReputation",
  "params": ["0x1306b01bC3e4AD202612D3843387e94737673F53"]
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": [
    { "address": "0x7A0A0d159218E6a2f407B99173A2b12A6DDfC2a6",
      "opsSeen": "0x14",
      "opsIncluded": "0x13",
      "status": "ok"
    }
  ]
}
```

#### * debug_bundler_addUserOps

Accept UserOperations into the mempool.
Assume the given UserOperations all pass validation (without actually validating them), and accept them directly into the mempool

**Parameters:**

* An array of UserOperations

```json=
# Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "debug_bundler_addUserOps",
  "params": [
    [
      { sender: "0xa...", ... },
      { sender: "0xb...", ... }
    ]
  ]
}

# Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": "ok"
}
```

## Backwards Compatibility

## Reference Implementation

## Security Considerations

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
