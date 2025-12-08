# Representable Contact State - XML Rendering of Smart Contract State

## Abstract

This ERC introduces `IXMLRepresentableState`, a standard interface and XML binding schema that allows an EVM
smart contract to define a static XML template with machine-readable bindings to its state and view functions.
Off-chain renderers use this template to build a canonical XML document representing the contract's state at
a specific block, without incurring any on-chain gas cost.

A contract that claims to implement `IXMLRepresentableState` MUST be *XML-complete*: every piece of mutable
state that the author considers semantically relevant MUST be represented in the XML via bindings, so that
the rendered XML is a complete representation of the contract at a given (chain-id, address, block-number).

## Motivation

Smart contracts can efficiently orchestrate and process the life-cycle of a financial (derivative) product to
an extent that they finally represent *the* financial product itself.

At the same time, many applications require a human-readable, machine-parseable representation of that product
and its state: valuation oracles need inputs for settlements, smart bonds and other tokenized instruments need
legal terms, term sheets or regulatory reports, and on-chain registries, governance modules or vaults benefit
from a stable "document view" of their state.

In the traditional off-chain world, such needs are addressed by standards like FpML, the ISDA Common Domain
Model, or the ICMA Bond Data Taxonomy. A common pattern is to treat an XML (or similar) document as the
definitive source defining the financial product and then generate code to interact with the corresponding data.
When a process modifies or updates properties of the product, developers must synchronize the smart contract's
internal state with the off-chain XML representation. Today, each project typically invents its own set of view
functions and off-chain conventions, so clients need bespoke code to map contract state into XML, JSON, or PDF.
This makes interoperability, independent auditing, and reuse of tooling harder.

This ERC inverts that pattern by putting the smart contract at the centre. A contract declares that it implements
`IXMLRepresentableState` and defines an interface of representable state. Off-chain renderers can then derive
a canonical XML document that reflects the semantically relevant state of the contract at a given
(chain-id, address, block-number), using only `eth_call` and a standardized XML binding schema. Rendering happens
entirely off-chain and does not change state, so there is no gas cost, yet the resulting XML remains
cryptographically anchored to the chain.

Typical use cases include:

- Smart derivative contracts that must present their current state to a valuation oracle or settlement engine.
- Smart bonds and other tokenized financial instruments that must generate legal terms, term sheets, or
  regulatory and supervisory reports.
- On-chain registries, governance modules, and vaults that want a reproducible, auditable document-style
  snapshot of their state.

By standardizing the Solidity interface and the XML attribute schema, this ERC allows generic tools to consume
any compliant contract without project-specific adapters, and to plug directly into existing XML-based workflows
in finance and beyond.

### Interfaces

- `contracts/IRepresentableState.sol` - Marker interface and optional state version/hash.
  - `IXMLRepresentableState`  - Contract is XML-complete providing XML template. 
  - `IJSONRepresentableState` - Contract is JSON-complete providing JSON template.
  - `IRepresentableStateVersioned` - Contract provides indication on state-change via a version. 
  - `IRepresentableStateHashed` - Contract provides indication on state-change via a hash.

### Contacts (Examples)

- `contracts/examples/TestContract.sol` - Illustrating different bindings.
- `contracts/examples/MinimalInstrument.sol` - Minimal contract example.
- `contracts/examples/InterestRateSwapSettleToMarket.sol` - FpML like XML from settle to market contract state.
- `contracts/examples/BondDataTaxonomyDemo.sol` - ICMA BDT like XML from contract state.

### Documentation

- `doc/xml-bindings.md` - XML bindings
