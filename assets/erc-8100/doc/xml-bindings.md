<script defer="defer" src="js/oracle-fees.js"></script>

# Representable Contact State - XML Rendering of Smart Contract State

---

> ⚠️ **Before you continue:** Please read the **[Disclaimer](disclaimer/index.html)**. *By using this site, software, or contracts, you acknowledge that you have read and accepted it.*

---
# XML Namespace and Bindings

## Namespace

This ERC defines the XML namespace URI:

- Namespace URI: `urn:evm:state:1.0`
- Recommended prefix: `evmstate`

The XML template MUST declare this namespace, for example:

```xml
<Contract xmlns="urn:example:instrument"
          xmlns:evmstate="urn:evm:state:1.0">
    ...
</Contract>
```

## Bindings

Bindings are expressed as attributes in the `evmstate` namespace on XML elements.

A binding element is any XML element that has one or more attributes in the `evmstate` namespace.

### Function binding

To bind an element or attribute to a contract view function, the template MUST use either:

1. **Signature form (preferred)**

```xml
<Notional
    evmstate:call="notional()(uint256)"
    evmstate:format="decimal" />
```

- `evmstate:call` is a Solidity function signature string of the form
  `functionName(inputTypes...)(outputTypes...)`, with no spaces.
- The renderer MUST:
    - Compute the function selector as `keccak256("notional()")[0:4]`.
    - Use the declared output type `(uint256)` to decode the return data.

2. **Selector form (low-level)**

```xml
<Notional
    evmstate:selector="0x70a08231"
    evmstate:returns="uint256"
    evmstate:format="decimal" />
```

- `evmstate:selector` is a 4‑byte hex selector as a string with a `0x` prefix.
- `evmstate:returns` is an ABI type string describing the return type.
- The renderer MUST call the contract using the provided selector and decode using the given type.

If both `evmstate:call` and `evmstate:selector` are present, the renderer MUST prefer `evmstate:call` and MAY treat `evmstate:selector` as an error.

The output type MUST be a single ABI type (e.g. `uint256`, `int256`, `address`, `bool`, `string`, etc.). Support for tuples and arrays is out of scope for this minimal ERC.

### Target location and multiple bindings per element

A single binding can either target the element's text content or one of its attributes:

- If `evmstate:target` is **absent** or empty, the renderer MUST replace the element's text content with the rendered value.

#### Example:

  ```xml
  <Notional evmstate:call="notional()(uint256)" />
  ```

might render to:

  ```xml
  <Notional>1000000.00</Notional>
  ```

- If `evmstate:target` is present and non-empty, its value is the local name of an attribute to be populated.

#### Example:

  ```xml
  <Party evmstate:call="partyALEI()(string)"
         evmstate:target="id" />
  ```

might render to:

  ```xml
  <Party id="LEI-of-Party-A" />
  ```

The renderer MUST create or overwrite the attribute with that name on the element. It MUST NOT change the element's text content in this case.

Bindings MUST NOT be attached directly to attributes (XML does not allow attributes on attributes); all `evmstate:*` attributes are always attached to elements.

### Multiple Targets

A single XML element can have one or more bindings associated with it. To support multiple bindings,  this ERC additionally allows `evmstate:call`, `evmstate:selector`, `evmstate:returns`, `evmstate:format`, `evmstate:scale`, and `evmstate:target` to contain **semicolon-separated lists**. In that case:

- Each attribute value MUST be split on `';'`, and each part MUST be trimmed of leading and trailing whitespace.
- All lists are interpreted positionally. For index `i`:
    - `call[i]` is the i-th function signature (optional).
    - `selector[i]` is the i-th selector (optional).
    - `returns[i]` is the i-th explicit return type (optional).
    - `format[i]` is the i-th format specifier (optional).
    - `scale[i]` is the i-th decimal scale (optional).
    - `target[i]` is the i-th target specifier (optional).

Bindings are resolved in order `i = 0..N-1`, where `N` is the length of the `evmstate:call` list. If both `call[i]` and `selector[i]` are empty for a given index, that index MUST be ignored. If a list is shorter than `N`, missing entries MUST be treated as empty strings.

A binding can target either the element's text content or one of its attributes:

- If `target[i]` is empty or missing (after trimming), the renderer MUST replace the element's text content with the rendered value for that binding. If multiple bindings for the same element write text, they MUST be applied in index order; later writes overwrite earlier ones.

- If `target[i]` is a non-empty string, the renderer MUST set (create or overwrite) an attribute on   the element with that local name and the rendered value as its value. It MUST NOT change the   element's text content because of this binding.

#### Example with a single binding to the element's text:

  ```xml
  <Notional evmstate:call="notional()(uint256)"
          evmstate:format="decimal"
          evmstate:scale="2" />
  ```

might render to:

  ```xml
<Notional>1000000.00</Notional>
  ```

#### Example with two bindings: the notional as element text and the currency as an attribute:

  ```xml
<Amount
    evmstate:call="notional()(uint256); currency()(string)"
    evmstate:format="decimal; string"
    evmstate:scale="2; "
    evmstate:target="; currency" />
  ```

MUST render to something equivalent to:

  ```xml
<Amount currency="EUR">1000000.00</Amount>
  ```

### Formatting

The optional attribute `evmstate:format` describes how to convert the decoded ABI value into a text string. If `evmstate:format` is absent or an entry `format[i]` is empty, a type-specific default is used.

When `evmstate:format` is a semicolon-separated list, `format[i]` applies to the i-th binding as described above. Similarly, when `evmstate:scale` is a list, `scale[i]` applies to the i-th binding; a missing or empty entry is treated as scale 0.

Implementations of this ERC MUST support at least the following combinations:

- For unsigned integers (`uint*`) and signed integers (`int*`):
    - Default / `"decimal"` → base-10 representation, optionally with scaling as described below.
    - `"hex"` → lower-case hex with `0x` prefix.
    - `"iso8601-date"` → interpret the integer as a UNIX timestamp in seconds since epoch and render
      a UTC calendar date in ISO 8601 form `YYYY-MM-DD`.
    - `"iso8601-datetime"` → interpret the integer as a UNIX timestamp in seconds since epoch and
      render a UTC timestamp in ISO 8601 form (e.g. `2025-01-02T00:00:00Z`).

- For `address`:
    - Default / `"address"` → hex with `0x` prefix and ERC-55 checksum.

- For `bool`:
    - Default / `"boolean"` → `"true"` or `"false"`.

- For `bytes` and `bytesN`:
    - Default / `"hex"` → hex with `0x` prefix.
    - `"base64"` → base64 representation.

- For `string`:
    - Default / `"string"` → UTF-8 text as returned.

Implementations MAY support additional formats. If the renderer encounters an unknown `evmstate:format`, it SHOULD treat this as an error.

Optionally, an `evmstate:scale` attribute MAY be used for decimal-like integers:

```xml
<Amount evmstate:call="notional()(uint256)"
        evmstate:format="decimal"
        evmstate:scale="2" />
```

This means that the raw integer is scaled by 10^(-scale) before rendering, e.g. `12345` with `scale="2"` becomes `"123.45"`.

## Chain and contract identification

The XML representation MUST identify the chain, contract, and block that it represents.

This ERC reserves the following attributes in the `evmstate` namespace on the root element:

- `evmstate:chain-id`
- `evmstate:contract-address`
- `evmstate:block-number`

Example root element in the template:

```xml
<Contract xmlns="urn:example:instrument"
          xmlns:evmstate="urn:evm:state:1.0"
          evmstate:chain-id=""
          evmstate:contract-address=""
          evmstate:block-number="">
    ...
</Contract>
```

These attributes are **context bindings**:

- The renderer MUST set `chain-id` to the ERC-155 chain ID, as a base-10 string.
- The renderer MUST set `contract-address` to the contract address, as a checksummed hex address.
- The renderer MUST set `block-number` to the block number at which the representation was evaluated, as a base-10 string.

These fields are filled based on the RPC context (chain id, contract address, and block tag) and do not correspond to actual contract calls.

After rendering, the root element in the final XML might look like:

```xml
<Contract xmlns="urn:example:instrument"
            xmlns:evmstate="urn:evm:state:1.0"
            evmstate:chain-id="1337"
            evmstate:contract-address="0x588d26a62d55c18cd6edc7f41ec59fcd4331e227"
            evmstate:block-number="37356">
    ...
</Contract>
```

The renderer SHOULD set these attributes in the evmstate namespace (e.g. evmstate:chain-id, evmstate:contract-address, evmstate:block-number) to avoid collisions with existing attributes defined by the business XML schema. Implementations MAY additionally provide non-namespaced duplicates if required by downstream tooling.

## XML representation and XML-complete contracts

For a given chain-id `C`, contract address `A`, and block-number `B`, and for a contract that implements
`IXMLRepresentableState`, the **XML representation at (C, A, B)** is defined as follows:

1. Choose a JSON-RPC provider for chain `C`.
2. Call `eth_getBlockByNumber` (or equivalent) to obtain block `B` and its number, or use an externally provided `B`.
3. Perform all `eth_call` invocations (for `xmlTemplate()` and for all bound functions) with `blockTag = B`.
4. Start from the XML template returned by `xmlTemplate()`.
5. Resolve all bindings as specified above and insert the resolved values.
6. Fill `chain-id`, `contract-address`, and `block-number` on the root element.
7. Optionally remove all `evmstate:*` attributes from the document.

A contract is **XML-complete** if, for every block `B` at which its code matches this ERC's interface,
the following holds:

> Given the XML representation at (C, A, B), one can reconstruct all semantically relevant mutable
> state that influences the contract's future behaviour (up to isomorphism).

This is a semantic property that cannot be enforced by the EVM itself, but it can be audited and
tested. Authors of contracts that claim to implement `IXMLRepresentableState` MUST ensure that:

- Every mutable storage variable that influences behaviour is either:
    - directly bound via an `evmstate:call` / `evmstate:selector`, or
    - deterministically derivable from bound values via a public algorithm.
- Adding new mutable state requires adding corresponding bindings to the template.

In practice, contracts MAY also expose a separate "state descriptor" view function that lists all
bound fields, but this is out of scope for this minimal ERC.
