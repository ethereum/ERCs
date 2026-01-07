# ERC-8119: Key Parameters - Standard Format for Parameterized String Keys

## Summary

This ERC proposes a standard format for parameterized string keys used in EVM key-value storage. It defines a simple convention using a colon and space separator (`: `) to represent variations or instances of metadata types, enabling better interoperability across different implementations.

**PR:** https://github.com/ethereum/ERCs/pull/1455/

## Motivation

Many EVM-based smart contracts use key-value storage (e.g., Solidity mappings, Vyper hash maps) to store metadata where string keys may need to represent multiple instances or variations of the same metadata type. Without a standardized format, different implementations use inconsistent formats like `"registration-1"`, `"registration:1"`, or `"registration1"`, leading to:

- **Interoperability issues** between contracts and tooling
- **Parsing difficulties** for clients and indexers
- **Fragmentation** in the ecosystem

This standard enables consistent parameterized keys that are both human-readable and easy to parse programmatically. Standards such as ERC-8048 (Onchain Metadata for Token Registries) and ERC-8049 (Contract-Level Onchain Metadata) can leverage this ERC to support parameterized metadata keys.

## Specification

When string keys include parameters, they **MUST** use a colon and space separator (`: `).

**Valid formats:**
- `"registration: 1"`
- `"registration: 2"`
- `"user: alice"`
- `"key: value:with:colons"` (colons allowed in parameter, but not `: `)

**Invalid formats:**
- `"registration-1"` (hyphen separator)
- `"registration:1"` (colon without space)
- `"registration1"` (no separator)

### Key Rules

1. The base key name and parameter MUST be separated by `: ` (colon followed by space)
2. The parameter value MAY be any string that does not contain `: ` (colon-space sequence)
3. This ERC specifies **exactly one** parameter per key. Applications needing multiple sub-parameters MAY encode them within the single parameter value using any application-defined encoding (e.g., space-separated lists)

## Rationale

The colon and space separator (`: `) was chosen because:
- It improves human readability compared to formats like `key:value` or `key-value`
- It provides a clear, unambiguous separator that is easy to parse programmatically
- It maintains compatibility with existing parsers that support this format

This format was inspired by TOON format (developed by Johann Schopplich), and we acknowledge this preceding work.

## Backwards Compatibility

This ERC is fully backwards compatible. Existing implementations that do not use parameterized keys are unaffected. Implementations using non-standard parameter formats may continue to work but are encouraged to migrate to this standard format for better interoperability.

## Reference Implementation

A minimal Solidity reference implementation is provided in the PR, demonstrating:
- Setting parameterized keys (`"registration: 1"`, `"registration: 2"`, etc.)
- Retrieving values using a loop with string concatenation
- Compatibility with standard Solidity mappings

The standard applies to all EVM-compatible languages (Solidity, Vyper, etc.) that support string-keyed storage.

## Questions for Discussion

1. Is the `: ` (colon-space) separator the right choice, or would you prefer a different format?
2. Are there any edge cases or use cases we should consider?
3. Should we specify encoding recommendations for multiple sub-parameters, or is application-defined encoding sufficient?
4. Are there any security considerations we should address?

## Next Steps

Please review the [full specification](https://github.com/ethereum/ERCs/pull/1455/) and share your feedback. Your input will help refine this standard before it moves forward.
