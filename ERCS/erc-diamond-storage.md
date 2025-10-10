---
eip: TBA
title: Diamond Storage
description: Define storage locations for structs using human-readable, meaningful strings.
author: Nick Mudge (@mudgen)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC # Only required for Standards Track. Otherwise, remove this field.
created: <date created on, in ISO 8601 (yyyy-mm-dd) format>
requires: eip-7201
---

<!--
  READ EIP-1 (https://eips.ethereum.org/EIPS/eip-1) BEFORE USING THIS TEMPLATE!

  This is the suggested template for new EIPs. After you have filled in the requisite fields, please delete these comments.

  Note that an EIP number will be assigned by an editor. When opening a pull request to submit your EIP, please use an abbreviated title in the filename, `eip-draft_title_abbrev.md`.

  The title should be 44 characters or less. It should not repeat the EIP number in title, irrespective of the category.

  TODO: Remove this comment before submitting
-->

## Abstract
This standard formalizes the diamond storage pattern originally introduced by EIP-2535 and widely adopted across modular smart contract systems.

Diamond storage defines struct locations in contract storage using the keccak256 hash of human-readable identifiers.

EIP-8035 standardizes this simple and production-proven approach, offering a lightweight alternative to EIP-7201 for new and existing projects.
<!--
  The Abstract is a multi-sentence (short paragraph) technical summary. This should be a very terse and human-readable version of the specification section. Someone should be able to read only the abstract to get the gist of what this specification does.

  TODO: Remove this comment before submitting
-->

## Motivation

On March 10, 2020, a change to the Solidity compiler introduced the ability to assign structs to any storage location. This enabled a new pattern for using separate areas of storage. The pattern became known as diamond storage, as it was first popularized by EIP-2535 Diamonds and has since been widely used.

Later, on June 20, 2023, EIP-7201 was introduced to standardize this general storage pattern. However, the formula that EIP-7201 proposed for generating storage locations differed from the one already established and in active use by diamond storage.

EIP-8035 standardizes diamond storage for new projects and validates past diamond storage implementations.

While EIP-7201 defines a generalized mechanism for storage namespaces, EIP-8035 preserves the simplicity and backward compatibility of the diamond storage convention already deployed in production across many projects.

Some developers may prefer diamond storage because of its restricted, ASCII-based identifiers and simpler formula for computing storage locations.

<!--
  This section is optional.

  The motivation section should include a description of any nontrivial problems the EIP solves. It should not describe how the EIP solves those problems, unless it is not immediately obvious. It should not describe why the EIP should be made into a standard, unless it is not immediately obvious.

  With a few exceptions, external links are not allowed. If you feel that a particular resource would demonstrate a compelling case for your EIP, then save it as a printer-friendly PDF, put it in the assets folder, and link to that copy.

  TODO: Remove this comment before submitting
-->

## Specification

<!--
  The Specification section should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for any of the current Ethereum platforms (besu, erigon, ethereumjs, go-ethereum, nethermind, or others).

  It is recommended to follow RFC 2119 and RFC 8174. Do not remove the key word definitions if RFC 2119 and RFC 8174 are followed.

  TODO: Remove this comment before submitting
-->
Diamond storage defines where structs are located in contract storage.

A diamond storage identifier is defined as a string containing only printable ASCII characters in it. That is characters `0x20` through `0x7E` inclusive.

The location of a diamond storage struct is determined by the keccak256 hash of a diamond storage identifier.

### Recommendations

1. #### Use unique, human-readable, meaningful strings

   A human-readable string is a string that humans can normally read and understand, like "Transaction successful".

   A meaningful string in this context is a string that appropriately names or describes a storage space, or uses a pattern to do so. For example, `"myproject.erc721.registry"` is a hierarchical pattern that specifies ERC-721 related storage for a registry. The string, `"car.fish.piano.run"` is not a meaningful string because it is random and does not appropriately name or describe something.

   Diamond storage identifiers should be unique, human-readable, meaningful strings.

2. #### Use Solidity's string literals

   A string literal is an ASCII string type that is literally written between quotes, for example: `"this is a string literal"`.

   It is recommended to use Solidity's string literals to create diamond storage identifiers because the Solidity compiler enforces that they only contain printable ASCII characters, characters `0x20` through `0x7E` inclusive. Hex (`\xNN`) and Unicode (`\uNNNN`) escape sequences should **NOT** be used in diamond storage identifiers.

   It is recommended to use compile-time constant string literals. Here is an example:

   `bytes32 constant STORAGE_POSITION = keccak256("myproject.erc721.registry");`
3. #### Do NOT use Unicode literals

   Unicode literals can contain invisible characters and other non-ASCII characters which violates the specification of this standard.

   Here is an example of a Unicode literal in Solidity: `string memory a = unicode"Hello 😃";`

   Unicode literals should **NOT** be used to create diamond storage identifiers.

4. #### Do not use the space `0x20` character

   Including the space (`0x20`) character in diamond storage identifiers is not recommended, as it may interfere with tooling such as the NatSpec tag described next.


### ERC-8035 NatSpec tag

EIP-7201 defines the NatSpec tag `@custom:storage-location <FORMULA_ID>:<NAMESPACE_ID>`, where `<FORMULA_ID>` identifies a formula used to compute the storage location of a struct based on the namespace id.

The formula identified by `erc8035` is defined as `erc8035(id: string literal) = keccak256(id)`. In Solidity, this corresponds to the expression `keccak256(id)`. When using this formula the annotation becomes `@custom:storage-location erc8035:<NAMESPACE_ID>`. For example, `@custom:storage-location erc8035:myproject.erc721.registry` annotates diamond storage with id `"myproject.erc721.registry"` rooted at `erc8035("myproject.erc721.registry")`.


## Rationale

Proxy contracts and contracts that use `DELEGATECALL` need a reliable and secure way to define, document, and manage separate areas of smart contract storage.

In March 2020, diamond storage established a way to do this and has been in use since then. However, diamond storage wasn't formalized as a standard, which is important to clarify its mechanics, usage and precise specification.

In June 2023, EIP-7201 standardized the general pattern but has looser restrictions on namespace ids and a more complicated formula for calculating storage locations. Some people may prefer using EIP-7201, especially if they may auto-generate machine-readable or random strings for their namespace ids.

Some people may prefer EIP-8035 for its ASCII-enforced, human-readable, meaningful strings and simple calculation of storage locations.

EIP-8035 depends conceptually on EIP-2535 Diamonds, which first introduced the pattern of distinct storage areas for modular contracts. EIP-7201 later standardized the idea. EIP-8035 standardizes the original, simpler diamond storage variant for new projects and legacy compatibility.

### Comparing EIP-8035 and EIP-7201

EIP-7201 applies a formula to a namespace id to generate a storage location. Per the EIP-7201 specification a namespace id is a string that should not contain any whitespace characters. A namespace id has no other restrictions. So a namespace id could be something meaningful like "mycompany.projectA.erc721" or it could be a series of random bytes, characters or words, etc.

EIP-7201 uses the following formula, given in Solidity, to generate a storage location: `keccak256(abi.encode(uint256(keccak256(bytes(namespace id))) - 1)) & ~bytes32(uint256(0xff))`.

The last part of EIP-7201, `& ~bytes32(uint256(0xff))` ensures that the final storage location is a multiple of 256 which may provide a gas optimization in the future.

EIP-8035 recommends a human-readable, meaningful string as a diamond storage. EIP-8035 identifiers can only contain printable ASCII characters and recommends using Solidity's string literals which enforces this constraint.

EIP-8035 uses the following formula, given in Solidity, to generate a storage location: `keccak256(string literal)`.

EIP-8035 and EIP-7201 both depend on keccak256 collision resistance.

## Backwards Compatibility

Diamond storage as described by this standard has been in use for 5 years. This standard validates and makes standard all past use of diamond storage that complies with this standard.

## Reference Implementation

This is a simple example of a Solidity library that uses diamond storage:
```solidity
library ERC721RegistryLib {

  error ERC721RegistryFull();
  
  // struct storage position defined by keccak256 hash
  // of diamond storage identifier
  bytes32 constant STORAGE_POSITION = 
    keccak256("myproject.erc721.registry");
  
  // @custom:storage-location erc8035:myproject.erc721.registry
  struct ERC721RegistryStorage {
    address[] erc721Contracts;
    uint256 registryLimit;    
  }

  function getStorage() 
    internal 
    pure 
    returns (ERC721RegistryStorage storage s) 
  {
    bytes32 position = STORAGE_POSITION;
    assembly {
      s.slot := position
    }
  }

  function setRegistryLimit(uint256 _newLimit) internal {
    getStorage().registryLimit = _newLimit;
  }

  function addERC721Contract(address _erc721Contract) internal { 
    ERC721RegistryStorage storage s = getStorage();

    if(s.erc721Contracts.length == s.registryLimit) 
      revert ERC721RegistryFull();
    
    s.erc721Contracts.push(_erc721Contract);        
  }

  function getERC721Registry() 
    internal 
    view 
    returns (address[] memory erc721Contracts) 
  {
    return getStorage().erc721Contracts;
  }
}
```

## Security Considerations

### Uniqueness of identifiers
Two independent contracts or libraries using the same human-readable string will map to the same storage slot. Developers must ensure that diamond storage identifiers are unique within a contract system to prevent unintentional data overlap or corruption. A common practice is to prefix identifiers with a project, organization, or standard name (for example, `"myproject.erc721.registry"`).


### ASCII Input Restriction to Prevent Storage Collisions

To prevent storage collisions, diamond storage identifiers must consist only of printable ASCII characters, specifically the range `0x20` to `0x7E` inclusive. Identifiers must not include Unicode escape sequences (`\uNNNN`) or hexadecimal escape sequences (`\xNN`).

Solidity’s storage slot encoding, as produced by `abi.encode(p)`, contains non-printable bytes, particularly null bytes (`0x00`), due to Solidity’s default storage layout and padding rules.

Allowing identifiers to include such bytes could enable a malicious developer to craft an identifier like `"config\x00\x00..."`. The bytes of such an identifier could collide with the storage encoded input of mappings, dynamic arrays, strings and bytes which use keccak256 to compute storage locations. Such collisions could result in overwrites, corruption of contract state, or security vulnerabilities.

Restricting identifiers to printable ASCII removes this exploitable source of collision. While this restriction does not provide a mathematical guarantee that collisions are impossible — because, in theory, a sufficiently large storage layout position (`p`) could accidentally contain all printable ASCII bytes — the probability of this occurring is extremely small, and impractical.

By using human-readable, meaningful strings for identifiers, the practical likelihood of any collision is virtually zero, providing strong protection for the integrity and safety of contract storage.

### String Literals

The specification recommends using string literals to create diamond storage identifiers because the Solidity compiler enforces that only printable ASCII characters are used. However, string literals should not use Unicode escape sequences (`\uNNNN` ) or hexadecimal escape sequences (`\xNN` ).

### Unicode Literals

Unicode literals (e.g. `unicode"Hello 😃"`) should not be used to create diamond storage identifiers because they can contain non-printable bytes and characters, and they can be used to obfuscate identifiers by using characters that look like other characters. For example, the Cyrillic character `а` (`\u0430`) looks identical to the ASCII character `a` (`\u0061`).” In addition Unicode has control characters that change the direction text is displayed.

### keccak256 Hash Collision Resistance

The location of a diamond storage struct is determined by the output of the keccak256 hash function. Some developers may wonder about the likelihood that a diamond storage struct lands at an address where it will accidentally overwrite existing storage data. The 256 bit address space of contract storage is so vast that the likelihood of data overlap is statistically improbable.

Solidity mappings, dynamic arrays, strings and bytes also use keccak256 to determine their location in contract storage.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).