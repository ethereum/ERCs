// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Accounts.sol";
import "./Funds.sol";

/// Unique identifier for a fund, chosen by the controller
type FundId is bytes32;

/// Records account balances. Accounts are separated into funds.
/// Funds are kept separate between controllers.
///
/// A fund can only be manipulated by a controller when it is locked. Tokens can
/// only be withdrawn when a fund is unlocked.
///
/// The warden maintains the lock invariant to ensure its integrity:
///
/// (∀ controller ∈ Controller, fundId ∈ FundId:
///   fund.lockExpiry <= fund.lockMaximum
///   where fund = _funds[controller][fundId])
///
abstract contract WardenBase {
  using SafeERC20 for IERC20;
  using Funds for Fund;

  IERC20 internal immutable _token;

  /// Represents a smart contract that can redistribute and burn tokens in funds
  type Controller is address;

  /// Each controller has its own set of funds
  mapping(Controller => mapping(FundId => Fund)) private _funds;
  /// Each account holder has its own set of accounts in a fund
  mapping(Controller => mapping(FundId => mapping(AccountId => Account)))
  private _accounts;

  constructor(IERC20 token) {
    _token = token;
  }

  function _getFundStatus(
    Controller controller,
    FundId fundId
  ) internal view returns (FundStatus) {
    return _funds[controller][fundId].status();
  }

  function _getLockExpiry(
    Controller controller,
    FundId fundId
  ) internal view returns (Timestamp) {
    return _funds[controller][fundId].lockExpiry;
  }

  function _getBalance(
    Controller controller,
    FundId fundId,
    AccountId accountId
  ) internal view returns (Balance memory) {
    if (_funds[controller][fundId].status() == FundStatus.Inactive) {
      return Balance({available: 0, designated: 0});
    }
    return _accounts[controller][fundId][accountId].balance;
  }

  function _lock(
    Controller controller,
    FundId fundId,
    Timestamp expiry,
    Timestamp maximum
  ) internal {
    Fund memory fund = _funds[controller][fundId];
    require(fund.status() == FundStatus.Inactive, WardenFundAlreadyLocked());
    fund.lockExpiry = expiry;
    fund.lockMaximum = maximum;
    _checkLockInvariant(fund);
    _funds[controller][fundId] = fund;

    emit WardenFundLocked(controller, fundId, expiry, maximum);
  }

  function _extendLock(
    Controller controller,
    FundId fundId,
    Timestamp expiry
  ) internal {
    Fund memory fund = _funds[controller][fundId];
    require(fund.status() == FundStatus.Locked, WardenFundNotLocked());
    require(fund.lockExpiry <= expiry, WardenInvalidExpiry());
    Timestamp previousExpiry = fund.lockExpiry;
    fund.lockExpiry = expiry;
    _checkLockInvariant(fund);
    _funds[controller][fundId] = fund;

    emit WardenLockExtended(controller, fundId, previousExpiry, expiry);
  }

  function _deposit(
    Controller controller,
    FundId fundId,
    AccountId accountId,
    uint128 amount
  ) internal {
    Fund storage fund = _funds[controller][fundId];
    require(fund.status() == FundStatus.Locked, WardenFundNotLocked());

    Account storage account = _accounts[controller][fundId][accountId];

    account.balance.available += amount;

    emit WardenDeposited(controller, fundId, accountId, amount);

    _token.safeTransferFrom(
      Controller.unwrap(controller),
      address(this),
      amount
    );
  }

  function _designate(
    Controller controller,
    FundId fundId,
    AccountId accountId,
    uint128 amount
  ) internal {
    Fund memory fund = _funds[controller][fundId];
    require(fund.status() == FundStatus.Locked, WardenFundNotLocked());

    Account memory account = _accounts[controller][fundId][accountId];
    require(amount <= account.balance.available, WardenInsufficientBalance());

    account.balance.available -= amount;
    account.balance.designated += amount;

    _accounts[controller][fundId][accountId] = account;

    emit WardenDesignated(controller, fundId, accountId, amount);
  }

  function _transfer(
    Controller controller,
    FundId fundId,
    AccountId from,
    AccountId to,
    uint128 amount
  ) internal {
    Fund memory fund = _funds[controller][fundId];
    require(fund.status() == FundStatus.Locked, WardenFundNotLocked());

    Account memory sender = _accounts[controller][fundId][from];
    require(amount <= sender.balance.available, WardenInsufficientBalance());

    sender.balance.available -= amount;

    _accounts[controller][fundId][from] = sender;

    _accounts[controller][fundId][to].balance.available += amount;

    emit WardenTransferred(controller, fundId, from, to, amount);
  }

  function _burnDesignated(
    Controller controller,
    FundId fundId,
    AccountId accountId,
    uint128 amount
  ) internal {
    Fund storage fund = _funds[controller][fundId];
    require(fund.status() == FundStatus.Locked, WardenFundNotLocked());

    Account storage account = _accounts[controller][fundId][accountId];
    require(account.balance.designated >= amount, WardenInsufficientBalance());

    account.balance.designated -= amount;

    emit WardenDesignatedBurned(controller, fundId, accountId, amount);

    _token.safeTransfer(address(0xdead), amount);
  }

  function _burnAccount(
    Controller controller,
    FundId fundId,
    AccountId accountId
  ) internal {
    require(
      _funds[controller][fundId].status() == FundStatus.Locked,
      WardenFundNotLocked()
    );

    Account memory account = _accounts[controller][fundId][accountId];
    uint128 available = account.balance.available;
    uint128 designated = account.balance.designated;
    uint128 amount = available + designated;

    delete _accounts[controller][fundId][accountId];

    emit WardenAccountBurned(
      controller,
      fundId,
      accountId,
      available,
      designated
    );

    _token.safeTransfer(address(0xdead), amount);
  }

  function _sealFund(Controller controller, FundId fundId) internal {
    Fund storage fund = _funds[controller][fundId];
    require(fund.status() == FundStatus.Locked, WardenFundNotLocked());

    fund.sealedAt = Timestamps.currentTime();

    emit WardenFundSealed(controller, fundId);
  }

  function _withdraw(
    Controller controller,
    FundId fundId,
    AccountId accountId
  ) internal {
    require(
      _funds[controller][fundId].status() == FundStatus.Withdrawing,
      WardenFundNotUnlocked()
    );

    Account memory account = _accounts[controller][fundId][accountId];
    uint128 available = account.balance.available;
    uint128 designated = account.balance.designated;
    uint128 amount = available + designated;

    delete _accounts[controller][fundId][accountId];

    emit WardenWithdrawn(controller, fundId, accountId, available, designated);

    (address owner, ) = Accounts.decodeId(accountId);
    _token.safeTransfer(owner, amount);
  }

  function _checkLockInvariant(Fund memory fund) private pure {
    require(fund.lockExpiry <= fund.lockMaximum, WardenInvalidExpiry());
  }

  /// Emitted when a fund is locked, transitioning it from `Inactive` to
  /// `Locked`. Implementations that do not support the lock extension emit
  /// `maximum` equal to `expiry`.
  /// Note that the subsequent transition to `Withdrawing` is derived from
  /// `expiry` and happens without a transaction, so it emits no event.
  event WardenFundLocked(
    Controller indexed controller,
    FundId indexed fundId,
    Timestamp expiry,
    Timestamp maximum
  );

  /// Emitted when the lock expiry of a locked fund is moved forward.
  event WardenLockExtended(
    Controller indexed controller,
    FundId indexed fundId,
    Timestamp previousExpiry,
    Timestamp expiry
  );

  /// Emitted when a locked fund is sealed, transitioning it from `Locked` to
  /// `Sealed`.
  event WardenFundSealed(Controller indexed controller, FundId indexed fundId);

  /// Emitted when tokens are deposited into an account, increasing its
  /// available balance.
  event WardenDeposited(
    Controller indexed controller,
    FundId indexed fundId,
    AccountId indexed accountId,
    uint128 amount
  );

  /// Emitted when available tokens move between two accounts in a fund.
  /// `from` and `to` are not indexed; only three topics are available and
  /// `controller` and `fundId` claim two of them. Keeping both accounts in the
  /// data section avoids making one side of a transfer filterable and the
  /// other not.
  event WardenTransferred(
    Controller indexed controller,
    FundId indexed fundId,
    AccountId from,
    AccountId to,
    uint128 amount
  );

  /// Emitted when available tokens are irreversibly designated for the account
  /// holder.
  event WardenDesignated(
    Controller indexed controller,
    FundId indexed fundId,
    AccountId indexed accountId,
    uint128 amount
  );

  /// Emitted when designated tokens are burned from an account.
  event WardenDesignatedBurned(
    Controller indexed controller,
    FundId indexed fundId,
    AccountId indexed accountId,
    uint128 amount
  );

  /// Emitted when an entire account is burned. Both balances are reported so
  /// that consumers can determine the final state of the account without
  /// having tracked every preceding event.
  event WardenAccountBurned(
    Controller indexed controller,
    FundId indexed fundId,
    AccountId indexed accountId,
    uint128 available,
    uint128 designated
  );

  /// Emitted when an account is emptied and its tokens are transferred to the
  /// account holder. Both balances are reported for the same reason as in
  /// `WardenAccountBurned`.
  event WardenWithdrawn(
    Controller indexed controller,
    FundId indexed fundId,
    AccountId indexed accountId,
    uint128 available,
    uint128 designated
  );

  error WardenInsufficientBalance();
  error WardenInvalidExpiry();
  error WardenFundNotLocked();
  error WardenFundNotUnlocked();
  error WardenFundAlreadyLocked();
}
