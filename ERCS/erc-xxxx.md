---
eip: XXXX
title: Atomic Module Installation for ERC-7579 Smart Accounts
description: Standard for installing and using ERC-7579 modules within a single user operation
author: Ernesto Garcia (@ernestognw), Taek Lee (@leekt)
discussions-to: TBD
status: Draft
type: Standards Track
category: ERC
created: 2025-10-02
requires: 712, 1271, 4337, 7579
---

## Abstract

This ERC defines a standard mechanism for [ERC-7579] compliant smart accounts to install and immediately use modules within a single user operation. The standard specifies a magic nonce prefix, signature encoding format, and [EIP-712] domain structure to enable atomic module installation while maintaining security through account owner authorization.

[ERC-7579]: ./eip-7579.md
[EIP-712]: ./eip-712.md
[ERC-1271]: ./eip-1271.md
[ERC-4337]: ./eip-4337.md
[ERC-7579]: ./eip-7579.md

## Motivation

Current [ERC-7579] implementations require separate transactions for module installation and usage, creating friction in user experience. Common use cases like session key modules and spending limit modules would benefit from atomic installation and immediate usage.

This standard addresses several key issues:

- **User Experience**: Reduces transaction count from 2+ to 1 for module installation and usage
- **Gas Efficiency**: Eliminates separate installation transactions
- **Interoperability**: Provides a standard pattern that works across different [ERC-7579] account implementations
- **Security**: Maintains strong authorization through [EIP-712] signatures from account owners

Real-world usage in production systems like Kernel has validated the need and feasibility of this pattern, particularly for session key management and dynamic module installation.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Atomic Module Installation**: The process of installing and using an [ERC-7579] module within a single user operation
- **Enable Mode**: The operational mode triggered by the atomic module prefix in the nonce
- **Installation Signature**: An [EIP-712] signature authorizing module installation
- **User Operation Signature**: The signature for validating the user operation itself

### Magic Nonce Prefix

Smart accounts implementing this standard MUST detect atomic module installation by checking for the magic prefix `0x01` in the most significant byte of the user operation nonce.

```solidity
bytes1 constant ATOMIC_MODULE_PREFIX = 0x01;

bytes1 result;
uint256 nonce = userOp.nonce;
assembly ("memory-safe") {
    result := and(nonce, shl(248, not(0)))
}
if (result == ATOMIC_MODULE_PREFIX) {
    // Enter atomic module installation mode
}
```

### Signature Encoding Format

When the atomic module prefix is detected, the user operation signature MUST be encoded as:

```solidity
abi.encode(
    uint256 moduleTypeId,
    address module,
    bytes initData,
    bytes installationSignature,
    bytes userOpSignature
)
```

Where:
- `moduleTypeId`: The [ERC-7579] module type identifier
- `module`: The address of the module to install
- `initData`: Initialization data to pass to the module's `onInstall` function
- `installationSignature`: [EIP-712] signature authorizing the module installation
- `userOpSignature`: Signature for validating the user operation

### EIP-712 Message Structure

The message structure MUST be:

```solidity
bytes32 constant INSTALL_MODULE_TYPEHASH = keccak256(
    "InstallAtomicModule(uint256 moduleTypeId,address module,bytes initData,uint256 nonce)"
);
```

### Validation Flow

Smart accounts implementing this standard on top of [ERC-4337]'s `validateUserOp` function:

1. MUST detect the atomic module prefix (`0x01`) in user operation nonces
2. MUST decode the signature according to the specified format
3. MUST validate the EIP-712 `installationSignature` using `isValidSignature`
4. SHOULD install the module using the standard ERC-7579 `installModule` flow using the `moduleTypeId`, `module`, and `initData`
5. MUST continue with normal user operation validation using the extracted `userOpSignature`
6. MUST return `SIG_VALIDATION_FAILED` (`1`) if signature decoding fails or installation signature is invalid

## Rationale

### Magic Nonce Prefix Choice

The prefix `0x01` was chosen because:
- It's unlikely to conflict with existing nonce usage patterns
- It's easily detectable with bitwise operations
- It follows the pattern established by successful implementations like Kernel

### Signature Structure Design

The signature encoding separates concerns cleanly:
- Module installation data is explicitly structured
- Installation authorization is separate from user operation validation
- The format is extensible for future enhancements

### EIP-712 Integration

Using EIP-712 for installation authorization provides:
- Strong cryptographic guarantees
- Human-readable signature requests in wallets
- Standard domain separation
- Replay protection through nonce inclusion

### Compatibility with ERC-7579

This standard extends ERC-7579 without breaking existing functionality:
- Normal user operations continue to work unchanged
- Standard module installation flows remain available
- All ERC-7579 security guarantees are preserved

## Backwards Compatibility

This standard is fully backwards compatible with existing ERC-7579 implementations:

- Accounts not implementing this standard ignore the magic nonce prefix
- Standard module installation methods remain unchanged
- Existing modules work without modification
- User operations without the magic prefix function normally

## Reference Implementation

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccountERC7579} from "@openzeppelin/contracts/account/extensions/draft-AccountERC7579.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

abstract contract AtomicModuleAccount is AccountERC7579, ... {
    bytes1 private constant ATOMIC_MODULE_PREFIX = 0x01;
    bytes32 private constant INSTALL_MODULE_TYPEHASH =
        keccak256(
            "InstallAtomicModule(uint256 moduleTypeId,address module,bytes initData,uint256 nonce)"
        );

    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256) {
        bytes1 result;
        uint256 nonce = userOp.nonce;
        assembly ("memory-safe") {
            result := and(nonce, shl(248, not(0)))
        }
        if (result == ATOMIC_MODULE_PREFIX) {
            return _validateAtomicModule(userOp, userOpHash);
        }
        return super._validateUserOp(userOp, userOpHash);
    }

    function _validateAtomicModule(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal returns (uint256) {
        (
            bool success,
            uint256 moduleTypeId,
            address module,
            bytes calldata initData,
            bytes calldata installationSignature,
            bytes calldata userOpSignature
        ) = _tryDecodeAtomicModule(userOp.signature);

        if (!success) {
            return ERC4337Utils.SIG_VALIDATION_FAILED;
        }

        bytes32 structHash = _installModuleStructHash(
            moduleTypeId,
            module,
            initData,
            userOp.nonce
        );

        if (
            isValidSignature(_hashTypedDataV4(structHash), installationSignature) ==
            IERC1271.isValidSignature.selector
        ) {
            _installModule(moduleTypeId, module, initData);
            
            // Create modified userOp with extracted signature
            PackedUserOperation memory modifiedUserOp = PackedUserOperation({
                sender: userOp.sender,
                nonce: userOp.nonce,
                initCode: userOp.initCode,
                callData: userOp.callData,
                accountGasLimits: userOp.accountGasLimits,
                preVerificationGas: userOp.preVerificationGas,
                gasFees: userOp.gasFees,
                paymasterAndData: userOp.paymasterAndData,
                signature: userOpSignature
            });
            
            return super._validateUserOp(modifiedUserOp, userOpHash);
        }

        return ERC4337Utils.SIG_VALIDATION_FAILED;
    }

    // Additional implementation methods...
}
```

## Security Considerations

- **Authorization**: Only account owners can authorize module installation through EIP-712 signatures
- **Signature Separation**: Installation authorization and user operation validation use separate signatures
- **Replay Protection**: Nonce inclusion in EIP-712 message prevents replay attacks
- **Module Validation**: Standard ERC-7579 module validation applies (type checking, duplicate prevention)

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
