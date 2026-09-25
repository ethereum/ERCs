// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IERC8262Oracle} from "../interfaces/IERC8262Oracle.sol";

/// @title EIP712Attestation -- EIP-712 typed data hashing for ComplianceAttestation
/// @notice Enables off-chain attestation verification with structured wallet display.
///         Integrators can use this to build signature-based relaying or off-chain
///         attestation verification without raw byte inspection.
library EIP712Attestation {
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 internal constant ATTESTATION_TYPEHASH = keccak256(
        "ComplianceAttestation(address subject,uint8 jurisdictionId,uint8 proofType,bool meetsThreshold,uint256 timestamp,uint256 expiresAt,bytes32 proofHash,bytes32 providerSetHash,bytes32 publicInputsHash,address verifierUsed)"
    );

    /// @notice Compute the EIP-712 domain separator for an oracle instance
    /// @dev Uses block.chainid at call time (not cached) so the separator stays
    ///      correct after a chain fork.
    /// @param verifyingContract The oracle contract address
    /// @return domainSeparator The domain separator hash
    function buildDomainSeparator(address verifyingContract) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH, keccak256("ERC8262Oracle"), keccak256("1"), block.chainid, verifyingContract
            )
        );
    }

    /// @notice Hash a ComplianceAttestation struct per EIP-712
    /// @param att The attestation to hash
    /// @return structHash The struct hash
    function hashAttestation(IERC8262Oracle.ComplianceAttestation memory att) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ATTESTATION_TYPEHASH,
                att.subject,
                att.jurisdictionId,
                att.proofType,
                att.meetsThreshold,
                att.timestamp,
                att.expiresAt,
                att.proofHash,
                att.providerSetHash,
                att.publicInputsHash,
                att.verifierUsed
            )
        );
    }

    /// @notice Compute the full EIP-712 digest for an attestation
    /// @param domainSeparator The domain separator (cache via buildDomainSeparator)
    /// @param att The attestation
    /// @return digest The EIP-712 digest (ready for ecrecover)
    function toTypedDataHash(bytes32 domainSeparator, IERC8262Oracle.ComplianceAttestation memory att)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, hashAttestation(att)));
    }
}
