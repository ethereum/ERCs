---
title: Smart Blobs
description: State machine based on lazy evaluation on top of blobspace
author: Rani El Husseini (@charmful0x), Benjamin Brandall (@xylophonez), Nik Rykov (@angrymouse)
discussions-to: https://ethereum-magicians.org/t/add-erc-smart-blobs/19672
status: Draft
type: Standards Track
category: ERC
created: 2024-04-15
requires: 1559, 4844
---


## Abstract
This EIP introduces "smart blobs" and standardizes an implementation of the [SmartWeave](https://github.com/ArweaveTeam/SmartWeave) protocol on top of EIP-4844 blobs, ensuring a certain degree of compatibility with the EVM.

## Motivation

Executing complex data computations directly on the EVM execution layer is costly and often not economically feasible. In 2020, SmartWeave introduced an Arweave-based protocol that operates as a general lazy evaluator for data computation. By implementing smart blobs, this proposal aims to decouple state transitions (which occur on-chain, using blobs) from execution processes (which occur off-chain, using a SmartWeave instance), enhancing efficiency and reducing costs.

Additionally, this EIP addresses the isolation of the SmartWeave protocol within the Arweave network and the lack of DA guarantees in Arweave. Smart blobs provide a standardized framework for deploying a SmartWeave execution machine for any EVM network that supports EIP-4844.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.


### Protocol design

The design of the proposal’s protocol is both a simple and straightforward ***computation protocol***. State transitions (transactions) are posted as EIP-4844 transactions by the user on the EVM network and then submitted by the user or dApp to the sequencer. The sequencer captures the EVM on-chain transaction, decodes the transaction data, performs the corresponding off-chain execution, and then indexes the state changes in the cloud (cache) after transmitting the blob data to Arweave.

To simplify the expansion of the protocol design, "blobvm" refers to an execution machine deployed according to the standards of this EIP. The terms "smart blob" and "blobvm smart contract" are used interchangeably.

### blobVM transactions

On the protocol level, blobVM distinguishes between 2 types of transactions:

- `type 1` : contract deployments
- `type 2` : contract calls

Transactions data structure MUST be as follows:

#### Contract deployment
```json
{
  "type": 1,
  "sc": [],
  "state":[]
}
```
#### Contract call
```json
{
  "type": 2,
  "inputs": [],
}
```

**Data encoding**

The properties `sc`, `state`, and `inputs` are initialized as listed below. They are then encoded according to the function `encodeBvmData()`

- `sc` : UTF-8 representation of the source code
- `state` : initial state as stringified JSON 
- `inputs` : stringified JSON of the contract's function call object

```ts
function encodeBvmData(data: string): number[] {
  const encodedData = data.split("").map((char) => char.charCodeAt(0));
  return encodeBvmData;
}
```

#### Additional information about Transactions:
- Regardless of the type, the transaction ***total size** MUST be less than or equal to 128 KiB.
- The EIP-4844 transaction (on-chain) MUST contain strictly one operation only.

### Examples

Smart Blobs can be written in any interpreted language, or in a compiled language provided it uses WASM. We will demonstrate two Smart Blob examples: a counter and a dummy token.

#### Counter Smart Blob

##### Counter Pseudocode
```plaintext
Function handle (state, action)
    Set input to action.input

    If input.function equals "increment" Then
        Increase state.counter by 1
        Add blobvm.msg.sender to state.users list
        Return state
    End If
End Function
```
##### Counter source code in JS
```js
export async function handle(state, action) {
  const input = action.input;

  if (input.function === "increment") {
    state.counter += 1;
    state.users.push(blobvm.msg.sender);
    return { state };
  }
}
```
##### Counter source code in Python
```python
def handle(state, action):
    input = action['input']

    if input['function'] == 'increment':
        state['counter'] += 1
        state['users'].append(action['sender'])
        return state

```
#### Counter initial state
```json
{
  "counter": 0,
  "users": []
}
```
#### Dummy Token Smart Blob
For the other example, Dummy Token Smart Blob, we will just add the source code in JS

##### Dummy Token source code in JS
```js
export async function handle(state, action) {
  const input = action.input;

  if (input.function === "mint") {
    const { amount } = input;
    ContractAssert(blobvm.msg.sender === state.owner, "err_invalid_caller");
    const newOwnerBalance =
      BigInt(amount) + BigInt(state.balances[state.owner]);
    state.balances[state.owner] = String(newOwnerBalance);
    return { state };
  }

  if (input.function === "transfer") {
    const { target, amount } = input;

    ContractAssert(blobvm.msg.sender in state.balances, "err_caller_not_found");

    const bintAmount = BigInt(amount);
    const callerBalance = BigInt(state.balances[blobvm.msg.sender]);

    ContractAssert(/^0x[a-fA-F0-9]{40}$/.test(target), "err_invalid_address");
    ContractAssert(callerBalance >= bintAmount, "err_invalid_amount");

    if (!(target in state.balances)) {
      state.balances[target] = BigInt(0n);
    }

    const newTargetBalance = bintAmount + BigInt(state.balances[target]);
    state.balances[target] = String(newTargetBalance);

    const newCallerBalance =
      BigInt(state.balances[blobvm.msg.sender]) - bintAmount;
    state.balances[blobvm.msg.sender] = String(newCallerBalance);

    return { state };
  }
}
```
##### Dummy Token initial state
```json
{
  "ticker": "SMARTBLOB",
  "decimals": 18,
  "balances": {},
  "owner": "0x197f818c1313DC58b32D88078ecdfB40EA822614"
}
```


## About the Execution Machine's Sequencer

Although developers have the freedom to extend or limit the sequencer's functionalities, there are 3 required components: the blobVM context, the gas formula, and the gateway interface.

### blobVM Context

The blobVM context is injected by the sequencer during the lazy evaluation of a transaction. Below are the mandatory methods in the Context:

| method  | description |
| :-------------: |:-------------:|
| `blobvm.msg.sender` | return the transaction sender (EOA)     |  
| `blobvm.tx.id`      | return the call's transaction id     |  


### Gas formula
A blobVM transaction consists of two factors affecting the gas calculation: gas paid for the EVM layer 1 (L1) and gas paid to the blobVM sequencer (Sequencer):

- **Gas Paid for L1**: This is the gas paid by a transaction that implements [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) and [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) standards.

- **Gas Paid to the Sequencer**: This occurs within the same transaction. It involves transferring a sufficient amount of gas fee to the sequencer's address under the `to` (destination) field.

The gas cost of a blobVM transaction (types `1` and `2`) is calculated as follows:

```plaintext
tx_gas = l1_gas_fees + (262604 * winston_byte_price * 1e-12 * ar_usd_price / eth_usd_price) * bvm_multiplier
```

#### Equation Terms Breakdown:

- `l1_gas_fees`: The gas paid to post the transaction to the EVM network.
- `262604`: The total byte size of an EIP-4844 transaction when archiving on Arweave. This includes data, KZG commitments, and proof.
- `winston_byte_price`: The cost price per byte on Arweave. This is dynamic and can be checked at `https://arweave.net/price/262604`.
- `1e-12 * ar_usd_price`: The conversion of `winston_byte_price` from winstons to AR and then to USD.
- `sequencer_multiplier` (>= 1): The total Arweave cost, converted to ETH, is then multiplied by the sequencer premium multiplier.

### Gateway interface
The designed sequencer MUST consistently expose the following methods:

#### Reading contract state

```bash
curl -X GET base_endpoint/state/target_contract_addr
```

#### Deploying a contract

```bash
curl -X POST -H "Content-Type: application/json" -d '{"txid": "contract_eip4844_txid"}' base_endpoint/deploy 
```

#### Sending a transaction

```bash
curl -X POST -H "Content-Type: application/json" -d '{"txid": "eip4844_txid"}' base_endpoint/transactions 
```
***N.B: Smart Blobs sequencers are centralized and do not offer censorship resistance guarantees. The end user must rely on the good faith of the sequencer.***

## Rationale
This proposal hopes to accomplish the following:
* Standardizing the usage of EIP-4844 blobs within the scope of creating execution machines on top of the blobspace
* Utilize SmartWeave's lazy evaluation paradigm within the EVM space.
* Extend the capabilities of lazy evaluation by using window-timegated DA
* Utilize blobspace instead of calldata to leverage off-chain execution more cheaply
* Write Smart Blobs in any interpreted language, or in a compiled language provided it uses WASM (JavaScript, Python, Rust, Lua, etc.)


## Backwards Compatibility
There is no existing standard for smart blobs as described in this EIP, indicating that the proposal introduces new standard without conflicting with or altering any current implementations.


## Reference Implementation

A reference implementation of this proposal is currently being developed by the weaveVM organization. The ongoing development can be accessed on GitHub at the following URL: [weaveVM blobvm-core](https://github.com/weavevm/blobvm-core).


## Security Considerations

While the proposed protocol allows any computation, referred computation should be deterministic (with the exception of a few rare cases like chain forks, which are not directly related to the execution of the transaction). This is because to fetch the final state of the contract, an entity requiring this state must execute all past state transitions (transactions) of the required contract. 

The ability to do any non-deterministic behavior in the runtime would mean the possibility of different states on each re-evaluation (and so each time the contract's state is fetched in a trustless way).

The execution also has to be gas-metered to avoid resource abuse and DoS attacks.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).




