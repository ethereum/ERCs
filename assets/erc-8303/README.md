# ERC-8303 Contract Version Reference Implementation

> [!WARNING]
> **This project has not been audited.** It is provided solely to illustrate a reference implementation of [ERC-8303](./erc-8303.md). Do not use in production without an independent security review.

A minimal reference implementation of [ERC-8303](./erc-8303.md), built with Foundry, Solidity `^0.8.20` (compiled at `0.8.34`), EVM `prague`, optimizer enabled, and OpenZeppelin Contracts.

## Overview

ERC-8303 defines a token-agnostic interface for exposing a contract implementation version string on-chain:

```solidity
interface IERC8303 {
    /// @notice Returns the implementation version string.
    /// @return The version value, for example "1.0.0".
    function version() external view returns (string memory);
}
```

The standard is intended to help integrators, operators, governance systems, and auditors identify which implementation version a deployed contract exposes.

Implementations SHOULD return stable, machine-comparable version values. The recommended format is SemVer-like:

```text
MAJOR.MINOR.PATCH
```

For example:

```text
1.0.0
```

## Contracts

| File | Description |
|------|-------------|
| `src/IERC8303.sol` | Minimal `version()` interface from ERC-8303 |
| `src/ERC8303.sol` | Reusable OpenZeppelin ERC-165 compatible base implementation with a constant version |
| `src/examples/ERC20VersionedExample.sol` | OpenZeppelin ERC-20 example with `version()` support |
| `src/examples/ERC721VersionedExample.sol` | OpenZeppelin ERC-721 example with `version()` support |

## Interface Discovery

ERC-8303 recommends ERC-165 support. This implementation advertises:

```solidity
type(IERC8303).interfaceId == 0x54fd4d50
```

`ERC8303.supportsInterface(0x54fd4d50)` returns `true`, and `supportsInterface(0xffffffff)` returns `false`.

## Examples

### ERC-20

`ERC20VersionedExample` combines OpenZeppelin `ERC20` with `ERC8303`:

```solidity
contract ERC20VersionedExample is ERC20, ERC8303 {
    constructor(uint256 initialSupply) ERC20("Versioned ERC20", "VER20") {
        _mint(msg.sender, initialSupply);
    }
}
```

### ERC-721

`ERC721VersionedExample` combines OpenZeppelin `ERC721URIStorage` with `ERC8303`:

```solidity
contract ERC721VersionedExample is ERC721URIStorage, ERC8303 {
    uint256 private _nextTokenId;

    constructor() ERC721("Versioned ERC721", "VER721") {}

    function mint(address to, string memory tokenURI) external returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721URIStorage, ERC8303)
        returns (bool)
    {
        return ERC8303.supportsInterface(interfaceId) || ERC721URIStorage.supportsInterface(interfaceId);
    }
}
```

The test suite mints an example NFT with:

```text
https://eips.ethereum.org/erc
```

## Design Decisions

- **Single-purpose interface** - `IERC8303` only exposes `version()`, keeping adoption simple for token and non-token contracts.
- **Constant version value** - `ERC8303` exposes a non-empty `VERSION = "1.0.0"` constant and `version()` returns that constant.
- **ERC-165 support** - `ERC8303` inherits OpenZeppelin `ERC165` and advertises the ERC-8303 interface ID.
- **No storage mutation** - the version string is compiled into the implementation and has no setter in this reference implementation.
- **Token examples use OpenZeppelin** - ERC-20 and ERC-721 examples compose the version interface with standard OpenZeppelin token contracts.

## Build Configuration

The Foundry profile is configured with:

```toml
solc = "0.8.34"
optimizer = true
optimizer_runs = 200
evm_version = "prague"
```

## Install Dependencies

Dependencies are vendored under `lib/`. To reinstall them in a fresh checkout:

```bash
forge install OpenZeppelin/openzeppelin-contracts
forge install foundry-rs/forge-std
```

## Build

```bash
forge build
```

## Test

```bash
forge test
```

The tests cover:

- `ERC8303` base contract directly, via a minimal concrete wrapper.
- `version()` returns the declared constant version string.
- `version()` returns a non-empty string.
- `type(IERC8303).interfaceId` matches `0x54fd4d50`.
- ERC-165 discovery returns `true` for `IERC8303`.
- ERC-165 discovery returns `false` for `0xffffffff`.
- ERC-20 behavior remains intact.
- ERC-721 behavior remains intact.

## Gas Report

```bash
forge test --gas-report
```

## Coverage

```bash
forge coverage
```

## Static Analysis

This repository includes an [Aderyn](https://github.com/Cyfrin/aderyn) static analysis report generated against the current source:

| Report | Feedback |
|--------|----------|
| [`doc/aderyn-report.md`](doc/aderyn-report.md) | [`doc/aderyn-feedback.md`](doc/aderyn-feedback.md) |

Summary of findings: 0 high, 2 low. The low findings are acknowledged configuration and deployment-target considerations. See the feedback document for details.

## Limitations

This is a minimal reference implementation. The following constraints are intentional:

- **No version mutation.** The version is fixed in the implementation bytecode. Upgradeable systems should expose the active implementation version through their proxy-facing implementation.
- **No SemVer parser.** This implementation uses the recommended `1.0.0` format, but does not parse or validate version strings on-chain. Off-chain tooling should validate the recommended `MAJOR.MINOR.PATCH` pattern when needed.
- **Metadata only.** `version()` is not an authorization primitive and must not be used as the sole trust signal for integrations.
- **Example tokens are simple.** The ERC-20 and ERC-721 contracts are examples of composition with OpenZeppelin, not production token templates.

## License

CC0-1.0
