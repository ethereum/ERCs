---
title: Equity Token
description: Equity token standard for corporations
author: Matt Rosendin <matt@capsign.com>
discussions-to: https://ethereum-magicians.org/t/equity-token-standard/20735
status: Draft
type: Standards
category: ERC
created: 2024-08-06
requires: EIP-173
---

## Abstract

An ERC token standard representing shares in a corporation. This new interface standardizes equity management for issuers, investors, transfer agents, and financial intermediaries.

## Motivation

Creating a standard for corporation requires an industry effort. That's why this token standard adheres to the same design principles as the [Open Cap Format](https://www.opencaptablecoalition.com/format) (OCF), an industry-approved data standard for cap tables. Now everyone can adopt the same OCF-compliant token standard for Ethereum and beyond!

## Specification

> The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

**MUST NOT** use ERC-20 transfer methods, which now **MUST** include the `securityId` parameter.

**SHOULD** use `balanceOf(address)` to get a holder's total share count, incuding all share classes.

**SHOULD** use `balanceOfByClass(address,string)` to lookup a holder's balance by the specified share class.

**MAY** use `balanceOf(address,string)` instead of `balanceOfByClass(address,string)`.

This standard is not backwards compatible with ERC-20 since it generates a unique security ID for each transfer and mint.

Every compliant contract must implement this interface:

```solidity
/// @dev types
library Types {

  /// @dev Stores details about the acquisition of a security
  struct Security {
    bytes32 id;
    address holder;
    bytes32 class;
    bytes32 balanceSecurityId;
    bytes32[] resultingSecurityIds;
    uint256 frozenAmount;
    uint256 amount;
    uint256 issuedAt; // Block timestamp of issuance tx
    string uri; // Additional metadata stored in json file at the uri
  }

  /// @dev Stores corporate governing documents (e.g. charter, stock plan)
  struct Document {
    string uri;
    bytes32 documentHash;
  }

  /// @dev Store details about frozen shares
  struct FrozenShares {
    bytes32 class;
    uint256 amount;
  }

}

/// @dev interface
interface IToken {

  /// events

  event Approval(address indexed _owner, address indexed _spender, uint256 _amount);

  event Transfer(address indexed from, address indexed to, bytes32 securityId, uint256 amount, bytes32[] newIds);

  event DocumentSet(bytes32 indexed _name, string _uri, bytes32 _documentHash);

  event ShareClassAdded(bytes32 indexed _class, string indexed _uri);

  event ShareClassUpdated(bytes32 indexed _class, string indexed _uri);

  event ShareClassRemoved(bytes32 indexed _class);

  /**
   *  this event is emitted when the token information is updated.
   *  the event is emitted by the token init function and by the setTokenInformation function
   *  `_newName` is the name of the token
   *  `_newSymbol` is the symbol of the token
   *  `_newDecimals` is the decimals of the token
   *  `_newVersion` is the version of the token, current version is 1.0
   *  `_newOnchainID` is the address of the onchainID of the token
   */
  event UpdatedTokenInformation(
    string indexed _newName,
    string indexed _newSymbol,
    uint8 _newDecimals,
    string _newVersion,
    address indexed _newOnchainID
  );

  /**
   *  this event is emitted when the IdentityRegistry has been set for the token
   *  the event is emitted by the token constructor and by the setIdentityRegistry function
   *  `_identityRegistry` is the address of the Identity Registry of the token
   */
  event IdentityRegistryAdded(address indexed _identityRegistry);

  /**
   *  this event is emitted when the Compliance has been set for the token
   *  the event is emitted by the token constructor and by the setCompliance function
   *  `_compliance` is the address of the Compliance contract of the token
   */
  event ComplianceAdded(address indexed _compliance);

  /**
   *  this event is emitted when an investor successfully recovers his tokens
   *  the event is emitted by the recoveryAddress function
   *  `_lostWallet` is the address of the wallet that the investor lost access to
   *  `_newWallet` is the address of the wallet that the investor provided for the recovery
   *  `_investorOnchainID` is the address of the onchainID of the investor who asked for a recovery
   */
  event RecoverySuccess(address indexed _lostWallet, address indexed _newWallet, address indexed _investorOnchainID);

  /**
   *  this event is emitted when the wallet of an investor is frozen or unfrozen
   *  the event is emitted by setAddressFrozen and batchSetAddressFrozen functions
   *  `_userAddress` is the wallet of the investor that is concerned by the freezing status
   *  `_isFrozen` is the freezing status of the wallet
   *  if `_isFrozen` equals `true` the wallet is frozen after emission of the event
   *  if `_isFrozen` equals `false` the wallet is unfrozen after emission of the event
   *  `_owner` is the address of the agent who called the function to freeze the wallet
   */
  event AddressFrozen(address indexed _userAddress, bool indexed _isFrozen, address indexed _owner);

  /**
   *  this event is emitted when a certain amount of tokens is frozen on a wallet
   *  the event is emitted by freezePartialTokens and batchFreezePartialTokens functions
   *  `_userAddress` is the wallet of the investor that is concerned by the freezing status
   *  `_amount` is the amount of tokens that are frozen
   *  `_securityId` is the ID of the security to freeze
   */
  event TokensFrozen(address indexed _userAddress, bytes32 _securityId, uint256 _amount);

  /**
   *  this event is emitted when a certain amount of tokens is unfrozen on a wallet
   *  the event is emitted by unfreezePartialTokens and batchUnfreezePartialTokens functions
   *  `_userAddress` is the wallet of the investor that is concerned by the freezing status
   *  `_amount` is the amount of tokens that are unfrozen
   *  `_securityId` is the ID of the security to unfreeze
   */
  event TokensUnfrozen(address indexed _userAddress, bytes32 _securityId, uint256 _amount);

  /**
   *  this event is emitted when the token is paused
   *  the event is emitted by the pause function
   *  `_userAddress` is the address of the wallet that called the pause function
   */
  event Paused(address _userAddress);

  /**
   *  this event is emitted when the token is unpaused
   *  the event is emitted by the unpause function
   *  `_userAddress` is the address of the wallet that called the unpause function
   */
  event Unpaused(address _userAddress);

  /// @dev Getter for securities mapping

  function securities(bytes32 securityId) external view returns (Types.Security memory);

  /// @dev Based on ERC1400 and ERC1155

  /**
   * @param _class The name of the share class to query
   * @param _holder The holder of the tokens to fetch the balance for
   */
  function balanceOfByClass(bytes32 _class, address _holder) external view returns (uint256);

  /**
   * @notice Fetches all share type details
   */
  function getShareClasses() external view returns (bytes32[] calldata);

  /**
   * @param _name The name of the document
   */
  function getDocument(bytes32 _name) external view returns (string memory, bytes32);

  /**
   * @notice Fetches total supply by share class
   */
  function totalSupplyByClass(bytes32 _class) external view returns (uint256);

  /**
   * @param _name The name of the document
   * @param _uri The URI of the document
   * @param _documentHash The document hash
   */
  function setDocument(bytes32 _name, string memory _uri, bytes32 _documentHash) external;

  /// @dev Based on ERC20

  function allowance(address owner, bytes32 shareClass, address spender) external view returns (uint256);
  function approve(address spender,  bytes32 shareClass, uint256 amount) external returns (bool);
  function increaseAllowance(address spender,  bytes32 shareClass, uint256 addedValue) external returns (bool);
  function decreaseAllowance(address spender,  bytes32 shareClass, uint256 subtractedValue) external returns (bool);
  function totalSupply() external view returns (uint256);

  /**
   * @notice Returns the total balance of all share classes for the user.
   * @param account The account to fetch the balance of.
   */
  function balanceOf(address account) external view returns (uint256);

  /**
   *  @notice ERC-20 overridden function that include logic to check for trade validity.
   *  Require that the from and to addresses are not frozen.
   *  Require that the value should not exceed available balance.
   *  Require that the to address is a verified address.
   *  @param _from The address of the sender
   *  @param _to The address of the receiver
   *  @param _securityId The ID of the security to transfer
   *  @param _amount The number of tokens to transfer
   *  @return `true` if successful and revert if unsuccessful
   */
  function transferFrom(
    address _from,
    address _to,
    bytes32 _securityId,
    uint256 _amount
  ) external returns (bool);

  /**
   *  @notice ERC-20 overridden function that include logic to check for trade validity.
   *  Require that the msg.sender and to addresses are not frozen.
   *  Require that the value should not exceed available balance .
   *  Require that the to address is a verified address
   *  @param _to The address of the receiver
   *  @param _securityId The ID of the security to transfer
   *  @param _amount The number of tokens to transfer
   *  @return `true` if successful and revert if unsuccessful
   */
  function transfer(address _to, bytes32 _securityId, uint256 _amount) external returns (bool);

  /// @dev Based on ERC3643

  /**
   *  @dev sets the token name
   *  @param _name the name of token to set
   *  Only the owner of the token smart contract can call this function
   *  emits a `UpdatedTokenInformation` event
   */
  function setName(string calldata _name) external;

  /**
   *  @dev sets the token symbol
   *  @param _symbol the token symbol to set
   *  Only the owner of the token smart contract can call this function
   *  emits a `UpdatedTokenInformation` event
   */
  function setSymbol(string calldata _symbol) external;

  /**
   *  @dev sets the onchain ID of the token
   *  @param _onchainID the address of the onchain ID to set
   *  Only the owner of the token smart contract can call this function
   *  emits a `UpdatedTokenInformation` event
   */
  function setOnchainID(address _onchainID) external;

  /**
   *  @dev pauses the token contract, when contract is paused investors cannot transfer tokens anymore
   *  This function can only be called by a wallet set as agent of the token
   *  emits a `Paused` event
   */
  function pause() external;

  /**
   *  @dev unpauses the token contract, when contract is unpaused investors can transfer tokens
   *  if their wallet is not blocked & if the amount to transfer is <= to the amount of free tokens
   *  This function can only be called by a wallet set as agent of the token
   *  emits an `Unpaused` event
   */
  function unpause() external;

  /**
   *  @dev sets an address frozen status for this token.
   *  @param _userAddress The address for which to update frozen status
   *  @param _freeze Frozen status of the address
   *  This function can only be called by a wallet set as agent of the token
   *  emits an `AddressFrozen` event
   */
  function setAddressFrozen(address _userAddress, bool _freeze) external;

  /**
   *  @dev freezes token amount specified for given address.
   *  @param _userAddress The address for which to update frozen tokens
   *  @param _securityId The security ID to perform partial freeze on
   *  @param _amount Amount of Tokens to be frozen
   *  This function can only be called by a wallet set as agent of the token
   *  emits a `TokensFrozen` event
   */
  function freezePartialTokens(address _userAddress, bytes32 _securityId, uint256 _amount) external;

  /**
   *  @dev unfreezes token amount specified for given address
   *  @param _userAddress The address for which to update frozen tokens
   *  @param _securityId The security ID to perform partial freeze on
   *  @param _amount Amount of Tokens to be unfrozen
   *  This function can only be called by a wallet set as agent of the token
   *  emits a `TokensUnfrozen` event
   */
  function unfreezePartialTokens(address _userAddress, bytes32 _securityId, uint256 _amount) external;

  /**
   *  @dev sets the Identity Registry for the token
   *  @param _identityRegistry the address of the Identity Registry to set
   *  Only the owner of the token smart contract can call this function
   *  emits an `IdentityRegistryAdded` event
   */
  function setIdentityRegistry(address _identityRegistry) external;

  /**
   *  @dev sets the compliance contract of the token
   *  @param _compliance the address of the compliance contract to set
   *  Only the owner of the token smart contract can call this function
   *  calls bindToken on the compliance contract
   *  emits a `ComplianceAdded` event
   */
  function setCompliance(address _compliance) external;

  /**
   *  @dev force a transfer of tokens between 2 whitelisted wallets
   *  In case the `from` address has not enough free tokens (unfrozen tokens)
   *  but has a total balance higher or equal to the `amount`
   *  the amount of frozen tokens is reduced in order to have enough free tokens
   *  to proceed the transfer, in such a case, the remaining balance on the `from`
   *  account is 100% composed of frozen tokens post-transfer.
   *  Require that the `to` address is a verified address,
   *  @param _from The address of the sender
   *  @param _to The address of the receiver
   *  @param _securityId The ID of the security to transfer
   *  @param _amount The number of tokens to transfer
   *  @return `true` if successful and revert if unsuccessful
   *  This function can only be called by a wallet set as agent of the token
   *  emits a `TokensUnfrozen` event if `_amount` is higher than the free balance of `_from`
   *  emits a `Transfer` event
   */
  function forcedTransfer(address _from, address _to, bytes32 _securityId, uint256 _amount) external returns (bool);

  /**
   *  @dev mint tokens on a wallet
   *  Improved version of default mint method. Tokens can be minted
   *  to an address if only it is a verified address as per the security token.
   *  @param _to Address to mint the tokens to.
   *  @param _shareClass The name of the share class (e.g., Common Class A).
   *  @param _amount The amount of tokens to mint.
   *  @param _uri The URI containing metadata about the security.
   *  This function can only be called by a wallet set as agent of the token
   *  emits a `Transfer` event
   */
  function mint(address _to, bytes32 _shareClass, uint256 _amount, string memory _uri) external;

  /**
   *  @dev burn tokens on a wallet
   *  In case the `account` address has not enough free tokens (unfrozen tokens)
   *  but has a total balance higher or equal to the `value` amount
   *  the amount of frozen tokens is reduced in order to have enough free tokens
   *  to proceed the burn, in such a case, the remaining balance on the `account`
   *  is 100% composed of frozen tokens post-transaction.
   *  @param _userAddress Address to burn the tokens from.
   *  @param _securityId The ID of the security to burn.
   *  @param _amount Amount of tokens to burn.
   *  This function can only be called by a wallet set as agent of the token
   *  emits a `TokensUnfrozen` event if `_amount` is higher than the free balance of `_userAddress`
   *  emits a `Transfer` event
   */
  function burn(address _userAddress, bytes32 _securityId, uint256 _amount) external;

  /**
   *  @dev recovery function used to force transfer tokens from a
   *  lost wallet to a new wallet for an investor.
   *  @param _lostWallet the wallet that the investor lost
   *  @param _newWallet the newly provided wallet on which tokens have to be transferred
   *  @param _investorOnchainID the onchainID of the investor asking for a recovery
   *  This function can only be called by a wallet set as agent of the token
   *  emits a `TokensUnfrozen` event if there are frozen tokens on the lost wallet if recovery process successful
   *  emits a `Transfer` event if the recovery process is successful
   *  emits a `RecoverySuccess` event if the recovery process is successful
   *  emits a `RecoveryFails` event if the recovery process fails
   */
  function recoveryAddress(address _lostWallet, address _newWallet, address _investorOnchainID) external returns (bool);

  /**
   *  @dev function allowing to issue transfers in batch
   *  Require that the msg.sender and `to` addresses are not frozen.
   *  Require that the total value should not exceed available balance.
   *  Require that the `to` addresses are all verified addresses,
   *  IMPORTANT : THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_toList.length` IS TOO HIGH,
   *  USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
   *  @param _toList The addresses of the receivers
   *  @param _securityIds The IDs of the securities to transfer
   *  @param _amounts The number of tokens to transfer to the corresponding receiver
   *  emits _toList.length `Transfer` events
   */
  function batchTransfer(
    address[] calldata _toList,
    bytes32[] memory _securityIds,
    uint256[] calldata _amounts
  ) external;

  /**
   *  @dev function allowing to issue forced transfers in batch
   *  Require that `_amounts[i]` should not exceed available balance of `_fromList[i]`.
   *  Require that the `_toList` addresses are all verified addresses
   *  IMPORTANT : THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_fromList.length` IS TOO HIGH,
   *  USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
   *  @param _fromList The addresses of the senders
   *  @param _toList The addresses of the receivers
   *  @param _securityIds The IDs of the securities to transfer
   *  @param _amounts The number of tokens to transfer to the corresponding receiver
   *  This function can only be called by a wallet set as agent of the token
   *  emits `TokensUnfrozen` events if `_amounts[i]` is higher than the free balance of `_fromList[i]`
   *  emits _fromList.length `Transfer` events
   */
  function batchForcedTransfer(
    address[] calldata _fromList,
    address[] calldata _toList,
    bytes32[] calldata _securityIds,
    uint256[] calldata _amounts
  ) external;

  /**
   *  @dev Batch mints multiple securities at once.
   *  Require that the `_toList` addresses are all verified addresses
   *  IMPORTANT: THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_toList.length` IS TOO HIGH,
   *  USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
   *  @param _toList The addresses of the receivers
   *  @param _shareClasses Array of classes for each security.
   *  @param _amounts Array of amounts to mint for each security.
   *  @param _metadataURIs Array of URIs containing metadata about each security.
   *  This function can only be called by a wallet set as agent of the token
   *  emits _toList.length `Transfer` events
   */
  function batchMint(
    address[] memory _toList,
    bytes32[] memory _shareClasses,
    uint256[] memory _amounts,
    string[] memory _metadataURIs
  ) external;

  /**
   *  @dev function allowing to burn tokens in batch
   *  Require that the `_userAddresses` addresses are all verified addresses
   *  IMPORTANT : THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_userAddresses.length` IS TOO HIGH,
   *  USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
   *  @param _userAddresses The addresses of the wallets concerned by the burn
   *  @param _securityIds The IDs of the securities to batch burn
   *  @param _amounts The number of tokens to burn from the corresponding wallets
   *  This function can only be called by a wallet set as agent of the token
   *  emits _userAddresses.length `Transfer` events
   */
  function batchBurn(address[] calldata _userAddresses, bytes32[] calldata _securityIds, uint256[] calldata _amounts) external;

  /**
   *  @dev function allowing to set frozen addresses in batch
   *  IMPORTANT : THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_userAddresses.length` IS TOO HIGH,
   *  USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
   *  @param _userAddresses The addresses for which to update frozen status
   *  @param _freeze Frozen status of the corresponding address
   *  This function can only be called by a wallet set as agent of the token
   *  emits _userAddresses.length `AddressFrozen` events
   */
  function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external;

  /**
   *  @dev function allowing to freeze tokens partially in batch
   *  IMPORTANT : THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_userAddresses.length` IS TOO HIGH,
   *  USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
   *  @param _userAddresses The addresses on which tokens need to be frozen
   *  @param _securityIds The security IDs to operate on
   *  @param _amounts the amount of tokens to freeze on the corresponding address
   *  This function can only be called by a wallet set as agent of the token
   *  emits _userAddresses.length `TokensFrozen` events
   */
  function batchFreezePartialTokens(
    address[] calldata _userAddresses,
    bytes32[] calldata _securityIds,
    uint256[] calldata _amounts
  ) external;

  /**
   *  @dev function allowing to unfreeze tokens partially in batch
   *  IMPORTANT : THIS TRANSACTION COULD EXCEED GAS LIMIT IF `_userAddresses.length` IS TOO HIGH,
   *  USE WITH CARE OR YOU COULD LOSE TX FEES WITH AN "OUT OF GAS" TRANSACTION
   *  @param _userAddresses The addresses on which tokens need to be unfrozen
   *  @param _securityIds The security IDs to operate on
   *  @param _amounts the amount of tokens to unfreeze on the corresponding address
   *  This function can only be called by a wallet set as agent of the token
   *  emits _userAddresses.length `TokensUnfrozen` events
   */
  function batchUnfreezePartialTokens(
    address[] calldata _userAddresses,
    bytes32[] calldata _securityIds,
    uint256[] calldata _amounts
  ) external;

  /**
   * @dev Returns the number of decimals used to get its user representation.
   * For example, if `decimals` equals `2`, a balance of `505` tokens should
   * be displayed to a user as `5,05` (`505 / 1 ** 2`).
   *
   * Tokens usually opt for a value of 18, imitating the relationship between
   * Ether and Wei.
   *
   * NOTE: This information is only used for _display_ purposes: it in
   * no way affects any of the arithmetic of the contract, including
   * balanceOf() and transfer().
   */
  function decimals() external view returns (uint8);

  /**
   * @dev Returns the name of the token.
   */
  function name() external view returns (string memory);

  /**
   * @dev Returns the address of the onchainID of the token.
   * the onchainID of the token gives all the information available
   * about the token and is managed by the token issuer or his agent.
   */
  function onchainID() external view returns (address);

  /**
   * @dev Returns the symbol of the token, usually a shorter version of the
   * name.
   */
  function symbol() external view returns (string memory);

  /**
   * @dev Returns the TREX version of the token.
   * current version is 3.0.0
   */
  function version() external view returns (string memory);

  /**
   *  @dev Returns the Identity Registry linked to the token
   */
  function identityRegistry() external view returns (address);

  /**
   *  @dev Returns the Compliance contract linked to the token
   */
  function compliance() external view returns (address);

  /**
   * @dev Returns true if the contract is paused, and false otherwise.
   */
  function paused() external view returns (bool);

  /**
   *  @dev Returns the freezing status of a wallet
   *  if isFrozen returns `true` the wallet is frozen
   *  if isFrozen returns `false` the wallet is not frozen
   *  isFrozen returning `true` doesn't mean that the balance is free, tokens could be blocked by
   *  a partial freeze or the whole token could be blocked by pause
   *  @param _userAddress the address of the wallet on which isFrozen is called
   */
  function isFrozen(address _userAddress) external view returns (bool);

  /**
   *  @dev Returns the amount of tokens that are partially frozen on a wallet
   *  the amount of frozen tokens is always <= to the total balance of the wallet
   *  @param _userAddress the address of the wallet on which getFrozenTokens is called
   */
  function getFrozenTokens(address _userAddress) external view returns (Types.FrozenShares[] memory);
}
```

## Rationale

This token is not backwards compatible with ERC-20 transfer methods because the spec requires the generation of a unique security balance ID for every mint and transfer call. We plan to include standards for vesting, equity derivatives, or convertibles in separate ERCs.

## Backwards Compatibility

Equity tokens should not be backwards compatible with ERC-20 nor ERC-3643.

## Security Considerations

Needs discussion.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).