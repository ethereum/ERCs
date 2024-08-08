---
eip: TBD
title: Cross-L2-Call Specification
description: Contract standard for cross-L2 calls facilitation
author: Wilson Cusack (@WilsonCusack)
discussions-to: pending
status: Draft
type: Standards Track
category: Core
created: 2024-08-07
---

## Abstract 
Contracts for facilitating request, fulfillment, and fulfillment reward of cross-L2 calls.

## Motivation
Ethreum layer 2 (L2) users should have access to a public, decentralized utility for making cross L2 calls. 

From any L2 chain, users should be able to request a call be made on any other L2 chain. Users should be able to guarentee a compensation for this call being made, and thus be able to control the liklihood this call will be made. 

User should have full assurance that compensation will only be paid if the call was made. This assurance should depend ONLY on onchain information. 

## Specification
To only rely on onchain information, we use
1. L1 blockhashes on the L2. 
    - We take as an assumption that every L2 should have a trusted L1 blockhash in the execution environment. 
2. L2 blockhashes on the L1.
   - e.g. via an [L2 Output Oracle Contract](https://specs.optimism.io/glossary.html?#l2-output-oracle-contract)

Using these inputs, on any L2, we can trustlessly verify [ERC-1183](https://eips.ethereum.org/EIPS/eip-1186) storage proofs of any other L2. 

Our contracts' job, then, is to represent call requests and fulfillment in storage on each chain. 

### CrossChainCall Struct 
```solidity 
struct CrossChainCall {
    // The address to call
	address callTo;
    // The calldata to call with
	bytes callData;
	// The native asset value of the call
	uint256 callValue;
    // The contract on origin chain where this cross-chain call request originated
    address originationContract;
    // The chainId of the origin chain
    uint originChainId;
    // The chainId of the destination chain
    uint destinationChainId;
	// The nonce of this call, to differentiate from other calls with the same values
	uint256 nonce;
	// The L2 contract on destination chain that's storage will be used to verify whether or not this call was made
	address verifyingContract;
	// The L1 address of the contract that should have L2 block info stored
	address l2Oracle;
	// The storage key at which we expect to find the L2 block info on the l2Oracle
	bytes32 l2OracleStorageKey;
	// The reward asset to be paid to whoever proves they filled this call
    // Native asset specified as in ERC-7528 format
	address rewardAsset;
	// The reward amount to pay 
	uint256 rewardAmount;
	// The minimum age of the L1 block used for the proof
	uint256 finalityDelaySeconds;
}

```

### CrossChainCallOriginator Contract
On the origin chain, there is an origination contract to receive cross-chain call requests and payout rewards on proof of their fulfillment. 

```solidity
pragma solidity ^0.8.23;

abstract contract CrossChainCallOriginator {

  enum CrossChainCallStatus {
    None,
    Requested,
    CancelRequested,
    Completed
  }

  error InvalidValue(uint expected, uint received);

  event CrossChainCallRequested(CrossChainCall call);

  mapping (bytes32 callHash => CrossChainCallStatus status) public requestStatus;

  address internal NATIVE_ASSET = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  uint internal _nonce;

  function requestCrossChainCall(CrossChainCall memory crossChainCall) external payable {
    crossChainCall.nonce = ++_nonce;
    crossChainCall.originChainId = block.chainid;
    crossChainCall.originationContract = address(this);
    requestStatus[keccak256(abi.encode(crossChainCall))] = CrossChainCallStatus.Requested;

    if (crossChainCall.rewardAsset == NATIVE_ASSET) {
      if (crossChainCall.rewardAmount != msg.value) {
        revert InvalidValue(crossChainCall.rewardAmount, msg.value);
      }
    } else {
      // SafeERC20(crossChainCall.rewardAsset).transferFrom(msg.sender, address(this), crossChainCall.rewardAmount);
    }

    emit CrossChainCallRequested(crossChainCall);
  }

  function claimReward(CrossChainCall calldata crossChainCall, bytes calldata storageProofData) external payable {  
    bytes32 storageKey = keccak256(
      abi.encodePacked(
        abi.encode(crossChainCall, msg.sender),
        uint(0) // Must be at slot 0
      )
    );
    
    _validate(storageKey, crossChainCall, storageProofData);

    // Pay reward

  }

  /// @dev Validates storage proofs and verifies that 
  /// verifyingContractStorageKey on crossChainCall.verifyingContract 
  /// is set to `true`. Raises error if proof not valid or value not `true`.
  /// @dev Implementation will vary by L2
  function _validate(bytes32 verifyingContractStorageKey, CrossChainCall calldata crossChainCall, bytes calldata storageProofData) internal virtual;

  // TODO requestCancel, finalizeCancel
}

### CrossChainCallFulfillment Contract
TODO

### Flow Diagrams
TODO
```