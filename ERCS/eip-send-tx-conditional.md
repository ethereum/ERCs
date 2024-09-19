```---
eip: send-tx-cond
title: Conditional send transaction RPC
description: Conditional send transaction RPC for better integration with sequencers
author: Dror Tirosh (@drortirosh), Yoav Weiss (@yoavw), Alex Forshtat (@forshtat), Shahaf Nacson (@shahafn)
discussions-to:
status: Draft
type: Standards Track
category: Interface
created: 2024-04-16
---
```

## Abstract

This EIP proposes a new RPC method `eth_sendRawTransactionConditional` for block builders and sequencers, enhancing transaction integration by allowing preconditions for transaction inclusion. This method aims to improve efficiency by reducing the need for transaction simulation, thereby improving transaction ordering cpu cost.

## Motivation

Current private APIs, such as the Flashbots API, require block builders to simulate transactions to determine eligibility for inclusion, a process that is CPU-intensive and inefficient. The proposed RPC method addresses this by enabling transactions to specify preconditions, thus reducing computational overhead and potentially lowering transaction costs.

Moreover, the flashbots API doesn't give any tool to a block-builder to determine the cross-dependencies of different transactions. The only way to guarantee that another transaction doesn't interfere with a given one is by placing it as the first transaction in the block.
This makes this placement very lucrative, and disproportionately expensive.
In addition, since there is no way to give any guarantee on other slots, their pricing has to be low accordingly.

Since there is no easy way to detect cross-dependencies of different transactions, it is cpu-intensive to find an optimal ordering of transactions.


### Out of scope

This document does not define an algorithm for a block builder to select a transaction in case of conflicting transactions.

## Specification

* Method: `eth_sendRawTransactionConditional`

* Parameters:

1.   transaction: The raw, signed transaction data. Similar to `eth_sendRawTransaction`
2. options: An object containing conditions under which the transaction must be included.
* The "options" param may include any of the following members:
    * **knownAccounts**: a map of accounts with expected storage
        * The key is account address
        * If the value is **hex string**, it is the known storage root hash of that account.
        * If the value is an **object**, then each member is in the format of `"slot": "value"`, which are explicit slot values within that account storage.
          both `slot` and `value` are hex values
        * a special key `balance` define the expected balance of the account
    * **blockNumberMin**: [optional] minimal block number for inclusion
    * **blockNumberMax**: [optional] maximum block number for inclusion
    * **timestampMin**: [optional] minimum block timestamp for inclusion
    * **timestampMax**: [optional] maximum block timestamp for inclusion
    * **paysConbase**: paysCoinbase[optional] this is not a precondition, but an expected outcome: the caller declares the minmimum amount paid to the coinbase by this transaction (including gas fees and direct payment)
      It is only relevant if the API is used to define a "marketplace" for clients to compete on inclusion.


* Before accepting the request, the block-builder/sequencer SHOULD:
    * If block range was given, check that the block number is within the range.
    * If timestamps range was given, check that the block's timestamp is within the range.
    * For an address with a storage root hash, validate the current root is unmodified.
    * For an address with a list of slots, it should verify that all these slots hold the exact value specified.
* The sequencer should REJECT the request if any address is doesn't pass the above rules.

### Return value

In case of successful inclusion, the call should return the same value as `sendRawTransaction` (namely, the transaction-hash)
In case of failure, it SHOULD return an error with indication of failure reason.
The error code SHOULD be -32003 (transaction rejected) with reason string describing the cause: storage error, out of block/time range,
In case of repeated failures or knownAccounts too large, the error code SHOULD be -32005 (Limit exceeded) with a description of the error

**NOTE:** Even if the transaction was accepted (into the internal mempool), the caller MUST NOT assume block inclusion, and must monitor the blockchain.


## Sample request:
```json
{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "eth_sendRawTransactionConditional",
    "params": [
        "0x2815c17b00...",
        {
            "blockNumberMax": 12345,
            "knownAccounts": {
                "0xadd1": "0xfedc....",
                "0xadd2": { 
                    "0x1111": "0x1234...",
                    "0x2222": "0x4567..."
                }
            }     
        } 
    ]
}
```
### Possible Use-cases:

- **auction market**:
- **alternative to flashbot api**:
  The flashbot api requires the builder to simulate the transactions to determine their cross-dependency. This can be cpu consuming.
  For high-MEV, this is acceptable, but not for cheap general-purpose account-abstraction transactions.

### Limitations

- Callers should not assume that a successul response means the transaction is included
  In particular, it is possible that a block re-order might remove the transaction, or cause it to fail, just like any other transaction.

### Security Consideration

The block-builder should protect itself against abuse of the API, namely, submitting a large #  of requests which are known to fail.

Following are suggested mechanisms:

* **Throttling**: the block builder should allow a maximum rate of rpc calls per sender, and increase
  that rate after successful inclusion. repeated rejection of blocks should reduce the allowed rate.
* **Arbitrum**-style protection: Arbitrum implemented this API, but they run the storage validation not only
  against the current block, but also into past 2 seconds.
  This prevents abusing the API for MEV, while making it viable for ERC-4337 account validation
* **Fastlane on Polygon** uses it explicitly for ERC-4337, by checking the submitted UserOperations exist on the public mempool (and reject the transaction otherwise)
