---
eip: XXXX
title: UserOperation Builder
description: Construct UserOperations without being coupled with account-specific logic.
author: Derek Chiang (derek@zerodev.app), Garvit Khatri (@plusminushalf), Fil Makarov (@filmakarov), Kristof Gazso (@kristofgazso), Derek Rein (@arein), Juan Caballero (@bumblefudge), Tomas Rocchi (@tomiir), Jake Moxey (@jxom)
discussions-to: https://ethereum-magicians.org/t/erc-XXXX-standardized-smart-account-interfaces/tbd
status: Draft
type: Standards Track
category: ERC
created: 2024-04-05
requires: 4337
---

## Abstract

Different [ERC-4337](./eip-4337.md) smart account implementations encode their signature, nonce, and calldata differently.  This makes it difficult for DApps, wallets, and smart account toolings to integrate with smart accounts without integrating with account-specific SDKs, which introduces vendor lock-in and hurts smart account adoption.

We propose a standard way for smart account implementations to put their account-specific encoding logic on-chain.

## Motivation

At the moment, to build a [ERC-4337](./eip-4337.md) UserOperation (UserOp for short) for a smart account requires detailed knowledge of how the smart account implementation works, since each implementation is free to encode its nonce, calldata, and signature differently.

As a simple example, one account might use an execution function called `executeFoo`, whereas another account might use an execution function called `executeBar`.  This will result in the `calldata` being different between the two accounts, even if they are executing the same call.

Therefore, someone who wants to send a UserOp for a given smart account needs to:

* Figure out which smart account implementation the account is using.
* Correctly encode signature/nonce/calldata given the smart account implementation, or use an account-specific SDK that knows how to do that.

In practice, this means that most DApps, wallets, and AA toolings today are tied to a specific smart account implementation, resulting in fragmentation and vendor lock-in.

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119.

### UserOp builder

To conform to this standard, a smart account implementation must provide a “UserOp builder” contract that implements the IUserOperationBuilder interface, as defined below:


```solidity
struct Execution {
    address target;
    uint256 value;
    bytes callData;
}

interface IUserOperationBuilder {
		/**
     * @dev Returns the ERC-4337 EntryPoint that the account implementation
     * supports.
     */
    function entryPoint() external view returns (address);
    
    /**
     * @dev Returns the nonce to use for the UserOp, given the context.
     * @param smartAccount is the address of the UserOp sender.
     * @param context is the data required for the UserOp builder to
     * properly compute the requested field for the UserOp.
     */
    function getNonce(
        address smartAccount,
        bytes calldata context
    ) external view returns (uint256);
	
    /**
     * @dev Returns the calldata for the UserOp, given the context and
     * the executions.
     * @param smartAccount is the address of the UserOp sender.
     * @param executions are (destination, value, callData) tuples that
     * the UserOp wants to execute.  It's an array so the UserOp can
     * batch executions.
     * @param context is the data required for the UserOp builder to
     * properly compute the requested field for the UserOp. 
     */
    function getCallData(
        address smartAccount,
        Execution[] calldata executions,
        bytes calldata context
    ) external view returns (bytes memory);
    
    /**
     * @dev Returns the dummy signature for the UserOp, given the context
     * and the executions.
     * @param smartAccount is the address of the UserOp sender.
     * @param executions are (destination, value, callData) tuples that
     * the UserOp wants to execute.  It's an array so the UserOp can
     * batch executions.
     * @param context is the data required for the UserOp builder to
     * properly compute the requested field for the UserOp.
     */
    function getDummySignature(
        address smartAccount,
        Execution[] calldata executions,
        bytes calldata context
    ) external view returns (bytes memory signature);
    
    /**
     * @dev Returns a correctly encoded signature, given a UserOp that
     * has been correctly filled out except for the signature field.
     * @param smartAccount is the address of the UserOp sender.
     * @param userOperation is the UserOp.  Every field of the UserOp should
     * be valid except for the signature field.  The "PackedUserOperation"
     * struct is as defined in ERC-4337.
     * @param context is the data required for the UserOp builder to
     * properly compute the requested field for the UserOp.
     */
    function getSignature(
        address smartAccount,
        PackedUserOperation calldata userOperation,
        bytes calldata context
    ) external view returns (bytes memory signature);
}
```

### Using the UserOp builder

To build a UserOp using the UserOp builder, the building party should proceed as follows:

1. Obtain the address of `UserOpBuilder` and a `context` from the account owner.  The `context` is an opaque bytes array from the perspective of the building party.  The smart account implementation may need the `context` in order to properly figure out the UserOp fields.  See the “Rationale” section for more info.
2. Execute a multicall (batched `eth_call`s) of `getNonce`, `getCallData`, `getDummySignature` with the `context` and executions.  The building party will now have obtained the nonce, calldata, and dummy signature (see “Rationale” for what a dummy signature is).
3. Fill out a UserOp with the data obtained previously.  This UserOp must be valid except for the `signature` field.  Then call (via `eth_call`) `getSignature` with the UserOp and `context` to obtain a completely valid UserOp.
    1. Note that a UserOp has a lot more fields than `nonce`, `callData`, and `signature`, but how the building party obtains the other fields is outside of the scope of this document, since only these three fields are heavily dependent on the smart account implementation.

At this point, the building party has a completely valid UserOp that they can then submit to a bundler or do whatever it likes with it.

## Using the UserOp builder when the account hasn’t been deployed

If the account has yet to be deployed, which means that the building party is looking to send the very first UserOp for this account, then the building party may modify the flow above as follows:

- In addition to the `UserOpBuilder` address and the `context`, the building party also obtains the `factory` and `factoryData` as defined in ERC-4337.
- When calling one of the view functions on the UserOp builder, the building party may use `eth_call` to deploy the `CounterfactualCall` contract with `factory` and `factoryData` (see below).  The `CounterfactualCall` contract would deploy the account before calling the view functions on the UserOp builder.
- When filling out the UserOp, the building party includes `factory` and `factoryData`.

## Counterfactual call

The counterfactual call contract is inspired by [ERC-6492](./eip-6492.md), which devised a mechanism to execute `isValidSignature` (ERC-1271) against a pre-deployed (counterfactual) contract.

```solidity
contract CounterfactualCall {
    
    error CounterfactualDeployFailed(bytes error);

    constructor(
        address smartAccount,
        address create2Factory, 
        bytes memory factoryData,
        address userOpBuilder, 
        bytes memory userOpBuilderCalldata
    ) { 
        if (address(smartAccount).code.length == 0) {
            (bool success, bytes memory err) = create2Factory.call(factoryData);
            if (!success) revert CounterfactualDeployFailed(err);
        }

        assembly {
            let success := call(gas(), userOpBuilder, 0, add(userOpBuilderCalldata, 0x20), mload(userOpBuilderCalldata), 0, 0)
            let ptr := mload(0x40)
            returndatacopy(ptr, 0, returndatasize())
            if iszero(success) {
                revert(ptr, returndatasize())
            }
            return(ptr, returndatasize())
        }
    }
    
}
```

Here’s an example of calling this contract using the ethers and viem libraries:

### Fractionally Represented Non-Fungible Token Banking Interface

This is a RECOMMENDED interface that is intended to be used by implementations of [ERC-7651](./eip-7651.md) that implement NFT ID reuse.

```javascript
// ethers
const nonce = await provider.call({
  data: ethers.utils.concat([
    counterfactualCallBytecode,
    (
      new ethers.utils.AbiCoder()).encode(['address','address', 'bytes', 'address','bytes'], 
      [smartAccount, userOpBuilder, getNonceCallData, factory, factoryData]
    )
  ])
})

// viem
const nonce = await client.call({
  data: encodeDeployData({
    abi: parseAbi(['constructor(address, address, bytes, address, bytes)']),
    args: [smartAccount, userOpBuilder, getNonceCalldata, factory, factoryData],
    bytecode: counterfactualCallBytecode,
  })
})
```

### Fractionally Represented Non-Fungible Token Transfer Exemptable Interface

This is a RECOMMENDED interface that is intended to be used by implementations of [ERC-7651](./eip-7651.md) that want to allow users to opt-out of NFT transfers.

```solidity
interface IERC7651NFTTransferExemptable {
  /// @notice Returns whether an address is NFT transfer exempt.
  /// @param account_ The address to check.
  /// @return Whether the address is NFT transfer exempt.
  isNFTTransferExempt(address account_) external view returns (bool);

  /// @notice Allows an address to set themselves as NFT transfer exempt.
  /// @param isExempt_ The flag, true being exempt and false being non-exempt.
  setSelfNFTTransferExempt(bool isExempt_) external;
}
```

## Rationale

### Context

The `context` is an array of bytes that encodes whatever data the UserOp builder needs in order to correctly determine the nonce, calldata, and signature.  Presumably, the `context` is constructed by the account owner, with the help of a wallet software.

Here we outline one possible use of `context`: delegation.  Say the account owner wants to delegate a transaction to be executed by the building party.  The account owner could encode a signature of the public key of the building party inside the `context`.  Let’s call this signature from the account owner the `authorization`.

Then, when the building party fills out the UserOp, it would fill the `signature` field with a signature generated by its own private key.  When it calls `getSignature` on the UserOp builder, the UserOp builder would extract the `authorization` from the `context` and concatenates it with the building party’s signature.  The smart account would presumably be implemented such that it would recover the building party’s public key from the signature, and check that the public key was in fact signed off by the `authorization`.  If the check succeeds, the smart account would execute the UserOp, thus allowing the building party to execute a UserOp on the user’s behalf.

### Dummy signature

The “dummy signature” refers to the signature used in a UserOp sent to a bundler for estimating gas (via `eth_estimateUserOperationGas`).  A dummy signature is needed because, at the time the bundler estimates gas, a valid signature does not exist yet, since the valid signature itself depends on the gas values of the UserOp, creating a circular dependency.  To break the circular dependency, a dummy signature is used.

However, the dummy signature is not just a fixed value that any smart account can use.  The dummy signature must be constructed such that it would cause the UserOp to use about as much gas as a real signature would.  Therefore, the dummy signature varies based on the specific validation logic that the smart account uses to validate the UserOp, making it dependent on the smart account implementation.

## Backwards Compatibility

This ERC is intended to be backwards compatible with all ERC-4337 smart accounts as of EntryPoint 0.7.

For smart accounts deployed against EntryPoint 0.6, the `IUserOperationBuilder` interface needs to be modified such that the `PackedUserOperation` struct is replaced with the corresponding struct in EntryPoint 0.6.

## Security Considerations

No new trust assumptions or functionality are introduced in this ERC. It standardizes existing functionality.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
