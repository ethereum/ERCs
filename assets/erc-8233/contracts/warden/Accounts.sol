// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// Used to identify an account. The first 20 bytes consist of the address of
/// the account holder, and the last 12 bytes consist of a discriminator value.
type AccountId is bytes32;

/// Records the token balance of an account
struct Account {
  Balance balance;
}

/// The account balance. Fits in 32 bytes to minimize storage costs.
/// A uint128 is used to record the amount of tokens, which should be more than
/// enough. Given a standard 18 decimal places for the ERC20 token, this still
/// allows for 10^20 whole coins.
struct Balance {
  /// Available tokens can be transferred
  uint128 available;
  /// Designated tokens can no longer be transferred
  uint128 designated;
}

library Accounts {
  /// Creates an account id from the account holder address and a discriminator.
  /// The discriminator can be used to create different accounts that belong to
  /// the same account holder.
  function encodeId(
    address holder,
    bytes12 discriminator
  ) internal pure returns (AccountId) {
    bytes32 left = bytes32(bytes20(holder));
    bytes32 right = bytes32(uint256(uint96(discriminator)));
    return AccountId.wrap(left | right);
  }

  /// Extracts the account holder and the discriminator from the account id
  function decodeId(AccountId id) internal pure returns (address, bytes12) {
    bytes32 unwrapped = AccountId.unwrap(id);
    address holder = address(bytes20(unwrapped));
    bytes12 discriminator = bytes12(uint96(uint256(unwrapped)));
    return (holder, discriminator);
  }
}
