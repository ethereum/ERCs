---
title: Protocol Interaction Manifest
description: a machine-readable JSON document that describes how to interact with a smart contract protocol
author: Paul Angus Bark (@cointrol-wallet)
discussions-to: https://ethereum-magicians.org/t/providing-protocol-interaction-knowledge-in-machine-readable-files-translating-intent-into-transactions/28663
status: Draft
type: Standards Track
category: ERC
created: 2026-06-19
---


## Abstract

A Protocol Interaction Manifest (PIM) is a structured, machine-readable JSON document that describes how to interact with a smart contract protocol. It is not just a list of available functions but the full workflow required to safely and correctly fulfil a user's intent while interacting with a smart contract protocol.

## Motivation

Protocol interaction knowledge exists primarily in websites and SDKs and not on-chain or in a portable machine-readable format. The websites set up to support dApps are a centralisation risk that depend upon developer team availability for regular maintenance.

Every DeFi protocol exposes functionality through smart contract ABIs. While an ABI can tell you the function names, parameter types and returned values, it does not tell you anything about how to use them.

The more complex protocols, such as UniSwap and ENS, are a system of smart contracts where one contract may be used to discover details while a different contract is used to complete an action. To use these protocols, a user must either connect their wallet to a dApp's webpage or write code using an SDK. 

As more protocols are introduced, the ability to maintain wallets supporting these protocols becomes more difficult. Every new protocol would require a new integration. Any update to a protocol would require updating code. Supporting 50 protocols means maintaining 50 integrations where none of the logic is portable, auditable, or shareable.

As an example, if an autonomous agent is instructed to “lend 500 USDC on Aave”, it would have to determine that it must call getReserveData first, check the health factor, approve an allowance for the pool contract, call supply with the right referral code, and then confirm that the aToken balance has increased. That knowledge is currently not available in a form that a generic agent can read.

This problem becomes even more significant for generic wallet software, automation systems, and autonomous agents which cannot rely on bespoke integrations for every protocol.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

### Top-level Objects

A PIM MUST include all nine top-level objects in the table below.

| Section | Purpose |
|---------|---------|
| schemaVersion | Identifies the PIM schema version used. Allows execution engines to handle schema evolution gracefully. MUST include the PIM schema version used to create the PIM. |
| metadata | Human-readable and machine-readable protocol identification, validity window, chain scope, and author. |
| contracts | Named registry of all contract addresses the PIM references, with roles and descriptions. |
| types | Reusable tuple and struct definitions for encoding/decoding calldata. Mirrors Solidity structs. |
| lookups | Named on-chain read operations. Defines what to call, with what args, and what to expect back. |
| calculations | Named off-chain computation steps. Deadline math, slippage application, path encoding. |
| intents | The core of the PIM. Named, executable workflows with ordered steps. |
| ui | Human-readable labels and display strings for wallets and agent interfaces. |
| signatures | Cryptographic signatures from the protocol or community, enabling trust level assignment. |
 
#### metadata

A PIM MUST include a completed metadata section. The section MAY include validFrom and/or validUntil fields. The notes field is OPTIONAL. All other fields MUST be included. Fields MUST only appear once.

The metadata section identifies the protocol, scopes the PIM to specific chains and contracts, and defines any temporal windows when the manifest is valid.

Execution engines MUST reject PIMs with expired validity windows or whose chainId does not match the current network.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| protocol | string | REQUIRED | Human-readable protocol name. e.g. "Aave V3", "ENS V2" |
| description | string | REQUIRED | One to three sentence description of what the protocol does, written for a non-technical reader. |
| category | string | REQUIRED | Protocol category. Allowed values: dex, lending, staking, bridge, vault, nft, governance, other. |
| website | string | REQUIRED | Website URL of the PIM author. Used for display and verification. |
| author | string | REQUIRED | Entity that authored this PIM. Should match the signer address' public identity. |
| chainId | number[] | REQUIRED | Array of EVM chain IDs to which this PIM applies. All reference contracts MUST have the same contract addresses on all listed chains. |
| pimVersion | string | REQUIRED | Semantic version of this PIM document. e.g. "1.0.0". Follows semver: major.minor.patch. |
| validFrom | number | RECOMMENDED | Unix timestamp. The PIM MUST NOT be used before this time. Prevents replay of old manifests. |
| validUntil | number | RECOMMENDED | Unix timestamp. The PIM MUST NOT be used after this time. Execution engines MUST enforce this. Set to a reasonable future date. |
| notes | string | OPTIONAL | Free-text field for implementer notes, caveats, or known imitations. Displayed to technical users. |

#### contracts

A PIM MUST include a completed contracts section. A contract entry MUST NOT have both address and lookup fields. An execution engine MUST NOT interact with any contracts that are not defined in this section.

The contract section is the address registry for the PIM. Every contract address referenced anywhere in the manifest, whether lookups, buildTransaction steps, or calculations, MUST be declared here first. The execution engine validates all referenced addresses against this registry before execution begins.

Each key in the contracts object is a logical name (example “pool”, “router”, “factory”) that the rest of the manifest references using template syntax: {{contracts.pool.address}}.

Each logical name object MUST include a type definition object using the fields defined in the table below. 

As some protocols may use factories that can create new contracts that cannot be defined in advance, or a protocol may manage a large number of template contracts that would make the contract section unmanageable, a contract MAY use a “lookup” field instead of an “address” field. The “lookup” MUST match a lookup in the PIM. 

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| address | string (hex) | OPTIONAL | The deployed contract address ([ERC-55](./erc-55.md) checksum format recommended). This field MUST be included if the lookup field is not used. |
| lookup | string | OPTIONAL | The method used to fetch the contract address. This field MUST be included if the address field is not used. |
| role | string | REQUIRED | Functional role. Standard values: router, factory, pool, quoter, registry, gateway, oracle, vault, token, other. |
| description | string | REQUIRED | Plain English description of what this contract does and why the PIM needs it. |

#### types

It is RECOMMENDED that a PIM includes a completed types section.

Each key in the types section is a named type and the value is an object that MUST include the required fields defined in the tables below. 

The types section mirrors Solidity structs and is used to define the data types and tuples used in PIMs. They are used to define contract inputs and outputs for use in encoding calldata for buildTransaction steps that accept tuple parameters as well as decode return values from lookup steps that return tuples.

Types are referenced by name in lookups and intents. The execution engine MUST be able to ABI-encode any type defined here using the standard Solidity encoding rules.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| kind | tuple (see table below) | REQUIRED | Identifies the format of the data type. |
| description | string | OPTIONAL | Plain English description of what the data type represents. |
| fields | object | REQUIRED | Map of field name to field definition object. Refer to table below for field definitions. |

##### Tuple kinds

| Kind | Description | When to Use |
|------|-------------|-------------|
| tuple | A named struct with typed fields. Maps directly to a Solidity struct, a function's input, or a function's output. | Any function that takes or returns a struct-like parameter. |
| array | A homogeneous array of a primitive or named type. | Functions returning address[], tuple[], etc. |
| primitive | A homogeneous array of a primitive or named type. | Simple return values. Usually inlined rather than named. |

##### Field definition objects

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| type | string | REQUIRED | Can refer to either a Solidity base unit type, or to another tuple defined in types. e.g. address, uin256. |
| description | string | OPTIONAL | Plain English description of what the field type represents. |
| unit | string | OPTIONAL | Unit of measure of field value. e.g. seconds, minutes, dollars, cents. |

#### lookups

The completion of the lookup section is OPTIONAL.

Each key in the lookups section is a named type and the value is an object that MUST include the required fields defined in the table below.

The lookups section defines named on-chain read operations or simulated write operations. If a reference function is not read-only, the execution engine MUST simulate the transaction only.

Each lookup describes a function call: which contract to call, what arguments to pass, and what structure to expect in the return value. Lookups are referenced by name in intent steps and contracts using the action: “lookup” directive.

Lookups MUST NOT trigger state changes.


| Field | Type | Required | Description |
|-------|------|----------|-------------|
| description | string | REQUIRED | Plain English description of what data this lookup retrieves and why it is needed. |
| contract | string | REQUIRED | Logical contract name that MUST match an entry in the contracts section. |
| function | string | REQUIRED | Contract function name to call. e.g. "getPool", "quoteExactInputSingle". |
| args | array or object | REQUIRED | Arguments to pass. Can be literal values, template variables {{tokenIn}}, iterate values (see below), or a type defined in the type section. |
| returns | string | Return type name or Solidity based unit type. Named type MUST be included in types section. |
| iterate | object | OPTIONAL | If present, execution engine MUST run this lookup multiple times varying the specified argument across the given values. Results MUST be returned as an array of named types keyed by the iterated argument values. |
| filter | object | OPTIONAL | Filters the results of an iteration using operators as keys. Supported operators: notEqual, greaterThan, lessThan, equals. |
| select | string | OPTIONAL | "all" returns the full filtered array. "max" and "min" return the highest or lowest numeric value based on the selectCriterion field. If the lookup only returns single primitive values, the selectCriterion field SHOULD NOT be included. |
| selectCriterion | string | OPTIONAL | This field MUST refer to a named field in the returns tuple. This field MUST NOT be used if the select field is not present. |
| validate | array | OPTIONAL | List of field-level assertation on the return value. Refer to table below. If any fail, the execution engine MUST halt activity and the errorMessage MUST be shown to the use. |

##### The iterate pattern

Many protocols may deploy multiple pools or fee tiers for the same token pair. The iterate pattern allows a single lookup definition to fan out across multiple values and collect all results. As an example:
```
"pool": {
 "contract": "factory",
 "function": "getPool",
 "args": ["{{tokenIn}}", "{{tokenOut}}", "{{fee}}"],
 "iterate": { "fee": [100, 500, 3000, 10000] },
 "filter": { "notEqual": "0x0000000000000000000000000000000000000000" },
 "select": "all"
}
```

The above partial sample runs getPool four times, once per fee tier, and only returns the results where a pool actually exists (non-zero address). The returned results are an array of results keyed by the iteration values. As an example of possible output from the fee iteration from above:
``` 
[
 {"100":"0x0000000000000000000000000000000000000001"},
 {"500":"0x0000000000000000000000000000000000000002"},
 {"3000":"0x0000000000000000000000000000000000000003"},
 {"10000":"0x0000000000000000000000000000000000000004"}
]
```

##### Validate assertions

Lookups can include field-level assertions that gate further execution. If a reserve is frozen, if borrow capacity is zero, if a health factor is critically low, the validate array can catch these transactions before any transaction is built.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| field | string | REQUIREDD | Name of data object in tuple subject to validation. Can be "returns" if a single primitive value is returned by the lookup. |
| notEqual | string | OPTIONAL | Used to confirm inequality. |
| equals | string | OPTIONAL | Used to confirm equality. |
| greaterThan | string | OPTIONAL | Used to confirm value is above a referenced value. |
| lessThan | string | OPTIONAL | Used to confirm value is below a referenced value. |

Referenced values can either be literal values or named types from the type section.

By convention, a validate object MUST contain at least one of the “notEqual”, “equals”, “greaterThan”, or “lessThan” fields. More than one of these fields MAY be used in combination (for example, if a value needs to be within a range of 1 – 10, then the validation can include “greaterThan”: “0” and “lessThan”: “11”). 
 
All values keyed to the operator fields MUST be strings and the execution engine MUST use the type to correctly read the data.

Validate assertions MUST only be applied to returned values.

#### calculations

It is RECOMMENDED that a PIM includes a completed calculations section.

Each key in the calculations section is a named type and the value is an object that MUST include the required fields defined in the table below.

The calculations section defines named off-chain computations. These are mathematical operations that the execution engine performs locally without making any RPC calls. Common uses can include computing deadlines, applying slippage tolerances, encoding multi-hop paths, and formatting display values.


| Field | Type | Required | Description |
|-------|------|----------|-------------|
| description | string | REQUIRED | Plain English description of what this calculation produces. |
| formula | Instruction | REQUIRED | The computation expressed as an type-defined formula instruction using Instruction objects defined in the below table. |
| inputs | string[] | RECOMMENDED | Explicit list of variable names the formula depends on. Helps the engine verify all inputs are available before computing. |
| outputUnit | string | OPTIONAL | Declare the unit of the output. Informational only. Values can include: unix_timestamp, uint256, percentage, decimal, bytes, address. |
| precision | string | OPTIONAL | Indicator of number type returned: can be "float" or "integer". |

The formula field MUST reference only variables listed in the types section, the intents section, or recognized global variables such as block.timestamp or msg.sender; best practice is to include variables (except global) in the inputs field.

##### Instruction objects

Instruction objects use a key:value method where the key indicates the operation to be done and the value is the scalar used in the operation.

The formula field MUST include one "set" object. The "set" object is always the first instruction and indicates the initial value; it can be a scalar value or a variable.

The "op" key MAY be used in place of a value for inner calculations (similar to using brackets in mathematical equations). An "op" key's inner calculation MUST include its own "set" object.

The formula field MUST NOT have more than one "set" object except for within inner "op" objects. "op" objects MUST NOT have more than one "set" object except for within inner "op" objects.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| set | string | REQUIRED | Defines the initial value (scalar or referenced variable). |
| add | string | OPTIONAL | Adds a scalar value, variable, or op-object to the running total. |
| subtract | string | OPTIONAL | Subtracts a scalar value, variable, or op-object from the running total. | 
| multiply | string | OPTIONAL | Multiples the running total by a scalar value, variable, or op-object. |
| divide | string | OPTIONAL | Divides the running total by a scalar value, variable, or op=object. |
| exp | string | OPTIONAL | Multiples the running total by a factor of ten to the power of a scalar value, variable, or op-object. Value MUST be an integer. |
| mod | string | OPTIONAL | Returns the remainder from the division of the running total by a scalar value, variable, or op-object. Running total and value MUST be integers. |
| power | string | OPTIONAL | Takes the running total as a base and applies a scalar value, variable, or op-object as an exponent. Value MUST be an integer. |
| op | string | OPTIONAL | Provides an evaluation of a sub-expression from scratch and returns a scalar value that is used as the operand of the parent instruction. Sub-expression MUST include a set-object. |

#### intents

The intents section is the operational core of the PIM. A PIM MUST contain at least one intent object.

Each intent is a named, executable workflow. When a user or agent expresses a goal (swap, borrow, register), the execution engine finds the matching intent, binds the user's inputs to the intent's variables, and executes each step in order.

Each key in the intents section is a named type and the value is an object that MUST include the required fields defined in the table below. Every intent MUST have a corresponding intentDescription object in the ui section.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| description | string | REQUIRED | Plain English description of what this intent does, written for a non-technical user. |
| requiredInputs | string[] | REQUIRED | Variable names that MUST be provided before this intent can execute. The execution engine MUST validate that these are present before starting. |
| optionalInputs | string[] | OPTIONAL | Variable names that MAY be provided. If absent, defaults specified in steps are used. Defaults MUST be specified using ?? notation. |
| notes | string | OPTIONAL | Additional context for implementers. Displayed to technical users. |
| steps | Step | REQUIRED | The sequential steps using Step objects defined in the below table. Step id values MUST begin at 1 and MUST NOT skip numbers. Each step's output is available to all subsequent steps. |

##### Step objects

Each step in the steps object has an action field that determines what the execution engine does.

| Action | Description |
|--------|-------------|
| lookup | Performs a named on-chain read call defined in the lookups section. |
| calculate | Runs a named off-chain computation defined in the calculations section. |
| buildTransaction | Constructs and submits a transaction. |

Step fields (all step types)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| id | integer | REQUIRED | Unique identifier for this step within the intent. Used by subsequent steps to reference this step's output. Steps must be executed in order starting from the number 1. Numbers MUST NOT be skipped. |
| action | string | REQUIRED | Value must be one of lookup, calculate, or buildTransaction. |
| condition | string | OPTIONAL | Expression that must evaluate as true before the step is executed. Examples include awaiting approval confirmation or ENS minimum waiting period post-commitment. The value in this field MUST be a Boolean expression. |
| description | string | RECOMMENDED/REQUIRED | Plain English description of what this step does. This MUST be shown in debug or audit output. This field MUST be included for all buildTransaction steps. |
| skipIf | string | OPTIONAL | The value in this field MUST be a Boolean expression. If the expression evaluates to true, the step MUST be skipped. Useful for conditional approvals. |
| storeAs | string | OPTIONAL | Stores the result of this step under a different variable name in the execution state. |

Step fields (buildTransactions only):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| contract | string | REQUIRED | Logical contract name from the contracts section. The contract MUST be declared in the contracts section. |
| function | string | REQUIRED | Contract function name to be called. |
| args | object | OPTIONAL | Map of parameter name to value or template expression. It is RECOMMENDED to reference an object from the types section. This field MUST be included for functions requiring input arguments. |
| value | string | OPTIONAL | ETH value in wei to send with the transaction. Used for native ETH interactions. This field MUST be included for payable functions. |

##### Template variables

Step arguments use double-bracket template syntax to reference values from the execution context. Examples include:

| Syntax | Resolves to |
| {{userAddress}} | The wallet address of the user initiating the event. |
| {{asset}} | An intent input variable named 'asset'. |
| {{asset.symbol}} | The symbol of the intent input variable names 'asset'. |

#### ui

The ui (user interface) section provides human-readable labels and display strings. It is consumed by wallets and agent interfaces to present intent results in plain English. Nothing in the ui section affects execution logic.

The ui section MUST include intentDescriptions for all named intents from the intent section. 

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| labels | object | RECOMMENDED | Map of variable name/field name to display label. For example {"tokenIn": "You pay", "tokenOut": "You receive". |
| intentDescriptions | object | REQUIRED | Map of template strings keyed by intent item names for displaying a completed intent. Variables are interpolated. For example {"exactInput": "Swap {{amountIn}} {{tokenIn}} for {{tokenOut}}."}. |
| iterateLabels | object | OPTIONAL | Map of iterated objects to human-readable label. For example {"fees": { "100": "0.01% - Stable pairs", "500": "0.05% - Low volatility pairs", "2500": "0.25% - Standard pairs", "10000": "1.00% - Exotic/low liquidity pairs" }}. |

#### signatures

It is RECOMMENDED to include a completed signatures section. 

Unsigned PIMs MUST be treated as Level 0 - Unverified.

The signatures section includes the cryptographic signature of the PIM content. Each signature enables the Trust Resolver to assign a trust level to the manifest. If the signature section is included, it MUST include either a signer field or a signerHashed field as well as all required fields listed in the table below.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| signer | address | OPTIONAL | The Ethereum address that produced this signature. It SHOULD be a well-known protocol-controlled address. This field MUST be used if the signature type is "ecdsa". |
| signerHashed | bytes32 | OPTIONAL | The keccak256 hash of the public key of the key pair used to product this signature. Since newer methods have larger keys (such as fips-204, fips-205, etc), the hash of the key can be provided to avoid large byte arrays. |
| type | string | REQUIRED | Signature scheme used to create this signature. Supported: "ecdsa". Future support for "fips-204", "fips-205", etc. |
| signature | bytes | REQUIRED | The hex-encoded signature. Validation is subject to type. |
| signerLabel | string | OPTIONAL | Human-readable name for the signer. For example "Aave DAO Multisig". Informational only. |

##### What is signed

The signature MUST be of the keccak256 hash of the entire PIM excluding the signatures section. Any spacing, new lines or hidden characters added for human-readability MUST be removed before the hash is generated.

##### Trust level assignment

An execution engine MUST include a trust resolver that assigns a trust level to a PIM.

| Level | Name | Criteria | Wallet Behaviour |
|-------|------|----------|------------------|
| 0 | Unverified | No signature included or signer address is unknown. | Maximum warnings. Execution only permitted in sandbox/simulation mode otherwise user MUST acknowledge risks explicitly. |
| 1 | Community | Signature from a known community publisher. Hash verified. Signer not the protocol team. | Standard warnings MUST be shown. Execution permitted with user confirmation. |
| 2 | Protocol Signed | Signature from an address on a protocol's website, or registered with an ENS domain, or broadcast using ECP. | Trust indicator MUST be shown. Security checks MUST still be run. |
| 3 | Wallet Verified | Internally reviewed and pinned by the wallet team. MAY be bundled with the wallet. | Silent trust. Security checks MUST still be run. No additional confirmation. |

### Chain Specifics

A PIM can be created for multiple chains but all chains MUST have the same contract addresses. If a chain has a different set of contract addresses, even if it is only one contract out of many that does not match other chains, it MUST have a separate PIM. 

## Rationale

TBD

## Backwards Compatibility

This ERC does not change the consensus layer, so there are no backwards compatibility issues for Ethereum as a whole. 

## Reference Implementation

No reference implementation is provided in this draft.

TBD

## Security Considerations

### Threat model

PIMs are untrusted inputs. Even a level 2 protocol-signed PIM can only be trusted to the extent of its verified content. The threat model assumes:
 - A PIM may be crafted by a malicious actor attempting to steal funds
 - A legitimate PIM may be compromised if the protocol's signing key is stolen
 - A community PIM may be well-intentioned but contain errors

The security model assumes zero trust in the PIM content and derives safety entirely from the execution engine's enforcement rules and simulation results.

### Attack vectors and mitigations

| Attack Vector | Description | Mitigation |
|---------------|-------------|------------|
| Recipient override | PIM sets recipient of token transfer to attacker address. | Security validator blocks any recipient not matching userAddress without explicit confirmation. |
| Spender injection | PIM generates approval to an unknown spender address. | Approval target must be in contracts registry. Unknown targets blocked. |
| Token substitution | PIM swaps tokenIn or tokenOut for a worthless token the attacker controls. | Token addresses compared against user's stated intent before calldata is constructed. |
| Quote manipulation | PIM returns a manipulated quote making a bad trade look favourable. | Simulation checks actual balance deltas, not PIM-declared outcomes. |
| Simulation spoofing | Attacker controls RPC endpoint used for simulation and returns false results. | Wallets should use multiple independent RPC endpoints for simulation. |
| Expired PIM replay | Old PIM with unfavourable parameters replayed after protocol update. | Execution engines enforce validUntil validations. |
| DelegateCall injection | PIM generates calldata that causes a delegateCall in the target contract. | Static analysis scans for delegateCall patterns before execution. |
| External call injection | PIM adds extra arbitrary calls outside its declared intent steps. | All transaction targets must be in contracts registry. |
| Unlimited approval abuse | PIM requests approval for max uint256 to accumulate future spending permission. | Execution engine monitors approval amounts and returns a warning for unnecessarily large amounts. |

### Simulation requirement

Simulation is the final line of defence. No matter how well the PIM is written, nor how high its trust level is, nor how clean its static analysis, the actual execution must be verified before the use signs.

A compliant engine must:

 - Simulate every transaction in the proposed sequence via eth_call against the current block state.
 - Compute the actual token balance delta for every address that appears in the transaction.
 - Compare the actual delta against the expected outcome declared in the intent.
 - Block submission if any delta deviates beyond a defined tolerance (typically 0.1%)
 - Show the user the simulated outcome, not the PIM-declared outcome

**Security:** If simulation is unavailable (RPC failure, rate limit), execution MUST NOT proceed. The user SHOULD be informed that pre-flight verification could not be completed.

### User experience model

#### Design principles

 - Users see outcomes, not calldata. The confirmation screen shows what token moves, in what amount, and to whom - never raw hex.
 - Complexity is hidden, risk is not. Fee tiers, routing, and path encoding are invisible. Slippage, price impact, and health factor risk are prominent.
 - Deterministic previews. The confirmation screen MUST reflect what will actually happen on-chain, verified by simulation.
 - Trust is visible. The trust level of the active PIM MUST always be shown. A level 0 PIM should feel meaningfully different from a level 2.
 - Multi-step is sequential. If an intent requires multiple transactions (e.g. approve then swap), each is confirmed individually by the user. Subsequent steps never proceed without confirmation.

#### Confirmation screen requirements

Every intent execution must display a confirmation screen before any transaction is submitted. The screen MUST include:

| Element | Content |
|---------|---------|
| Protocol identity | Protocol name, PIM version, trust level badge. |
| Intent summary | The intentDescription from the ui section, with variables interpolated. |
| Token movements | Itemised list of every token that moves: symbol, amount, direction, address. |
| Simulated outcome | Actual expected result from simulation, not PIM-declared values. |
| Risk indicators | Slippage, price impact, health factor, approval type. |
| Trust level warning | Prominent indicator if PIM is level 0 or 1. |
| Cancel/Confirm | Clear action buttons. Cancel MUST be the default-focused element. |

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).