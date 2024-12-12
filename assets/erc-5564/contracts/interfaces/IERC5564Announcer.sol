// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.23;

/// @notice Interface for calling the `ERC5564Announcer` contract, which emits an `Announcement`
/// event to broadcast information about a transaction involving a stealth address. See
/// [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) to learn more.
interface IERC5564Announcer {
  /// @notice Emitted when something is sent to a stealth address.
  /// @param schemeId Identifier corresponding to the applied stealth address scheme, e.g. 1 for
  /// secp256k1, as specified in ERC-5564.
  /// @param stealthAddress The computed stealth address for the recipient.
  /// @param caller The caller of the `announce` function that emitted this event.
  /// @param ephemeralPubKey Ephemeral public key used by the sender to derive the `stealthAddress`.
  /// @param metadata Arbitrary data to emit with the event. The first byte MUST be the view tag.
  /// @dev The remaining metadata can be used by the senders however they like. See
  /// [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) for recommendations on how to structure
  /// this metadata.
  event Announcement(
    uint256 indexed schemeId,
    address indexed stealthAddress,
    address indexed caller,
    bytes ephemeralPubKey,
    bytes metadata
  );

  /// @notice Called by integrators to emit an `Announcement` event.
  /// @param schemeId Identifier corresponding to the applied stealth address scheme, e.g. 1 for
  /// secp256k1, as specified in ERC-5564.
  /// @param stealthAddress The computed stealth address for the recipient.
  /// @param ephemeralPubKey Ephemeral public key used by the sender.
  /// @param metadata Arbitrary data to emit with the event. The first byte MUST be the view tag.
  /// @dev The remaining metadata can be used by the senders however they like. See
  /// [ERC-5564](https://eips.ethereum.org/EIPS/eip-5564) for recommendations on how to structure
  /// this metadata.
  function announce(
    uint256 schemeId,
    address stealthAddress,
    bytes memory ephemeralPubKey,
    bytes memory metadata
  ) external;
}
