---
title: Diamonds, Simplified
description: A structured approach to isolate, organize, test, and manage distinct areas of contract functionality. 
author: Nick Mudge (@mudgen)
discussions-to: https://ethereum-magicians.org/t/proposal-for-a-simplified-standard-for-diamond-contracts/27119
status: Draft
type: Standards Track
category: ERC
created: 2025-12-21
---


## Abstract

A diamond is a proxy contract that `delegatecall`s to multiple implementation contracts called facets. 

<img alt="Diagram showing how facets compose into a diamond contract" class="" src="../assets/erc-xxxx/basic-diamond-diagram.svg" style="max-width: 100%; height: auto;">


Diamond contracts were originally standardized by [ERC-2535](https://eips.ethereum.org/EIPS/eip-2535). This standard refines that specification by simplifying terminology, reducing the implementation complexity of introspection functions, and standardizing events that are easier for block explorers, indexers, and other tooling to consume. 


This standard preserves the full capabilities of diamond contracts while reducing complexity. It also specifies an optional upgrade path for existing ERC-2535 diamonds.

## Motivations

<div style="float: right; font-size: 10rem; line-height: 1;">💎</div>A diamond provides a single address with the functionality of multiple contracts (facets) that are independent from each other but can share internal functions and data storage. This architecture enables unlimited smart-contract functionality to be presented through one address, simplifying deployment, testing, and integration with other smart contracts, software, and user interfaces.

Diamonds reduce complexity in large smart contract systems by providing a structured approach to isolating, organizing, testing, and managing distinct areas of functionality.

Diamonds can be used to implement large **immutable** smart contract systems, where functionality is composed from multiple facets at deployment time.

For upgradeable smart contract systems, diamonds enable incremental development: new functionality can be added, or existing functionality modified, over time without redeploying unaffected facets.

Additional motivation for diamond-based smart contract systems can be found in [ERC-1538](https://eips.ethereum.org/EIPS/eip-1538) and [ERC-2535](https://eips.ethereum.org/EIPS/eip-2535).

## Specification

### Terms
1. A **diamond** is a smart contract that routes external function calls to one or more implementation contracts, referred to as facets. A diamond is stateful: all persistent data is stored in the diamond’s contract storage.
2. A **facet** is a stateless smart contract that defines one or more external functions. A facet is deployed independently, and one or more of its functions are added to one or more diamonds. A facet does not store persistent data in its own contract storage, but its functions may read from and write to the storage of a diamond. The term facet is derived from the diamond industry, referring to a flat surface of a diamond.
3. An **introspection function** is a function that returns information about the facets and functions used by a diamond.
4. For the purposes of this specification, a **mapping** refers to a conceptual association between two items and does not refer to a specific implementation.


### Diamond Diagram

This diagram shows the structure of a diamond. 

It shows that a diamond has a mapping from function to facet and that facets can access the storage inside a diamond.

<img alt="Diagram showing structure of a diamond" class="" src="../assets/erc-xxxx/functionFacetMapping.svg" align="left" style="max-width: 100%; height: auto;">


### Fallback

When an external function is called on a diamond its fallback function is executed. The fallback function determines which facet to call based on the first four bytes of the call data (known as the function selector) and executes that function from the facet using `delegatecall`.

A diamond’s fallback function and `delegatecall` enable a diamond to execute a facet’s function as if it was implemented by the diamond itself. The `msg.sender` and `msg.value` values do not change and only the diamond’s storage is read and written to.

Here is an example of how a diamond’s fallback function might be implemented:

```Solidity
error FunctionNotFound(bytes4 _selector);

// Executes function call on facet using delegatecall.
// Returns function call return data or revert data.
fallback() external payable {
    // Get facet address from function selector
    address facet = selectorToFacet[msg.sig];
    if (facet == address(0)) {
        revert FunctionNotFound(msg.sig);
    }
    // Execute external function on facet using delegatecall and return any value.
    assembly {
        // Copy function selector and any arguments from calldata to memory.
        calldatacopy(0, 0, calldatasize())
        // Execute function call using the facet.
        let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
        // Copy all return data from the previous call into memory.
        returndatacopy(0, 0, returndatasize())
        // Return any return value or error back to the caller.
        switch result
        case 0 {revert(0, returndatasize())}
        default {return (0, returndatasize())}
    }
}
```
### Events

#### Adding/Replacing/Removing Functions

These events are REQUIRED.

For each function selector that is added, replaced, or removed, the corresponding event MUST be emitted.

```Solidity
/**
* @notice Emitted when a function is added to a diamond.
*
* @param _selector The function selector being added.
* @param _facet    The facet address that will handle calls to `_selector`.
*/
event DiamondFunctionAdded(bytes4 indexed _selector, address indexed _facet);

/**
* @notice Emitted when changing the facet that will handle calls to a function.
* 
* @param _selector The function selector being affected.
* @param _oldFacet The facet address previously responsible for `_selector`.
* @param _newFacet The facet address that will now handle calls to `_selector`.
*/
event DiamondFunctionReplaced(
    bytes4 indexed _selector,
    address indexed _oldFacet,
    address indexed _newFacet
);

/**
* @notice Emitted when a function is removed from a diamond.
*
* @param _selector The function selector being removed.
* @param _oldFacet The facet address that previously handled `_selector`.
*/
event DiamondFunctionRemoved(
    bytes4 indexed _selector, 
    address indexed _oldFacet
);
```

#### Recording Explicit Delegatecalls

The `DiamondDelegateCall` event is OPTIONAL.

A diamond MAY emit this event to record when it executes logic using `delegatecall`, such as during construction, initialization, or upgrades.

For example, a diamond may emit this event when calling an initialization function after functions are added, replaced, or removed.

This event MUST NOT be emitted for `delegatecall`s made by a diamond’s fallback function when routing calls to facets. It is only intended for `delegatecall`s made by functions in facets or a diamond’s constructor.


```Solidity
/**
* @notice Emitted when a diamond's constructor function or function from a
*         facet makes a `delegatecall`. This event is optional.
* 
* @param _contract     The contract address where the function is.
* @param _functionCall The function call, including function selector and 
*                      any arguments.
*/
event DiamondDelegateCall(address indexed _contract, bytes _functionCall);
```

#### Diamond Metadata

This event is OPTIONAL. This event can be used to record versioning or other information about diamonds.

It can be used to record information about diamond upgrades.

```Solidity
/**
* @notice Emitted to record information about a diamond.
* @dev    This event is optional and records any arbitrary metadata. 
*         The format of `_tag` and `_data` are not specified by the 
*         standard.
*
* @param _tag   Arbitrary metadata, such as a release version.
* @param _data  Arbitrary metadata.
*/
event DiamondMetadata(bytes32 indexed _tag, bytes _data);
```

### Diamond Upgrades

The following upgrade function is OPTIONAL.

This means two important things:

#### 1. Diamonds Can Be Immutable

- A diamond can be fully constructed within its constructor function without adding any upgrade function, making it immutable upon deployment.

- A large immutable diamond can be built using well organized facets.

- A diamond can initially be upgradeable, and later made immutable by removing its upgrade function.

#### 2. You Can Create Your Own Upgrade Functions

Instead of, or in addition to the upgrade function specified below, you can design and create your own upgrade functions and remain compliant with this standard. All that is required is that you emit the appropriate required events specified in the [events section](#events).

#### upgradeDiamond Function

This upgrade function is designed for interoperability with tools, such as GUIs and command line tools, which can be used to perform upgrades on diamonds.

This upgrade function adds/replaces/removes any number of functions from any number of facets in a single transaction. In addition it can execute an optional initialization function.

```Solidity
/**
 * @notice The upgradeDiamond function below detects and reverts
 *         with the following errors.
 */
error NoSelectorsProvidedForFacet(address _facet);
error NoBytecodeAtAddress(address _contractAddress, string _message);
error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
error CannotReplaceFunctionThatDoesNotExist(bytes4 _selector);
error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
error CannotReplaceFunctionWithTheSameFacet(bytes4 _selector);
error InitializationFunctionReverted(address _init, bytes _functionCall);

struct FacetFunctions {
    address facet;
    bytes4[] selectors;
}

/**
* @notice Upgrade the diamond by adding, replacing, or removing functions.
*
* @dev
* - `_addFunctions` maps new selectors to their facet implementations.
* - `_replaceFunctions` updates existing selectors to new facet addresses.
* - `_removeFunctions` removes selectors from the diamond.
*
* Functions are first added, then replaced, then removed.
*
* `delegatecall` is made to `_init` with `_functionCall` for initialization.
* The `DiamondDelegateCall` event is emitted.
* However, if `_init` is zero, no `delegatecall` is made and no 
* `DiamondDelegateCall` event is emitted.
*
* If _tag is non-zero or if _metadata size is greater than zero then the
* `DiamondMetadata` event is emitted with that data.
*
* @param _addFunctions     Selectors to add, grouped by facet.
* @param _replaceFunctions Selectors to replace, grouped by facet.
* @param _removeFunctions  Selectors to remove.
* @param _init             Optional initialization contract (zero to skip).
* @param _functionCall     Optional function call for the initialization.
* @param _tag              Optional arbitrary metadata, such as release version.
* @param _metadata         Optional arbitrary data.
*/
function upgradeDiamond(
    FacetFunctions[] calldata _addFunctions,
    FacetFunctions[] calldata _replaceFunctions,
    bytes4[] calldata _removeFunctions,           
    address _init,
    bytes calldata _functionCall,
    bytes32 _tag,
    bytes calldata _metadata
) external;
```

After adding/replacing/removing functions the `_functionCall` argument is executed with `delegatecall` on `_init`. This execution is done to initialize data or setup or remove anything needed or no longer needed after adding, replacing and/or removing functions. 

However if `_init` is `address(0)` then no initialization function is called.

If `_init` is not `address(0)` but has no code then the transaction should revert.

The reference implementation for this upgrade function is here: [DiamondUpgradeFacet.sol](../assets/erc-xxxx/DiamondUpgradeFacet.sol).

## Inspecting Diamonds

Diamond introspection functions return information about what functions and facets are used in a diamond.

These functions MUST be implemented and are required by the standard:

```Solidity
/** @notice Gets the facet that handles the given selector.
 *
 *  @dev If facet is not found return address(0).
 *  @param _functionSelector The function selector.
 *  @return The facet address associated with the function selector.
 */
function facetAddress(bytes4 _functionSelector) external view returns (address);

struct FunctionFacetPair {
    bytes4 selector;
    address facet;
}

/**
* @notice Returns an array of all function selectors and their 
*         corresponding facet addresses.
*
* @dev    Iterates through the diamond's stored selectors and pairs
*         each with its facet.
* @return pairs An array of `FunctionFacetPair` structs, each containing
*         a selector and its facet address.
*/
function functionFacetPairs() external view returns(FunctionFacetPair[] memory pairs);
```

The essence of a diamond is its `function -> facet` mapping. The `functionFacetPairs()` returns that mapping as an array of `(selector, facet)` pairs.

These functions were chosen because they provide all necessary facet and function data about a diamond. They are very simple to implement and are computationally efficient.

Block explorers, GUIs, tests, and other tools may rely on their presence.

A reference implementation exists for these two introspection functions here: [DiamondInspectFacet.sol](../assets/erc-xxxx/DiamondInspectFacet.sol)

Other introspection functions may be added to a diamond. The above two functions are the only ones required by this standard.

### Implementation Requirements

A diamond MUST implement the following to be compliant with this standard:

1. **Diamond Structure**

   A diamond MUST implement a fallback function.

   A diamond MUST have a constructor function to add external functions and perform any initialization.

   A diamond MUST NOT have any external or public functions defined directly within it.

2. **Function Association**

   A diamond MUST associate function selectors with facet addresses.

3. **Function Execution**

   When an external function is called on a diamond:

   - The diamond’s fallback function is executed. 
   - The fallback function MUST find the facet associated with the function selector.
   - The fallback function MUST execute the function on the facet using `delegatecall`.
   - If no facet is associated with the function selector, the diamond MAY execute a default function or apply another handling mechanism.
   - If no facet, default function, or other handling mechanism exists, execution MUST revert.

4. **Events**

   The following events MUST be emitted:

   - `DiamondFunctionAdded` — when a function is added to a diamond.
   - `DiamondFunctionReplaced` — when a function is replaced in a diamond.
   - `DiamondFunctionRemoved` — when a function is removed from a diamond.
   
5. **Introspection**

   A diamond MUST implement the following introspection functions:

   - `facetAddress(bytes4 _functionSelector)`
   - `functionFacetPairs()`

## Rationale

This standard provides standard events, an upgrade function and introspection functions so that GUIs, block explorers, command line programs, and other tools and software can detect and interoperate with diamond contracts.

Software can retrieve function selectors and facet addresses from a diamond in order to show what functions a diamond has. Function selectors with the ABI of a contract provide enough information about functions to be useful for various software.

### ERC-XXXX Diamonds vs ERC-2535 Diamonds

This standard is a simplification and refinement of ERC-2535 Diamonds. 

A diamond compliant with ERC-XXXX is not required to implement ERC-2535.

### Gas Considerations
Delegating function calls has a small amount of gas overhead. This is mitigated in several ways:

1. Because diamonds do not have a max size limitation it is possible to add gas optimizing functions. For example someone could use a diamond to implement the [ERC-721](https://eips.ethereum.org/EIPS/eip-721) standard and implement batch transfer functions to reduce gas (and make batch transfers more convenient).
2. Some contract architectures require multiple external function calls in the same transaction. Gas savings can be realized by condensing contracts into a single diamond and accessing contract storage directly.
3. Facets can contain few external functions, reducing gas costs. It can cost more gas to call a function on a contract with many functions than a contract with few functions.
4. The Solidity optimizer can be set to a high setting causing more bytecode to be generated but the facets will use less gas when executed.

### `functionFacetPairs()` Gas Usage

The `functionFacetPairs()` function is meant to be called off-chain. At this time major RPC providers have a maximum gas limit of about 550 million gas. Gas benchmark tests show that the `functionFacetPairs()` function can return 60,000 `(selector, facet)` pairs using less gas than that.

ERC-XXXX implementations are free to add iteration or pagination-based introspection functions, but they are not required by this standard.

### Storage Layout

Diamonds and facets need to use a storage layout organizational pattern because Solidity’s default storage layout doesn’t support proxy contracts or diamonds. The particular technique of storage layout to use is not specified in this ERC. However, examples of storage layout patterns that work with diamonds are [ERC-8042 Diamond Storage](https://eips.ethereum.org/EIPS/eip-8042) and [ERC-7201 Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201).

### Facets Sharing Storage & Functionality

Facets are separately deployed, independent units, but can share state and functionality in the following ways:

- Facets can share state variables by using the same structs at the same storage positions. 
- Facets can share internal functions by importing them or inheriting contracts. 


### On-chain Facets can be Reused and Composed

A deployed facet can be used by many diamonds.

It is possible to create and deploy a set of facets that are reused by different diamonds.

The ability to use the same deployed facets for many diamonds has the potential to reduce development time, increase reliability and security, and reduce deployment costs.

It is possible to implement facets in a way that makes them usable/composable/compatible with other facets. 

### Function Signature Limitation

A function signature is the name of a function and its parameter types. Example function signature: `myfunction(uint256)`. A limitation is that two external functions with the same function signature can’t be added to the same diamond at the same time because a diamond, or any contract, cannot have two external functions with the same function signature.

## Backwards Compatibility

Existing, deployed ERC-2535 Diamonds implementations MAY upgrade to this standard by performing an upgrade that does the following:

1. Removes the existing upgrade function and adds a new upgrade function that uses the new events.
2. Adds the new `functionFacetPairs()` introspection function.
3. Emits a `DiamondFunctionAdded` event for every function currently in the diamond, including the new upgrade function and the new `functionFacetPairs()` function.

After this upgrade, the diamond is considered compliant with this standard and SHOULD be indexed and treated as a diamond of this standard going forward.

This upgrade acts as a 'state snapshot'. Indexers only interested in the current state of the diamond can start indexing from this transaction onwards, without needing to parse the legacy `DiamondCut` history.

To reconstruct the complete upgrade history requires retrieving all the past `DiamondCut` events as well as all new events defined in this standard.

#### ERC-2535 Diamonds with Legacy Immutable Functions

Definition:

> An immutable function is an external or public function defined directly in a diamond contract, not in a facet.

Immutable functions are intentionally excluded from ERC-XXXX to keep the function–facet model uniform and to simplify implementations.

Immutable functions are not allowed in ERC-XXXX diamonds.

However, to enable existing ERC-2535 diamonds to upgrade to this standard, ERC-XXXX permits a compatibility mode for diamonds that contain immutable functions.

An existing ERC-2535 diamond that contains immutable functions MAY upgrade to this standard subject to the following additional requirements:

1. The `DiamondFunctionAdded` event MUST be emitted for each immutable function.
2. Immutable functions MUST be returned by the introspection functions `facetAddress(bytes4 _functionSelector)` and `functionFacetPairs()`, where the facet address is the diamond’s own address.
3. Any upgrade function MUST revert on an attempt to replace or remove an immutable function.

## Reference Implementation

- The reference implementation for the `upgradeDiamond` function is here: [DiamondUpgradeFacet.sol](../assets/erc-xxxx/DiamondUpgradeFacet.sol).
- The reference implementation for the `facetAddress(bytes4 _functionSelector)` and `functionFacetPairs()` introspection functions is here: [DiamondInspectFacet.sol](../assets/erc-xxxx/DiamondInspectFacet.sol)
- An example implementation of an ERC-XXXX diamond is here: [DiamondExample.sol](../assets/erc-xxxx/DiamondExample.sol)

## Security Considerations

### Ownership and Authentication

The design and implementation of diamond ownership/authentication is not part of this standard. 

It is possible to create many different authentication or ownership schemes with diamonds. Authentication schemes can be very simple or complex, fine grained or coarse. This proposal does not limit it in any way. For example ownership/authentication could be as simple as a single account address having the authority to add/replace/remove functions. Or a decentralized autonomous organization could have the authority to add/replace/remove certain functions.

The development of standards and implementations of ownership, control and authentication of diamonds is encouraged.

### Arbitrary Execution with `upgradeDiamond`

The `upgradeDiamond` function allows arbitrary execution with access to the diamond’s storage (through `delegatecall`). Access to this function must be restricted carefully.

### Function Selector Clash

A function selector clash occurs when two different function signatures hash to the same four-byte hash. This has the unintended consequence of replacing an existing function in a diamond when the intention was to add a new function. This scenario is not possible with a properly implemented `upgradeDiamond` function because it prevents adding function selectors that already exist.

### Transparency

Diamonds emit an event every time one or more functions are added, replaced or removed. Source code can be verified. This enables people and software to monitor changes to a contract. If any bad acting function is added to a diamond then it can be seen.

Security and domain experts can review the history of change of a diamond to detect foul play.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).