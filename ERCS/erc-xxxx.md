---
eip: xxxx
title: JSON-RPC API for RIP-7560 Native Account Abstraction
description: A set of JSON-RPC API methods that are required for a fully functional Native Account Abstraction protocol
author:
discussions-to:
status: Draft
type: Standards Track
category: ERC
created:
requires: RIP-7560, ERC-7562, EIP-7702
---

## Abstract

[RIP-7560](https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7560.md) defines the new transaction type
and the modifications to the EVM needed for the Native Account Abstraction support.

However, there are a number of modifications to the Ethereum JSON-RPC API that is needed as well.
This proposal contains the full description of the new or modified APIs, and it would be highly beneficial
for the Native Account Abstraction ecosystem to implement these APIs in a standardised and compatible way.

## Motivation

Native Account Abstraction is expected to supersede [ERC-4337](https://eips.ethereum.org/EIPS/eip-4337)
by making all the benefits of Account Abstraction a core part of the protocol, bringing down the cost for the users,
enabling easy migration to post-quantum cryptography and eventually deprecation of Externally Owned Accounts altogether.

A number of current Ethereum JSON-RPC API methods are defined for transactions of existing types, such as legacy,
[EIP-2930](https://eips.ethereum.org/EIPS/eip-2930),
[EIP-1559](https://eips.ethereum.org/EIPS/eip-1559),
[EIP-4844](https://eips.ethereum.org/EIPS/eip-4844),
and the upcoming [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702).
They are not properly defined for RIP-7560 transaction type.

There are also some actions that are only applicable in the context of Native Account Abstraction,
which requires a creation of new JSON-RPC API methods.

## Specification

We define the following changes to the Ethereum JSON-RPC API:

#### Create a new JSON-RPC API method `eth_signRip7560Transaction`

This method is used by an RIP-7560 wallet application that operates the credentials for the Smart Contract Account
specified as a `sender` of the provided RIP-7560 transaction.

In case the node is not able to create such a `signature` returns an error describing the failure reason.

Parameters:

1. OBJECT - The RIP-7560 transaction object. The `signature` parameter must be `null`.

| Name                            | Type           | Description                                                    |
|---------------------------------|----------------|----------------------------------------------------------------|
| **sender**                      | DATA, 20 Bytes | Address of the Smart Contract Account making the transaction   |
| **deployer**                    | DATA, 20 Bytes | Address of the Deployer - account factory contract             |
| **deployerData**                | DATA           | Data that is provided to the Deployer contract                 |
| **paymaster**                   | DATA, 20 Bytes | Address of the Paymaster contract                              |
| **paymasterData**               | DATA           | Data that is provided to the Paymaster contract                |
| callData                        | DATA           | Data that is provided to the Account contract for execution    |
| nonce                           | QUANTITY       | A 256 bit nonce. Use of `nonce > 2^64` is defined in RIP-7712) |
| **builderFee**                  | QUANTITY       | Value passed from sender or paymaster to the `coinbase`        |
| maxPriorityFeePerGas            | QUANTITY       | The maximum gas price to be included as a tip to the validator |
| maxFeePerGas                    | QUANTITY       | The maximum fee per unit of gas                                |
| **validationGasLimit**          | QUANTITY       | Gas provided for the transaction account validation frame      |
| **paymasterValidationGasLimit** | QUANTITY       | Gas provided for the transaction paymaster validation frame    |
| **paymasterPostOpGasLimit**     | QUANTITY       | Gas provided for the transaction paymaster `postOp` frame      |
| callGasLimit                    | QUANTITY       | Gas provided for the transaction execution frame               |
| accessList                      | OBJECT         | An EIP-2930 compatible Access List structure                   |
| EIP-7702 authorizations (WIP)   | ARRAY          | An EIP-7702 compatible list of contracts injected into EOAs    |

\* fields marked as **bold** are unique for the RIP-7560 transaction type

Returns:

1. DATA - a value to be used as a `signature` parameter that makes the provided RIP-7560 transaction valid.

#### Add RIP-7560 support for `eth_getTransaction` APIs

This includes the following APIs: `eth_getTransactionByHash`, `eth_getTransactionByBlockHashAndIndex`,
`eth_getTransactionByBlockNumberAndIndex`.

These methods have a very similar purpose and should support returning the new transaction type object.

Parameters:
`eth_getTransactionByHash`:

1. DATA, 32 Bytes - hash of a transaction

`eth_getTransactionByBlockHashAndIndex`:

1. DATA, 32 Bytes - hash of a block.
2. QUANTITY - the transaction index position.

`eth_getTransactionByBlockNumberAndIndex`:

1. QUANTITY | TAG - a block number, or the string "earliest", "latest", "pending", "safe" or "finalized", as in the
   default block parameter.
2. QUANTITY - the transaction index position.

Note that the "transaction index position" is determined by the position of the transaction's **validation frame**.

Returns:

1. OBJECT - A transaction object, or `null` when no transaction was found:

| Name             | Type           | Description                                                             |
|------------------|----------------|-------------------------------------------------------------------------|
| blockHash        | DATA, 32 Bytes | Hash of the block where this transaction was in, or `null` when pending |
| blockNumber      | QUANTITY       | Block number where this transaction was in, or `null` when pending      |
| transactionIndex | QUANTITY       | The transaction's index position in the block, or `null` when pending   |
| type             | QUANTITY       | The transaction type                                                    |

\* followed by the entire RIP-7560 transaction object as described in `eth_sendRip7560Transaction`

#### Add RIP-7560 support for `eth_getTransactionReceipt`

For an RIP-7560 transaction included in a block, return also the values specific to this transaction type
in addition to all the existing fields.

Parameters:

1. DATA, 32 Bytes - hash of a transaction

Returns:

1. OBJECT - A transaction receipt object, or `null` when no receipt was found:

Fields specific to an RIP-7560 transaction receipt:

| Name                       | Type            | Description                                                                    |
|----------------------------|-----------------|--------------------------------------------------------------------------------|
| sender                     | DATA, 20 Bytes  | Address of the sender of this transaction                                      |
| paymaster                  | DATA, 20 Bytes  | Address of the Paymaster if it is paying for the transaction, `null` otherwise |
| deployer                   | DATA, 20 Bytes  | Address of the Deployer if it is included in the transaction, `null` otherwise |
| senderCreationGasUsed      | QUANTITY        | The amount of gas actually used by the sender deployment frame                 |
| senderValidationGasUsed    | QUANTITY        | The amount of gas actually used by the sender validation frame                 |
| paymasterValidationGasUsed | QUANTITY        | The amount of gas actually used by the paymaster validation frame              |
| executionGasUsed           | QUANTITY        | The amount of gas actually used by the execution frame                         |
| postOpStatus               | QUANTITY        | 1 (success), 0 (failure), or `null` (did not run) status of the `postOp` frame |
| postOpGasUsed              | QUANTITY        | The amount of gas actually used by the paymaster `postOp` frame                |
| validationLogs             | ARRAY           | Array of log objects, which this transaction'S VALIDATION FRAME generated.     |
| validationLogsBloom        | DATA, 256 Bytes | Array of log objects, which this transaction'S VALIDATION FRAME generated.     |

Continued, these fields are shared by all transaction types:

| Name              | Type            | Value                                                                                      |
|-------------------|-----------------|--------------------------------------------------------------------------------------------|
| transactionHash   | DATA, 32 Bytes  | Hash of the transaction.                                                                   |
| transactionIndex  | QUANTITY        | Integer of the transactions index position in the block.                                   |
| blockHash         | DATA, 32 Bytes  | Hash of the block where this transaction was in.                                           |
| blockNumber       | QUANTITY        | Block number where this transaction was in.                                                |
| cumulativeGasUsed | QUANTITY        | The total amount of gas used when this transaction was executed in the block.              |
| effectiveGasPrice | QUANTITY        | The sum of the base fee and tip paid per unit of gas.                                      |
| gasUsed           | QUANTITY        | The amount of gas used by this specific transaction alone.                                 |
| contractAddress   | DATA, 20 Bytes  | The contract address created, if the transaction was a contract creation, otherwise `null` |
| logs              | ARRAY           | Array of log objects, which this transaction'S EXECUTION FRAME generated.                  |
| logsBloom         | DATA, 256 Bytes | Bloom filter for light clients to quickly retrieve related logs.                           |
| type              | QUANTITY        | Integer of the transaction type                                                            |
| status            | QUANTITY        | Either 1 (success) or 0 (failure) status of the execution frame                            |

#### Create a new JSON-RPC API method `eth_executeRip7560Transaction`

Executes the entire RIP-7560 transaction in memory without broadcasting it or including it in a block.
Does not require the transaction to be properly signed, meaning it continues execution after either an account
or a paymaster contract make a `sigFailAccount` or `sigFailPaymaster` call.
If all frames execute successfully, simply returns the data returned by the top level frame of the execution phase.
If any of the validation or execution frames revers, returns an error object containing the revert message.
If the transaction validation fails for any reason other than the failed signature check,
returns an error object containing the details of the validation failure.

Parameters:

1. OBJECT - The RIP-7560 transaction object (as defined in `eth_sendRip7560Transaction`).
   The `signature` field is optional.
2. QUANTITY | TAG - integer block number, or the string "latest", "earliest", "pending", "safe" or "finalized"

Returns:

DATA - The return value of the `sender` execution frame.

Error:

DATA - The revert data of the first reverted frame.
CODE - The error code indicating the type of error, which may include the entity that caused the revert on-chain.
MESSAGE - The human-readable error that may include a decoding of the `DATA` field if possible.

#### Create a new JSON-RPC API method `eth_estimateRip7560TransactionGas`

Performs a search for gas limit values required to make each of the frames of the RIP-7560 transaction execute
successfully and without running out of gas.
Note that for validation frames, only valid calls to an appropriate `AA_ENTRY_POINT` callback,
such as `acceptAccount`, `acceptPaymaster`, `sigFailAccount` and `sigFailPaymaster`, is considered a success.

If it fails to find such a value, returns an error message with the detailed description of the failure reason.

Parameters:

1. OBJECT - The RIP-7560 transaction object (as defined in `eth_sendRip7560Transaction`).
   The `validationGasLimit`, paymasterValidationGasLimit, `paymasterGasLimit` and `callGasLimit` fields are optional.
2. QUANTITY | TAG - integer block number, or the string "latest", "earliest", "pending", "safe" or "finalized"
3. OBJECT - State override set
   The State Override Set option allows you to change the state of a contract before executing the call. This means you
   can modify the values of variables stored in the contract, such as balances and approvals for that call without
   actually modifying the contract on the blockchain.
   This behavior is equivalent to the one defined for the `eth_call` RPC method.

Returns:

1. Object

| Name                        | Type     |
|-----------------------------|----------|
| validationGasLimit          | QUANTITY |
| paymasterValidationGasLimit | QUANTITY |
| paymasterPostOpGasLimit     | QUANTITY |
| callGasLimit                | QUANTITY |

Error:

DATA - The revert data of the first reverted frame.
CODE - The error code indicating the type of error, which may include the entity that caused the revert on-chain.
MESSAGE - The human-readable error that may include a decoding of the `DATA` field if possible.

##### Notes on implementation details

As mentioned in the RIP-7560, the `sender` and `paymaster` contracts should not revert on the validation failure
and should make calls to `sigFailAccount` and `sigFailPaymaster` respectively
in order to support `eth_estimateRip7560TransactionGas`.

The recommended way to achieve this behavior for Smart Contract Accounts and Paymasters is to compare the `signature`
parameter to a predetermined "dummy signature" and to call a `sigFail` callback in case the values match.

#### Create a new JSON-RPC API method `eth_traceRip7560Validation`

Only executes the validation phase of the RIP-7560 transaction and returns the tracing results of this execution.
This is done in order to allow other clients to determine
whether all contracts used within the validation phase of this transaction are compliant with the rules
defined in the [ERC-7562](https://eips.ethereum.org/EIPS/eip-7562).

Parameters:

1. OBJECT - The RIP-7560 transaction object (as defined in `eth_sendRip7560Transaction`).
2. QUANTITY | TAG - a block number, or the string "earliest", "latest", "pending", "safe" or "finalized", as in the
   default block parameter.

Returns:

1. OBJECT - the tracing result of executing the entire validation phase of the RIP-7560 transaction.

Example of the tracing result JSON response:

```json
{
  "callsFromEntryPoint": [
    {
      "topLevelTargetAddress": "<address>",
      "access": {
        "<address>": {
          "reads": {
            "slot": "value"
          },
          "writes": {
            "slot": "value"
          },
          "transientReads": {},
          "transientWrites": {}
        }
      },
      "opcodes": {
        "<OPCODE>": "<count>"
      },
      "contractSize": {
        "<address>": {
          "contractSize": 0,
          "opcode": "CALL"
        }
      },
      "calls": [
        {
          "type": "CALL",
          "from": "<address>",
          "to": "<address>",
          "method": "0x",
          "value": "0x0",
          "gas": 2000000,
          "gasUsed": 0,
          "data": "<data>"
        }
      ],
      "logs": [
        {
          "data": "<data>",
          "topic": [
            "<topic>"
          ]
        }
      ]
    }
  ]
}

```

### Error Codes

* code: -32500 - transaction validation failed by `sender`.
  The message field SHOULD be set to the revert message from the `sender`.

* code: -32501 - transaction validation failed by `paymaster`.
  The message field SHOULD be set to the revert message from the `paymaster`.

* code: -32502 - transaction validation failed by `deployer`
  The message field SHOULD be set to the revert message from the `deployer`.

* code: -32503 - Transaction out of time range.
  The message field SHOULD include the requested time range and the current block timestamp.

## Rationale

### Creating `eth_executeRip7560Transaction` instead of modifying `eth_call`

The semantics of the `eth_call` are currently very simple for all existing transaction types, and would become
significantly more complex with the addition of the RIP-7560 transaction type support.

It seems like the difference between these transaction types warrants a separate standalone RPC API method.

## Security Considerations

The RPC API methods standard described in this document does not have any consequences for the security of the
Native Account Abstraction ecosystem.

The implementations of these APIs, especially the ones related to generating a `signature` for a transaction,
must be extremely careful when handling the Smart Contract Accounts' credentials.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
