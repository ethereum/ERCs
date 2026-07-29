# ERC-7303 Conformance Fixture

A redeployable fixture and test suite answering one question: **does a contract actually implement ERC-7303?**

The durable part of this fixture is the sources in `contracts/` and the expected values asserted in [`test/conformance.js`](./test/conformance.js) — everything is recomputable and redeployable on any chain. Concrete testnet addresses are listed at the end for convenience only; they are not the fixture.

## Layout

| File | Purpose |
|------|---------|
| [`contracts/IERC7303.sol`](./contracts/IERC7303.sol) | The introspection interface from the ERC text |
| [`contracts/ERC7303.sol`](./contracts/ERC7303.sol) | The reference implementation from the ERC text |
| [`contracts/FixtureTarget.sol`](./contracts/FixtureTarget.sol) | Compliant fixture with a fixed, canonical role structure |
| [`contracts/LegacyTarget.sol`](./contracts/LegacyTarget.sol) | Negative fixture: identical balance gating, no `IERC7303` |
| [`contracts/ERC721ControlToken.sol`](./contracts/ERC721ControlToken.sol) | Minimal issuer-burnable ERC-721 control token |
| [`contracts/ERC1155ControlToken.sol`](./contracts/ERC1155ControlToken.sol) | Minimal issuer-burnable ERC-1155 control token |
| [`test/conformance.js`](./test/conformance.js) | Assertions of all expected values below |

## Running

```sh
npm install
npx hardhat test
```

## Expected values

### Interface identifier

The `IERC7303` identifier is the XOR of its three function selectors (events do not contribute):

| Function | Selector |
|----------|----------|
| `hasRole(bytes32,address)` | `0x91d14854` |
| `getERC721ControlTokens(bytes32)` | `0xa2911fab` |
| `getERC1155ControlTokens(bytes32)` | `0x7da6c4c8` |
| **XOR** | **`0x4ee69337`** |

A compliant contract answers `supportsInterface(0x01ffc9a7)` = `true`, `supportsInterface(0x4ee69337)` = `true`, and `supportsInterface(0xffffffff)` = `false`.

### Canonical role structure of `FixtureTarget`

Deployed as `FixtureTarget(ct721, ct1155)`:

| Role | `getERC721ControlTokens` | `getERC1155ControlTokens` |
|------|--------------------------|---------------------------|
| `keccak256("MINTER_ROLE")` | `[ct721]` | `([ct1155], [1])` |
| `keccak256("BURNER_ROLE")` | `[]` | `([ct1155], [2])` |
| any other role | `[]` | `([], [])` |

Deployment emits exactly one `ERC721ControlTokenAdded` and two `ERC1155ControlTokenAdded` events matching the table.

Roles compose in two directions:

* **OR within a role** — holding **either** entry of `MINTER_ROLE` grants the role.
* **AND across roles** — `reissue(tokenId, to)` stacks the modifiers of `MINTER_ROLE` and `BURNER_ROLE` and succeeds only for a caller holding **both**, whether the two roles are satisfied through the same standard (ERC-1155 + ERC-1155) or across standards (ERC-721 + ERC-1155).

### Role lifecycle

For each control-token path: `hasRole` is `false` before minting, `true` after the issuer mints, and `false` again after the issuer burns — with no cooperation from the holder (the kill switch). The gated functions (`safeMint`, `burn`) succeed exactly when the caller holds the role and otherwise revert with `"ERC7303: not has a required token"`.

### Negative case

`LegacyTarget` gates identically to `FixtureTarget` (same control tokens, same revert string) but pre-dates `IERC7303`: it exposes no `hasRole`/getter functions and `supportsInterface(0x4ee69337)` answers `false`. Discovery tooling encountering such a contract must classify it as **not** implementing this ERC, behavioral equivalence notwithstanding. This is the boundary the fixture pins down: conformance is the declared, machine-readable interface — not the gating behavior.

## Convenience deployments (informational, not normative)

An instance of each case is deployed on Sepolia. Testnets are ephemeral; if these disappear, redeploy the sources above — the expected values are unchanged on any chain.

| Case | Address |
|------|---------|
| Compliant (`IERC7303`, interfaceId `0x4ee69337`) | `0x4C0a78803D47154B9C6F42EC4AEbab2D1C94c97D` |
| Legacy negative (pre-`IERC7303`) | `0xa52fe39D0de852e88488faa34e723E861D0b09BD` |
