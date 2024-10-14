---
title: Cross-Chain Messaging Gateway
description: An interface for contracts to send and receive cross-chain messages.
author: Francisco Giordano (@frangio), Hadrien Croubois (@Amxx), Ernesto Garcia (@ernestognw), CJ Cobb (@cjcobb23)
discussions-to: https://ethereum-magicians.org/t/erc-yyyy-cross-chain-messaging-gateway/21374
status: Draft
type: Standards Track
category: ERC
created: 2024-10-14
---

## Abstract

This proposal describes an interface, and the corresponding workflow, for smart contracts to send arbitrary data through cross-chain messaging systems. The end goal of this proposal is to have all such messaging protocols accessible via this interface (natively or using "adapters") to improve their composability and interoperability. That would allow a new class of cross-chain native smart contracts to emerge while reducing vendor lock-in. This proposal is modular by design, allowing users to leverage bridge-specific features through attributes while providing simple "universal" access to the simple feature of "just getting a simple message through".

## Motivation

Cross-chain messaging systems (or bridges) allow communication between smart contracts deployed on different blockchains. There is a large diversity of such systems with multiple degrees of decentralization, with various components, that implement different interfaces, and provide different guarantees to the users.

Because almost every protocol implementing a different workflow, using a specific interface, portability between bridges is basically impossible. This also forbid the development of generic contracts that rely on cross chain communication.

The objective of the ERC is to provide a standard interface, and a corresponding workflow, for performing cross-chain communication between contracts. Existing cross-chain communication protocols, that do not nativelly implement this interface, should be able to adopt it using adapter gateway contracts.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Message Field Encoding

A cross-chain message consists of a sender, receiver, payload, and list of attributes.

#### Sender & Receiver

The sender account (in the source chain) and receiver account (in the destination chain) MUST be represented using CAIP-10 account identifiers. Note that these are ASCII-encoded strings.

A CAIP-10 account identifier embeds a CAIP-2 chain identifier along with an address. In some parts of the interface, the address and the chain parts will be provided separately rather than as a single string, or the chain part will be implicit.

#### Payload

The payload is an opaque `bytes` value.

#### Attributes

Attributes are structured pieces of message data and/or metadata. Each attribute is a key-value pair, where the key determines the type and encoding of the value, as well as its meaning and behavior.

Some attributes are message data that must be sent to the receiver, although they can be transformed as long as their meaning is preserved. Other attributes are metadata that will be used by the intervening gateways and potentially removed before the message reaches the receiver.

The set of attributes is extensible. It is RECOMMENDED to standardize attributes and their characteristics by publishing them as ERCs.

A gateway MAY support any set of attributes. An empty attribute list MUST always be accepted by a gateway.

Each attribute key MUST have the format of a Solidity function signature, i.e., a name followed by a list of types in parentheses. For example, `minGasLimit(uint256)`.

In this specification attributes are encoded as an array of `bytes` (i.e., `bytes[]`). Each element of the array MUST encode an attribute in the form of a Solidity function call, i.e., the first 4 bytes of the hash of the key followed by the ABI-encoded value.

##### Standard Attributes

The following standard attributes MAY be supported by a gateway.

- `postProcessingOwner(address)`: The address of the account that shall be in charge of message post-processing.

### Source Gateway

An Source Gateway is a contract that offers a protocol to send a message to a receiver on another chain. It MUST implement `IGatewaySource`.

```solidity
interface IGatewaySource {
    event MessageCreated(bytes32 outboxId, string sender, string receiver, bytes payload, uint256 value, bytes[] attributes);
    event MessageSent(bytes32 indexed outboxId);

    error UnsupportedAttribute(bytes4 signature);

    function supportsAttribute(bytes4 signature) external view returns (bool);

    function sendMessage(
        string calldata destination, // CAIP-2 chain identifier
        string calldata receiver, // CAIP-10 account address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId);
}
```

#### `supportsAttribute`

Returns a boolean indicating whether an attribute is supported by the gateway, identified by the selector computed from the attribute signature.

A gateway MAY be upgraded with support for additional attributes. Once present support for an attribute SHOULD NOT be removed to preserve backwards compatibility with users of the gateway.

#### `sendMessage`

Initiates the sending of a message.

Further action MAY be required by the gateway to make the sending of the message effective, such as providing payment for gas. See Post-processing.

MUST revert with `UnsupportedAttribute` if an unsupported attribute key is included. MAY revert if the value of an attribute is not a valid encoding for its expected type.

MAY accept call value (native token) to be sent with the message. MUST revert if call value is included but it is not a feature supported by the gateway. It is unspecified how this value is represented on the destination.

MAY generate and return a unique non-zero *outbox identifier*, otherwise returning zero. This identifier shall be used to track the lifecycle of the message in the outbox in events and for post-processing.

MUST emit a `MessageCreated` event, including the optional outbox identifier that is returned by the function.

If an outbox identifier was generated, MUST emit a `MessageSent` event if no post-processing is required.

#### `MessageCreated`

This event signals that a would-be sender has initiated the sending of a message.

If `outboxId` is present, post-processing MAY be required to send the message through the cross-chain channel.

#### `MessageSent`

This event signals that no more post-processing in the source chain is required, and that the message has been sent through the cross-chain channel.

#### Post-processing

After a sender has invoked `sendMessage`, further action MAY be required by the gateways to make the message effective. This is called *post-processing*. For example, some payment is typically required to cover the gas of executing the message at the destination.

The exact interface for any such action is out of scope of this ERC. If the `postProcessingOwner` attribute is supported and present, such actions MUST be restricted to the specified account, otherwise they MUST be able to be performed by any party in a way that MUST NOT be able to compromise the eventual receipt of the message.

The gateway MUST emit a `MessageSent` event with the appropriate identifier once no more post-processing is required by the source gateway. Further post-processing MAY be required in the source or destination gateways.

### Destination Gateway

A Destination Gateway is a contract that implements a protocol to validate messages sent on other chains and have them received at their destination.

The gateway can operate in Active or Passive Mode.

In both modes, the destination account of a message, aka the receiver, MUST implement a `receiveMessage` function. The use of this function depends on the mode of the gateway as described in the following sections.

```solidity
interface IGatewayReceiver {
    function receiveMessage(
        address gateway,
        bytes calldata gatewayMessageKey,
        string calldata source, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable;
}
```

#### Active Mode

The gateway directly invokes `receiveMessage`, and only does so with valid messages. The receiver MUST assume that a message is valid if the caller is a known gateway.

The arguments `gateway` and `gatewayMessageKey` are unused in active mode and SHOULD be zero and empty respectively.

#### Passive Mode

The gateway does not directly invoke `receiveMessage`, but provides a means to validate messages. The receiver allows any party to invoke `receiveMessage`, but if the caller is not a known gateway it MUST check that the gateway provided as an argument is a known gateway, and it MUST validate the message against it before accepting it, forwarding the message key.

A gateway acting in passive mode MUST implement `IGatewayDestinationPassive`. If a gateway operates exclusively in active mode, the implementation of this interface is OPTIONAL.

```solidity
interface IGatewayDestinationPassive {
    function validateReceivedMessage(
        bytes calldata messageKey,
        string calldata source, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external;
}
```

##### `validateReceivedMessage`

Checks that there is a valid and as yet unexecuted message whose contents are exactly those passed as arguments and whose receiver is the caller of the function. The message key MAY be an identifier, or another piece of data necessary for validation.

MUST revert if the message is invalid or has already been executed.

TBD: Passing full payload or payload hash (as done by Axelar). Same question for attributes, possibly different answer depending on attribute malleability.

#### Dual Active-Passive Mode

A gateway MAY operate in both active and passive modes, or it MAY switch from operating exclusively in active mode to passive mode or vice versa.

A receiver SHOULD support both active and passive modes for any gateway. This is accomplished by first checking whether the caller of `receiveMessage` is a known gateway, and only validating the message if it is not; the first case supports an active mode gateway, while the second case supports a passive mode gateway.

### Pending discussion

- How to "reply" to a message? Duplex gateway? Getter for reverse gateway address? Necessary for some applications, e.g., recovery from token bridging failure?
- Should the destination and receiver inputs of `sendMessage` be kept as two separate strings, or merged as a single CAIP-10 string with a `:` separator? This has implication of the calldata length, which in some cases may be stored.
- Do we want the gateway to have the ability to inform users of the address of the new version, similar to how `AccessManager` can update then authority trusted by an `AccessManaged`? This could be useful if a gateway is ever deprecated in favor of a new version.
- Should data and metadata attributes be split in two? What are data attributes used for? Do we need them?

## Rationale

Attributes are designed so that gateways can expose any specific features the bridge offers without having to use a specific endpoint. Having a unique endpoint, with modularity through attributes, SHOULD allow contracts to change the gateway they use while continuing to express messages the same way. This portability offers many advantages:
- A contract that relies on a specific gateway for sending messages is vulnerable to the gateway being paused, deprecated, or simply breaking. If the communication between the contract and the gateway is standard, an admin of the contract COULD update the address (in storage) of the gateway to use. In particular, senders to update to the new gateway when a new version is available.
- Bridge layering SHOULD be possible. In particular, this interface should allow for a new class of bridges that routes the message through multiple independent bridges. Delivery of the message could require one or multiple of these independent bridges depending on whether improved liveness or safety is desired.

As some cross-chain communication protocols require additional parameters beyond the destination and the payload, and because we want to send messages through those bridges without any knowledge of these additional parameters, a post-processing of the message MAY be required (after `sendMessage` is called, and before the message is delivered). The additional parameters MAY be supported through attributes, which would remove the need for a post-processing step. If these additional parameters are not provided through an attribute, an additional call to the gateway is REQUIRED for the message to be sent. If possible, the gateway SHOULD be designed so that anyone with an incentive for the message to be delivered can jump in. A malicious actor providing invalid parameters SHOULD NOT prevent the message from being successfully relayed by someone else.

Some protocols gateway support doing arbitrary direct calls on the receiver. In that case, the receiver must detect that they are being called by the gateway to properly identify cross-chain messages. Getters are available on the gateway to figure out where the cross-chain message comes from (source chain and sender address). This approach has the downside that it allows anyone to trigger any call from the gateway to any contract. This is dangerous if the gateway ever holds any assets (ERC-20 or similar). The use of a dedicated `receiveMessage` function on the receiver protects any assets or permissions held by the gateway against such attacks. If the ability to perform direct calls is desired, this can be implemented as a wrapper on top of any gateway that implements this ERC.

## Backwards Compatibility

Existing cross-chain messaging protocols implement proprietary interfaces. We recommend that protocols natively implement the standard interface defined here, and propose the development of standard adapters for those that don't.

## Security Considerations

Unfortunately, CAIP-2 and CAIP-10 names are not unique. Using non-canonical strings may lead to undefined behavior, including message delivery failure and locked assets. While source gateways have a role to play in checking that user input are valid, we also believe that more effort should be put into standardizing and documenting what the canonical format is for each CAIP-2 namespace. This effort is beyond the scope of this ERC.

Needs discussion.

## References

We recommend reading [Norswap](https://twitter.com/norswap)'s [cross-chain interoperability report](https://github.com/0xFableOrg/xchain/blob/7789933bba24e2dd893cf515157af70474e7180b/README.md) that describes the properties of different bridge types. Wording used in this ERC aims for consistency with this report.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
