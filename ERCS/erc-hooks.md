---
eip: TBD
title: Metadata Hooks
description: A method for redirecting metadata records to a different contract for secure resolution.
author: Prem Makeig (@nxt3d)
discussions-to: https://ethereum-magicians.org/t/erc-metadata-hooks/XXXXX
status: Draft
type: Standards Track
category: ERC
created: 2025-12-12
requires: 3668
---

## Abstract

This ERC introduces Metadata Hooks, a method for redirecting metadata records to a different contract for resolution. When a metadata value contains a hook, clients "jump" to the destination contract to resolve the actual value by calling the specified function. This enables secure resolution from known contracts, such as singleton registries with known security properties. Hooks can call any function that returns a single `bytes` value.

## Motivation

The goal of this ERC is to propose a method for securely resolving onchain metadata from known contracts. Hooks allow metadata records to be redirected to trusted resolvers by specifying a function call and destination contract address. If the destination is a known contract, such as a credential resolver for proof of personhood (PoP) or know your customer (KYC), clients can verify the contract's security properties before resolving.

The hook both notifies resolving clients of a credential source, as well as provides the method for resolving the credential.

### Use Cases

- **Credential Resolution**: Redirect a `proof-of-person` or `kyc` record to a trusted credential registry
- **Singleton Registries**: Point to canonical registries with known security properties
- **Shared Metadata**: Multiple contracts can reference the same metadata source
- **Generic Function Calls**: Call any function on any contract that returns a single `bytes` value

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Overview

A hook is an ABI-encoded value stored in a metadata record that redirects resolution to a different contract. When a client encounters a hook, it:

1. Parses the hook to extract the function call and target contract address
2. Verifies the target contract is trusted (RECOMMENDED)
3. Calls the specified function on the target contract
4. Returns the resolved value

The target function MUST return a single `bytes` value.

### Hook Function Signature

```solidity
function hook(
    string calldata functionCall,
    address target
)
```

```solidity
bytes4 constant HOOK_SELECTOR = 0x9645b9c8;
```

#### Parameters

- **`functionCall`**: A string representation of the function to call with its parameters
- **`target`**: The address of the target contract to call

### Function Call Format

The `functionCall` parameter uses a Solidity-style syntax:

- String parameters are enclosed in single quotes: `'value'`
- Bytes/hex parameters use the `0x` prefix: `0x1234abcd`
- Numbers are written as literals: `42` or `1000000`

Functions MUST return a single `bytes` value. Since `bytes` values can be ABI-encoded, this enables returning arrays, structs, strings, and other complex types as ABI-encoded bytes.

**Examples:**

```
getContractMetadata('kyc')
getMetadata(42,'avatar')
getBytes(0x42)
```

### Hook Encoding

Hooks can be encoded in two formats depending on the storage type:

#### Bytes Format

For metadata systems that store `bytes` values (e.g., ERC-8049, ERC-8048), hooks MUST be ABI-encoded:

```solidity
bytes4 constant HOOK_SELECTOR = 0x9645b9c8;

bytes memory hookData = abi.encodeWithSelector(
    HOOK_SELECTOR,
    "getContractMetadata('kyc')",
    targetContract
);

// Store the hook as the value
originatingContract.setContractMetadata("kyc", hookData);
```

#### String Format

For metadata systems that store `string` values, hooks SHOULD be formatted as:

```
hook("functionCall()", 0xTargetAddress)
```

**Examples:**

```
hook("getContractMetadata('kyc')", 0x1234567890AbcdEF1234567890aBcdef12345678)
hook("text(12453)", 0x1234567890AbcdEF1234567890aBcdef12345678)
```

### Detecting Hooks

Clients SHOULD be aware in advance which metadata keys may contain hooks. It is intentional that hook-enabled keys are known by clients beforehand, similar to how clients know to look for keys like `"image"` or `"description"`.

For bytes values, hooks can be detected by checking if the value starts with the hook selector `0x9645b9c8`. For string values, hooks can be detected by checking if the value starts with `hook(`.

Specific implementations MAY:
- Require that hooks are supported for every key
- Specify a subset of keys that MUST use hooks
- Define which keys are hook-enabled on a per-contract basis

### Resolving Hooks

When a client encounters a hook that it wants to use:

1. **Parse the hook** to extract the `functionCall` and `target` address
2. **Verify the target** (RECOMMENDED): Check that the target contract is known and trusted
3. **Parse the function call**: Extract the function name and parameters from the string
4. **Call the target**: Execute the function on the target contract
5. **Support ERC-3668**: Clients MUST support [ERC-3668](./eip-3668.md) offchain data retrieval when resolving from the target contract

Clients MAY choose NOT to resolve hooks if the target contract is not known to be secure and trustworthy. Some clients have ERC-3668 disabled by default, but clients MUST enable it before resolving the hook.

### Example: KYC Credential Resolution

A contract can redirect its `"kyc"` metadata key to a trusted KYC provider contract:

**Step 1: Store the hook in the originating contract**

```solidity
bytes4 constant HOOK_SELECTOR = 0x9645b9c8;

// KYCProvider is a trusted singleton registry at a known address
address kycProvider = 0x1234567890AbcdEF1234567890aBcdef12345678;

// Create hook that calls getCredential('kyc:0x76F1Ff...') on the KYC provider
bytes memory hookData = abi.encodeWithSelector(
    HOOK_SELECTOR,
    "getCredential('kyc:0x76F1Ff0186DDb9461890bdb3094AF74A5F24a162')",
    kycProvider
);

// Store the hook
originatingContract.setContractMetadata("kyc", hookData);
```

**Step 2: Client resolves the hook**

```javascript
// Client reads metadata from originating contract
const value = await originatingContract.getContractMetadata("kyc");

// Client detects this is a hook (starts with HOOK_SELECTOR)
if (value.startsWith("0x9645b9c8")) {
    // Parse the hook (ABI decode after 4-byte selector)
    const { functionCall, target } = decodeHook(value);
    
    // Verify target is trusted (implementation-specific)
    if (!isTrustedResolver(target)) {
        throw new Error("Untrusted resolver");
    }
    
    // Parse the function call string to get function name and args
    const { functionName, args } = parseFunctionCall(functionCall);
    // functionName = "getCredential"
    // args = ["kyc:0x76F1Ff0186DDb9461890bdb3094AF74A5F24a162"]
    
    // Enable ERC-3668 (CCIP-Read) support for this resolution
    const targetContract = new ethers.Contract(
        target,
        [`function ${functionName}(string) view returns (bytes)`],
        provider.ccipReadEnabled(true)  // Enable CCIP-Read
    );
    
    // Resolve from target contract
    const credential = await targetContract[functionName](...args);
    
    // credential is bytes containing: "Maria Garcia /0x76F1Ff0186DDb9461890bdb3094AF74A5F24a162/ ID: 146-DJH-6346-25294"
}
```

## Rationale

Hooks introduce redirection for resolving metadata records, which allows for resolving records from "known" contracts. Known contracts may have security properties which are verifiable, for example a singleton registry which resolves Proof-of-Personhood IDs or Know-your-Customer credentials.

### Why Mandate ERC-3668?

ERC-3668 (CCIP-Read) is a powerful technology that enables both cross-chain and verified offchain resolution of metadata. However, because some clients disable ERC-3668 by default due to security considerations, hooks explicitly mandate ERC-3668 support. This gives clients the opportunity to enable ERC-3668 specifically for hook resolution without needing to have it enabled globally. By tying ERC-3668 to hooks, clients can make a deliberate choice to enable it when resolving from known, trusted contracts, while keeping it disabled for general use.

## Backwards Compatibility

Hooks are backwards compatible; clients that are not aware of hooks will simply return the hook encoding as the raw value.

## Security Considerations

### Target Trust

The primary use of hooks is to resolve data from known contracts with verifiable security properties. Clients SHOULD:

- Maintain a list of trusted target contract addresses or use a third-party registry
- Fail when resolving from untrusted targets

### Function Call Validation

Clients SHOULD validate the parsed function call before execution to prevent:
- Calls to dangerous functions (e.g., `selfdestruct`, `delegatecall`)
- Malformed function call strings

### Recursive Hooks

Implementations SHOULD limit the depth of hook resolution to prevent infinite loops where a hook resolves to another hook. A reasonable limit is 3-5 levels of indirection.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
