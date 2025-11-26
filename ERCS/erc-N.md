---
title: Associated Accounts
description: A way to publicly associate two accounts with arbitrary contextual data
authors: Steve Katzman (@stevieraykatz), Amie Corso (@amiecorso), Stephan Cilliers (@stephancill)
discussions-to:
status: Draft
type: Standards Track
category: ERC
created: 2025-11-25
requires: EIP-712, ERC-1271, ERC-5267, ERC-6492, ERC-7930
---

## Abstract
This specification defines a standard for establishing and verifying associations between blockchain accounts. This allows addresses to publicly declare, prove and revoke a relationship with other addresses by sharing a standardized payload. For onchain applications, this payload may be signed by both parties for third-party authentication. This enables use cases like sub-account identity inheritance, authorization delegation, and reputation collation. 

## Motivation 
A key motivation is the simplification of multi-address resolution, which is essential for managing complex digital identities across multiple platforms and accounts. This simplification aims to streamline the process of locating and verifying individuals or entities by efficiently handling multiple addresses linked by Associations. 
By providing a standard mechanism for signaling an association between two accounts, this standard unlocks the capability to link the activities or details of these accounts. 

The inclusion of arbitrary data into the specified payload ensures flexibility for various use cases such as delegation, hierarchical relationships, and authentication. By maintaining a flexible architecture that accepts an interface identifier paired with arbitrary data bytes, accounts that associate can do so with application-specific context. 

## Overview
The system outlined in this document describes a way for two accounts to be linked by a specified data struct which describes the relationship between them. It offers the mechanism by which these parties can sign over the contents to prove validity. It focuses on the structure and process for generating, validating and revoking such records while maintaining an implementation agnostic approach. 

## Specification
The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “NOT RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Core Concepts
Each Association between two accounts denotes the participating addresses as `initiator` and `approver`. These accounts can be on disparate chains with different architectures made possible by a combination of [ERC-7930 Interoperable Addresses](https://eips.ethereum.org/EIPS/eip-7930) and an enumeration of signature key types. To accommodate non-EVM account types, addresses are recorded in the association as raw bytes.

The specification outlines a nested structure for recording Associations:
1. An underlying Associated Account Record (AAR) for storing accounts, timestamps and association context
2. A wrapper Signed Association Record (SAR) structure for storing signature and validation data

### Associated Account Record
The following is a Solidity implementation of an `AssociatedAccountRecord` which contains the shared payload describing the association.

```solidity
/// @notice Represents an association between two accounts.
struct AssociatedAccountRecord {
    /// @dev The ERC-7930 binary representation of the initiating account's address.
    bytes initiator;
    /// @dev The ERC-7930 binary representation of the approving account's address.
    bytes approver;
    /// @dev The timestamp from which the association is valid.
    uint40 validAt;
    /// @dev The timestamp when the association expires.
    uint40 validUntil;
    /// @dev Optional 4-byte selector for interfacing with the `data` field.
    bytes4 interfaceId;
    /// @dev Optional additional data.
    bytes data;
}
```
Where the AssociatedAccountRecord contains: 
- `initiator` is the binary representation of an ERC-7930 address for the initiating account. 
- `approver` is the binary representation of an ERC-7930 address for the approving account.
- `validAt` is the timestamp from which the association is valid.
- `validUntil` is the timestamp at which the association expires (optional).
- `interfaceId` is the 4-byte interface or method selector for the `data` field (optional).
- `data` is the arbitrary context data payload (optional).

### Signed Association Record
When public declaration of validity is desired, one or both of the accounts MAY sign over the Associated Account Record. The EIP-712 hash (see Support for EIP-712 below) of the `AssociatedAccountRecord` can be signed by the initiating and approving accounts. The resulting signatures are included in a `SignedAssociationRecord`: 

```solidity
    /// @notice Complete payload containing a finalized association.
    struct SignedAssociationRecord {
        /// @dev The timestamp the association was revoked.
        uint40 revokedAt;
        /// @dev The initiator key type specifier.
        bytes2 initiatorKeyType;
        /// @dev The approver key type specifier.
        bytes2 approverKeyType;
        /// @dev The signature of the initiator.
        bytes initiatorSignature;
        /// @dev The signature of the approver.
        bytes approverSignature;
        /// @dev The underlying AssociatedAccountRecord.
        AssociatedAccountRecord record;
    }
```
Where the SignedAssociationRecord contains: 
- `revokedAt` is the timestamp when the association was revoked, which is `0` unless the association has been revoked by either party. 
- `initiatorSignature` is the signature bytes generated by the `initiator` by signing the EIP-712 compliant hash of the AssociatedAccountRecord.
- `initiatorKeyType` is the key type designator for the initiator's signature (see Key Types below).
- `approverSignature` is the signature bytes generated by the `approver` by signing the EIP-712 compliant hash of the AssociatedAccountRecord.
- `approverKeyType` is the key type designator for the approver's signature (see Key Types below).
- `record` is the AssociatedAccountRecord that was signed by both parties. 

### Key Types
To accommodate known curves and signing protocols while providing future extensibility, this specification relies on the enumeration of cryptographic curves and signing protocols. Each signature MUST be paired with a valid "Key ID" designator.

The Key IDs SHALL be identified as a 2-byte integer according to the following extensible table. We accommodate two types of keys:
1. Applied cryptographic curves (i.e. secp256k1)
2. Protocol integrations (i.e. WebAuthn, contract validation)

To distinguish these key types, the most significant bit in the 2-byte identifier SHALL be used as a bit flag. As such, key type protocols are constructed by bitwise OR: 
`0x8000 | PROTOCOL_ID`. 

The resulting table enumerates the known keys and distinguishes between the two types: 

| Key ID | Type | Curve/Standard |
| -------- | -------- | -------- |
| 0x0000 | Delegated | Delegated auth | 
| 0x0001 | K1 | secp256k1 |
| 0x0002 | R1 | secp256r1 |
| 0x0003 | BLS | BLS12-381 |
| 0x0004 | EdDSA | Ed25519 |
| 0x8001 | WebAuthn | WebAuthn/Passkey |
| 0x8002 | ERC-1271 | Contract validation |
| 0x8003 | ERC-6492 | Predeploy contract validation |

#### Delegated Auth
In some contexts it might be ergonomic to delegate authorization to another account, address, or external protocol. Implementers leveraging the `Delegated` key type MUST also publish a standard mechanism for parsing and accommodating the application-specific delegation schema.

### Support for EIP-712
All signatures contained in this specification MUST comply with EIP-712 wherein the signature pre-image can be generated from:

```solidity
keccak256(abi.encodePacked(
   hex"1901",
   DOMAIN_SEPARATOR,
   keccak256(abi.encode(
    keccak256("AssociatedAccountRecord(bytes initiator,bytes approver,uint40 validAt,uint40 validUntil,bytes4 interfaceId,bytes data)"),
    keccak256(initiator), 
    keccak256(approver),
    validAt,
    validUntil,
    interfaceId,
    keccak256(data)
    ))
))
```

Where `DOMAIN_SEPARATOR` is defined according to EIP-712. The `DOMAIN_SEPARATOR` for this ERC SHALL be defined as: 
```solidity
keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version)"),
    keccak256(bytes("AssociatedAccounts")),
    keccak256(bytes("1"))
))
```

### Onchain Storage
If desired, a `SignedAssociationRecord` MAY be stored onchain in a context-specific storage contract.

An onchain storage contract SHALL comply with the following steps: 
1. The SAR MUST be validated according to the steps detailed in the Validation section. 
2. The contract MUST emit the `AssociationCreated` event:

```solidity
    event AssociationCreated(
        bytes32 indexed hash, bytes32 indexed initiator, bytes32 indexed approver, SignedAssociationRecord sar
    );
```
where:
- `hash` is the indexed hash for the SignedAssociationRecord, equivalent to the EIP-712 hash of the underlying AAR.
- `initiator` is the keccak256 hash of the ERC-7930 address of the account that initiated the association.
- `approver` is the keccak256 hash of the ERC-7930 address of the account that accepted and completed the association.
- `sar` is the completed SignedAssociationRecord. 

If a SignedAssociationRecord is stored onchain, it MUST also be revokable onchain (see Revocation) below. 

### Offchain Storage
In some contexts, it might be desirable for Signed Association Records to be stored in an offchain store. While the implementation will differ from application-to-application, the following considerations SHOULD be taken into account:
- Access to this data store MUST be made available to all expected consumers through publicly accessible endpoints
- The store MUST perform validation on incoming Associations before storage 
- The location of this offchain store SHOULD be searchable by some standard fetching mechanism, e.g. a text record on an ENS name

### Validation
Clients or contracts determining whether a SignedAssociationRecord is valid at the time of consumption MUST check all of the following validation steps:
1. The current timestamp MUST be greater than or equal to the `validAt` timestamp.
2. If the `validUntil` timestamp is nonzero, the current timestamp MUST be less than the `validUntil` timestamp. 
3. If the `revokedAt` timestamp is nonzero, the current timestamp MUST be less than the `revokedAt` timestamp.
4. If the `initiatorSignature` field is populated, the signature MUST be valid for the EIP-712 preimage of the underlying `AssociatedAccountRecord` using an appropriate `initiatorKeyType` validation mechanism. 
5. If the `approverSignature` field is populated, the signature MUST be valid for the EIP-712 preimage of the underlying `AssociatedAccountRecord` using an appropriate `approverKeyType` validation mechanism.

Onchain validation is possible as long as there are sufficient validation mechanisms for the various key types used by the two accounts. In the case that validation occurs onchain, implementations MUST replace "current timestamp" with `block.timestamp`. 

### Revocation
Onchain Association stores MUST implement a revocation method. This method MUST allow either party of an Association to revoke a valid, active association by submitting a revocation request. 

In such contexts, storage contracts MUST update the `revokedAt` field of the SAR to `block.timestamp` OR the account-specified revocation timestamp, whichever is greater. Then the implementation contract MUST emit the following event upon accepting a valid revocation request: 
```solidity
    event AssociationRevoked(bytes32 indexed hash, bytes32 indexed revokedBy, uint256 revokedAt);
```
where: 
- `hash` is the indexed unique identifier for the association, equivalent to the EIP-712 hash of the underlying AAR.
- `revokedBy` is the indexed keccak256 hash of the ERC-7930 address of the revoking account.
- `revokedAt` is the timestamp at which the association is revoked.

Offchain stores MUST allow either account to revoke a stored association and MUST update the `revokedAt` timestamp accordingly.

## Security Considerations
For onchain applications, the validation mechanisms for some key types might be gas-cost prohibitive or entirely unavailable. It is the responsibility of the integrator to ensure that unsupported key types are appropriately handled given these constraints.

Offchain stores expose a trust vector to consumers. Integrators and consumers MUST take into account this centralization vector and expose the risk to users or offer mechanisms for minimizing the trust assumptions (i.e. storing some state onchain).

Associations SHOULD have a canonical storage location given an application. However, in the event that the same Association data is stored both on and offchain, precedence SHOULD be given to the onchain data. 

## Copyright
Copyright and related rights waived via [CC0](https://eips.ethereum.org/LICENSE).