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
1. A **diamond** is a smart contract that routes external function calls to to one or more implementation contracts, referred to as facets. A diamond is stateful: all persistent data is stored in the diamond’s contract storage.
2. A facet is a stateless smart contract that defines one or more external functions. A facet is deployed independently, and one or more of its functions are added to one or more diamonds. A facet does not store persistent data in its own contract storage, but its functions may read from and write to the storage of a diamond. The term facet is derived from the diamond industry, referring to a flat surface of a diamond.
3. An **introspection function** is a function that returns information about the facets and functions used by a diamond.
4. An **immutable function** is an external function whose implementation cannot be replaced or removed. This may be because the function is defined directly in the diamond contract rather than in a facet, or because the diamond’s logic does not permit modification of that function.
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



### Storage

A storage layout organizational pattern is needed because Solidity’s default storage layout doesn’t support proxy contracts or diamonds. The particular layout of storage is not defined in this ERC. Examples of storage layout patterns that work with diamonds are [ERC-8042 Diamond Storage](https://eips.ethereum.org/EIPS/eip-8042) and [ERC-7201 Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201).

Facets can share state variables by using the same structs at the same storage positions. Facets can share internal functions and libraries by inheriting the same contracts or using the same libraries. In these ways facets are separate, independent units but can share state and functionality.



