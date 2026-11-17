# Financial Lease — Reference Implementation

Reference implementation of ERC-8348. Core contract, conversion oracle
interface and adapters, and a Foundry test suite (94 tests, including fuzz
coverage of the rounding and frequency-invariance properties).

Payment-path liveness: `declareDefault` and `terminateForDefault` revert while
the index is stale (`PaymentPathUnavailable`) and until it has been
continuously fresh for `G = maxOracleStaleness / 2` (`RecoveryGraceActive`).
Freshness over that window is read from the oracle's own history
(`IConversionOracleHistory`), so indexed leases with a tolerance require an
oracle that implements it. `test/OracleHistory.t.sol` covers both.

## Setup

    forge install foundry-rs/forge-std
    forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
    forge test

`foundry.toml` and `remappings.txt` are included. The suite requires
`via_ir` and is verified with the optimizer enabled — running without it
may mask timestamp-related test failures.

Built against OpenZeppelin Contracts v5.x and solc 0.8.33.
