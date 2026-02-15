# Representable Contract State - XML/JSON Rendering of Smart Contract State

## Description

This ERC (ERC-8100) introduces `IXMLRepresentableState` and `IJSONRepresentableState`, a standard interface that allows an EVM
smart contract to define a static XML/JSON template with machine-readable bindings to its state and view functions.
An XML binding schema is provided.
Off-chain renderers use this template to build a canonical XML document representing the contract's state at
a specific block, without incurring any on-chain gas cost.

### Interfaces

- `contracts/IRepresentableState.sol` - Marker interface and optional state version/hash.
  - `IXMLRepresentableState`  - Contract is XML-complete providing XML template. 
  - `IJSONRepresentableState` - Contract is JSON-complete providing JSON template.
  - `IRepresentableStateVersioned` - Contract provides indication on state-change via a version. 
  - `IRepresentableStateHashed` - Contract provides indication on state-change via a hash.

### Implementations (Examples)

- `contracts/examples/TestContract.sol` - Illustrating different bindings.
- `contracts/examples/MinimalInstrument.sol` - Minimal contract example.
- `contracts/examples/InterestRateSwapSettleToMarket.sol` - FpML like XML from settle to market contract state.
- `contracts/examples/BondDataTaxonomyDemo.sol` - ICMA BDT like XML from contract state.

### Documentation

- `doc/event-life-cycle.svg` - Sequence diagram sketching the interaction of a contract and a renderer.