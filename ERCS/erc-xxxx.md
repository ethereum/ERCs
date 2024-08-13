---
eip: xxxx
title:
description:
author:
discussions-to:
status: Draft
type: Standards Track
category: ERC
created:
requires:
---

## Abstract

## Motivation

## Specification

#### `eth_sendRawTransaction`

Parameters

1. DATA - The signed RLP-encoded RIP-7560 transaction data.

Returns

1. DATA, 32 Bytes - the transaction hash, or the zero hash if the transaction is not yet available.

#### `eth_sendRip7560Transaction`

Parameters:

1. Object - The RIP-7560 transaction object

| Name                            | Type           | Description                                                    |
|---------------------------------|----------------|----------------------------------------------------------------|
| **sender**                      | DATA, 20 Bytes | Address of the Smart Contract Account making the transaction   |
| **deployer**                    | DATA, 20 Bytes | Address of the Deployer - account factory contract             |
| **deployerData**                | DATA           | Data that is provided to the Deployer contract                 |
| **paymaster**                   | DATA, 20 Bytes | Address of the Pyaymaster contract                             |
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
| **signature**                   | DATA           | A signature of any kind used by Account to verify transaction  |

\* fields marked as **bold** are unique for the RIP-7560 transaction type

Returns:

1. DATA, 32 Bytes - the transaction hash, or the zero hash if the transaction is not yet available.

Error:

DATA - The revert data of the first reverted frame.
CODE - The error code indicating the type of error, which may include the entity that caused the revert on-chain.
MESSAGE - The human-readable error that may include a decoding of the `DATA` field if possible.

#### `eth_getTransactionByHash`

Parameters

1. DATA, 32 Bytes - hash of a transaction

Returns

1. Object - A transaction object, or null when no transaction was found:

| Name             | Type           | Description                                                           |
|------------------|----------------|-----------------------------------------------------------------------|
| blockHash        | DATA, 32 Bytes | Hash of the block where this transaction was in, or null when pending |
| blockNumber      | QUANTITY       | Block number where this transaction was in, or null when pending      |
| transactionIndex | QUANTITY       | The transaction's index position in the block, or null when pending   |
| type             | QUANTITY       | The transaction type                                                  |

\* followed by the entire RIP-7560 transaction object as described in `eth_sendRip7560Transaction`

#### `eth_getTransactionReceipt`

For an `AA_TX_TYPE` transaction is included in a block, returns the following values in addition to the existing fields:

Returns

1. Object - A transaction receipt object, or null when no receipt was found:

Fields specific to an RIP-7560 transaction receipt:

| Name                       | Type            | Description                                                                    |
|----------------------------|-----------------|--------------------------------------------------------------------------------|
| sender                     | DATA, 20 Bytes  | Address of the sender of this transaction                                      |
| paymaster                  | DATA, 20 Bytes  | Address of the Paymaster if it is paying for the transaction, null otherwise   |
| deployer                   | DATA, 20 Bytes  | Address of the Deployer if it is included in the transaction, null otherwise   |
| senderCreationGasUsed      | QUANTITY        | The amount of gas actually used by the sender deployment frame                 |
| senderValidationGasUsed    | QUANTITY        | The amount of gas actually used by the sender validation frame                 |
| paymasterValidationGasUsed | QUANTITY        | The amount of gas actually used by the paymaster validation frame              |
| executionGasUsed           | QUANTITY        | The amount of gas actually used by the execution frame                         |
| postOpStatus               | QUANTITY        | 1 (success), 0 (failure), or `null` (did not run) status of the `postOp` frame |
| postOpGasUsed              | QUANTITY        | The amount of gas actually used by the paymaster `postOp` frame                |
| validationLogs             | ARRAY           | Array of log objects, which this transaction'S VALIDATION FRAME generated.     |
| validationLogsBloom        | DATA, 256 Bytes | Array of log objects, which this transaction'S VALIDATION FRAME generated.     |

Continued, these fields are shared by all transaction types:

| Name              | Type            | Value                                                                                    |
|-------------------|-----------------|------------------------------------------------------------------------------------------|
| transactionHash   | DATA, 32 Bytes  | Hash of the transaction.                                                                 |
| transactionIndex  | QUANTITY        | Integer of the transactions index position in the block.                                 |
| blockHash         | DATA, 32 Bytes  | Hash of the block where this transaction was in.                                         |
| blockNumber       | QUANTITY        | Block number where this transaction was in.                                              |
| cumulativeGasUsed | QUANTITY        | The total amount of gas used when this transaction was executed in the block.            |
| effectiveGasPrice | QUANTITY        | The sum of the base fee and tip paid per unit of gas.                                    |
| gasUsed           | QUANTITY        | The amount of gas used by this specific transaction alone.                               |
| contractAddress   | DATA, 20 Bytes  | The contract address created, if the transaction was a contract creation, otherwise null |
| logs              | ARRAY           | Array of log objects, which this transaction'S EXECUTION FRAME generated.                |
| logsBloom         | DATA, 256 Bytes | Bloom filter for light clients to quickly retrieve related logs.                         |
| type              | QUANTITY        | Integer of the transaction type                                                          |
| status            | QUANTITY        | Either 1 (success) or 0 (failure) status of the execution frame                          |

#### `eth_executeRip7560Transaction`

Parameters:

1. Object - The RIP-7560 transaction object (as defined in `eth_sendRip7560Transaction`).
   The `signature` field is optional.

Returns:

DATA - The return value of the `sender` execution frame.

Error:

DATA - The revert data of the first reverted frame.
CODE - The error code indicating the type of error, which may include the entity that caused the revert on-chain.
MESSAGE - The human-readable error that may include a decoding of the `DATA` field if possible.

#### `eth_estimateRip7560TransactionGas`

Parameters:

1. Object - The RIP-7560 transaction object (as defined in `eth_sendRip7560Transaction`).
   The `validationGasLimit`, `paymasterGasLimit`, `callGasLimit` fields are optional.
2. QUANTITY|TAG - integer block number, or the string "latest", "earliest", "pending", "safe" or "finalized"
3. Object - State override set
   The State Override Set option allows you to change the state of a contract before executing the call. This means you
   can modify the values of variables stored in the contract, such as balances and approvals for that call without
   actually modifying the contract on the blockchain.
   This behavior is equivalent to the one defined for the `eth_call` RPC method.

Returns:

1. Object

| Name               | Type     |
|--------------------|----------|
| validationGasLimit | QUANTITY |
| paymasterGasLimit  | QUANTITY |
| callGasLimit       | QUANTITY |
| builderFee         | QUANTITY |

Error:

DATA - The revert data of the first reverted frame.
CODE - The error code indicating the type of error, which may include the entity that caused the revert on-chain.
MESSAGE - The human-readable error that may include a decoding of the `DATA` field if possible.

##### Notes on implementation details

As mentioned earlier, the `sender` and `paymaster` contracts should not revert on the validation failure
and should make calls to `sigFailAccount` and `sigFailPaymaster` accordingly
in order to support `eth_estimateRip7560TransactionGas`.

The recommended way to achieve this behavior for Smart Contract Accounts and Paymasters is to compare the `signature`
parameter to a predetermined "dummy signature" and to call a `sigFail` callback in case the values match.

#### `eth_traceRip7560Validation`

TODO

### Error Codes

## Rationale

## Security Considerations

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
