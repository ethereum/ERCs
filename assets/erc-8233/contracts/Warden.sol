// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./warden/WardenBase.sol";

/// A warden provides a means for smart contracts to control allocation of ERC20
/// tokens without the need to hold the ERC20 tokens themselves, thereby
/// decreasing their own attack surface.
///
/// A warden keeps track of funds for a smart contract. This smart contract is
/// called the controller of the funds. Each controller has its own independent
/// set of funds. Each fund has a number of accounts.
///
///     Warden -> Controller -> Fund -> Account
///
/// Funds are identified by a unique 32 byte identifier, chosen by the
/// controller.
///
/// An account has a balance, of which a part can be designated. Designated
/// tokens can no longer be transferred to another account, although they can be
/// burned.
/// Accounts are identified by the address of the account holder, and an id that
/// can be used to create different accounts for the same holder.
///
/// A typical flow in which a controller uses the warden to handle funds:
/// 1. the controller chooses a unique id for the fund
/// 2. the controller locks the fund for an amount of time
/// 3. the controller deposits ERC20 tokens into the fund
/// 4. the controller transfers tokens between accounts in the fund
/// 5. the fund unlocks after a while, freezing the account balances
/// 6. the controller withdraws ERC20 tokens from the fund for an account holder,
///    or the account holder initiates the withdrawal itself
///
/// The warden makes it harder for an attacker to extract funds, through several
/// mechanisms:
/// - tokens in a fund can only be reassigned while the fund is time-locked, and
///   only be withdrawn after the lock unlocks, delaying an attacker's attempt
///   at extraction of tokens from the warden
/// - tokens in a fund can not be reassigned when the lock unlocks, ensuring
///   that they can no longer be reassigned to an attacker
/// - when storing collateral, it can be designated for the collateral provider,
///   ensuring that it cannot be reassigned to an attacker
/// - malicious upgrades to a fund controller cannot prevent account holders
///   from withdrawing their tokens
/// - burning tokens in a fund ensures that these tokens can no longer be
///   extracted by an attacker
///
contract Warden is WardenBase {
  constructor(IERC20 token) WardenBase(token) {}

  function getToken() public view returns (IERC20) {
    return _token;
  }

  /// Creates an account id that encodes the address of the account holder, and
  /// a discriminator. The discriminator can be used to create different
  /// accounts within a fund that all belong to the same account holder.
  function encodeAccountId(
    address holder,
    bytes12 discriminator
  ) public pure returns (AccountId) {
    return Accounts.encodeId(holder, discriminator);
  }

  /// Extracts the address of the account holder and the discriminator from the
  /// account id.
  function decodeAccountId(
    AccountId id
  ) public pure returns (address holder, bytes12 discriminator) {
    return Accounts.decodeId(id);
  }

  /// The amount of tokens that are currently in an account.
  /// This includes available and designated tokens. Available tokens can be
  /// transferred to other accounts, but designated tokens cannot.
  function getBalance(
    FundId fundId,
    AccountId accountId
  ) public view returns (uint128) {
    Controller controller = Controller.wrap(msg.sender);
    Balance memory balance = _getBalance(controller, fundId, accountId);
    return balance.available + balance.designated;
  }

  /// The amount of tokens that are currently designated in an account
  /// These tokens can no longer be transferred to other accounts.
  function getDesignatedBalance(
    FundId fundId,
    AccountId accountId
  ) public view returns (uint128) {
    Controller controller = Controller.wrap(msg.sender);
    Balance memory balance = _getBalance(controller, fundId, accountId);
    return balance.designated;
  }

  /// Returns the status of the fund. Most operations on the warden can only be
  /// done by the controller when the funds are locked. Withdrawals can only be
  /// done in the withdrawing state.
  function getFundStatus(FundId fundId) public view returns (FundStatus) {
    Controller controller = Controller.wrap(msg.sender);
    return _getFundStatus(controller, fundId);
  }

  /// Returns the expiry time of the lock on the fund. A locked fund unlocks
  /// automatically at this timestamp.
  function getLockExpiry(FundId fundId) public view returns (Timestamp) {
    Controller controller = Controller.wrap(msg.sender);
    return _getLockExpiry(controller, fundId);
  }

  /// Locks the fund until the expiry timestamp. The lock expiry can be extended
  /// later, but no more than the maximum timestamp.
  function lock(
    FundId fundId,
    Timestamp expiry,
    Timestamp maximum
  ) public {
    Controller controller = Controller.wrap(msg.sender);
    _lock(controller, fundId, expiry, maximum);
  }

  /// Locks the fund until the expiry timestamp.
  function lock(
    FundId fundId,
    Timestamp expiry
  ) public {
    Controller controller = Controller.wrap(msg.sender);
    _lock(controller, fundId, expiry, expiry);
  }

  /// Delays unlocking of a locked fund. The new expiry should be later than
  /// the existing expiry, but no later than the maximum timestamp that was
  /// provided when locking the fund.
  /// Only allowed when the lock has not unlocked yet.
  function extendLock(FundId fundId, Timestamp expiry) public {
    Controller controller = Controller.wrap(msg.sender);
    _extendLock(controller, fundId, expiry);
  }

  /// Deposits an amount of tokens into the warden, and adds them to the balance
  /// of the account. ERC20 tokens are transferred from the caller to the warden
  /// contract.
  /// Only allowed when the fund is locked.
  function deposit(
    FundId fundId,
    AccountId accountId,
    uint128 amount
  ) public {
    Controller controller = Controller.wrap(msg.sender);
    _deposit(controller, fundId, accountId, amount);
  }

  /// Takes an amount of tokens from the account balance and designates them
  /// for the account holder. These tokens are no longer available to be
  /// transferred to other accounts.
  /// Only allowed when the fund is locked.
  function designate(
    FundId fundId,
    AccountId accountId,
    uint128 amount
  ) public {
    Controller controller = Controller.wrap(msg.sender);
    _designate(controller, fundId, accountId, amount);
  }

  /// Transfers an amount of tokens from one account to the other.
  /// Only allowed when the fund is locked.
  function transfer(
    FundId fundId,
    AccountId from,
    AccountId to,
    uint128 amount
  ) public {
    Controller controller = Controller.wrap(msg.sender);
    _transfer(controller, fundId, from, to, amount);
  }

  /// Burns an amount of designated tokens from the account.
  /// Only allowed when the fund is locked.
  function burnDesignated(
    FundId fundId,
    AccountId accountId,
    uint128 amount
  ) public {
    Controller controller = Controller.wrap(msg.sender);
    _burnDesignated(controller, fundId, accountId, amount);
  }

  /// Burns all tokens from the account.
  /// Only allowed when the fund is locked.
  /// Only allowed when no funds are flowing into or out of the account.
  function burnAccount(
    FundId fundId,
    AccountId accountId
  ) public {
    Controller controller = Controller.wrap(msg.sender);
    _burnAccount(controller, fundId, accountId);
  }

  /// Seals a fund. Disallows any further transfers, designations, deposits,
  /// or burns until the fund unlocks and withdrawals begin.
  /// Only allowed when the fund is locked.
  function sealFund(FundId fundId) public {
    Controller controller = Controller.wrap(msg.sender);
    _sealFund(controller, fundId);
  }

  /// Transfers all ERC20 tokens in the account out of the warden to the account
  /// owner.
  /// Only allowed when the fund is unlocked.
  /// ⚠️ The account holder can also withdraw itself, so when designing a smart
  /// contract that controls funds in the warden, don't assume that only this
  /// smart contract can initiate a withdrawal ⚠️
  function withdraw(FundId fund, AccountId accountId) public {
    Controller controller = Controller.wrap(msg.sender);
    _withdraw(controller, fund, accountId);
  }

  /// Allows an account holder to withdraw its tokens from a fund directly,
  /// bypassing the need to ask the controller of the fund to initiate the
  /// withdrawal.
  /// Only allowed when the fund is unlocked.
  function withdrawByRecipient(
    Controller controller,
    FundId fund,
    AccountId accountId
  ) public {
    (address holder, ) = Accounts.decodeId(accountId);
    require(msg.sender == holder, WardenOnlyAccountHolder());
    _withdraw(controller, fund, accountId);
  }

  error WardenOnlyAccountHolder();
}
