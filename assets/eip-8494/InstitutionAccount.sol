// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IInstitutionAccount, AccountState} from "./IInstitutionAccount.sol";

/// @notice Reference user payment ledger; institutions manage task status and business authorization.
contract InstitutionAccount is IInstitutionAccount {
    error Unauthorized();
    error InvalidAddress();
    error InvalidCurrency();
    error InvalidAmount();
    error InvalidOperationId();
    error ReusedOperation();
    error AmountRange();
    error EmptyPeriod();
    error StaleStatement();

    string private _currency;
    uint8 private immutable _decimals;
    mapping(address => mapping(address => AccountState)) private _states;
    mapping(bytes32 => bool) private _used;
    mapping(address => mapping(address => bool)) private _writers;

    /// @notice Example governance event, outside the standard interface; does not change account periods.
    event WriterAuthorizationChanged(address indexed institution, address indexed writer, bool allowed);

    /// @notice Fixes the monetary unit; the deployer chooses a valid ISO currency and this checks the code format.
    constructor(string memory currency_, uint8 decimals_) {
        bytes memory code = bytes(currency_);
        if (code.length != 3) revert InvalidCurrency();
        for (uint256 i; i < 3; ++i) {
            if (code[i] < 0x41 || code[i] > 0x5a) revert InvalidCurrency();
        }
        _currency = currency_;
        _decimals = decimals_;
    }

    /// @notice Public and virtual for explicit overrides in composed contracts, satisfying both external ABIs.
    function currency() public view virtual returns (string memory) {
        return _currency;
    }

    /// @notice Ledgers in one deployment share this fixed decimal precision.
    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    /// @notice An institution manages only its own authorized callers.
    function setWriter(address writer, bool allowed) external {
        if (writer == address(0)) revert InvalidAddress();
        _writers[msg.sender][writer] = allowed;
        emit WriterAuthorizationChanged(msg.sender, writer, allowed);
    }

    /// @notice All-zero amounts are valid; no separate registration or closure flag is stored.
    function accountState(address account, address institution) external view returns (AccountState memory state) {
        _addresses(account, institution);
        state = _states[institution][account];
    }

    /// @notice Raises the baseline, with duplicate prevention and amount checks before committing.
    function addLimit(address account, address institution, bytes32 operationId, uint96 amount) external {
        _institution(institution);
        _addresses(account, institution);
        _amount(amount);
        AccountState memory state = _states[institution][account];
        state.limit = _sum(state.limit, amount);
        _managementOperation(institution, operationId);
        _commit(account, institution, state);
        emit LimitAdded(account, institution, operationId, amount, state.limit);
    }

    /// @notice Floors the baseline at zero; rejects negative resulting capacity and preserves entries.
    function subLimit(address account, address institution, bytes32 operationId, uint96 amount) external {
        _institution(institution);
        _addresses(account, institution);
        _amount(amount);
        AccountState memory state = _states[institution][account];
        uint96 actualAmount = amount < state.limit ? amount : state.limit;
        state.limit -= actualAmount;
        _managementOperation(institution, operationId);
        _commit(account, institution, state);
        emit LimitSubtracted(account, institution, operationId, actualAmount, state.limit);
    }

    /// @notice External recording requires the institution or its authorized writer.
    function debit(address account, address institution, bytes32 operationId, uint96 amount) external virtual {
        _writer(institution);
        _recordDebit(account, institution, operationId, amount);
    }

    /// @notice Records a validated inflow to its account, including an account with zero capacity.
    function credit(address account, address institution, bytes32 operationId, uint96 amount) external virtual {
        _writer(institution);
        _recordCredit(account, institution, operationId, amount);
    }

    /// @notice Validated composed entry points can call internally without an external self-call changing msg.sender.
    /// @dev Derived implementations must validate upstream authorization first; this internal path is not a public bypass.
    function _recordDebit(address account, address institution, bytes32 operationId, uint96 amount) internal {
        _addresses(account, institution);
        _amount(amount);
        AccountState memory state = _states[institution][account];
        if (amount > _available(state)) revert AmountRange();
        state.debit = _sum(state.debit, amount);
        _receiptOperation(institution, operationId);
        _commit(account, institution, state);
        emit Debited(account, institution, operationId, amount, state.statementId, msg.sender);
    }

    /// @notice Upstream-validated inflows use the corresponding account and institution; refunds use the original account.
    function _recordCredit(address account, address institution, bytes32 operationId, uint96 amount) internal {
        _addresses(account, institution);
        _amount(amount);
        AccountState memory state = _states[institution][account];
        state.credit = _sum(state.credit, amount);
        _receiptOperation(institution, operationId);
        _commit(account, institution, state);
        emit Credited(account, institution, operationId, amount, state.statementId, msg.sender);
    }

    /// @notice The period check prevents a stale rollup from sealing the next period; it does not lock a state snapshot.
    function rollup(address account, address institution, uint32 expectedStatementId) external {
        _institution(institution);
        _addresses(account, institution);
        AccountState memory state = _states[institution][account];
        if (state.statementId != expectedStatementId) revert StaleStatement();
        if (state.debit == 0 && state.credit == 0) revert EmptyPeriod();
        uint32 statementId = state.statementId;
        uint96 previousLimit = state.limit;
        uint96 previousDebit = state.debit;
        uint96 previousCredit = state.credit;
        state.limit = _available(state);
        state.debit = 0;
        state.credit = 0;
        state.statementId += 1;
        _commit(account, institution, state);
        emit RolledUp(account, institution, statementId, previousLimit, previousDebit, previousCredit, state.limit);
    }

    /// @notice Management operations use local duplicate prevention; derived compositions may restrict their namespace.
    function _managementOperation(address institution, bytes32 operationId) internal virtual {
        _consumeOperation(institution, operationId);
    }

    /// @notice Direct recording checks locally; controlled compositions may reuse upstream uniqueness on validated paths.
    function _receiptOperation(address institution, bytes32 operationId) internal virtual {
        _consumeOperation(institution, operationId);
    }

    /// @notice Successful identifiers are unique per institution across functions, accounts, callers, and periods.
    function _consumeOperation(address institution, bytes32 operationId) private {
        if (operationId == 0) revert InvalidOperationId();
        bytes32 key = keccak256(abi.encode(institution, operationId));
        if (_used[key]) revert ReusedOperation();
        _used[key] = true;
    }

    /// @notice Checks bounds and commits state; subsequent failure also rolls back identifier consumption.
    function _commit(address account, address institution, AccountState memory state) private {
        _available(state);
        _states[institution][account] = state;
    }

    /// @notice Adds using wide intermediates, checks the uint96 bound, then converts; failure reverts state and identifiers.
    function _sum(uint96 left, uint96 right) private pure returns (uint96) {
        uint256 total = uint256(left) + uint256(right);
        if (total > type(uint96).max) revert AmountRange();
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint96(total);
    }

    /// @notice Adds widely, checks debit coverage, subtracts, and checks uint96 bounds; negative capacity is not clamped.
    function _available(AccountState memory state) private pure returns (uint96) {
        uint256 total = uint256(state.limit) + state.credit;
        if (total < state.debit) revert AmountRange();
        uint256 available = total - state.debit;
        if (available > type(uint96).max) revert AmountRange();
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint96(available);
    }

    /// @notice Account and institution addresses must be nonzero.
    function _addresses(address account, address institution) private pure {
        if (account == address(0) || institution == address(0)) revert InvalidAddress();
    }

    /// @notice Requested amounts must be positive; the actual baseline reduction may be zero.
    function _amount(uint96 amount) private pure {
        if (amount == 0) revert InvalidAmount();
    }

    /// @notice Management permission comes from the institution caller, which may be a contract wallet.
    function _institution(address institution) private view {
        if (msg.sender != institution) revert Unauthorized();
    }

    /// @notice Writer authorization is institution-scoped and is not inferred from an account private key.
    function _writer(address institution) private view {
        if (msg.sender != institution && !_writers[institution][msg.sender]) revert Unauthorized();
    }
}
