# Reference implementation

This example implements `IInstitutionAccount` for independent, institution-authorized recording. It uses local duplicate prevention across all four incremental operations. It is not an implementation of ERC-8439 or of the controlled-composition alternative.

## Files and compilation

- [IInstitutionAccount.sol](IInstitutionAccount.sol): the complete interface and account state, matching the specification.
- [InstitutionAccount.sol](InstitutionAccount.sol): the implementation; it imports only the adjacent interface file and has no third-party source dependencies.
- [InstitutionAccount.t.sol](test/InstitutionAccount.t.sol): the 39 independent-account tests.
- [AccountRead.sol](test/AccountRead.sol): the test helper for deriving available capacity from account state.

The files use the CC0-1.0 license. Compile with Solidity 0.8.30, EVM target Prague, optimizer enabled with 200 runs. Their source pragma is `^0.8.20`; the stated toolchain is the one used for validation. For example, from this directory with the Solidity compiler installed:

```sh
solc --base-path . --optimize --optimize-runs 200 --evm-version prague --abi --bin InstitutionAccount.sol
```

Compilation establishes syntactic and type correctness, not business correctness or production readiness.

## Implementation choices

Each institution can authorize writers through `setWriter`. This example governance function and its event are outside the standard interface. The implementation does not maintain a separate institution-admission registry; a production deployment defines its admission and authorization policy.

The constructor fixes currency and decimal precision. It checks the currency code's three-uppercase-ASCII format; the deployer remains responsible for choosing an actual ISO 4217 code.

The institution can adjust limits and roll up its account periods. The institution or one of its authorized writers can record debits and credits. Internal recording hooks are provided for derived contracts, which must validate business authorization before invoking them. Using those hooks does not by itself implement the standard's composition guarantees.

Events reconstruct historical entries and sealed periods. Account addresses are accounting identifiers; their private keys do not grant write permission. Task authorization, identity mapping, original-payment and refund validation, event indexing, and actual funds processing remain integration responsibilities.

## Reproducing the tests

With Foundry installed, run the following command from the published `assets/eip-8494/` directory. It needs only the four Solidity files listed above; no `forge-std` dependency or project configuration file is required. Validation used Forge 1.7.1 and Solidity 0.8.30.

```sh
forge test --root . --contracts . --match-path 'test/InstitutionAccount.t.sol' \
  --use 0.8.30 --evm-version prague --optimize true --optimizer-runs 200 \
  --fuzz-runs 512 --out .build/out --cache-path .build/cache
```

The expected result is 39 passing tests, including `testFuzzRollup` and `testFuzzMixedOperations` with 512 runs each. The latter compares state and available capacity with a separate arithmetic model after each of 48 operations per run.

The suite covers account and institution isolation, writer permissions, identifier reuse across functions and periods, retry after reversion, amount and period-counter bounds, event amounts, rollup preservation of capacity, zero actual reductions, and late inflows before and after rollup.

## Validation boundary

The interface declaration matches the specification. These are tests of the attached independent-recording implementation: its example `setWriter` policy, custom errors, and storage layout are not additional standard requirements. In particular, `testStatementCounterCannotWrap` sets the reference implementation's period counter through a Foundry storage cheatcode; that test must be adapted for a different layout.

The tests do not cover the controlled-composition alternative, ERC-8439 signature validation, or off-chain funds execution. They do not constitute an independent security audit or certify production readiness. Gas values printed by Forge describe test execution, not the cost of a production payment or fiat settlement.
