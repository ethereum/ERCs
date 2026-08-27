# Financial Lease — Reference Implementation

Reference implementation of ERC-8348. Core contract, conversion oracle
interface and adapters, and a Foundry test suite (76 tests, including fuzz
coverage of the rounding and frequency-invariance properties).

## Setup

    forge install foundry-rs/forge-std
    forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
    forge test

`foundry.toml` and `remappings.txt` are included. The suite requires
`via_ir` and is verified with the optimizer enabled — running without it
may mask timestamp-related test failures.

Built against OpenZeppelin Contracts v5.x and solc 0.8.33.
