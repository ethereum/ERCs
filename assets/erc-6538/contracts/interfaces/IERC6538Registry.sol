// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.23;

/// @dev Interface for calling the `ERC6538Registry` contract to map accounts to their stealth
/// meta-address. See [ERC-6538](https://eips.ethereum.org/EIPS/eip-6538) to learn more.
interface IERC6538Registry {
  /// @notice Emitted when an invalid signature is provided to `registerKeysOnBehalf`.
  error ERC6538Registry__InvalidSignature();

  /// @dev Emitted when a registrant updates their stealth meta-address.
  /// @param registrant The account that registered the stealth meta-address.
  /// @param schemeId Identifier corresponding to the applied stealth address scheme, e.g. 1 for
  /// secp256k1, as specified in ERC-5564.
  /// @param stealthMetaAddress The stealth meta-address.
  /// [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) bases the format for stealth
  /// meta-addresses on [ERC-3770](https://eips.ethereum.org/EIPS/eip-3770) and specifies them as:
  ///   st:<shortName>:0x<spendingPubKey>:<viewingPubKey>
  /// The chain (`shortName`) is implicit based on the chain the `ERC6538Registry` is deployed on,
  /// therefore this `stealthMetaAddress` is just the `spendingPubKey` and `viewingPubKey`
  /// concatenated.
  event StealthMetaAddressSet(
    address indexed registrant, uint256 indexed schemeId, bytes stealthMetaAddress
  );

  /// @notice Emitted when a registrant increments their nonce.
  /// @param registrant The account that incremented the nonce.
  /// @param newNonce The new nonce value.
  event NonceIncremented(address indexed registrant, uint256 newNonce);

  /// @notice Sets the caller's stealth meta-address for the given scheme ID.
  /// @param schemeId Identifier corresponding to the applied stealth address scheme, e.g. 1 for
  /// secp256k1, as specified in ERC-5564.
  /// @param stealthMetaAddress The stealth meta-address to register.
  function registerKeys(uint256 schemeId, bytes calldata stealthMetaAddress) external;

  /// @notice Sets the `registrant`'s stealth meta-address for the given scheme ID.
  /// @param registrant Address of the registrant.
  /// @param schemeId Identifier corresponding to the applied stealth address scheme, e.g. 1 for
  /// secp256k1, as specified in ERC-5564.
  /// @param signature A signature from the `registrant` authorizing the registration.
  /// @param stealthMetaAddress The stealth meta-address to register.
  /// @dev Supports both EOA signatures and EIP-1271 signatures.
  /// @dev Reverts if the signature is invalid.
  function registerKeysOnBehalf(
    address registrant,
    uint256 schemeId,
    bytes memory signature,
    bytes calldata stealthMetaAddress
  ) external;

  /// @notice Increments the nonce of the sender to invalidate existing signatures.
  function incrementNonce() external;

  /// @notice Returns the domain separator used in this contract.
  function DOMAIN_SEPARATOR() external view returns (bytes32);

  /// @notice Returns the stealth meta-address for the given `registrant` and `schemeId`.
  function stealthMetaAddressOf(address registrant, uint256 schemeId)
    external
    view
    returns (bytes memory);

  /// @notice Returns the EIP-712 type hash used in `registerKeysOnBehalf`.
  function ERC6538REGISTRY_ENTRY_TYPE_HASH() external view returns (bytes32);

  /// @notice Returns the nonce of the given `registrant`.
  function nonceOf(address registrant) external view returns (uint256);
}
