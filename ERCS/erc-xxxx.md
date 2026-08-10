---
eip:
title: Parametric Token
description: An extension of ERC-20 enabling fungible tokens with account-specific mutable or immutable parameters and sub-accounts.
author: Alexander Zvezdin (@k2eno)
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-parametric-token/29385
status: Draft
type: Standards Track
category: ERC
created: 2026-08-10
requires: 20, 165
---

## Abstract

This proposal introduces a standard for parametric ERC‑20 tokens—tokens that carry additional, account‑specific parameters beyond simple balances. Parameters may be **mutable** (updated during transfers according to token‑specific rules, e.g., weighted averages) or **immutable** (must remain identical across all tokens that can coexist in the same account). The standard defines an account model that supports **sub‑accounts** (partitions) within a single address, enabling a user to hold multiple parameter variants without requiring multiple wallets. It also extends the ERC‑20 allowance system to support sub‑account‑specific approvals with a one‑off consumption option.

The standard is fully backward‑compatible with ERC‑20, ensuring seamless integration with existing wallets, exchanges, and DeFi protocols.

## Motivation

The parametric token standard is a primitive for the next generation of ERC-20 compatible DeFi and agentic finance: assets that carry state, liquidity that consolidates rather than fragments, value that can be containerized, and tokenomics engineered at the parameter level to support both human and autonomous, self-improving value transfer.

### Liquidity Consolidation

Existing asset price predictions use a multi-binary approach: users bet yes or no across discrete outcome pools, which fragments liquidity and distorts the prediction itself, forcing users to select from preset buckets rather than simply quoting an expected price.

Tokens with different mutable parameters (e.g., price predictions) can trade in the same environment because the contract manages parameter logic and allows tokens to merge in the same account. No need to split markets into separate pools per parameter value. This capability is unique to the parametric model.

### Velocity Control

Parameters allow deliberate control of token turnover:

- **Utility‑bearing tokens** (hedging instruments, access passes) benefit from higher velocity. Progressive age‑based fees stimulate higher turnover: users who no longer need the utility sell the token to avoid extra costs.
- **Yield‑bearing tokens** (staking, governance, credentials, RWAs) benefit from user loyalty (i.e. lower velocity). Progressive age‑based rewards incentivise long‑term holding. Age‑weighted rewards or voting power align incentives with genuine commitment.

### Advanced Derivatives

The Bundle construct (convex portfolio of WBTC and its inverse) demonstrates how parametric tokens enable sophisticated synthetic instruments out‑of‑the‑box, with robust, abuse-resistant mechanics. Token‑controlled parameters allow institutions to launch new derivative types, including RWA extensions.

### Agentic & Autonomous Systems

Parametric tokens provide a secure evaluation and execution framework for autonomous agents. Agents implement logic, while parametric tokens serve as the rails - enabling agents to shape solutions, generate value, and channel it through the token's parameter topology on a competitive basis. Unlike static tokens, parametric tokens allow agents to keep track of these value flows, encoding strategy outcomes directly into the token state. The Bundle capability further extends this: agents can now containerize value, creating compound structures that represent complex strategies or aggregated positions. This aligns with the agentic economy's core principles—utility generation, capital efficiency, and just-in-time token usage—making parametric tokens an intrinsic enabler for the next generation of autonomous finance.

### UX Simplification

Sub‑accounts let users hold multiple parameter variants in a single address – no need for multiple wallets. Fine‑grained permissions (sub‑account‑specific, one‑off allowances) give precise control over delegated spending.

## Specification

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “NOT RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119 and RFC 8174\.

### ⚠️ Core Design Principle: Separation of Ledger Accounting and Economic Value

The standard treats parameters as abstract, uninterpreted numerical structures (`uint64[]`). It is entirely agnostic to economic meaning, game-theoretic impacts, or market valuation. Its sole invariant is deterministic preservation, partitioning, and mutation of the parameter matrix.

The reference implementations are minimally complex execution proofs that intentionally abstract away all production layers: minting is permissionless, rewards are illustrative, and economic safeguards (e.g., inbound allowances, collateralization, oracle cross-checks) are left to external controllers.

Implementers **MUST** build their own security and economic perimeters on top of this standard.

### Definitions

- **Parameter**: An attribute associated with a **non-zero** token balance (account or sub‑account). Parameters are stored as `uint64` values (may represent timestamps, prices, or any numeric value). The token contract defines a fixed number of parameters via `NUMBER_OF_PARAMETERS`.
- **Parameter Mutability**:
  - **Mutable**: The parameter value changes during token transfers according to token‑specific rules (e.g., weighted average, max operation). The token contract MUST implement the mutation logic inside its transfer functions.
  - **Immutable**: The parameter value never changes. Tokens with different immutable parameter values MUST NOT be allowed to coexist in the same account or sub‑account; the token contract SHALL revert any transfer that would cause such a conflict.
- **Account**: An Ethereum address that holds tokens. Accounts can be of two types:
  - **Normal**: Holds a single balance and a single set of parameters.
  - **Super**: Holds multiple sub‑accounts, each with its own balance and parameters.
- **Sub‑account**: A partition within a Super account, identified by a `uint48` index (starting from `0`). Sub‑account `0` is created automatically when an account is converted to Super.
- **Allowance**: Standard allowance is divided into two components:
  - **General**: The part of total allowance that can be spent from any sub‑account except the one identified by `subId` in allowance record. Represented by (`total - sub`) expression. For Normal accounts and Super accounts with a single sub‑account, this is the only usable allowance.
  - **Specific**: The part of total allowance that is restricted to a particular sub‑account identified by `subId` in allowance record. Represented by the `sub` field. Non-zero Specific allowances SHALL only apply to sub-accounts with `subId > 0`.
- **Transfer**: Two types of transfers are considered:
  - **Zero‑Sum**: A default parametric transfer where the amount debited from the sender's balance MUST equal the amount credited to the recipient's balance (`debitAmount == creditAmount`).
  - **Non‑Zero‑Sum (NZS)**: A transfer of a parametric token where the amount debited from the sender's balance MAY not equal the amount credited to the recipient's balance (`debitAmount != creditAmount`) is qualified as non-zero-sum (NZS) transfer. NZS tokens MUST implement the optional `IParametricTokenNzs` interface.

### Interface

#### Main Interface

Every compliant Parametric Token MUST implement the following `IParametricToken` interface, in addition to the standard ERC‑20 interface (`IERC20`).

```solidity
interface IParametricToken is IERC20 {
  // Constants

  enum AccountType {
    Normal,
    Super
  }

  // Events

  /**
   * @notice Emitted when a Normal account is converted to a Super account.
   * @dev This creates the default sub-account `0`, transferring the existing
   *      balance and parameters to it. The account's type is permanently changed.
   *      Can only be triggered by the account owner.
   * @param account The address of the account that was converted to Super
   */
  event AccountConvertedToSuper(address indexed account);

  /**
   * @notice Emitted when a new sub-account is created within a Super account.
   * @dev The new sub-account is initialized with zero balance and default
   *      parameters. Can only be triggered by the Super account owner.
   * @param superAccount The address of the Super account that owns the new sub-account
   * @param subId The index of the newly created sub-account
   */
  event SubAccountCreated(address indexed superAccount, uint48 indexed subId);

  /**
   * @notice Emitted when a zero-sum parametric token transfer occurs.
   * @dev The standard ERC-20 `Transfer` event MUST also be emitted using the `amount`.
   *      This event SHOULD NOT be emitted for NZS token transfers, instead `ParametricTransferNzs`
   *      SHALL be emitted.
   * @param from The sender address
   * @param fromSubId The sender's sub-account
   * @param to The recipient address
   * @param toSubId The recipient's sub-account
   * @param amount The exact amount added to the recipient's balance
   * @param resultingParams The full parameter array of the receiver AFTER parameters update
   */
  event ParametricTransfer(
    address indexed from,
    uint48 indexed fromSubId,
    address indexed to,
    uint48 toSubId,
    uint256 amount,
    uint64[] resultingParams
  );

  /**
   * @notice Emitted when a sub-account specific allowance is set or updated.
   * @dev This allowance applies specifically to `subId`. If `oneOff` is `true`,
   *      the allowance is consumed entirely after the first non-zero spend from
   *      that sub-account. The general allowance (`total - sub`) is adjusted to
   *      ensure `total >= sub`. Standard ERC-20 `Approval` events remain unaffected.
   * @param owner The address of the token owner
   * @param subId The sub-account for which the allowance is granted
   * @param spender The address authorized to spend the tokens
   * @param amount The specific allowance amount for the sub-account
   * @param oneOff `true` if the allowance is one-time use
   */
  event ApprovalForSub(
    address indexed owner,
    uint48 indexed subId,
    address indexed spender,
    uint256 amount,
    bool oneOff
  );

  // Account settings

  /**
   * @notice Returns the total number of parameters defined by this token.
   * @dev MUST be a constant value.
   */
  function NUMBER_OF_PARAMETERS() external view returns (uint8);

  // Account management

  /**
   * @notice Converts the caller's account from Normal to Super
   * @dev This creates sub-account 0 with the current balance and parameters,
   *      and clears the Normal account parameters. Only callable by the account owner
   * @param account The address of the account to convert
   * @return true if the conversion succeeded
   */
  function convertToSuper(address account) external returns (bool);

  /**
   * @notice Creates a new sub-account for a Super account
   * @dev Only callable by the owner of the Super account. The new sub-account
   *      has zero balance and default parameters
   * @param account The Super account to create a sub-account for
   * @return subId The index of the newly created sub-account
   */
  function createSubAccount(address account) external returns (uint48);

  /**
   * @notice Returns the account type (Normal or Super) for a given address
   * @param account The address to query
   * @return AccountType The account type
   */
  function accountType(address account) external view returns (AccountType);

  // Sub-account queries

  /**
   * @notice Returns the balance of a Normal account or specific sub-account
   * @dev For Normal accounts, subId must be 0. For Super accounts,
   *      the subId must correspond to an existing sub-account
   * @param account The address of the account (Normal or Super)
   * @param subId The index of the sub-account (0 for Normal accounts)
   * @return uint256 The balance of the specified sub-account
   */
  function parametricBalanceOf(
    address account,
    uint48 subId
  ) external view returns (uint256);

  /**
   * @notice Returns the number of sub-accounts for an account
   * @dev Returns 0 if the account is not Super
   * @param account The account to query
   * @return uint48 The number of sub-accounts
   */
  function subsCountOf(address account) external view returns (uint48);

  /**
   * @notice Returns the value of a parameter for a given account or sub-account
   * @dev paramIndex must be less than NUMBER_OF_PARAMETERS
   *      For Normal accounts, subId must be 0
   * @param paramIndex The index of the parameter (0 to NUMBER_OF_PARAMETERS-1)
   * @param account The address of the account
   * @param subId The sub-account index (0 for Normal accounts)
   * @return uint64 The parameter value
   */
  function parameterOf(
    uint8 paramIndex,
    address account,
    uint48 subId
  ) external view returns (uint64);

  /**
   * @notice Returns allowance settings for a given subId, owner and spender
   * @dev If the stored subId matches the queried subId, returns the sub-specific
   *      allowance and its oneOff flag. Otherwise, returns the general allowance
   *      (total - sub) and `false` for oneOff
   * @param owner The address of the token owner
   * @param subId The sub-account index
   * @param spender The address of the spender
   * @return (uint256, bool) The allowance amount and whether it is one-off
   */
  function allowanceForSub(
    address owner,
    uint48 subId,
    address spender
  ) external view returns (uint256, bool);

  /**
   * @notice Returns sub-allowance settings for a given owner and spender
   * @dev Returns (0, 0, false) for Normal accounts
   * @param owner The address of the token owner
   * @param spender The address of the spender
   * @return (uint48, uint256, bool) The allowance subId, sub amount and whether it is one-off
   */
  function subAllowance(
    address owner,
    address spender
  ) external view returns (uint48, uint256, bool);

  // Sub-account approval

  /**
   * @notice Sets an allowance for a specific sub-account.
   * @dev Only callable by the owner of a Super account. The allowance applies
   *      specifically to the given subId. If oneOff is true, the allowance is
   *      consumed entirely after the first non-zero spend from that subId
   * @param ownerSubId The sub-account for which the allowance is granted
   * @param spender The address authorized to spend
   * @param amount The allowance amount (sub-account-specific)
   * @param oneOff If true, the allowance is one-time use
   * @return true if the approval succeeded
   */
  function approveForSub(
    uint48 ownerSubId,
    address spender,
    uint256 amount,
    bool oneOff
  ) external returns (bool);

  // Parametric transfers

  /**
   * @notice Transfers tokens from the caller's specified account/sub-account to a recipient's account/sub-account
   * @dev The caller must have sufficient balance in account/fromSubId.
   *      The transfer will apply parameter mutation logic (weighted average, conflict checks)
   *      before updating balances
   * @param fromSubId The sub-account to transfer from (0 for Normal accounts)
   * @param to The recipient address
   * @param toSubId The recipient's sub-account (0 for Normal accounts)
   * @param amount The number of tokens to transfer
   * @return true if the transfer succeeded
   */
  function parametricTransfer(
    uint48 fromSubId,
    address to,
    uint48 toSubId,
    uint256 amount
  ) external returns (bool);

  /**
   * @notice Transfers tokens from a specified sub-account using an allowance
   * @dev This is the parametric equivalent of ERC-20 transferFrom.
   *      The spender must have sufficient allowance for the specified fromSubId.
   *      The transfer will apply parameter mutation logic before updating balances
   * @param from The token owner address
   * @param fromSubId The sub-account to transfer from (0 for Normal accounts)
   * @param to The recipient address
   * @param toSubId The recipient's sub-account (0 for Normal accounts)
   * @param amount The number of tokens to transfer
   * @return true if the transfer succeeded
   */
  function parametricTransferFrom(
    address from,
    uint48 fromSubId,
    address to,
    uint48 toSubId,
    uint256 amount
  ) external returns (bool);
}
```

#### Optional Extension: Non‑Zero‑Sum (NZS) Transfers

Parametric NZS Tokens (where in general case `debitAmount != creditAmount`) MUST implement the following `IParametricTokenNzs` interface:

```solidity
interface IParametricTokenNzs is IParametricToken {
  // Events

  /**
   * @notice Emitted when a non-zero-sum parametric token transfer occurs
   * @dev The standard ERC-20 `Transfer` event MUST also be emitted using the `creditAmount`.
   *      The base `ParametricTransfer` event SHOULD NOT be emitted for NZS token transfers
   * @param from The sender address
   * @param fromSubId The sender's sub-account
   * @param to The recipient address
   * @param toSubId The recipient's sub-account
   * @param debitAmount The exact amount deducted from the sender's balance
   * @param creditAmount The exact amount added to the recipient's balance
   * @param incomingParams The full incoming parameter array
   * @param resultingParams The full resulting parameter array
   */
  event ParametricTransferNzs(
    address indexed from,
    uint48 indexed fromSubId,
    address indexed to,
    uint48 toSubId,
    uint256 debitAmount,
    uint256 creditAmount,
    uint64[] incomingParams,
    uint64[] resultingParams
  );

  // Functions

  /// @notice Returns true if the token implements non‑zero‑sum transfers.
  function isNonZeroSum() external pure returns (bool);
}
```

#### Interface Detection (ERC‑165)

Tokens implementing `IParametricTokenNzs` MUST support ERC‑165 and return `true` for the NZS interface identifier. Off‑chain indexers SHOULD use `supportsInterface(NZS_INTERFACE_ID)` to determine whether to listen to `ParametricTransferNzs` events. If `false`, they MUST rely on the base `ParametricTransfer` event (where `amount` represents both the debit and the credit).

### Parameter Configuration

The token contract MUST define:

- `NUMBER_OF_PARAMETERS` – a **public** constant `uint8` indicating the total number of parameters.
- A parameter configuration struct (see below in Data Model section; RECOMMENDED to be exposed via a public array or getter).

The contract MUST implement `parameterOf(uint8 paramIndex, address account, uint48 subId) external view returns (uint64)` to return the current parameter value for a given account/sub‑account. For Normal accounts, `subId` MUST be `0`; for Super accounts, the caller MUST provide a valid `subId`.

The following getter function is RECOMMENDED (especially for tokens with multiple parameters):

```solidity
/**
 * @notice Returns all parameter values for a given account/sub-account as an array.
 * @dev This is a convenience getter. The array length MUST equal NUMBER_OF_PARAMETERS.
 * @param account The address of the account
 * @param subId The sub-account index (0 for Normal accounts)
 * @return uint64[] The full parameter array
 */
function allParametersOf(
  address account,
  uint48 subId
) external view returns (uint64[] memory);
```

### Data Model

Compliant implementations MUST maintain the following data structures to ensure consistent parameter tracking and sub‑account management.

```solidity
struct ParamConfig {
  bytes32 name; // Human‑readable identifier (e.g., "mintTime", "anchor")
  uint8 decimals; // Number of decimals for display
  bool isMutable; // True if parameter changes during transfers
}

struct Account {
  AccountType accountType; // Normal or Super
  uint256 balance; // Total balance across all sub‑accounts
  uint64[NUMBER_OF_PARAMETERS] parameters; // Parameters for Normal accounts
}

struct SubAccount {
  uint256 balance; // Balance of this sub‑account
  uint64[NUMBER_OF_PARAMETERS] parameters; // Parameters for this sub‑account
}

struct SuperAccount {
  SubAccount[] subs; // Array of sub‑accounts
  uint48 subsCount; // Number of sub‑accounts
}

struct Allowance {
  uint256 total; // Total allowance across all sub‑accounts
  uint256 sub; // Allowance for subId
  uint48 subId; // Sub‑account this allowance applies to
  bool oneOff; // True if this is a one‑time allowance
}
```

#### Storage Mappings

The following mappings are REQUIRED:

```solidity
mapping(address => Account) private _accounts;
mapping(address => SuperAccount) private _supers;
mapping(address => mapping(address => Allowance)) private _allowances;
```

- `_accounts[address]` holds the account data (type, balance, parameters),
- `_supers[address]` holds the sub‑account array if the account is Super,
- `_allowances[owner][spender]` holds the allowance record.

#### Invariants

- If `_accounts[addr].accountType == AccountType.Normal`, then `_supers[addr].subsCount` MUST be 0,
- If `_accounts[addr].accountType == AccountType.Super`, then `_supers[addr].subsCount > 0` and `_supers[addr].subs.length == _supers[addr].subsCount`,
- `_accounts[addr].balance == sum(_supers[addr].subs[i].balance)` for Super accounts,
- `_accounts[addr].balance` MUST equal `balanceOf(addr)`.

### Account Types and Sub‑accounts

- **Normal accounts** hold a single balance and one set of parameters.
- **Super accounts** hold multiple sub‑accounts, each with its own balance and parameters. The aggregate balance of a Super account is the sum of all its sub‑account balances (accessible via `balanceOf`).
- An account is initially Normal. The owner MAY convert it to Super by calling `convertToSuper(address account)`. This creates sub‑account `0` with the current balance and parameters, and clears the Normal parameters.
- Additional sub‑accounts can be created by the owner via `createSubAccount(address account)`, which returns the new sub‑account index.

### Parameter Semantics

#### Immutable Parameters

- Tokens with different immutable parameter values MUST NOT be merged into the same account/sub‑account.
- If the recipient’s balance is zero, the incoming tokens’ immutable parameters are accepted (the account inherits them).
- If the recipient already holds tokens, any transfer that would result in a mix of different immutable parameter values MUST revert.
- This check applies to both standard ERC‑20 transfers and parametric transfers.

#### Mutable Parameters

- When tokens are transferred, the recipient’s mutable parameters MUST be updated according to token‑specific rules.
- The token contract MUST implement the mutation logic inside its internal transfer functions (e.g. `weightedAverage`, `maximum` etc).
- The mutation logic for each mutable parameter MUST be implemented as a **pure** function whose return value is computed deterministically from:
  - parameters of the source account,
  - parameters of the destination account,
  - the transfer value,
  - pre-transfer balance value of the destination account,
  - other state variables or deterministic blockchain parameters (e.g., `block.timestamp`, external price oracles).
- When the balance of an account or sub‑account becomes zero, its parameters MUST be reset to a default initial value (e.g., `0` or `block.timestamp` at creation).

#### Resulting Balance

- The post‑transfer balance of the destination account MAY be calculated using logic other than a simple sum of the pre‑transfer balance and the transfer amount. If such custom logic is used, it MUST be implemented as a **pure** function whose return value is computed deterministically from:
  - parameters of the source account,
  - parameters of the destination account,
  - the transfer value,
  - pre-transfer balance value of the destination account,
  - other state variables or deterministic blockchain parameters (e.g., `block.timestamp`, external price oracles).

  **A. Zero‑Sum Transfers (Default)**

  If token transfers imply that the computed `creditAmount` always equals the `debitAmount` (the amount deducted from the sender), the transfer is a standard zero‑sum transfer. The token MUST emit the base `ParametricTransfer` event.

  **B. Non‑Zero‑Sum Transfers (NZS)**

  If the computed `creditAmount` MAY differ from the `debitAmount` (i.e., `creditAmount != debitAmount`), the token transfer is qualified as a Non‑Zero‑Sum (NZS) transfer. In this case:

  - The token MUST implement the `IParametricTokenNzs` optional extension.
  - The token MUST emit the `ParametricTransferNzs` event with the exact `debitAmount`, `creditAmount`, and the **initial** parameter sender and **final** parameter receiver states.
  - The token SHOULD NOT emit the base `ParametricTransfer` event to avoid ambiguous amount semantics.
  - The token MUST still emit the standard ERC‑20 Transfer event (see ERC‑20 Compatibility below) using the `creditAmount`.

  _Example_: See Bundle Token implementation for a NZS transfer sample.

#### Parameter Initialization

Parameter initialization (setting initial values when tokens are minted) is **outside the scope of this standard**, as minting is typically controlled by an external engine contract rather than the token itself. However, compliant implementations MUST ensure that every mint operation results in all parameters being set to well‑defined initial values.

The initialization mechanism MAY be implemented in one of the following ways (or a combination thereof):

- The minting engine provides the initial parameter values as arguments to the mint function.
- The minting user (the recipient) selects the initial parameter values at the time of minting (e.g., choosing a prediction price for a resolution time they believe will prevail).
- The token contract derives initial values from deterministic blockchain parameters (e.g., `block.timestamp` for a mintTime parameter).

Regardless of the mechanism, the token contract MUST NOT allow a mint operation to complete with uninitialized or default‑zero parameters unless zero is explicitly intended as a valid initial value.

### Allowances and Approvals

The standard extends the ERC‑20 allowance system to support both **General** allowances (usable across sub‑accounts) and **Specific** allowances (restricted to a particular sub‑account).

#### Data Structure

Each allowance record is represented by:

```solidity
struct Allowance {
  uint256 total; // Total allowance for all sub‑accounts (general + specific)
  uint256 sub; // Specific allowance for the sub‑account identified by subId
  uint48 subId; // Sub‑account to which the specific allowance applies
  bool oneOff; // If true, the specific allowance is consumed entirely after one use
}
```

#### Invariants

- `total >= sub` MUST always hold
- `(total - sub)` represents the General allowance available for any sub‑account **except** the one specified by `subId`.
- Sub-account `0` (the default sub-account) MUST always use the General allowance, even if the allowance record has `subId == 0`.
- If `total == 0`, then `sub` MUST be `0`, `subId` MUST be `0`, and `oneOff` MUST be `false`.
- If `subId == 0`, then `sub` MUST be `0`, and `oneOff` MUST be `false`.

#### Normal Accounts and Super Accounts with a Single Sub‑account

- MUST NOT use Specific allowances, only the General allowance (`total`) is available for spending.
- `subId` MUST be `0`, `sub` MUST be `0`, and `oneOff` MUST be `false`.

#### Standard ERC‑20 Approvals

- `approve(address spender, uint256 amount)`:
  - Sets `total` to `amount`.
  - If `sub` exceeds `amount`, it is capped to `amount`.
  - If `amount == 0`, then `subId` MUST be `0` and `oneOff` MUST be `false`.
  - This function does **not** affect `subId` or `oneOff` for non‑zero amounts.

#### Sub‑account‑specific Approvals

- `approveForSub(uint48 ownerSubId, address spender, uint256 amount, bool oneOff)`:
  - **Only callable** by the owner of a Super account with at least **two** sub-accounts (`subsCount > 1`).
  - If `ownerSubId == 0`: `amount` MUST be `0` and `oneOff` MUST be `false`. Resulting state implies the account has no Specific allowance.
  - If `ownerSubId > 0`: if `oneOff == true`, `amount` MUST be `> 0`.
  - MUST implement conservative allowance logic:
    - Sets `subId` to `ownerSubId`, `sub` to `amount`, and `oneOff` to the provided value.
    - **increase** in sub-specific allowance MUST happen at the expense of General allowance (`total - sub`).
    - **reduction** in sub-specific allowance MUST not change General allowance (`total - sub`).
  - If `amount > total`, `total` is raised to `amount` (maintaining `total >= sub`).
  - Emits `ApprovalForSub`.

#### Spending Allowances

#### A. For Normal Accounts (any transfer):

- `transferFrom` and `parametricTransferFrom` MUST spend from General allowance (`total`).

#### B. For Super Accounts:

- `transferFrom` (standard ERC‑20, uses `fromSubId = 0`):

| Condition                                | Allowance Used          | Effect                             |
| ---------------------------------------- | ----------------------- | ---------------------------------- |
| `subId == 0` (no Specific allowance)     | General (`total - sub`) | `total` decreases; `sub` unchanged |
| `subId != 0` (Specific allowance exists) | General (`total - sub`) | `total` decreases; `sub` unchanged |

⚠️ `transferFrom` never spends from the Specific allowance (even if `subId == 0`), because sub‑account `0` cannot have a Specific allowance.

- `parametricTransferFrom` (uses `fromSubId` from caller):

| Condition                                | Allowance Used          | Effect                                                        |
| ---------------------------------------- | ----------------------- | ------------------------------------------------------------- |
| `fromSubId == subId` and `fromSubId > 0` | Specific (`sub`)        | `sub` and `total` decrease; general (`total - sub`) unchanged |
| `fromSubId != subId` or `fromSubId == 0` | General (`total - sub`) | `total` decreases; `sub` unchanged                            |

- In all cases, insufficient allowance MUST trigger a revert.

#### One‑off Allowance Behavior

- If `oneOff` is `true` and the allowance is spent using the exact `subId` stored in the allowance record:
  - `total` MUST be reduced by `sub`, `sub` MUST be set to `0`.
  - The `oneOff` flag MUST be set to `false`.
  - The `subId` MUST be set to `0`.
- If the allowance is spent from a different `subId`, the `oneOff` flag is ignored.
- Standard `approve()` cannot set `oneOff`; calling it with `amount == 0` clears the flag.

### Sub‑account Validation

The standard defines a helper modifier (RECOMMENDED):

```solidity
modifier onlyValidSub(address account, uint48 subId) {
 if (subId > 0) require(_accounts[account].accountType == AccountType.Super, "Not super account");
 if (subId > 0) require(subId < _supers[account].subsCount, "Sub-account doesn't exist");
 _;
}
```

This ensures that `subId` is valid for the given account.

### ERC‑20 Compatibility

All standard ERC‑20 functions (`transfer`, `transferFrom`, `balanceOf`, `allowance`, `approve`, `totalSupply`, `name`, `symbol`, `decimals`) MUST behave as defined in ERC‑20. In particular:

- `transfer(address to, uint256 amount)` MUST be equivalent to `parametricTransfer(0, to, 0, amount)` – i.e., transfer from sub‑account 0 to sub‑account 0\.
- `transferFrom(address from, address to, uint256 amount)` MUST spend allowance from the owner's sub‑account 0 and transfer to sub‑account 0 of the recipient.
- `balanceOf(address account)` MUST return the total balance across all sub‑accounts for Super accounts, or the balance for Normal accounts.
- `allowance(address owner, address spender)` MUST return `total` (the sum of all sub‑allowances).
- For Non‑Zero‑Sum (NZS) tokens, the `amount` parameter of the standard `Transfer` event MUST equal the `creditAmount` (the amount credited to the recipient's balance).

## Rationale

### Why Sub‑accounts?

Sub‑accounts allow a single address to hold tokens with different immutable parameters (or simply different parameter histories) without requiring multiple wallets. This simplifies user experience and reduces the need for key management. Sub‑account `0` serves as the default for ERC‑20 compatibility, ensuring that existing wallets and tools work without modification.

### Why Separate `total` and `sub` Allowance?

The split between `total` and `sub` provides flexibility: an owner can grant a specific allowance for a particular sub‑account (e.g., to a trading bot that should only access that sub‑account) while still allowing a larger general allowance for other sub‑accounts. This is crucial in scenarios where different sub‑accounts represent different strategies or risk profiles.

### Why One‑off Allowance?

One‑off allowances are useful for atomic operations where the spender should only be able to use the allowance once (e.g., for a single redemption or swap). The standard ensures that after any positive spend from the designated sub‑account, the entire sub‑allowance is consumed, preventing accidental or malicious reuse. The invariant is preserved by adjusting `total` to reflect the remaining general allowance.

### Why `uint64` for Parameters?

`uint64` is sufficient for most use cases (timestamps, prices scaled by `10^decimals`, etc.) and is gas‑efficient. The `decimals` field in `ParamConfig` allows for human‑readable formatting.

### Why `uint48` for Sub‑account Index?

`uint48` is enough to support an enormous number of sub‑accounts (over 2.8e14) while being storage‑efficient when packed with other fields.

### Why Parametric Tokens Are Agentic‑Friendly?

Deterministic pure‑function mutations, sub‑account isolation, and composable allowances make parametric tokens a natural fit for autonomous agents. Predictable (reproducible) state transitions, independent strategy management, and secure atomic workflows — the features agents need - are already built in.

### Why Non‑Zero‑Sum Transfers?

Advanced financial instruments, such as tokenized containers (see Bundle Token example), might require that the value of a position is not a linear function of the underlying tokens. When two holdings with different parameter values (e.g., different `anchor` prices) are merged, the resulting position may have a different total balance than the simple arithmetic sum of the inputs due to the convexity of the payoff function.

Providing an optional NZS extension allows the standard to support such sophisticated derivatives without forcing every parametric token to implement complex accounting logic. The extension gives indexers and wallets a clear, standardised way to detect and correctly track non‑linear balance updates, ensuring that off‑chain systems can accurately reflect on‑chain state.

### Relation to Existing Standards

Existing token standards define parameters or state at different levels, but none support **account‑specific**, **updatable parameters** while preserving fungibility and ERC‑20 compatibility.

#### Comparison A: Fungibility and Liquidity

| Standard                        | State / Parameter Location         | Fungibility                | Liquidity         |
| ------------------------------- | ---------------------------------- | -------------------------- | ----------------- |
| **ERC‑20**                      | None (only balance)                | ✅ Fungible                | Consolidated      |
| **ERC‑721**                     | Per `tokenId` (metadata)           | ❌ Non‑fungible            | Highly fragmented |
| **ERC‑1155**                    | Per `id` (token class)             | 🔶 Mixed                   | Fragmented        |
| **ERC‑3525**                    | Per `slot` (token‑level container) | 🔶 Mixed                   | Highly fragmented |
| **ERC‑4626**                    | Global (vault‑level)               | ✅ Fungible                | Consolidated      |
| **ERC‑XXXX (Parametric Token)** | **Per account / sub‑account**      | ✅ Conditional fungibility | Consolidated      |

In ERC‑1155, different parameter values require distinct `id`s, fragmenting liquidity into separate pools. ERC‑3525 introduces slots, but these are token‑level constructs that complicate standard ERC‑20 integration. ERC‑4626 parameters are global to the vault, not individualised per user.

#### Comparison B: Parameters Initialization, Mutability and Partitioning

| Standard                        | Initialization             | Transfer Mutability     | Fungible Partition |
| ------------------------------- | -------------------------- | ----------------------- | ------------------ |
| **ERC‑20**                      | ❌ None                    | ❌ None                 | ❌ None            |
| **ERC‑721**                     | ✅ Minter-Defined          | ❌ None                 | ❌ None            |
| **ERC‑1155**                    | ✅ Minter-Defined          | ❌ None                 | ❌ None            |
| **ERC‑3525**                    | ✅ Minter-Defined          | ❌ None                 | ❌ None            |
| **ERC‑4626**                    | 🔶 Auto (contract defined) | ❌ None                 | ❌ None            |
| **ERC‑XXXX (Parametric Token)** | ✅ Minter-Defined OR Auto  | ✅ Auto (deterministic) | ✅ Yes             |

The Parametric Token standard fills this gap by attaching parameters **directly to the account** (or sub‑account), with deterministic or user-defined parameters initialization at mint and strictly deterministic mutation logic applied on transfers, while remaining **fully compatible with ERC‑20**. This enables novel applications like scalar prediction markets, convex stablecoins, and tokens with velocity‑based economics without the limitations of existing standards.

## Backwards Compatibility

- This standard is fully ERC‑20 compatible; all standard functions behave as expected.
- Optional NZS extension requires usage of both `debitAmount` and `creditAmount` from `ParametricTransferNzs` event for proper balance updates.
- Existing wallets and exchanges that only implement ERC‑20 will work with Parametric Tokens, seeing only the aggregate balance and total allowance.
- Advanced features (sub‑accounts, parameters) are accessed via additional functions; they do not interfere with standard operations, allowances implement conservative logic.
- The standard does not introduce any new security risks beyond those inherent in ERC‑20 (e.g., reentrancy, allowance attacks) and the recommended implementation patterns mitigate them.

## Test Cases

A comprehensive test suite for the reference implementation is available in the `/test` directory of the [Foundry repository](https://github.com/K2eno/parametric-token). The suite includes over 100 unit tests covering all core functions, parameter mutation logic, sub‑account transitions, allowance spending, NZS mints/transfers and revert conditions for Normal and Super accounts.

## Reference Implementation

[Foundry repository](https://github.com/K2eno/parametric-token) includes scripts in `/script` demonstrating three implementations of this ERC: Prediction, Tenure and Bundle tokens with respective engines - in all cases scripts cover deploy and trading scenarios.

## Security Considerations

### Parameter Conflict Checks

Implementations MUST verify immutable parameter compatibility before executing any transfer. Failure to do so could allow tokens with different immutable parameters to mix, breaking the intended semantics.

### Allowance Manipulation

As with standard ERC‑20, users should be cautious when approving large allowances. The `oneOff` feature mitigates some risks by automatically consuming the allowance after a single use, but it only applies to sub‑account allowances. Standard approvals (`approve`) remain subject to the same risks as in ERC‑20.

### Reentrancy

All external functions that modify state (transfers, approvals, sub‑account creation) SHOULD be protected with reentrancy guards, especially when they call external contracts (e.g., during transfers that may trigger hooks).

### Sub‑account Ownership

Only the account owner can convert to Super or create sub‑accounts. However, once an account is Super, the owner must manage sub‑account indices carefully; there is no mechanism to delete sub‑accounts, so the number of sub‑accounts should be bounded.

### Parameter Mutation

The mutation logic for mutable parameters must be carefully designed to avoid overflow or underflow. Since parameters are `uint64`, all arithmetic should be checked (or use Solidity’s built‑in overflow checks). The weighted average calculation, for example, should use `uint256` intermediate values to prevent overflow.

### Parameters Poisoning & Manipulation

In parametric tokens, an attacker may transfer tokens with unfavourable parameter values to degrade a victim's aggregate state (e.g., lowering a weighted-average prediction). Protection can be implemented via account-specific **inbound allowances** (pre-authorised parameter ranges) or **post-transfer validation** (reverting if resulting parameters fall outside bounds). These mechanisms preserve economic interest, as a parametric token's value is intrinsically bound to its parameter state.

Flash-loan-based parameter manipulation is theoretically possible but economically deterred by the fundamental utility‑bearing nature of parametric tokens and the associated **utility vs reasonable cost** trade-off. Consequently, the cost of manipulation will generally exceed the extractable value.

### Protection Against Unauthorised Engine Access

In encapsulated token systems (like the Inverse Token example), the engine contract may have special privileges. The standard does not mandate such a mechanism, but if implemented (e.g., via `onlyEngine` modifiers), the contract must ensure that the engine cannot bypass user approvals without explicit consent.

### One‑off Allowance Reset

The reset logic (zeroing remaining sub and adjusting total) must be performed atomically within the same transaction to avoid race conditions. The implementation must not allow the allowance to be spent in two separate transactions after the first use.

### Non‑Zero‑Sum Transfer Accounting

Implementers of NZS transfers must be acutely aware that the `Transfer` event carries the `creditAmount`, not the `debitAmount`. Off‑chain systems that rely on deriving sender balances from `Transfer` events will compute an incorrect `balanceOf(from)` if they attempt to subtract the `creditAmount` from the sender. Implementers MUST document this behaviour prominently and off‑chain indexers MUST detect NZS tokens via ERC‑165 and subtract the `debitAmount` from `ParametricTransferNzs` event when updating the sender's balance. Failure to do so will result in persistent accounting mismatches.

## Copyright

Copyright and related rights waived via [CC0](https://eips.ethereum.org/LICENSE).

## Citation

Please cite this document as:

```bibtex
@article{ERC-Parametric-Token,
  title = {ERC-XXXX: Parametric Token},
  author = {Alexander Zvezdin},
  url = {https://github.com/k2eno/parametric-token/blob/main/ERCS/erc-xxxx.md},
  year = {2026}
}
```
