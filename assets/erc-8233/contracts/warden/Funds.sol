// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../Timestamps.sol";

struct Fund {
  /// The time-lock unlocks at this time
  Timestamp lockExpiry;
  /// The lock expiry can be extended no further than this
  Timestamp lockMaximum;
  /// Indicates whether fund is sealed, and at what time
  Timestamp sealedAt;
}

/// A fund can go through the following states:
///
///     -->  Inactive ---> Locked -----> Withdrawing
///                          \               ^
///                           \             /
///                            --> Sealed --
///
enum FundStatus {
  /// Indicates that the fund is inactive and contains no tokens. This is the
  /// initial state.
  Inactive,
  /// Indicates that a time-lock is set and withdrawing tokens is not allowed. A
  /// fund needs to be locked for deposits, transfers and burning to be
  /// allowed.
  Locked,
  /// Indicates that a locked fund is sealed. Nothing is allowed until the
  /// fund unlocks.
  Sealed,
  /// Indicates the fund has unlocked and withdrawing is allowed. Other
  /// operations are no longer allowed.
  Withdrawing
}

library Funds {
  function status(Fund memory fund) internal view returns (FundStatus) {
    if (Timestamps.currentTime() < fund.lockExpiry) {
      if (fund.sealedAt != Timestamp.wrap(0)) {
        return FundStatus.Sealed;
      }
      return FundStatus.Locked;
    }
    if (fund.lockMaximum == Timestamp.wrap(0)) {
      return FundStatus.Inactive;
    }
    return FundStatus.Withdrawing;
  }

}
