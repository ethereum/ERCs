---
title: Diamonds, Simplified
description: A structured approach to isolate, organize, test, and manage distinct areas of contract functionality. 
author: Nick Mudge (@mudgen)
discussions-to: https://ethereum-magicians.org/t/proposal-for-a-simplified-standard-for-diamond-contracts/27119
status: Draft
type: Standards Track
category: ERC
created: 2025-12-13
requires: 2535, 1538 
---


## Abstract

A diamond is a proxy contract that `delegatecall`s to multiple implementation contracts called facets. 

<img alt="Diagram showing how facets compose into a diamond contract" class="" src="../assets/erc-xxxx/basic-diamond-diagram.svg" align="left" style="max-width: 100%; height: auto;">


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
2. A facet is a stateless smart contract that defines one or more external functions. A facet is deployed independently, and one or more of its functions are added to one or more diamonds. A facet does not store persistent data in its own contract storage, but its functions may read from and write to the storage of a diamond. The term facet is derived from the diamond industry, referring to a flat surface of a diamond.
3. An **introspection function** is a function that returns information about the facets and functions used by a diamond.
4. An **immutable function** is an external function whose implementation cannot be replaced or removed because it is defined directly in the diamond contract rather than in a facet.
5. For the purposes of this specification, a **mapping** refers to a conceptual association between two items and does not refer to a specific implementation.


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
  // Get facet from function selector
    address facet = selectorTofacet[msg.sig];
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

### Facets Sharing Storage & Functionality

A storage layout organizational pattern is needed because Solidity’s default storage layout doesn’t support proxy contracts or diamonds. The particular technique of storage layout to use is not specified in this ERC. However, examples of storage layout patterns that work with diamonds are [ERC-8042 Diamond Storage](https://eips.ethereum.org/EIPS/eip-8042) and [ERC-7201 Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201).

Facets are separately deployed, independent units, but can share state and functionality in the following ways:

- Facets can share state variables by using the same structs at the same storage positions. 
- Facets can share internal functions by importing them or inheriting contracts. 

### Events

#### Adding/Replacing/Removing Functions

These events are REQUIRED.

Anytime a function is added or replaced or removed from a diamond, one of these functions MUST be emitted:


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

#### Recording Delegatecalls

The `DiamondDelegateCall` event is OPTIONAL.

A diamond contract MAY emit this event to record execution of logic via `delegatecall`, including during construction, initialization, or upgrade operations. 

For example this event can be emitted to record the execution of an initialization function after add/replacing/removing functions in a diamond.

This event MUST NOT be used to record `delegatecall`s performed by a diamond’s fallback function when routing calls to facets. Instead, it is intended to record `delegatecall`s made by a diamond's constructor function or by functions defined in facets.


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

#### 2. You Can Creating Your Own Upgrade Functions

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
error CannotReplaceFunctionThatDoesNotExists(bytes4 _selector);
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
* The `DiamondStateModified` event is emitted.
* However, if `_init` is zero, no `delegatecall` is made and no 
* `DiamondStateModified` event is emitted.
*
* If _tag is none zero or if _metadata size is greater than zero then the
* `DiamondMetadata` event is emitted with that data.
*
* All the parameters of this function are optional.
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
    bytes32 calldata _tag,
    bytes calldata _metadata
) external;
```

After adding/replacing/removing functions the `_functionCall` argument is executed with `delegatecall` on `_init`. This execution is done to initialize data or setup or remove anything needed or no longer needed after adding, replacing and/or removing functions. 

However if `_init` is `address(0)` then no initialization function is called.

## Inspecting Diamonds

Diamond introspection functions return information about what functions and facet are used in a diamond.

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

These function were chosen because they provide all necessary facet and function data about a diamond. They are very simple to implement and are computationally efficient.

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




