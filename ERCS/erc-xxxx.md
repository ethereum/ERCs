---
eip: XXXX
title: Gateway Attributes for Message Control
description: Gateway attributes for cancellation, timeout, retry, dependencies, and execution control in cross-chain messaging.
author: Ernesto García (@ernestognw), Kalman Lajko (@LajkoKalman), Valera Grinenko (@0xValera)
discussions-to: TODO
status: Draft
type: Standards Track
category: ERC
created: 2024-XX-XX
requires: 7786
---

## Abstract

This ERC defines standard attributes for ERC-7786 cross-chain messaging gateways to enable consistent cancellation, timeout, retry, dependency, and execution control mechanisms across implementations. These attributes provide applications with predictable control over message lifecycle, ordering, and execution requirements.

## Motivation

ERC-7786 introduces an extensible attribute system for cross-chain messaging, but leaves attribute standardization to follow-up specifications. As cross-chain applications mature, consistent patterns for message control have emerged as essential requirements:

1. **Cancellation**: Applications need to cancel pending messages due to changed conditions
2. **Timeouts**: Automatic cancellation prevents indefinite pending states
3. **Retry Logic**: Standardized failure handling improves reliability
4. **Revert Behavior**: Consistent error semantics across gateways
5. **Message Dependencies**: Ensuring correct ordering when messages must execute in sequence
6. **Gas Requirements**: Preventing execution failures due to insufficient gas
7. **Execution Timing**: Controlling when messages can be executed for scheduling and coordination

Without standardized attributes, each gateway implements these features differently, fragmenting the ecosystem and requiring application-specific integration logic.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Standard Attributes

This specification defines standard attributes for ERC-7786 cross-chain messaging gateways.

Gateways MAY implement attributes independently. Gateways MUST validate the attribute's encoding for each attribute they implement and revert the transaction if the encoding is invalid.

#### `cancellable(bool)`

Indicates whether a message can be cancelled after submission. This attribute uses selector `0xde986d7f`, which represents the first 4 bytes of `keccak256("cancellable(bool)")`.

The attribute value is encoded as an ABI-encoded boolean, and COULD default to `false` when not specified. When set to `true`, gateways MUST provide a cancellation mechanism to allow applications to cancel pending messages due to changed conditions or requirements.

#### `timeout(uint256)`

Specifies a timestamp after which the message is automatically cancelled. This attribute uses selector `0x08148f7a`, derived from the first 4 bytes of `keccak256("timeout(uint256)")`.

The value is encoded as an ABI-encoded Unix timestamp, and COULD default to `0` when not specified. Gateways MUST NOT execute messages after the timeout timestamp unless `0` is specified, which MUST be interpreted as no timeout.

#### `earliestExecTime(uint256)`

Specifies the earliest timestamp at which the message can be executed. This attribute uses selector `0x6c5875a2`, derived from the first 4 bytes of `keccak256("earliestExecTime(uint256)")`.

The value is encoded as an ABI-encoded Unix timestamp, and COULD default to `0` when not specified. Gateways MUST NOT execute messages before the earliestExecTime timestamp unless `0` is specified, which MUST be interpreted as no delay. When combined with `timeout(uint256)`, this creates an execution time window.

#### `retryPolicy(bytes)`

Defines retry behavior for failed message execution. Using selector `0xf002c055` from the first 4 bytes of `keccak256("retryPolicy(bytes)")`, this attribute encodes retry parameters as ABI-encoded bytes.

The format follows `abi.encodePacked(uint16(maxRetries), uint32(retryDelay), uint32(backoffMultiplier))`, where `maxRetries` specifies the maximum number of retry attempts (with 0 indicating no retries), `retryDelay` defines the initial delay between retries in seconds, and `backoffMultiplier` provides the multiplier for exponential backoff in basis points (with 10000 representing 1x multiplier).

The attribute value COULD default to `0x` when not specified, equivalent to infinite retries, no delay, and no backoff (or `maxRetries = 0`, `retryDelay = 0`, and `backoffMultiplier = 0`).

#### `revertBehavior(uint8)`

Specifies how execution failures MUST be handled. This attribute uses selector `0x9e521a77`, representing the first 4 bytes of `keccak256("revertBehavior(uint8)")`.

The value is encoded as an ABI-encoded uint8 with three possible values: `0` for silent failure (the default behavior), `1` for reverting the transaction, and `2` for emitting a failure event and continuing execution. When not specified, the attribute defaults to `0`.

#### `dependsOn(bytes32[])`

Specifies message dependencies that must be executed before this message. This attribute uses selector `0xa9fed7b9`, derived from the first 4 bytes of `keccak256("dependsOn(bytes32[])")`.

The value is encoded as an ABI-encoded array of message identifiers. Gateways MUST NOT execute a message until all messages specified in the `dependsOn` array have been successfully executed. When not specified or empty, the message has no dependencies. This ensures correct ordering and prevents out-of-order delivery issues.

#### `minGasLimit(uint256)`

Specifies the minimum gas limit required for message execution. This attribute uses selector `0x39f87ba1`, derived from the first 4 bytes of `keccak256("minGasLimit(uint256)")`.

The value is encoded as an ABI-encoded uint256 representing the minimum gas units required. Gateways MUST ensure at least this amount of gas is available before attempting message execution. When not specified, gateways MAY use their default gas allocation strategies.

## Rationale

These attributes address the most common cross-chain message control requirements:

- **Lifecycle control** via cancellation and timeout mechanisms
- **Execution timing** through earliest execution time and timeout windows
- **Failure handling** via retry policies and revert behavior
- **Message ordering** through dependency chains
- **Execution guarantees** via minimum gas requirements

The byte-encoded retry policy allows for extensible parameters without requiring additional attributes. The dependency mechanism enables complex multi-message workflows while maintaining simplicity for single-message scenarios.

## Backwards Compatibility

This specification extends ERC-7786 without breaking changes. Gateways not supporting these attributes will operate normally per the base specification's requirement to handle unknown attributes gracefully.

## Security Considerations

<!-- TODO: Discuss -->

<!-- Maybe? -->
<!-- - **Dependency Cycles**: Gateways should detect and reject circular dependencies in `dependsOn` arrays -->

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
