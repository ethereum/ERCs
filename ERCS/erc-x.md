---
eip: 9999
title: Readable Typed Signatures for Smart Accounts
description: Nested typed data structure for readable replay-safe signatures
author: vectorized (@vectorized), Sihoon Lee (@push0ebp), Francisco Giordano (@frangio), Im, Juno (@junomonster), howydev (@howydev), 0xcuriousapple (@0xcuriousapple)
discussions-to: https://ethereum-magicians.org/t/readable-typed-signatures-for-smart-accounts/20513
status: Draft
type: Standards Track
category: ERC
created: 2024-05-28
requires: 191, 712, 1271, 5267
---

## Abstract

This proposal defines a nested [EIP-712](./eip-712.md) typed structure and wrapped signature scheme for [ERC-1271](./erc-1271.md) verification. 

It prevents signature replays when multiple smart accounts are owned by a single Externally Owned Account (EOA), while allowing signed contents to be readable during signature requests.

## Motivation

Smart accounts can verify signatures with via [ERC-1271](./erc-1271.md) using the `isValidSignature` function.

A straightforward implementation as shown below, is vulnerable to signature replay attacks.

```solidity
/// @dev This implementation is NOT safe.
function isValidSignature(
    bytes32 hash,
    bytes calldata signature
) external override view returns (bytes4) {
    if (ECDSA.recover(hash, signature) == owner) {
        return 0x1626ba7e;
    } else {
        return 0xffffffff;
    }
}
```

When a multiple smart accounts are owned by a single EOA, the same signature can be replayed across the smart accounts if the `hash` does not include the smart account address. 

Unfortunately, this is the case for many popular applications (e.g. Permit2). As such, many smart account implementations perform some form of defensive rehashing. First, the smart account computes a final hash from minimally: (1) the hash, (2) its own address, (3) the chain ID. Then, the smart account verifies the final hash against the signature. Defensive rehashing can be implemented with [EIP-712](./eip-712.md), but a straightforward implementation will make the signed contents opaque. 

This standard provides a defensive rehashing scheme that makes the signed contents visible across all wallet clients that support [EIP-712](./eip-712.md). It is designed for minimal adoption friction. Even if wallet clients or application frontends are not updated, users can still inject client side JavaScript to enable the defensive rehashing.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

The smart account MUST implement the following:

- [EIP-712](./eip-712.md) Typed structured data hashing and signing.  
  Provides the relevant typed data hashing logic internally, which is required to construct the final hashes.

- [ERC-1271](./erc-1271.md) Standard Signature Validation Method for Contracts.  
  Provides the `isValidSignature(bytes32 hash, bytes calldata signature)` function.

- [ERC-5267](./erc-5267.md) Retrieval of EIP-712 domain.  
  Provides the `eip712Domain()` function which is required to compute the final hashes.

The bulk of this standard defines the behavior of the `isValidSignature` function for [ERC-1271](./erc-1271.md). 

The `isValidSignature` must implement two workflows: the `TypedDataSign` workflow and the `PersonalSign` workflow.

### `TypedDataSign` workflow 

The `TypedDataSign` workflow handles the case where the `hash` is originally computed with [EIP-712](./eip-712.md).

#### `TypedDataSign` final hash

The final hash for the `TypedDataSign` workflow is defined as:

```
keccak256(\x19\x01 ‖ APP_DOMAIN_SEPARATOR ‖
    hashStruct(TypedDataSign({
        contents: hashStruct(originalStruct),
        name: eip712Domain().name,
        version: eip712Domain().version,
        chainId: eip712Domain().chainId,
        verifyingContract: eip712Domain().verifyingContract,
        salt: eip712Domain().salt,
        extensions: eip712Domain().extensions
    }))
)
```

where `‖` denotes the concatenation operator for bytes.

In Solidity, this can be written as:

```solidity
keccak256(
    abi.encodePacked(
        hex"1901",
        // Application specific domain separator. Passed via `signature`.
        bytes32(APP_DOMAIN_SEPARATOR),
        keccak256(
            abi.encode(
                // Computed on-the-fly with `contentsType`, which is passed via `signature`.
                typedDataSignTypehash, 
                // This is the `contents` struct hash, which is passed via `signature`.
                bytes32(hashStruct(originalStruct)),
                // `eip712Domain()` is from ERC-5267. 
                keccak256(bytes(eip712Domain().name)), 
                keccak256(bytes(eip712Domain().version)),
                uint256(eip712Domain().chainId),
                uint256(uint160(eip712Domain().verifyingContract)),
                bytes32(eip712Domain().salt),
                keccak256(abi.encodePacked(eip712Domain().extensions))
            )
        )
    )
)
```

where `typedDataSignTypehash` is:

```solidity
abi.encodePacked(
    "TypedDataSign(",
        contentsTypeName,
        "bytes1 fields,",
        "string name,",
        "string version,",
        "uint256 chainId,",
        "address verifyingContract,",
        "bytes32 salt,",
        "uint256[] extensions",
    ")",
    contentsType
)
```

If `contentsType` is `"Mail(address from,address to,string message)"`, then `contentsTypeName` will be `"Mail"`.

The `contentsTypeName` function can be computed with:

```solidity
// `LibString`: https://github.com/Vectorized/solady/blob/main/src/utils/LibString.sol
//
// `slice(string memory subject, uint256 start, uint256 end)` 
// returns a copy of `subject` sliced from `start` to `end` (exclusive).
// `start` and `end` are byte offsets.
//
// `indexOf(string memory subject, string memory search)`
// Returns the byte index of the first location of `search` in `subject`,
// searching from left to right. Returns `2**256 - 1` if `search` is not found.
LibString.slice(t, 0, LibString.indexOf(t, "("));
```

For safety, smart accounts MUST treat the signature as invalid if any of the following is true:

- `contentsTypeName` is the empty string (i.e. `bytes(contentsTypeName).length == 0`).
- `contentsTypeName` starts with any of the following bytes `abcdefghijklmnopqrstuvwxyz(`.
- `contentsTypeName` contains any of the following bytes `, )\x00`.

#### `TypedDataSign` signature

The `signature` passed into `isValidSignature` will be changed to:

```
originalSignature ‖ APP_DOMAIN_SEPARATOR ‖ contents ‖ contentsType ‖ uint16(contentsType.length)
```

where `contents` is the bytes32 struct hash of the original struct.

In Solidity, this can be written as:

```solidity
abi.encodePacked(
    bytes(originalSignature),
    bytes32(APP_DOMAIN_SEPARATOR),
    bytes32(contents),
    bytes(contentsType),
    uint16(contentsType.length)
)
```

The appended `APP_DOMAIN_SEPARATOR` and `contents` struct hash will be used to verify if the `hash` passed into `isValidSignature` is indeed correct via:

```solidity
hash == keccak256(
    abi.encodePacked(
        hex"1901",
        bytes32(APP_DOMAIN_SEPARATOR),
        bytes32(contents)
    )
)
```

### `PersonalSign` workflow 

This `PersonalSign` workflow handles the case where the `hash` is originally computed with [EIP-191](./eip-191.md).

#### `PersonalSign` final hash

The final hash for the `PersonalSign` workflow is defined as:

```
keccak256(\x19\x01 ‖ ACCOUNT_DOMAIN_SEPARATOR ‖
    hashStruct(PersonalSign({
        prefixed: keccak256(bytes(\x19Ethereum Signed Message:\n ‖
        base10(bytes(someString).length) ‖ someString))
    }))
)
```

where `‖` denotes the concatenation operator for bytes.

In Solidity, this can be written as:

```solidity
keccak256(
    abi.encodePacked(
        hex"1901",
        // Smart account domain separator.
        // Can be computed via `eip712Domain()` from ERC-5267.
        bytes32(ACCOUNT_DOMAIN_SEPARATOR),
        keccak256(
            abi.encode(
                // `PERSONAL_SIGN_TYPEHASH`.
                keccak256("PersonalSign(bytes prefixed)"),
                // `hash` is from `isValidSignature(hash, signature)`
                hash
            )
        )
    )
)
```

Here, `hash` is computed in the application contract and passed into `isValidSignature`. 

The smart account does not need to know how `hash` is computed. For completeness, this is how it can be computed:

```solidity
abi.encodePacked(
    "\x19Ethereum Signed Message:\n",
    // `LibString`: https://github.com/Vectorized/solady/blob/main/src/utils/LibString.sol
    //
    // `toString` returns the base10 representation of a uint256.
    LibString.toString(someString.length),
    // This is the original message to be signed.
    someString
)
```

#### `PersonalSign` signature 

The `PersonalSign` workflow does not require additional data to be appended to the `signature` passed into `isValidSignature`.

### `supportsNestedTypedDataSign` function for detection

To facilitate automatic detection, smart accounts SHOULD implement the following function:

```solidity
/// @dev For automatic detection that the smart account supports the nested EIP-712 workflow.
/// By default, it returns `bytes32(bytes4(keccak256("supportsNestedTypedDataSign()")))`,
/// denoting support for the default behavior, as implemented in
/// `_erc1271IsValidSignatureViaNestedEIP712`, which is called in `isValidSignature`.
/// Future extensions should return a different non-zero `result` to denote different behavior.
/// This method intentionally returns bytes32 to allow freedom for future extensions.
function supportsNestedTypedDataSign() public view virtual returns (bytes32 result) {
    result = bytes4(0xd620c85a);
}
```

### Conditional skipping of defensive rehashing

Smart accounts MAY skip the defensive rehashing workflows if any of the following is true:

- `isValidSignature` is called off-chain.
- The `hash` passed into `isValidSignature` has already included the address of the smart account.

## Rationale

### `TypedDataSign` structure

The `typedDataSignTypehash` must be constructed on-the-fly on-chain. This is to enforce that the signed contents will be visible in the signature request, by requiring that `contents` be a user defined type. 

The structure is intentionally made flat with the fields of `eip712Domain` to make implementation feasible. Otherwise, smart accounts must implement on-chain lexographical sorting of strings for the struct type names when constructing `typedDataSignTypehash`.

### `supportsNestedTypedDataSign` for detection

Without this function, this standard will not change the interface of the smart account, as it defines the behavior of `isValidSignature` without adding any new functions. As such, [ERC-165](./erc-165.md) cannot be used.

For future extendability, `supportsNestedTypedDataSign` is defined to return a bytes32 as the first word of its returned data. For bytecode compactness and to leave space for bit packing, only the leftmost 4 bytes are set to the function selector of `supportsNestedTypedDataSign`.

The `supportsNestedTypedDataSign` function may be extended to return multiple values (e.g. `bytes32 result, bytes memory data`), as long as the first word of the returned data is a bytes32 identifier. This will not change the function selector.

## Backwards Compatibility

No backwards compatibility issues.

## Reference Implementation

The following reference implementation is production ready and optimized. It also includes relevant complementary features required for safety, flexibility, developer experience, and user experience.

It is intentionally not minimalistic. This is to avoid repeating the mistake of [ERC-1271](./erc-1271.md), where a reference implementation is wrongly assumed to be safe for production use.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

// https://github.com/Vectorized/solady/blob/main/src/utils/EIP712.sol
import {EIP712} from "../utils/EIP712.sol";
// https://github.com/Vectorized/solady/blob/main/src/utils/SignatureCheckerLib.sol
import {SignatureCheckerLib} from "../utils/SignatureCheckerLib.sol";

/// @notice ERC1271 mixin with nested EIP-712 approach.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/accounts/ERC1271.sol)
abstract contract ERC1271 is EIP712 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev `keccak256("PersonalSign(bytes prefixed)")`.
    bytes32 internal constant _PERSONAL_SIGN_TYPEHASH =
        0x983e65e5148e570cd828ead231ee759a8d7958721a768f93bc4483ba005c32de;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ERC1271 OPERATIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Validates the signature with ERC1271 return,
    /// so that this account can also be used as a signer.
    function isValidSignature(bytes32 hash, bytes calldata signature)
        public
        view
        virtual
        returns (bytes4 result)
    {
        bool success = _erc1271IsValidSignature(hash, _erc1271UnwrapSignature(signature));
        /// @solidity memory-safe-assembly
        assembly {
            // `success ? bytes4(keccak256("isValidSignature(bytes32,bytes)")) : 0xffffffff`.
            // We use `0xffffffff` for invalid, in convention with the reference implementation.
            result := shl(224, or(0x1626ba7e, sub(0, iszero(success))))
        }
    }

    /// @dev For automatic detection that the smart account supports the nested EIP-712 workflow.
    /// By default, it returns `bytes32(bytes4(keccak256("supportsNestedTypedDataSign()")))`,
    /// denoting support for the default behavior, as implemented in
    /// `_erc1271IsValidSignatureViaNestedEIP712`, which is called in `isValidSignature`.
    /// Future extensions should return a different non-zero `result` to denote different behavior.
    /// This method intentionally returns bytes32 to allow freedom for future extensions.
    function supportsNestedTypedDataSign() public view virtual returns (bytes32 result) {
        result = bytes4(0xd620c85a);
    }

    /// @dev Returns the ERC1271 signer.
    /// Override to return the signer `isValidSignature` checks against.
    function _erc1271Signer() internal view virtual returns (address);

    /// @dev Returns whether the `msg.sender` is considered safe, such
    /// that we don't need to use the nested EIP-712 workflow.
    /// Override to return true for more callers.
    /// See: https://mirror.xyz/curiousapple.eth/pFqAdW2LiJ-6S4sg_u1z08k4vK6BCJ33LcyXpnNb8yU
    function _erc1271CallerIsSafe() internal view virtual returns (bool) {
        // The canonical `MulticallerWithSigner` at 0x000000000000D9ECebf3C23529de49815Dac1c4c
        // is known to include the account in the hash to be signed.
        return msg.sender == 0x000000000000D9ECebf3C23529de49815Dac1c4c;
    }

    /// @dev Returns whether the `hash` and `signature` are valid.
    /// Override if you need non-ECDSA logic.
    function _erc1271IsValidSignatureNowCalldata(bytes32 hash, bytes calldata signature)
        internal
        view
        virtual
        returns (bool)
    {
        return SignatureCheckerLib.isValidSignatureNowCalldata(_erc1271Signer(), hash, signature);
    }

    /// @dev Unwraps and returns the signature.
    function _erc1271UnwrapSignature(bytes calldata signature)
        internal
        view
        virtual
        returns (bytes calldata result)
    {
        result = signature;
        /// @solidity memory-safe-assembly
        assembly {
            // Unwraps the ERC6492 wrapper if it exists.
            // See: https://eips.ethereum.org/EIPS/eip-6492
            if eq(
                calldataload(add(result.offset, sub(result.length, 0x20))),
                mul(0x6492, div(not(mload(0x60)), 0xffff)) // `0x6492...6492`.
            ) {
                let o := add(result.offset, calldataload(add(result.offset, 0x40)))
                result.length := calldataload(o)
                result.offset := add(o, 0x20)
            }
        }
    }

    /// @dev Returns whether the `signature` is valid for the `hash.
    function _erc1271IsValidSignature(bytes32 hash, bytes calldata signature)
        internal
        view
        virtual
        returns (bool)
    {
        return _erc1271IsValidSignatureViaSafeCaller(hash, signature)
            || _erc1271IsValidSignatureViaNestedEIP712(hash, signature)
            || _erc1271IsValidSignatureViaRPC(hash, signature);
    }

    /// @dev Performs the signature validation without nested EIP-712 if the caller is
    /// a safe caller. A safe caller must include the address of this account in the hash.
    function _erc1271IsValidSignatureViaSafeCaller(bytes32 hash, bytes calldata signature)
        internal
        view
        virtual
        returns (bool result)
    {
        if (_erc1271CallerIsSafe()) result = _erc1271IsValidSignatureNowCalldata(hash, signature);
    }

    /// @dev ERC1271 signature validation (Nested EIP-712 workflow).
    ///
    /// This uses ECDSA recovery by default (see: `_erc1271IsValidSignatureNowCalldata`).
    /// It also uses a nested EIP-712 approach to prevent signature replays when a single EOA
    /// owns multiple smart contract accounts,
    /// while still enabling wallet UIs (e.g. Metamask) to show the EIP-712 values.
    ///
    /// Crafted for phishing resistance, efficiency, flexibility.
    /// __________________________________________________________________________________________
    ///
    /// Glossary:
    ///
    /// - `APP_DOMAIN_SEPARATOR`: The domain separator of the `hash` passed in by the application.
    ///   Provided by the front end. Intended to be the domain separator of the contract
    ///   that will call `isValidSignature` on this account.
    ///
    /// - `ACCOUNT_DOMAIN_SEPARATOR`: The domain separator of this account.
    ///   See: `EIP712._domainSeparator()`.
    /// __________________________________________________________________________________________
    ///
    /// For the `TypedDataSign` workflow, the final hash will be:
    /// ```
    ///     keccak256(\x19\x01 ‖ APP_DOMAIN_SEPARATOR ‖
    ///         hashStruct(TypedDataSign({
    ///             contents: hashStruct(originalStruct),
    ///             name: keccak256(bytes(eip712Domain().name)),
    ///             version: keccak256(bytes(eip712Domain().version)),
    ///             chainId: eip712Domain().chainId,
    ///             verifyingContract: eip712Domain().verifyingContract,
    ///             salt: eip712Domain().salt,
    ///             extensions: keccak256(abi.encodePacked(eip712Domain().extensions))
    ///         }))
    ///     )
    /// ```
    /// where `‖` denotes the concatenation operator for bytes.
    /// The order of the fields is important: `contents` comes before `name`.
    ///
    /// The signature will be `r ‖ s ‖ v ‖
    ///     APP_DOMAIN_SEPARATOR ‖ contents ‖ contentsType ‖ uint16(contentsType.length)`,
    /// where `contents` is the bytes32 struct hash of the original struct.
    ///
    /// The `APP_DOMAIN_SEPARATOR` and `contents` will be used to verify if `hash` is indeed correct.
    /// __________________________________________________________________________________________
    ///
    /// For the `PersonalSign` workflow, the final hash will be:
    /// ```
    ///     keccak256(\x19\x01 ‖ ACCOUNT_DOMAIN_SEPARATOR ‖
    ///         hashStruct(PersonalSign({
    ///             prefixed: keccak256(bytes(\x19Ethereum Signed Message:\n ‖
    ///                 base10(bytes(someString).length) ‖ someString))
    ///         }))
    ///     )
    /// ```
    /// where `‖` denotes the concatenation operator for bytes.
    ///
    /// The `PersonalSign` type hash will be `keccak256("PersonalSign(bytes prefixed)")`.
    /// The signature will be `r ‖ s ‖ v`.
    /// __________________________________________________________________________________________
    ///
    /// For demo and typescript code, see:
    /// - https://github.com/junomonster/nested-eip-712
    /// - https://github.com/frangio/eip712-wrapper-for-eip1271
    ///
    /// Their nomenclature may differ from ours, although the high-level idea is similar.
    ///
    /// Of course, if you have control over the codebase of the wallet client(s) too,
    /// you can choose a more minimalistic signature scheme like
    /// `keccak256(abi.encode(address(this), hash))` instead of all these acrobatics.
    /// All these are just for widespread out-of-the-box compatibility with other wallet clients.
    /// We want to create bazaars, not walled castles.
    /// And we'll use push the Turing Completeness of the EVM to the limits to do so.
    function _erc1271IsValidSignatureViaNestedEIP712(bytes32 hash, bytes calldata signature)
        internal
        view
        virtual
        returns (bool result)
    {
        bytes32 t = _typedDataSignFields();
        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            // `c` is `contentsType.length`, which is stored in the last 2 bytes of the signature.
            let c := shr(240, calldataload(add(signature.offset, sub(signature.length, 2))))
            for {} 1 {} {
                let l := add(0x42, c) // Total length of appended data (32 + 32 + c + 2).
                let o := add(signature.offset, sub(signature.length, l)) // Offset of appended data.
                mstore(0x00, 0x1901) // Store the "\x19\x01" prefix.
                calldatacopy(0x20, o, 0x40) // Copy the `APP_DOMAIN_SEPARATOR` and `contents` struct hash.
                // Use the `PersonalSign` workflow if the reconstructed hash doesn't match,
                // or if the appended data is invalid, i.e.
                // `appendedData.length > signature.length || contentsType.length == 0`.
                if or(xor(keccak256(0x1e, 0x42), hash), or(lt(signature.length, l), iszero(c))) {
                    t := 0 // Set `t` to 0, denoting that we need to `hash = _hashTypedData(hash)`.
                    mstore(t, _PERSONAL_SIGN_TYPEHASH)
                    mstore(0x20, hash) // Store the `prefixed`.
                    hash := keccak256(t, 0x40) // Compute the `PersonalSign` struct hash.
                    break
                }
                // Else, use the `TypedDataSign` workflow.
                // `TypedDataSign({ContentsName} contents,bytes1 fields,...){ContentsType}`.
                mstore(m, "TypedDataSign(") // Store the start of `TypedDataSign`'s type encoding.
                let p := add(m, 0x0e) // Advance 14 bytes to skip "TypedDataSign(".
                calldatacopy(p, add(o, 0x40), c) // Copy `contentsType` to extract `contentsName`.
                // `d & 1 == 1` means that `contentsName` is invalid.
                let d := shr(byte(0, mload(p)), 0x7fffffe000000000000010000000000) // Starts with `[a-z(]`.
                // Store the end sentinel '(', and advance `p` until we encounter a '(' byte.
                for { mstore(add(p, c), 40) } iszero(eq(byte(0, mload(p)), 40)) { p := add(p, 1) } {
                    d := or(shr(byte(0, mload(p)), 0x120100000001), d) // Has a byte in ", )\x00".
                }
                mstore(p, " contents,bytes1 fields,string n") // Store the rest of the encoding.
                mstore(add(p, 0x20), "ame,string version,uint256 chain")
                mstore(add(p, 0x40), "Id,address verifyingContract,byt")
                mstore(add(p, 0x60), "es32 salt,uint256[] extensions)")
                p := add(p, 0x7f)
                calldatacopy(p, add(o, 0x40), c) // Copy `contentsType`.
                // Fill in the missing fields of the `TypedDataSign`.
                calldatacopy(t, o, 0x40) // Copy the `contents` struct hash to `add(t, 0x20)`.
                mstore(t, keccak256(m, sub(add(p, c), m))) // Store `typedDataSignTypehash`.
                // The "\x19\x01" prefix is already at 0x00.
                // `APP_DOMAIN_SEPARATOR` is already at 0x20.
                mstore(0x40, keccak256(t, 0x120)) // `hashStruct(typedDataSign)`.
                // Compute the final hash, corrupted if `contentsName` is invalid.
                hash := keccak256(0x1e, add(0x42, and(1, d)))
                signature.length := sub(signature.length, l) // Truncate the signature.
                break
            }
            mstore(0x40, m) // Restore the free memory pointer.
        }
        if (t == bytes32(0)) hash = _hashTypedData(hash); // `PersonalSign` workflow.
        result = _erc1271IsValidSignatureNowCalldata(hash, signature);
    }

    /// @dev For use in `_erc1271IsValidSignatureViaNestedEIP712`,
    function _typedDataSignFields() private view returns (bytes32 m) {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = eip712Domain();
        /// @solidity memory-safe-assembly
        assembly {
            m := mload(0x40) // Grab the free memory pointer.
            mstore(0x40, add(m, 0x120)) // Allocate the memory.
            // Skip 2 words for the `typedDataSignTypehash` and `contents` struct hash.
            mstore(add(m, 0x40), shl(248, byte(0, fields)))
            mstore(add(m, 0x60), keccak256(add(name, 0x20), mload(name)))
            mstore(add(m, 0x80), keccak256(add(version, 0x20), mload(version)))
            mstore(add(m, 0xa0), chainId)
            mstore(add(m, 0xc0), shr(96, shl(96, verifyingContract)))
            mstore(add(m, 0xe0), salt)
            mstore(add(m, 0x100), keccak256(add(extensions, 0x20), shl(5, mload(extensions))))
        }
    }

    /// @dev Performs the signature validation without nested EIP-712 to allow for easy sign ins.
    /// This function must always return false or revert if called on-chain.
    function _erc1271IsValidSignatureViaRPC(bytes32 hash, bytes calldata signature)
        internal
        view
        virtual
        returns (bool result)
    {
        // Non-zero gasprice is a heuristic to check if a call is on-chain,
        // but we can't fully depend on it because it can be manipulated.
        // See: https://x.com/NoahCitron/status/1580359718341484544
        if (tx.gasprice == uint256(0)) {
            /// @solidity memory-safe-assembly
            assembly {
                mstore(gasprice(), gasprice())
                // See: https://gist.github.com/Vectorized/3c9b63524d57492b265454f62d895f71
                let b := 0x000000000000378eDCD5B5B0A24f5342d8C10485 // Basefee contract,
                pop(staticcall(0xffff, b, codesize(), gasprice(), gasprice(), 0x20))
                // If `gasprice < basefee`, the call cannot be on-chain, and we can skip the gas burn.
                if iszero(mload(gasprice())) {
                    let m := mload(0x40) // Cache the free memory pointer.
                    mstore(gasprice(), 0x1626ba7e) // `isValidSignature(bytes32,bytes)`.
                    mstore(0x20, b) // Recycle `b` to denote if we need to burn gas.
                    mstore(0x40, 0x40)
                    let gasToBurn := or(add(0xffff, gaslimit()), gaslimit())
                    // Burns gas computationally efficiently. Also, requires that `gas > gasToBurn`.
                    if or(eq(hash, b), lt(gas(), gasToBurn)) { invalid() }
                    // Make a call to this with `b`, efficiently burning the gas provided.
                    // No valid transaction can consume more than the gaslimit.
                    // See: https://ethereum.github.io/yellowpaper/paper.pdf
                    // Most RPCs perform calls with a gas budget greater than the gaslimit.
                    pop(staticcall(gasToBurn, address(), 0x1c, 0x64, gasprice(), gasprice()))
                    mstore(0x40, m) // Restore the free memory pointer.
                }
            }
            result = _erc1271IsValidSignatureNowCalldata(hash, signature);
        }
    }
}
```

## Security Considerations

### Rejecting invalid `contentsTypeName`

Current major implementations of `eth_signTypedData` do not sanitize the names of custom types.

A phishing website can craft a `contentsTypeName` with control characters to break out of the `PersonalSign` type encoding, resulting in the wallet client asking the user to sign an opaque hash.

Requiring on-chain sanitization of `contentsTypeName` will block this phishing attack vector.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
