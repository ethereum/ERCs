// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @notice Current user period, entry totals, and baseline for one (account, institution); events reconstruct history.
struct AccountState {
    /// @notice Unsigned baseline; the baseline floors at zero on reduction, and increases above the uint96 bound revert.
    uint96 limit;
    /// @notice Current user-period outflow total; uint96 matches the ERC-8439 amount range.
    uint96 debit;
    /// @notice Current user-period inflow total; uint96 matches the ERC-8439 amount range.
    uint96 credit;
    /// @notice Current user period, incremented on rollup and independent of the institution period.
    uint32 statementId;
}

/// @notice Institution-managed user payment ledger; institution scopes customer records, not institution-level totals.
/// @dev Writes require nonzero account/institution. Incremental operations require a nonzero stable operationId,
/// @dev unique per institution; the ledger or a controlled entry point covering all paths enforces this uniqueness.
/// @dev amount is a positive uint96 in the deployment's currency/decimals unit; entries use the account's perspective.
/// @dev Recording entries does not transfer assets.
interface IInstitutionAccount {
    /// @notice Amount added and resulting baseline; does not prove that funds were frozen.
    event LimitAdded(
        address indexed account, address indexed institution, bytes32 indexed operationId, uint96 amount, uint96 limit
    );
    /// @notice amount is the actual baseline reduction, possibly below the request or zero; limit is the new baseline.
    event LimitSubtracted(
        address indexed account, address indexed institution, bytes32 indexed operationId, uint96 amount, uint96 limit
    );
    /// @notice One account outflow in the current period; writer is the submitter of the call or composed execution.
    event Debited(
        address indexed account,
        address indexed institution,
        bytes32 indexed operationId,
        uint96 amount,
        uint32 statementId,
        address writer
    );
    /// @notice One account inflow in the current period, also increasing available capacity.
    event Credited(
        address indexed account,
        address indexed institution,
        bytes32 indexed operationId,
        uint96 amount,
        uint32 statementId,
        address writer
    );
    /// @notice Seals both totals of the old period; newLimit equals the unchanged available capacity.
    /// @dev statementId identifies the old period; the event does not prove successful customer funds processing.
    event RolledUp(
        address indexed account,
        address indexed institution,
        uint32 indexed statementId,
        uint96 previousLimit,
        uint96 debit,
        uint96 credit,
        uint96 newLimit
    );

    /// @notice Immutable three-character uppercase ASCII ISO 4217 code.
    function currency() external view returns (string memory);
    /// @notice Immutable decimal precision; all amounts are in units of 10^-decimals.
    function decimals() external view returns (uint8);
    /// @notice Returns current amounts and period, not identity, task status, or historical funds-processing results.
    /// @dev account and institution must be nonzero; queries with zero addresses revert.
    /// @return state Current accounting state, all zero before any successful write; no separate initialization flag.
    /// @dev Derive available as limit+credit-debit using wide unsigned arithmetic after checking coverage of debit.
    /// @dev No redundant available-capacity field is returned.
    function accountState(address account, address institution) external view returns (AccountState memory state);
    /// @notice The account's institution provides spending capacity without registration or initialization.
    /// @param amount Increment to limit and available only; does not change the period or entry totals.
    function addLimit(address account, address institution, bytes32 operationId, uint96 amount) external;
    /// @notice The account's institution withdraws unused capacity without erasing recorded entries.
    /// @param amount Requested baseline reduction; floor the baseline at zero, and revert if new limit+credit<debit.
    /// @dev A zero baseline yields zero actual reduction; success still emits an event and consumes operationId.
    /// @dev Success does not guarantee zero available capacity.
    function subLimit(address account, address institution, bytes32 operationId, uint96 amount) external;
    /// @notice Records outflow through deployment-authorized entry points, checked against execution-time available.
    /// @param amount Outflow amount; must not exceed available capacity, and the cumulative total must remain in range.
    function debit(address account, address institution, bytes32 operationId, uint96 amount) external;
    /// @notice Records inflow through deployment-authorized entry points, including accounts with zero capacity.
    /// @param amount Inflow amount, increasing credit and available without changing limit.
    function credit(address account, address institution, bytes32 operationId, uint96 amount) external;
    /// @notice The institution seals a nonempty user period, resets limit, and clears debit/credit without changing available.
    /// @param expectedStatementId Current user period to process; reject a mismatch at execution.
    function rollup(address account, address institution, uint32 expectedStatementId) external;
}
