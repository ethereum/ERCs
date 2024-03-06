---
title: Fractionally Represented Non-fungible Token Standard
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

Non-fungible [ERC-721](./eip-721.md) token contracts have experienced steady discussion and development surrounding the concept of fractionalization, a means by which a distinct, singular token may be represented fractionally. This proposal defines a standard by which the concept of fractionalization may be natively implemented and supported in non-fungible token contracts.

## Motivation

<!--
  This section is optional.

  The motivation section should include a description of any nontrivial problems the EIP solves. It should not describe how the EIP solves those problems, unless it is not immediately obvious. It should not describe why the EIP should be made into a standard, unless it is not immediately obvious.

  With a few exceptions, external links are not allowed. If you feel that a particular resource would demonstrate a compelling case for your EIP, then save it as a printer-friendly PDF, put it in the assets folder, and link to that copy.

  TODO: Remove this comment before submitting
-->

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Fractionally Represented Non-fungible Token Interface

All ERC-XXXX compliant contracts MUST implement the IERCXXXX and IERC165 interfaces.

```solidity
interface IERCXXXX is /* IERC165 */ {
  /// @notice Decimal places in fractional representation
  /// @dev Decimals are used as a means of determining when balances or amounts
  ///      contain whole or purely fractional components
  /// @return Number of decimal places used in fractional representation
  function decimals() external view returns (uint8 decimals_);

  /// @notice The total supply of a token in fractional representation
  /// @dev The total supply of NFTs may be recovered by computing
  ///      `totalSupply() / 10 ** decimals()`
  /// @return Total supply of the token in fractional representation
  function totalSupply() external view returns (uint256 totalSupply_);

  /// @notice Balance of a given address in fractional representation
  /// @dev The total supply of NFTs may be recovered by computing
  ///      `totalSupply() / 10 ** decimals()`
  /// @param owner_ The address that owns the tokens
  /// @return Balance of a given address in fractional representation
  function balanceOf(address owner_) external view returns (uint256 balance_);

  /// @notice Query if an address is an authorized operator for another address
  /// @param owner_ The address that owns the NFTs
  /// @param operator_ The address being checked for approval to act on behalf of the owner
  /// @return True if `operator_` is an approved operator for `owner_`, false otherwise
  function isApprovedForAll(
    address owner_,
    address operator_
  ) external view returns (bool isApproved_);

  /// @notice Query the allowed amount an address can spend for another address
  /// @param owner_ The address that owns tokens in fractional representation
  /// @param spender_ The address being checked for allowance to spend on behalf of the owner
  /// @return The amount of tokens `spender_` is approved to spend on behalf of `owner_`
  function allowance(
    address owner_,
    address spender_
  ) external view returns (uint256 allowance_);

  /// @notice Query the owner of a specific NFT
  /// @dev Tokens owned by the zero address are considered invalid and should revert on
  ///      ownership query
  /// @param id_ The unique identifier for an NFT
  /// @return The address of the token's owner
  function ownerOf(uint256 id_) external view returns (address owner_);

  /// @notice Set approval for an address to spend a fractional amount,
  ///         or to spend a specific NFT
  /// @dev There must be no overlap between valid ids and fractional values
  /// @dev Throws unless `msg.sender` is the current NFT owner, or an authorized
  ///      operator of the current owner if an id is provided
  /// @dev Throws if the id is not a valid NFT
  /// @param spender_ The spender of a given token or value
  /// @param amountOrId_ A fractional value or id to approve
  /// @return Whether the approval operation was successful or not
  function approve(
    address spender_,
    uint256 amountOrId_
  ) external returns (bool success_);

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
  ) external returns (bool success_);

  /// @notice Transfer fractional tokens from one address to another
  /// @dev The operation should revert if amount is less than the balance of `from_`
  /// @param to_ The address to transfer fractional tokens to
  /// @param amount_ The fractional value to transfer
  /// @return True if the operation was successful
  function transfer(address to_, uint256 amount_) external returns (bool success_);

  /// @notice Transfers the ownership of an NFT from one address to another address
  /// @dev Throws unless `msg.sender` is the current owner, an authorized
  ///      operator, or the approved address for this NFT
  /// @dev Throws if `_from` is not the current owner
  /// @dev Throws if `_to` is the zero address
  /// @dev Throws if `_tokenId` is not a valid NFT
  /// @dev When transfer is complete, this function checks if `_to` is a
  ///      smart contract (code size > 0). If so, it calls `onERC721Received`
  ///      on `_to` and throws if the return value is not
  ///      `bytes4(keccak256("onERC721Received(address,uint256,bytes)"))`.
  /// @param _from The address to transfer the NFT from
  /// @param _to The address to transfer the NFT to
  /// @param _tokenId The NFT to transfer
  /// @param data Additional data with no specified format, sent in call to `_to`
  function safeTransferFrom(
    address from_,
    address to_,
    uint256 id_,
    bytes calldata data_
  ) external;

  /// @notice Transfers the ownership of an NFT from one address to another address
  /// @dev This is identical to the above function safeTransferFrom interface
  ///      though must pass empty bytes as data to `to_`
  /// @param _from The address to transfer the NFT from
  /// @param _to The address to transfer the NFT to
  /// @param _tokenId The NFT to transfer
  function safeTransferFrom(address from_, address to_, uint256 id_) external;
}

interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceID The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    ///      uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceID` and
    ///         `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}
```

### Fractionally Represented Non-fungible Token Events

All ERC-XXXX compliant contracts MUST use the following library definitions. Compliant contracts MUST emit fractional Approval or Transfer events on approval or transfer of tokens in fractional representation. Compliant contracts MUST additionally emit non-fungible ApprovalForAll, Approval or Transfer on approval for all, approval, and transfer in non-fungible representation.

Note that these event libraries draw from existing ERC-721 and ERC-20 standards as a means of ensuring a reasonable degree of backward compatability and alignment with existing expectations surrounding event definitions.

```solidity
/// @title ERC-XXXX Fractional Event Library
library FractionalEvents {
  /// @dev This emits when fractional representation approval for a given spender
  ///      is changed or reaffirmed.
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /// @dev This emits when ownership of fractionally represented tokens changes
  ///      by any mechanism. This event emits when tokens are both created and destroyed,
  ///      ie. when from and to are assigned to the zero address respectively.
  event Transfer(address indexed from, address indexed to, uint256 amount);
}
```

```solidity
/// @title ERC-XXXX Non-Fungible Event Library
library NonFungibleEvents {
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
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 indexed id
  );

  /// @dev This emits when ownership of any NFT changes by any mechanism.
  ///      This event emits when NFTs are both created and destroyed, ie. when
  ///      from and to are assigned to the zero address respectively.
  event Transfer(address indexed from, address indexed to, uint256 indexed id);
}
```

### Fractionally Represented Non-fungible Token Metadata Interface

This is a RECOMMENDED interface, identical in definition to the [ERC-721 Metadata Interface](./eip-721.md). Rather than using this interface directly, a distinct metadata interface should be used here to avoid confusion surrounding ERC-721 inheritance.

```solidity
/// @title ERC-XXXX Fractional Non-Fungible Token Standard, optional metadata extension
interface IERCXXXXMetadata {
  /// @notice A descriptive, long-form name for a given token collection
  function name() external view returns (string memory name_);

  /// @notice An abbreviated, short-form name for a given token collection
  function symbol() external view returns (string memory symbol_);

  /// @notice A distinct Uniform Resource Identifier (URI) for a given asset.
  /// @dev Throws if `_tokenId` is not a valid NFT. URIs are defined in RFC
  ///      3986. The URI may point to a JSON file that conforms to the "ERC721
  ///      Metadata JSON Schema".
  /// @param id_ The NFT to fetch a token URI for
  /// @return The token's URI as a string
  function tokenURI(uint256 id_) external view returns (string memory uri_);

  /// @notice Get the number of NFTs not currently owned
  /// @dev This should be the number of unowned NFTs, limited by the total
  ///      fractional supply
  /// @return The number of NFTs not currently owned
  function getNFTQueueLength() external view returns (uint256 queueLength_);

  /// @notice Get a paginated list of NFTs not currently owned
  /// @param start_ Start index in queue
  /// @param count_ Number of tokens to return from start index, inclusive
  /// @return An array of queued NFTs from `start_`, of maximum length `count_`
  function getNFTsInQueue(
    uint256 start_,
    uint256 count_
  ) external view returns (uint256[] memory nftsInQueue_);
}
```

## Rationale

TBD

## Backwards Compatibility

The fractional non-fungible token standard aims to be nearly backwards compatible with existing ERC-721 and ERC-20 standards, though makes no claim to fully adhere to either.

### Events

Events in ERC-721 and ERC-20 specifications share conflicting selectors on approval and transfer, meaning an adherent hybrid of the two cannot be achieved. In practice, however, distinct usage of indexed event parameters between the two specifications allows for

### balanceOf

The `balanceOf` function as defined in both ERC-20 and ERC-721 standards varies, in practice, to represent either whole or fractional token ownership. Given franctional non-fungible tokens should adhere to an underlying fractional representation, it follows that this function should return a balance in that representation. This does, however, imply that fractional NFT contracts cannot fully adhere to the specification provided by ERC-721.

## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
