// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./IClearSigningRegistry.sol";
import "./ClearSigningRegistryConstants.sol";
import "./MirrorListRefLib.sol";

/// @title  RegistrationHashLib — EIP-712 struct-hash helpers for createAttestations batches
/// @notice Pure hashing only; no storage access. Attach via 'using RegistrationHashLib for
///         DescriptorInfo[]' / 'RevocationEntry[]', or call the functions directly.
library RegistrationHashLib {
    using MirrorListRefLib for IClearSigningRegistry.MirrorListRef;

    /// @dev EIP-712 array-hash of 'descriptors': one descriptorInfo hash per entry
    ///      (covering the descriptor identity and the attestation reference together),
    ///      aggregated via 'keccak256(abi.encodePacked(...))'.
    function hashDescriptorInfos(IClearSigningRegistry.DescriptorInfo[] calldata descriptors)
        internal pure returns (bytes32)
    {
        uint256 descriptorCount = descriptors.length;
        bytes32[] memory descriptorInfoHashes = new bytes32[](descriptorCount);
        for (uint256 descriptorIndex = 0; descriptorIndex < descriptorCount; descriptorIndex++) {
            descriptorInfoHashes[descriptorIndex] = hashDescriptorInfo(descriptors[descriptorIndex]);
        }
        return keccak256(abi.encodePacked(descriptorInfoHashes));
    }

    /// @dev EIP-712 descriptorInfo hash of a single descriptor. 'mirrorListId' is
    ///      re-derived from 'descriptorURIs' rather than read back from storage, since
    ///      storage only keeps the attester's latest pointer per descriptor hash and
    ///      would collapse two same-'descriptorHash' entries in one batch onto the same value.
    function hashDescriptorInfo(IClearSigningRegistry.DescriptorInfo calldata descriptor)
        internal pure returns (bytes32)
    {
        return keccak256(
            abi.encode(
                ClearSigningRegistryConstants.DESCRIPTOR_TYPEHASH,
                descriptor.descriptorHash,
                descriptor.schemaMajor,
                keccak256(abi.encodePacked(descriptor.contextIds)),
                descriptor.descriptorMirrorListURIs.resolvedId(),
                descriptor.attestationId,
                hashAttestationRefs(descriptor.additionalAttestations)
            )
        );
    }

    /// @dev EIP-712 array-hash of 'additionalAttestations': one 'ATTESTATION_REF_TYPEHASH'
    ///      hash per entry, aggregated via 'keccak256(abi.encodePacked(...))'.
    function hashAttestationRefs(IClearSigningRegistry.AttestationRef[] calldata refs)
        internal pure returns (bytes32)
    {
        bytes32[] memory refHashes = new bytes32[](refs.length);
        for (uint256 refIndex = 0; refIndex < refs.length; refIndex++) {
            refHashes[refIndex] = keccak256(
                abi.encode(
                    ClearSigningRegistryConstants.ATTESTATION_REF_TYPEHASH,
                    refs[refIndex].attestationId,
                    refs[refIndex].format
                )
            );
        }
        return keccak256(abi.encodePacked(refHashes));
    }

    /// @dev EIP-712 array-hash of 'revocations': one 'REVOCATION_ENTRY_TYPEHASH' hash per
    ///      entry, aggregated via 'keccak256(abi.encodePacked(...))'.
    function hashRevocationEntries(IClearSigningRegistry.RevocationEntry[] calldata revocations)
        internal pure returns (bytes32)
    {
        uint256 count = revocations.length;
        bytes32[] memory entryHashes = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            IClearSigningRegistry.RevocationEntry calldata entry = revocations[i];
            entryHashes[i] = keccak256(
                abi.encode(
                    ClearSigningRegistryConstants.REVOCATION_ENTRY_TYPEHASH,
                    entry.attestationId,
                    keccak256(abi.encodePacked(entry.contextIds))
                )
            );
        }
        return keccak256(abi.encodePacked(entryHashes));
    }
}
