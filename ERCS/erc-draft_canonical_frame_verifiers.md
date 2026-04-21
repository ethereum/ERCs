---
title: Canonical Verifiers for Frame Transactions
description: Standard ECDSA and P256 verifier contracts for EIP-8141 frame transactions, deployed at canonical addresses across EVM chains
author: Derek Chiang (@derekchiang), Vitalik Buterin (@vbuterin), lightclient (@lightclient), Felix Lange (@fjl)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2026-04-19
requires: 1967, 7702, 7819, 7951, 7997, 8141
---

## Abstract

This ERC defines a set of **canonical verifiers** for [EIP-8141](./eip-8141.md) frame transactions. Each canonical verifier is a contract that validates a single signature scheme (ECDSA or P256) over the transaction's canonical signature hash using a public key stored in the account's own storage, and then calls `APPROVE` with the frame's allowed scope. The verifier is also an [ERC-1967](./eip-1967.md) proxy: any call whose selector is not a canonical selector falls through to an implementation in the account's ERC-1967 implementation slot, allowing accounts to use other account logic alongside the verifier. Verifiers are deployed at well-known addresses via the [EIP-7997](./eip-7997.md) deterministic factory and are therefore available at the same address on all EVM chains.

This ERC also defines a canonical **account factory** that creates new [EIP-7819](./eip-7819.md) delegation accounts pointing at a canonical verifier and atomically installs their public key. The factory is itself deployed via EIP-7997, so accounts created through it have deterministic addresses across EVM chains.

Because canonical verifiers have fully deterministic behavior, L1 mempool nodes and L2 sequencers MAY short-circuit the EVM execution of a `VERIFY` frame whose resolved target delegates to a canonical verifier, replacing it with equivalent native code.

As Ethereum adds new signature precompiles — in particular post-quantum schemes such as ML-DSA, SLH-DSA, or Falcon — this specification is expected to be extended with additional canonical verifiers following the same pattern.

## Motivation

EIP-8141 permits arbitrary account logic to validate transactions, which enables important AA use cases such as paying gas with ERC20 tokens, originating transactions from privacy protocols, validating signatures with quantum-resistant schemes, and more.

However, arbitrary validation also has some downsides:

- Users who want to simply use a known signature algorithm such as ECRECOVER or P256VERIFY to validate their transactions must develop and audit their own account contracts, or use and trust account contracts developed by third parties.

- Nodes who need to validate transactions, such as L1 mempool nodes and L2 sequencers, must expend more resources when validating frame transactions, since the transaction validity can only be determined by executing EVM code (as opposed to simple signature/nonce/balance checks).

To address these issues, this ERC defines a set of "canonical verifiers" that wrap known signature algorithms.  Accounts who want to validate transactions with these known algorithms can use these verifiers, which are intentionally minimalistic and will have been audited by the time this ERC goes live.  Nodes can "short-circuit" transaction validation with native code when validating transactions from accounts using these verifiers, thereby reducing the cost of validation.

As a side benefit, accounts using these verifiers can rotate keys by simply swapping their delegated verifier and public key.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

Throughout this document, `XXXX` is a placeholder for this ERC's final assigned number. The literal values of all names that contain `XXXX` are fixed once that number is assigned.

### Constants

| Name                        | Value                                                                                                                     |
|-----------------------------|---------------------------------------------------------------------------------------------------------------------------|
| `ERC_XXXX_KEY_SLOT`         | `keccak256("erc-XXXX.canonical-verifier.key")`                                                                            |
| `ERC_1967_IMPL_SLOT`        | `keccak256("eip1967.proxy.implementation") - 1`                                                                           |
| `VERIFY_SELECTOR`           | `bytes4(keccak256("verifyXXXX()"))`                                                                                       |
| `INITIALIZE_SELECTOR`       | `bytes4(keccak256("initializeXXXX(bytes)"))`                                                                              |
| `CLEAR_SELECTOR`            | `bytes4(keccak256("clearXXXX()"))`                                                                                        |
| `ECDSA_VERIFIER_ADDRESS`    | TBD (placeholder; assigned by EIP-7997 deployment)                                                                        |
| `P256_VERIFIER_ADDRESS`     | TBD (placeholder; assigned by EIP-7997 deployment)                                                                        |
| `ACCOUNT_FACTORY_ADDRESS`   | TBD (placeholder; assigned by EIP-7997 deployment)                                                                        |
| `SECP256K1N_DIV_2`          | `0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0`                                                       |
### Verifier Behavior

Every canonical verifier MUST implement the following top-level dispatch:

```python
def main(calldata):
    if len(calldata) >= 4 and calldata[:4] == VERIFY_SELECTOR:
        do_verify(calldata[4:])
    elif len(calldata) >= 4 and calldata[:4] == INITIALIZE_SELECTOR:
        do_initialize(calldata[4:])
    elif len(calldata) >= 4 and calldata[:4] == CLEAR_SELECTOR:
        do_clear()
    else:
        do_proxy(calldata)
```

#### `verifyXXXX()` — verification path

The verify path is intended to be invoked from an EIP-8141 `VERIFY` frame, where `msg.sender == ENTRY_POINT` (`0xaa`) and `CALLVALUE == 0`. The verifier does not enforce this; the protocol-defined rules around `APPROVE` (in particular that `ADDRESS == resolved_target`) provide the necessary guards.

Behavior:

1. Let `sig_hash = TXPARAM(0x08)` — the canonical signature hash.
2. Let `frame_index = TXPARAM(0x0A)` — the currently executing frame index.
3. Let `allowed_scope = FRAMEPARAM(0x06, frame_index)` — the allowed approval scope of the current frame.
4. Execute the scheme-specific verification below. Any failure path MUST revert.
5. Call `APPROVE(allowed_scope, 0, 0)` (scope, memory offset, memory length). This successfully terminates the frame and updates the transaction-scoped approval state as defined in EIP-8141.

#### `initializeXXXX(bytes)` — public-key installation

The initialization path is intended to be called exactly once at account deployment time, atomically with the `SETDELEGATE` that creates the account. The canonical account factory (defined below) is the standard caller, but any other contract that wraps account creation in the same transaction MAY call this selector directly.

Behavior:

1. Let `publicKey` be the ABI-decoded `bytes` argument at `calldata[4:]`.
2. Let `raw = SLOAD(ERC_XXXX_KEY_SLOT)`. If `raw != 0`, revert. This prevents re-initialization of an already-keyed account.
3. Validate the scheme-specific `publicKey` (e.g. for ECDSA that `len(publicKey) == 20`).
4. Write the key material into stroage slots starting from `ERC_XXXX_KEY_SLOT`.
  - Note that signature schemes with large public keys may elect to write key commitments to storage, as opposed to storing the keys themselves.  The ERC is agnostic to what's actually stored in the storage slots.

#### `clearXXXX()` — public-key clearing

The clear path is intended to be called by the canonical account factory when an account is being rotated to a new verifier, a new public key, or both. Its purpose is to zero out *every* storage slot that this verifier manages, so that after clearing the account's storage contains no residual key material for this scheme. Because rotation may cross verifier schemes, each verifier is responsible for clearing its own slots; the factory does not know the slot layout of any specific verifier.

Behavior:

1. Require `CALLER == ACCOUNT_FACTORY_ADDRESS`; otherwise revert. The factory's own logic (defined below) authenticates the request as coming from the account itself before making this call.
2. Zero every slot this verifier manages.

#### Proxy fallback

If `msg.sig` is none of `VERIFY_SELECTOR`, `INITIALIZE_SELECTOR`, or `CLEAR_SELECTOR`, or `len(calldata) < 4`:

1. Let `impl = address(uint160(SLOAD(ERC_1967_IMPL_SLOT)))`. If `impl == address(0)`, revert with empty return data.
2. `DELEGATECALL` to `impl`, forwarding all calldata, gas, and value semantics as defined for a standard minimal ERC-1967 proxy.
3. Bubble up the child frame's return data: on success, return it; on revert, revert with the same data.

### Account Factory

The canonical account factory at `ACCOUNT_FACTORY_ADDRESS` is a contract that creates new accounts delegated to a canonical verifier, installs their public key atomically, and performs authenticated rotations of their verifier and/or public key. It exposes the following two entry points:

```solidity
function deploy(bytes32 salt, address verifier, bytes calldata publicKey)
    external
    returns (address location);

function rotate(bytes32 salt, address newVerifier, bytes calldata newPublicKey)
    external;
```

#### `deploy`

1. Execute `SETDELEGATE(salt, verifier)` (EIP-7819). This produces a new delegation account at

    ```
    location = keccak256(0xef0100 || ACCOUNT_FACTORY_ADDRESS || salt)[12:]
    ```

    whose code is the 23-byte EIP-7702 delegation indicator `0xef0100 || verifier`.
2. Invoke `location.call(abi.encodeWithSelector(INITIALIZE_SELECTOR, publicKey))`. The call is routed through the fresh delegation indicator into the verifier's `initializeXXXX(bytes)` implementation, which runs in `location`'s storage context and writes the public-key slot.
3. If the `call` fails, the factory reverts, bubbling up the child's return data. This guarantees that either the account is both delegated *and* initialized, or neither step persists.
4. Return `location`.

Because `ACCOUNT_FACTORY_ADDRESS` is itself fixed across chains (deployed via EIP-7997), the derived `location` is identical for the same `(salt, verifier, publicKey)` tuple on every EVM chain where this ERC is active.

`verifier` MAY be any canonical verifier defined by this ERC or by a compatible future extension.

#### `rotate`

1. Derive `location = keccak256(0xef0100 || ACCOUNT_FACTORY_ADDRESS || salt)[12:]`.
2. Require `CALLER == location`; otherwise revert. This constrains rotation to calls originating from the account itself.
3. Invoke `location.call(abi.encodeWithSelector(CLEAR_SELECTOR))`. The call routes through the account's *current* delegation indicator into the *outgoing* verifier's `clearXXXX()`, which runs in `location`'s storage context and zeroes every slot that verifier manages.
4. Execute `SETDELEGATE(salt, newVerifier)`. Because the factory and salt are unchanged, this overwrites the existing delegation at `location` with `0xef0100 || newVerifier`, without changing the address.
5. Invoke `location.call(abi.encodeWithSelector(INITIALIZE_SELECTOR, newPublicKey))`. The call now routes through the *new* delegation indicator into `newVerifier.initializeXXXX(bytes)`, which runs in `location`'s storage context and writes the public-key slot(s).

`newVerifier` MAY be the same verifier as before (to rotate the public key only) or a different canonical verifier (to rotate to a new signature scheme).

Because the factory authenticates the caller against `location`, no other party can rotate a canonical-factory-deployed account, and the rotation logic does not need to live in the verifier itself. Because the outgoing verifier clears its own slots, rotation remains safe across arbitrary cross-scheme transitions — the factory does not need to know the slot layout of either verifier.

### Deployment via EIP-7997

Each contract defined by this ERC — the two verifiers and the account factory — is deployed by calling the EIP-7997 deterministic factory at `0x12` with calldata `salt || initcode`. Per EIP-1014, the resulting address is:

```
address = keccak256(0xff || 0x12 || salt || keccak256(initcode))[12:]
```

The canonical salt, initcode, and resulting address for each contract defined in this specification are:

| Contract        | Salt              | Initcode          | Address                     |
|-----------------|-------------------|-------------------|-----------------------------|
| ECDSA verifier  | TBD (placeholder) | TBD (placeholder) | `ECDSA_VERIFIER_ADDRESS`    |
| P256 verifier   | TBD (placeholder) | TBD (placeholder) | `P256_VERIFIER_ADDRESS`     |
| Account factory | TBD (placeholder) | TBD (placeholder) | `ACCOUNT_FACTORY_ADDRESS`   |

Once deployed, each contract's runtime code is immutable and its address is fixed across all EVM chains where EIP-7997 is active.

### Native Execution Shortcut

A node processing an EIP-8141 frame transaction MAY replace EVM execution of a `VERIFY` frame with equivalent native code if all of the following hold:

1. The frame's `mode` is `VERIFY`.
2. The code at `resolved_target` is a valid delegation indicator of the form `0xef0100 || target_address` (as defined in EIP-7702 and reused by EIP-7819), and `target_address` equals one of the canonical verifier addresses.
3. The first 4 bytes of `frame.data` equal `VERIFY_SELECTOR`.

When the shortcut applies, the node MUST produce a state transition that is observationally indistinguishable from full EVM execution of the verifier. In particular:

- Storage reads target `resolved_target`'s storage and MUST update the shared warm/cold access journal as defined in EIP-8141.
- `APPROVE(allowed_scope)` MUST be applied with the same transaction-scoped effects the EVM path would produce.

The shortcut is purely an implementation-level optimization. Gas charged against the frame's `gas_limit` MUST match what full EVM execution of the verifier would charge; this ERC does not modify the EVM gas schedule.

### Extensibility

This ERC defines two canonical verifiers. As Ethereum introduces new signature precompiles — in particular post-quantum schemes such as ML-DSA, SLH-DSA, or Falcon — additional canonical verifiers SHOULD be standardized following the same pattern:

- A single `verifyXXXX()` entry point that reads the signature from `msg.data[4:]`.
- An `initializeXXXX(bytes)` entry point that writes the public key (or key commitment) to `ERC_XXXX_KEY_SLOT` (and any additional scheme-specific slots), reverting if the slot is already non-zero.
- A `clearXXXX()` entry point that zeroes every slot the verifier manages, gated to `CALLER == ACCOUNT_FACTORY_ADDRESS`.
- An ERC-1967 proxy fallback for all other selectors.
- Deterministic deployment via EIP-7997, producing an address consistent across all chains.

New verifiers that follow this pattern are compatible with the existing canonical account factory, which accepts any verifier address as its `verifier` parameter.

Additional verifiers MAY be added by amendment to this ERC or by follow-up ERCs that incorporate this specification by reference. New canonical verifiers do not affect existing ones; each is independently deployed at a fixed address, with no shared registry or versioning surface.

## Reference Implementation

The canonical verifiers are defined by the Solidity source below. Each contract is compiled and deployed via the EIP-7997 factory; the resulting creation bytecode determines the initcode hash, and therefore the canonical address, that appears in the Constants table.

The `verbatim_*i_*o` intrinsics are used to emit opcodes that ordinary Solidity does not know about at the time of writing this ERC — `APPROVE = 0xaa`, `TXPARAM = 0xb0`, and `FRAMEPARAM = 0xb3` from EIP-8141, and `SETDELEGATE = 0xf6` from EIP-7819 — and are not modified by the Solidity optimizer. `XXXX` in the function names is the eventual ERC number and MUST be replaced before deployment.

### ECDSA verifier

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title Canonical ECDSA Verifier for EIP-8141 Frame Transactions
/// @notice Intended to be the target of an EIP-7702 or EIP-7819 delegation
///         indicator. When a VERIFY frame targets the delegating account,
///         this code runs in the account's storage context, reads a 20-byte
///         authorized signer from KEY_SLOT, verifies the ECDSA signature over
///         the canonical signature hash (TXPARAM(0x08)), and calls APPROVE
///         with the frame's allowed approval scope.
///
///         Three selectors are reserved by this contract:
///         verifyXXXX(), initializeXXXX(bytes), and clearXXXX().
///         Any call with a different selector is forwarded via DELEGATECALL
///         to the address stored in the ERC-1967 implementation slot.
contract CanonicalECDSAVerifier {
    // keccak256("erc-XXXX.canonical-verifier.key")
    uint256 private constant KEY_SLOT =
        uint256(keccak256("erc-XXXX.canonical-verifier.key"));

    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant ERC1967_IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Canonical account factory address (EIP-7997 deployment).
    // clearXXXX is gated to this address so that only the factory's
    // authenticated `rotate` path can clear an account's key slot.
    address private constant ACCOUNT_FACTORY = address(0); // TBD: EIP-7997 address

    uint256 private constant SECP256K1N_DIV_2 =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @notice Verify a 65-byte ECDSA signature and approve the current frame.
    /// @dev Invoked by an EIP-8141 VERIFY frame with calldata
    ///      `selector || r (32) || s (32) || v (1)`.
    function verifyXXXX() external {
        require(msg.data.length == 4 + 65, "bad sig length");

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := calldataload(4)
            s := calldataload(36)
            v := byte(0, calldataload(68))
        }

        require(uint256(s) <= SECP256K1N_DIV_2, "high-s");

        // sig_hash = TXPARAM(0x08)
        bytes32 sigHash;
        assembly ("memory-safe") {
            sigHash := verbatim_1i_1o(hex"b0", 0x08)
        }

        address recovered = ecrecover(sigHash, v, r, s);
        require(recovered != address(0), "recover failed");

        uint256 raw;
        assembly ("memory-safe") {
            raw := sload(KEY_SLOT)
        }

        address expected;
        if (raw == 0) {
            // Zero slot: authorized signer is the delegating account's own address.
            expected = address(this);
        } else {
            require(raw >> 160 == 0, "key slot dirty");
            expected = address(uint160(raw));
        }
        require(expected == recovered, "signer mismatch");

        // allowed_scope = FRAMEPARAM(0x06, TXPARAM(0x0A))
        // APPROVE(scope, offset=0, length=0) halts the frame.
        assembly ("memory-safe") {
            let idx := verbatim_1i_1o(hex"b0", 0x0A)
            let scope := verbatim_2i_1o(hex"b3", 0x06, idx)
            verbatim_3i_0o(hex"aa", 0, 0, scope)
        }
    }

    /// @notice Install a 20-byte authorized signer into the account's storage.
    /// @dev Expected to be called once at account deployment, atomically with
    ///      the SETDELEGATE that created the account. Reverts if the slot
    ///      already holds a non-zero value, which prevents re-initialization
    ///      or hijack by a front-runner.
    function initializeXXXX(bytes calldata publicKey) external {
        require(publicKey.length == 20, "bad key length");
        uint256 raw;
        assembly ("memory-safe") {
            raw := sload(KEY_SLOT)
        }
        require(raw == 0, "already initialized");
        uint256 signer;
        assembly ("memory-safe") {
            signer := shr(96, calldataload(publicKey.offset))
            sstore(KEY_SLOT, signer)
        }
    }

    /// @notice Zero this verifier's storage slot(s).
    /// @dev Invoked by the canonical account factory on the *outgoing*
    ///      verifier during rotation, so that no stale key material is left
    ///      behind before the new verifier initializes its own slots.
    function clearXXXX() external {
        require(msg.sender == ACCOUNT_FACTORY, "not factory");
        assembly ("memory-safe") {
            sstore(KEY_SLOT, 0)
        }
    }

    fallback() external payable {
        assembly {
            let impl := sload(ERC1967_IMPL_SLOT)
            if iszero(impl) { revert(0, 0) }
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
```

### P256 verifier

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title Canonical P256 Verifier for EIP-8141 Frame Transactions
/// @notice Intended to be the target of an EIP-7702 or EIP-7819 delegation
///         indicator. When a VERIFY frame targets the delegating account,
///         this code runs in the account's storage context, reads the P256
///         public key (qx, qy) from KEY_SLOT and KEY_SLOT+1, verifies the
///         signature over the canonical signature hash via the EIP-7951
///         precompile, and calls APPROVE with the frame's allowed scope.
///
///         Three selectors are reserved by this contract:
///         verifyXXXX(), initializeXXXX(bytes), and clearXXXX().
///         Any call with a different selector is forwarded via DELEGATECALL
///         to the address stored in the ERC-1967 implementation slot.
contract CanonicalP256Verifier {
    uint256 private constant KEY_SLOT =
        uint256(keccak256("erc-XXXX.canonical-verifier.key"));

    bytes32 private constant ERC1967_IMPL_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Canonical account factory address (EIP-7997 deployment).
    address private constant ACCOUNT_FACTORY = address(0); // TBD: EIP-7997 address

    // EIP-7951 P256VERIFY precompile.
    address private constant P256VERIFY = address(0x100);

    /// @notice Verify a 64-byte P256 signature and approve the current frame.
    /// @dev Invoked by an EIP-8141 VERIFY frame with calldata
    ///      `selector || r (32) || s (32)`.
    function verifyXXXX() external {
        require(msg.data.length == 4 + 64, "bad sig length");

        bytes32 r;
        bytes32 s;
        assembly ("memory-safe") {
            r := calldataload(4)
            s := calldataload(36)
        }

        bytes32 sigHash;
        uint256 qx;
        uint256 qy;
        assembly ("memory-safe") {
            sigHash := verbatim_1i_1o(hex"b0", 0x08)
            qx := sload(KEY_SLOT)
            qy := sload(add(KEY_SLOT, 1))
        }

        // P256VERIFY input: hash (32) || r (32) || s (32) || qx (32) || qy (32).
        // Output: 32 bytes of `0x...01` on success; empty returndata on failure.
        bool valid;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, sigHash)
            mstore(add(ptr, 0x20), r)
            mstore(add(ptr, 0x40), s)
            mstore(add(ptr, 0x60), qx)
            mstore(add(ptr, 0x80), qy)

            let outPtr := add(ptr, 0xa0)
            mstore(outPtr, 0) // zero the return region so failure (0 bytes) reads as 0

            let ok := staticcall(gas(), P256VERIFY, ptr, 0xa0, outPtr, 0x20)
            valid := and(ok, eq(mload(outPtr), 1))

            mstore(0x40, add(outPtr, 0x20))
        }
        require(valid, "p256 invalid");

        // allowed_scope = FRAMEPARAM(0x06, TXPARAM(0x0A)); APPROVE halts the frame.
        assembly ("memory-safe") {
            let idx := verbatim_1i_1o(hex"b0", 0x0A)
            let scope := verbatim_2i_1o(hex"b3", 0x06, idx)
            verbatim_3i_0o(hex"aa", 0, 0, scope)
        }
    }

    /// @notice Install a 64-byte P256 public key (qx || qy) into the account.
    /// @dev Expected to be called once at account deployment, atomically with
    ///      the SETDELEGATE that created the account. Reverts if the slot
    ///      already holds a non-zero value.
    function initializeXXXX(bytes calldata publicKey) external {
        require(publicKey.length == 64, "bad key length");
        uint256 raw;
        assembly ("memory-safe") {
            raw := sload(KEY_SLOT)
        }
        require(raw == 0, "already initialized");
        assembly ("memory-safe") {
            sstore(KEY_SLOT, calldataload(publicKey.offset))
            sstore(add(KEY_SLOT, 1), calldataload(add(publicKey.offset, 0x20)))
        }
    }

    /// @notice Zero this verifier's storage slots (qx and qy).
    /// @dev Gated to the canonical account factory. Invoked on the outgoing
    ///      verifier during rotation, so that switching to a verifier with a
    ///      different slot layout cannot leave stale key material behind.
    function clearXXXX() external {
        require(msg.sender == ACCOUNT_FACTORY, "not factory");
        assembly ("memory-safe") {
            sstore(KEY_SLOT, 0)
            sstore(add(KEY_SLOT, 1), 0)
        }
    }

    fallback() external payable {
        assembly {
            let impl := sload(ERC1967_IMPL_SLOT)
            if iszero(impl) { revert(0, 0) }
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
```

### Account factory

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title Canonical Verifier Account Factory
/// @notice Creates EIP-7819 delegation accounts that point at a canonical
///         verifier, initializes them with a public key atomically, and
///         performs authenticated rotations of their verifier and/or
///         public key through a clear-then-initialize handshake with the
///         verifiers. This contract is itself deployed via EIP-7997 at a
///         fixed address on every EVM chain, so the addresses it produces
///         are also fixed across chains:
///
///             location = keccak256(0xef0100 || this || salt)[12:]
contract CanonicalVerifierAccountFactory {
    /// @notice Deploy a new delegation account and install its public key.
    /// @param salt Caller-chosen salt that, combined with this factory's
    ///             address, determines the new account address.
    /// @param verifier Canonical verifier to delegate to. Must implement
    ///                 `initializeXXXX(bytes)`.
    /// @param publicKey Scheme-specific public-key material.
    /// @return location The newly created account address.
    function deploy(bytes32 salt, address verifier, bytes calldata publicKey)
        external
        returns (address location)
    {
        // SETDELEGATE (EIP-7819, opcode 0xf6): pops (salt, target), pushes location.
        assembly ("memory-safe") {
            location := verbatim_2i_1o(hex"f6", salt, verifier)
        }

        // Call routes through the fresh delegation indicator into the
        // verifier's initializeXXXX, which runs in `location`'s storage
        // context and writes the public-key slot.
        (bool ok, bytes memory ret) = location.call(
            abi.encodeWithSignature("initializeXXXX(bytes)", publicKey)
        );
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    /// @notice Rotate an existing account's verifier and/or public key.
    /// @dev The account at `location = keccak256(0xef0100 || this || salt)[12:]`
    ///      MUST be the caller. The factory runs a three-step atomic
    ///      sequence: (1) call clearXXXX() on the account, routed through the
    ///      *outgoing* verifier so it zeroes its own slots; (2) run
    ///      SETDELEGATE with the same salt to swap in the new verifier at the
    ///      same address; (3) call initializeXXXX(bytes) on the account,
    ///      routed through the *new* verifier so it installs the new key.
    ///      Any step failing causes the whole rotate to revert.
    /// @param salt The same salt originally passed to `deploy`.
    /// @param newVerifier New canonical verifier; may equal the previous one
    ///                    to rotate the key only. Must implement
    ///                    initializeXXXX(bytes).
    /// @param newPublicKey Replacement public-key material for newVerifier.
    function rotate(bytes32 salt, address newVerifier, bytes calldata newPublicKey)
        external
    {
        address location = address(uint160(uint256(keccak256(
            abi.encodePacked(hex"ef0100", address(this), salt)
        ))));
        require(msg.sender == location, "not the account");

        // Step 1: ask the outgoing verifier to zero its own slots. This
        // runs through the account's *current* delegation indicator, so
        // "outgoing verifier" = whatever the account currently delegates to.
        (bool okClear, bytes memory retClear) = location.call(
            abi.encodeWithSignature("clearXXXX()")
        );
        if (!okClear) {
            assembly ("memory-safe") {
                revert(add(retClear, 0x20), mload(retClear))
            }
        }

        // Step 2: overwrite the delegation indicator at `location`. Because
        // the factory and salt are unchanged, SETDELEGATE targets the same
        // address and simply replaces its target verifier.
        assembly ("memory-safe") {
            pop(verbatim_2i_1o(hex"f6", salt, newVerifier))
        }

        // Step 3: ask the new verifier to install the new public key. This
        // routes through the just-updated delegation indicator, so
        // initializeXXXX runs under the new verifier's implementation and
        // its "slot must be zero" guard holds (step 1 ensured it).
        (bool okInit, bytes memory retInit) = location.call(
            abi.encodeWithSignature("initializeXXXX(bytes)", newPublicKey)
        );
        if (!okInit) {
            assembly ("memory-safe") {
                revert(add(retInit, 0x20), mload(retInit))
            }
        }
    }
}
```

### Deployment

To produce the canonical addresses listed in the Deployment table, each contract MUST be compiled with a pinned Solidity version and compiler settings (pragma, optimizer, evm-version) and deployed via the EIP-7997 factory with a fixed salt. The compiled creation bytecode (initcode) is the input that is hashed into the CREATE2 address, so any change to compiler configuration or source code changes the resulting address.

For each contract, the deployment input to the EIP-7997 factory at `0x12` is:

```
salt (32 bytes) || initcode (variable)
```

and the resulting canonical address is:

```
address = keccak256(0xff || 0x12 || salt || keccak256(initcode))[12:]
```

## Rationale

TODO

## Backwards Compatibility

TODO

## Security Considerations

TODO

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
