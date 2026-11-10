# Reference implementation

This example implements `IInstitutionAccount` for independent, institution-authorized recording. It uses local duplicate prevention across all four incremental operations. It is not an implementation of ERC-8439 or of the controlled-composition alternative.

## Files and compilation

- [IInstitutionAccount.sol](IInstitutionAccount.sol): the complete interface and account state, matching the specification.
- [InstitutionAccount.sol](InstitutionAccount.sol): the implementation; it imports only the adjacent interface file and has no third-party source dependencies.

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

## Validation boundary

The executable tokens of this implementation match the project's v5 independent implementation; only documentation comments are translated into English. The interface declaration matches the English specification. Packaging validation compiles these exact files and runs the existing 39 independent-account tests against them, including two fuzz tests with 512 runs each.

Those checks cover amount bounds, caller isolation, institution-wide duplicate prevention, rollup, and limit-reduction behavior. They do not constitute an independent security audit, certify deployment policy, or demonstrate fiat settlement. The broader composition example and its tests are separate from this minimal attachment.
