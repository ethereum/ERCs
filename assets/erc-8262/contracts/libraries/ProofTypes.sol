// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title ProofTypes -- Proof type definitions for ERC-8262 compliance oracle
/// @notice Defines the nine proof types and their public input schemas.
///         Each proof type corresponds to a separate Noir circuit.
library ProofTypes {
    /// @notice Proof type identifiers (one per circuit)
    uint8 internal constant COMPLIANCE = 0x01; // compliance circuit
    uint8 internal constant RISK_SCORE = 0x02; // risk_score circuit
    uint8 internal constant PATTERN = 0x03; // pattern circuit
    uint8 internal constant ATTESTATION = 0x04; // attestation circuit
    uint8 internal constant MEMBERSHIP = 0x05; // membership circuit
    uint8 internal constant NON_MEMBERSHIP = 0x06; // non_membership circuit
    /// @dev Provider-signed-signals variants close audit finding I-1. They share the
    ///      semantic of their unsigned siblings but verify an in-circuit ECDSA-secp256k1
    ///      signature of the screening-signal payload by an Oracle-registered signer.
    uint8 internal constant COMPLIANCE_SIGNED = 0x07; // compliance_signed circuit
    uint8 internal constant RISK_SCORE_SIGNED = 0x08; // risk_score_signed circuit
    /// @dev Multi-provider signed compliance. M of N (max 5) registered signers must
    ///      each individually attest the subject is below the jurisdiction's high-risk
    ///      floor. Reduces single-provider trust to M-of-N quorum.
    uint8 internal constant COMPLIANCE_MULTI_SIGNED = 0x09; // compliance_multi_signed circuit

    error InvalidProofType(uint8 proofType);
    error InvalidPublicInputLength(uint8 proofType, uint256 expected, uint256 actual);

    /// @notice Expected number of public inputs per proof type
    /// @dev Must match the `pub` parameters in each Noir circuit's main() function
    /// @param proofType The proof type identifier (0x01-0x09)
    /// @return count Number of bytes32 public inputs expected
    function expectedPublicInputCount(uint8 proofType) internal pure returns (uint256 count) {
        // compliance: jurisdiction_id, provider_set_hash, config_hash, timestamp, meets_threshold, submitter
        if (proofType == COMPLIANCE) return 6;
        // risk_score: proof_type, direction, bound_lower, bound_upper, result, config_hash, provider_set_hash, submitter
        if (proofType == RISK_SCORE) return 8;
        // pattern: analysis_type, result, reporting_threshold, time_window, tx_set_hash, submitter, settlement_root
        if (proofType == PATTERN) return 7;
        // attestation: provider_id, credential_type, is_valid, credential_root, current_timestamp, submitter
        if (proofType == ATTESTATION) return 6;
        // membership: merkle_root, set_id, timestamp, is_member, submitter
        if (proofType == MEMBERSHIP) return 5;
        // non_membership: merkle_root, set_id, timestamp, is_non_member, submitter
        if (proofType == NON_MEMBERSHIP) return 5;
        // compliance_signed: compliance fields + signer_pubkey_hash + chain_id + oracle_address
        if (proofType == COMPLIANCE_SIGNED) return 9;
        // risk_score_signed: risk_score fields + signer_pubkey_hash + chain_id + oracle_address
        if (proofType == RISK_SCORE_SIGNED) return 11;
        // compliance_multi_signed: compliance fields + threshold_m + 5 signer_pubkey_hash slots + chain_id + oracle_address
        if (proofType == COMPLIANCE_MULTI_SIGNED) return 14;
        revert InvalidProofType(proofType);
    }

    error UnalignedPublicInputs(uint256 length);

    /// @notice Validate that public inputs match expected count for a proof type
    function validatePublicInputs(uint8 proofType, bytes calldata publicInputs) internal pure {
        if (publicInputs.length % 32 != 0) revert UnalignedPublicInputs(publicInputs.length);
        uint256 expected = expectedPublicInputCount(proofType);
        uint256 actual = publicInputs.length / 32;
        if (actual != expected) {
            revert InvalidPublicInputLength(proofType, expected, actual);
        }
    }

    /// @notice Decode packed bytes into a bytes32 array for the verifier
    /// @dev Uses calldatacopy to batch-copy all slots in one operation instead of
    ///      per-slot calldata slicing. Saves ~60 gas per additional public input.
    function decodePublicInputs(bytes calldata packed) internal pure returns (bytes32[] memory inputs) {
        uint256 count = packed.length / 32;
        inputs = new bytes32[](count);
        /// @solidity memory-safe-assembly
        assembly {
            calldatacopy(add(inputs, 0x20), packed.offset, packed.length)
        }
    }

    /// @notice Check if a proof type is valid
    function isValidProofType(uint8 proofType) internal pure returns (bool valid) {
        return proofType >= COMPLIANCE && proofType <= COMPLIANCE_MULTI_SIGNED;
    }

    /// @notice Whether a proof type is a provider-signed-signals variant.
    /// @dev Used by the Oracle to enforce per-jurisdiction signed-signals policy.
    function isSignedVariant(uint8 proofType) internal pure returns (bool isSigned) {
        return proofType == COMPLIANCE_SIGNED || proofType == RISK_SCORE_SIGNED || proofType == COMPLIANCE_MULTI_SIGNED;
    }

    /// @notice Whether a proof type is the unsigned compliance/risk_score sibling
    ///         of a signed variant. PATTERN/ATTESTATION/MEMBERSHIP/NON_MEMBERSHIP
    ///         are not classified as "screening" types.
    function isUnsignedScreeningVariant(uint8 proofType) internal pure returns (bool isUnsigned) {
        return proofType == COMPLIANCE || proofType == RISK_SCORE;
    }
}
