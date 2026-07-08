// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ClearSigningRegistryConstants — Namespacing tags and EIP-712 typehashes
/// @notice Pure constant values with no state or logic, kept in their own file so
///         ClearSigningRegistry.sol stays focused on registry behavior. The context
///         and format tags are reference values for off-chain use (wallets derive
///         context IDs and declare format tags locally per the formulas here) — the
///         registry itself never reads them, so they are not re-exposed as getters.
library ClearSigningRegistryConstants {
    bytes32 internal constant CONTEXT_TAG_CONTRACT   = keccak256("erc7730.context.contract");

    bytes32 internal constant CONTEXT_TAG_FACTORY    = keccak256("erc7730.context.factory");

    bytes32 internal constant CONTEXT_TAG_EIP712_DEP = keccak256("erc7730.context.eip712.deployment");

    bytes32 internal constant CONTEXT_TAG_EIP712_DS  = keccak256("erc7730.context.eip712.domainseparator");

    bytes32 internal constant ATTESTATION_FORMAT_EAS_OFFCHAIN = keccak256("erc7730.attestation.eas.offchain");

    bytes32 internal constant DESCRIPTOR_TYPEHASH = keccak256(
        "DescriptorInfo(bytes32 descriptorHash,uint256 schemaMajor,bytes32[] contextIds,bytes32 descriptorMirrorListId,bytes32 attestationId,bytes32 format)"
    );

    bytes32 internal constant REVOCATION_ENTRY_TYPEHASH = keccak256(
        "RevocationEntry(bytes32 attestationId,bytes32[] contextIds)"
    );

    bytes32 internal constant REGISTRATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningRegistrationBatch(DescriptorInfo[] descriptors,bytes32 attestationMirrorListId,RevocationEntry[] revocations,uint256 nonce)"
        "DescriptorInfo(bytes32 descriptorHash,uint256 schemaMajor,bytes32[] contextIds,bytes32 descriptorMirrorListId,bytes32 attestationId,bytes32 format)"
        "RevocationEntry(bytes32 attestationId,bytes32[] contextIds)"
    );

    bytes32 internal constant REVOCATION_BATCH_TYPEHASH = keccak256(
        "ClearSigningRevocationBatch(RevocationEntry[] revocations,uint256 nonce)"
        "RevocationEntry(bytes32 attestationId,bytes32[] contextIds)"
    );

    bytes32 internal constant DESCRIPTOR_MIRROR_UPDATE_TYPEHASH = keccak256(
        "DescriptorMirrorListUpdate(bytes32[] descriptorHashes,bytes32 descriptorMirrorListId,uint256 nonce)"
    );

    bytes32 internal constant ATTESTATION_MIRROR_UPDATE_TYPEHASH = keccak256(
        "AttestationMirrorListUpdate(bytes32[] attestationIds,bytes32 attestationMirrorListId,uint256 nonce)"
    );

    bytes32 internal constant ATTESTER_PROFILE_UPDATE_TYPEHASH = keccak256(
        "AttesterProfileUpdate(string profileURI,uint256 nonce)"
    );
}
