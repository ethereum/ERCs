---
title: Fractionally Represented Non-Fungible Token Standard
description: A standard for fractionally represented non-fungible tokens.
author: Acme (@0xacme), Calder (@caldereth)
discussions-to: <URL>
status: Draft
type: Standards Track
category: ERC
created: 2024-03-05
requires: 165, 20, 721
---

## Abstract

This proposal introduces a standard for fractionally represented non-fungible tokens, allowing NFTs to be managed and owned fractionally within a single contract. This approach enables ERC-721 NFTs to coexist with ERC-20 tokens seamlessly, enhancing liquidity and access without dividing the NFT itself, and without the need for an explicit conversion step. The standard includes mechanisms for both fractional and whole token transfers, approvals, and event emissions.

## Motivation

Fractional ownership of NFTs has historically relied on external protocols that manage division and reconstitution of individual NFTs into fractional representations. The approach of dividing specific NFTs results in fragmented liquidity of the total token supply, as the fractional representations of two NFTs are not equivalent and therefore must be traded separately. Additionally, this approach requires locking of fractionalized NFTs, preventing free transfer until they are reconstituted.

Other approaches involve multiple linked contracts, which add unnecessary complexity and overhead to the interface. Dual linked contracts are also an atypical pattern for token contracts and therefore harder for users to understand.

This standard offers a unified solution to fractional ownership, aiming to increase the liquidity and accessibility of NFTs without compromising transferability or flexiblity.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Fractionally Represented Non-Fungible Token Interface

All ERC-XXXX compliant contracts MUST implement the IERCXXXX and IERC165 interfaces.

Compliant contracts MUST emit fractional Approval or Transfer events on approval or transfer of tokens in fractional representation. Compliant contracts MUST additionally emit non-fungible ApprovalForAll, Approval or Transfer on approval for all, approval, and transfer in non-fungible representation.

Note that the events portion of the interface draws from existing ERC-721 and ERC-20 standards but is not fully backwards compatible.

```solidity
interface IERCXXXX is /* IERC165 */ {
    /// @dev This emits when fractional representation approval for a given spender
  ///      is changed or reaffirmed.
  event FractionalApproval(address indexed owner, address indexed spender, uint256 value);

  /// @dev This emits when ownership of fractionally represented tokens changes
  ///      by any mechanism. This event emits when tokens are both created and destroyed,
  ///      ie. when from and to are assigned to the zero address respectively.
  event FractionalTransfer(address indexed from, address indexed to, uint256 amount);

  /// @dev This emits when an operator is enabled or disabled for an owner.
  ///      The operator can manage all NFTs of the owner.
  event ApprovalForAll(
    address indexed owner,
    address indexed operator,
    bool approved
  );

  /// @dev This emits when the approved spender is changed or reaffirmed for a given NFT.
  ///      A zero address emitted as spender implies that no addresses are approved for
  ///      this token.
  event NonFungibleApproval(
    address indexed owner,
    address indexed spender,
    uint256 indexed id
  );

  /// @dev This emits when ownership of any NFT changes by any mechanism.
  ///      This event emits when NFTs are both created and destroyed, ie. when
  ///      from and to are assigned to the zero address respectively.
  event NonFungibleTransfer(address indexed from, address indexed to, uint256 indexed id);

  /// @notice Decimal places in fractional representation
  /// @dev Decimals are used as a means of determining when balances or amounts
  ///      contain whole or purely fractional components
  /// @return Number of decimal places used in fractional representation
  function decimals() external view returns (uint8 decimals);

  /// @notice The total supply of a token in fractional representation
  /// @dev The total supply of NFTs may be recovered by computing
  ///      `totalSupply() / 10 ** decimals()`
  /// @return Total supply of the token in fractional representation
  function totalSupply() external view returns (uint256 totalSupply);

  /// @notice Balance of a given address in fractional representation
  /// @dev The total supply of NFTs may be recovered by computing
  ///      `totalSupply() / 10 ** decimals()`
  /// @param owner_ The address that owns the tokens
  /// @return Balance of a given address in fractional representation
  function balanceOf(address owner_) external view returns (uint256 balance);

  /// @notice Query if an address is an authorized operator for another address
  /// @param owner_ The address that owns the NFTs
  /// @param operator_ The address being checked for approval to act on behalf of the owner
  /// @return True if `operator_` is an approved operator for `owner_`, false otherwise
  function isApprovedForAll(
    address owner_,
    address operator_
  ) external view returns (bool isApproved);

  /// @notice Query the allowed amount an address can spend for another address
  /// @param owner_ The address that owns tokens in fractional representation
  /// @param spender_ The address being checked for allowance to spend on behalf of the owner
  /// @return The amount of tokens `spender_` is approved to spend on behalf of `owner_`
  function allowance(
    address owner_,
    address spender_
  ) external view returns (uint256 allowance);

  /// @notice Query the owner of a specific NFT.
  /// @dev Tokens owned by the zero address are considered invalid and should revert on
  ///      ownership query.
  /// @param id_ The unique identifier for an NFT.
  /// @return The address of the token's owner.
  function ownerOf(uint256 id_) external view returns (address owner);

  /// @notice Set approval for an address to spend a fractional amount,
  ///         or to spend a specific NFT.
  /// @dev There must be no overlap between valid ids and fractional values.
  /// @dev Throws unless `msg.sender` is the current NFT owner, or an authorized
  ///      operator of the current owner if an id is provided.
  /// @dev Throws if the id is not a valid NFT
  /// @param spender_ The spender of a given token or value.
  /// @param amountOrId_ A fractional value or id to approve.
  /// @return Whether the approval operation was successful or not.
  function approve(
    address spender_,
    uint256 amountOrId_
  ) external returns (bool success);

  /// @notice Set approval for a third party to manage all of the callers
  ///         non-fungible assets
  /// @param operator_ Address to add to the callers authorized operator set
  /// @param approved_ True if the operator is approved, false if not approved
  function setApprovalForAll(address operator_, bool approved_) external;

  /// @notice Transfer fractional tokens or an NFT from one address to another
  /// @dev There must be no overlap between valid ids and fractional values
  /// @dev The operation should revert if the caller is not `from_` or is not approved
  ///      to spent the tokens or NFT owned by `from_`
  /// @dev The operation should revert if value is less than the balance of `from_` or
  ///      if the NFT is not owned by `from_`
  /// @dev Throws if the id is not a valid NFT
  /// @param from_ The address to transfer fractional tokens or an NFT from
  /// @param to_ The address to transfer fractional tokens or an NFT to
  /// @param amountOrId_ The fractional value or a distinct NFT id to transfer
  /// @return True if the operation was successful
  function transferFrom(
    address from_,
    address to_,
    uint256 amountOrId_
  ) external returns (bool success);

  /// @notice Transfer fractional tokens from one address to another
  /// @dev The operation should revert if amount is less than the balance of `from_`
  /// @param to_ The address to transfer fractional tokens to
  /// @param amount_ The fractional value to transfer
  /// @return True if the operation was successful
  function transfer(address to_, uint256 amount_) external returns (bool success);

  /// @notice Transfers the ownership of an NFT from one address to another address
  /// @dev Throws unless `msg.sender` is the current owner, an authorized
  ///      operator, or the approved address for this NFT
  /// @dev Throws if `from_` is not the current owner
  /// @dev Throws if `to_` is the zero address
  /// @dev Throws if `tokenId_` is not a valid NFT
  /// @dev When transfer is complete, this function checks if `to_` is a
  ///      smart contract (code size > 0). If so, it calls `onERC721Received`
  ///      on `to_` and throws if the return value is not
  ///      `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`.
  /// @param from_ The address to transfer the NFT from
  /// @param to_ The address to transfer the NFT to
  /// @param tokenId_ The NFT to transfer
  /// @param data_ Additional data with no specified format, sent in call to `to_`
  function safeTransferFrom(
    address from_,
    address to_,
    uint256 id_,
    bytes calldata data_
  ) external;

  /// @notice Transfers the ownership of an NFT from one address to another address
  /// @dev This is identical to the above function safeTransferFrom interface
  ///      though must pass empty bytes as data to `to_`
  /// @param from_ The address to transfer the NFT from
  /// @param to_ The address to transfer the NFT to
  /// @param tokenId_ The NFT to transfer
  function safeTransferFrom(address from_, address to_, uint256 id_) external;
}

interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceID_ The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    ///      uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceID` and
    ///         `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceID_) external view returns (bool);
}
```

### Fractionally Represented Non-Fungible Token Metadata Interface

This is a RECOMMENDED interface, identical in definition to the [ERC-721 Metadata Interface](./eip-721.md). Rather than using this interface directly, a distinct metadata interface should be used here to avoid confusion surrounding ERC-721 inheritance.

```solidity
/// @title ERC-XXXX Fractional Non-Fungible Token Standard, optional metadata extension
interface IERCXXXXMetadata {
  /// @notice A descriptive, long-form name for a given token collection
  function name() external view returns (string memory name);

  /// @notice An abbreviated, short-form name for a given token collection
  function symbol() external view returns (string memory symbol);

  /// @notice A distinct Uniform Resource Identifier (URI) for a given asset.
  /// @dev Throws if `tokenId_` is not a valid NFT. URIs are defined in RFC
  ///      3986. The URI may point to a JSON file that conforms to the "ERC721
  ///      Metadata JSON Schema".
  /// @param id_ The NFT to fetch a token URI for
  /// @return The token's URI as a string
  function tokenURI(uint256 id_) external view returns (string memory uri);

  /// @notice Get the number of NFTs that have been minted but are not currently owned.
  /// @dev This should be the number of unowned NFTs, limited by the total
  ///      fractional supply.
  /// @return The number of NFTs not currently owned.
  function getBankedNFTsLength() external view returns (uint256 queueLength);

  /// @notice Get a paginated list of NFTs that have been minted but are not currently owned.
  /// @param start_ Start index in queue.
  /// @param count_ Number of tokens to return from start index, inclusive.
  /// @return An array of queued NFTs from `start_`, of maximum length `count_`.
  function getBankedNFTs(
    uint256 start_,
    uint256 count_
  ) external view returns (uint256[] memory nftsInQueue);
}
```

## Rationale

The design ideology behind this proposal can best be described as a standard, ERC-721 aligned non-fungible token implementation that represents balances in a fractional manner, while supporting traditional, non-specific transfer / approval logic seen in the ERC-20 standard.

It's important to note that our goal is to implicitly support as high a degree of backwards compatability with ERC-20 and ERC-721 standards as possible to reduce or negate integration lift for existing protocols. Much of the rationale behind the proposed fractional non-fungible token specification resides within two trains of thought: isolating interface design to adhere to either the ERC-721 or ERC-20 standards, or outlining implementation standards that isolate overlapping functionality at the logic level.

### ID and Amount Isolation

A crucial piece of our design approach has been to ensure that the discrete value space representing ID's and amounts is sufficiently isolated. More explicitly, this should be taken to mean that for all possible inputs, no ID may be assumed to be an amount and no amount may be assumed to be an ID. Given the goal of this proposal is to outline an interface and set of standards, we won't dive into implementation guidelines, though want to note that this effect can be achieved by checking ownership of a given ID input, isolating a range for NFT ID's, etc.

This approach ensures that logic in "overlapping" interfaces is similarly isolated, such that the probability of unexpected outcome for a given function call is minimized.

### Transfer Logic

Much of the decision

### Events

Given event selectors on both ERC-20 and ERC-721 overlap, we have decided to deviate from backwards compatability efforts in the definition of ERC-XXXX events. Recent efforts have revealed a range of potential solutions here, such as supporting events for one standard, emitting conflicting events that utilize distinct parameter indexing, amongst others.

We feel that, when moving towards standardization, ensuring events are properly descriptive and isolated is the ideal solution despite introducing complexity for indexing software. As a result, we adhere to traditional transfer and approval event definitions, though distinguish these events by the `Fractional` or `NonFungible` prefix.

### Pathing Logic

### NFT Banking

### ERC-165 Interface

We have decided to include the ERC-165 interface in specification both to adhere to ERC-721 design philosophy, and as a means of exposing interfaces at the contract level. We see this as a valuable, accepted standard to adhere to such that integrating applications may identify underlying specification.

Note that ERC-XXXX contracts should not make any claim through `supportsInterface` to support ERC-721 or ERC-20 standards as, despite strong backwards compatibility efforts, these contracts cannot fully adhere to existing specifications.

### Metadata

In-line with ERC-721, we've decided to isolate replicated metadata functionality through a separate interface. This interface includes traditional naming and token URI logic, though also introduces patterns surrounding token banking visibility, as outlined above in both the NFT Banking and Transfer Logic sections.

## Backwards Compatibility

The fractional non-fungible token standard aims to be nearly backwards compatible with existing ERC-721 and ERC-20 standards, though makes no claim to fully adhere to either and has as such been proposed through a distinct interface.

### Events

Events in ERC-721 and ERC-20 specifications share conflicting selectors on approval and transfer, meaning an adherent hybrid of the two cannot be achieved.

This is one of the few areas where backwards compatiblity has been intentionally broken, resulting in a new series of events with either a `Fractional` or `NonFungible` prefix. We believe that a decisive move to a non-conflicting, descriptive solution is ideal here, though will require external lift for indexing software.

### balanceOf

The `balanceOf` function as defined in both ERC-20 and ERC-721 standards varies, in practice, to represent either fractional or whole token ownership respectively. Given fractional non-fungible tokens should adhere to an underlying fractional representation, it follows that this function should return a balance in that representation. This does, however, imply that fractional NFT contracts cannot fully adhere to the `balanceOf` specification provided by ERC-721.

### Success Return Values

The `transfer` and `approve` functions both return a boolean value indicating success or failure. This is non-standard for the ERC-721 specification, though is standard for ERC-20. Fractional non-fungible tokens adhere to a returned boolean value to meet minimum expectations for the ERC-20 standard, acknowledging that this deviates from a state of ideal backwards compatability.

## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
