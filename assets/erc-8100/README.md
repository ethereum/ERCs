# Representable Contract State - XML/JSON Rendering of Smart Contract State

Standard interfaces that allow an EVM  smart contract to define a static XML/JSON template
with machine-readable bindings to its state and view functions.

## Interfaces

- `contracts/IRepresentableState.sol` - Marker interface and optional state version/hash.
  - `IXMLRepresentableState`  - Contract is XML-complete providing XML template. 
  - `IJSONRepresentableState` - Contract is JSON-complete providing JSON template.
  - `IRepresentableStateVersioned` - Contract provides indication on state-change via a version. 
  - `IRepresentableStateHashed` - Contract provides indication on state-change via a hash.
- `contracts/ITextResource.sol` - Interface for immutable, integrity-verifiable on-chain text resources.

## Supporting Reference Implementation

- `contracts/TextResource.sol` - Informative, SSTORE2-backed implementation of `ITextResource` supporting one-shot and staged publishing for the optional external-template profile.

`ChunkAppended` indexes the sender, storage pointer and chunk index for log filtering;
the chunk length remains in the event data. Event decoders must use the ABI of the deployed resource.

The implementation-specific limits are 200,000 total bytes, 20,000 bytes per chunk, and 32 chunks. They are not ERC-8100 conformance requirements. Compile the reference implementation and examples with Solidity 0.8.30, the
optimizer and via-IR enabled, and the Paris EVM target. Direct `solc` compilation
requires the remapping `solady/=node_modules/solady/src/`.

## Examples

- `contracts/examples/TestContract.sol` - Illustrating different bindings.
- `contracts/examples/MinimalInstrument.sol` - Minimal contract example.
- `contracts/examples/InterestRateSwapSettleToMarket.sol` - FpML like XML from settle to market contract state.
- `contracts/examples/BondDataTaxonomyDemo.sol` - ICMA BDT like XML from contract state.

## Documentation

- `doc/event-life-cycle.svg` - Sequence diagram sketching the interaction of a contract and a renderer.

## Metadata

- `package.json` - Metadata for publishing the interface as NPM package.

## Packaging

The npm package is built from `assets/erc-8100` in the ERCs repository.
Run `npm pack --dry-run` from this directory to inspect its contents. Source,
documentation and configuration are included; generated build and coverage files
are excluded. File-specific CC0-1.0 and MIT terms are included in [LICENSE.md](LICENSE.md).
