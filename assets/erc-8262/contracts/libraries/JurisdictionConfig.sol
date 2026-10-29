// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title JurisdictionConfig -- Jurisdiction threshold definitions for ERC-8262
/// @notice Defines risk score thresholds per jurisdiction as specified in the ERC
library JurisdictionConfig {
    /// @notice Jurisdiction identifiers
    uint8 internal constant EU = 0; // AMLD6
    uint8 internal constant US = 1; // BSA
    uint8 internal constant UK = 2; // MLR
    uint8 internal constant SINGAPORE = 3;
    uint8 internal constant UAE = 4; // VARA

    /// @notice Risk tiers
    uint8 internal constant TIER_LOW = 0;
    uint8 internal constant TIER_MEDIUM = 1;
    uint8 internal constant TIER_HIGH = 2;

    error InvalidJurisdiction(uint8 jurisdictionId);

    /// @notice Threshold boundaries for a jurisdiction
    /// @dev Scores are 0-100 (percentage scale). The Noir circuits use basis points (0-10000);
    ///      a Solidity value of 71 corresponds to 7100 bps in the circuit. Both representations
    ///      encode the same percentage (71%).
    ///      Low: [0, mediumFloor-1], Medium: [mediumFloor, highFloor-1], High: [highFloor, 100]
    struct Thresholds {
        uint8 mediumFloor; // score >= this enters medium tier
        uint8 highFloor; // score >= this enters high tier (filing trigger)
    }

    /// @notice Get the threshold configuration for a jurisdiction
    /// @param jurisdictionId The jurisdiction (0=EU, 1=US, 2=UK, 3=SG, 4=UAE)
    /// @return thresholds The threshold boundaries
    function getThresholds(uint8 jurisdictionId) internal pure returns (Thresholds memory thresholds) {
        if (jurisdictionId == EU) return Thresholds({mediumFloor: 31, highFloor: 71});
        if (jurisdictionId == US) return Thresholds({mediumFloor: 26, highFloor: 66});
        if (jurisdictionId == UK) return Thresholds({mediumFloor: 31, highFloor: 71});
        if (jurisdictionId == SINGAPORE) return Thresholds({mediumFloor: 36, highFloor: 76});
        if (jurisdictionId == UAE) return Thresholds({mediumFloor: 31, highFloor: 71});
        revert InvalidJurisdiction(jurisdictionId);
    }

    /// @notice Determine the risk tier for a given score and jurisdiction
    /// @param score The risk score (0-100)
    /// @param jurisdictionId The jurisdiction to evaluate against
    /// @return tier The risk tier (0=low, 1=medium, 2=high)
    function getRiskTier(uint8 score, uint8 jurisdictionId) internal pure returns (uint8 tier) {
        Thresholds memory t = getThresholds(jurisdictionId);
        if (score >= t.highFloor) return TIER_HIGH;
        if (score >= t.mediumFloor) return TIER_MEDIUM;
        return TIER_LOW;
    }

    /// @notice Check if a score meets the compliance threshold (below high risk)
    /// @dev Not used by the Oracle (threshold check happens in the ZK circuit).
    ///      Provided for off-chain consumers and integrators who need to replicate
    ///      the threshold logic without generating a proof.
    /// @param score The risk score (0-100, percentage scale)
    /// @param jurisdictionId The jurisdiction to evaluate against
    /// @return compliant Whether the score is below the high-risk filing trigger
    function meetsThreshold(uint8 score, uint8 jurisdictionId) internal pure returns (bool compliant) {
        Thresholds memory t = getThresholds(jurisdictionId);
        return score < t.highFloor;
    }

    /// @notice Validate that a jurisdiction ID is valid
    /// @param jurisdictionId The jurisdiction to validate
    function validateJurisdiction(uint8 jurisdictionId) internal pure {
        if (jurisdictionId > UAE) {
            revert InvalidJurisdiction(jurisdictionId);
        }
    }

    /// @notice Get the high-risk threshold for a jurisdiction (used as public circuit input)
    /// @param jurisdictionId The jurisdiction
    /// @return threshold The score at or above which filing is triggered
    function getHighRiskThreshold(uint8 jurisdictionId) internal pure returns (uint8 threshold) {
        return getThresholds(jurisdictionId).highFloor;
    }

    /// @notice Whether the jurisdiction requires provider-signed screening signals.
    /// @dev When true, the Oracle accepts only the signed proof-type variants
    ///      (COMPLIANCE_SIGNED, RISK_SCORE_SIGNED) and rejects unsigned (COMPLIANCE,
    ///      RISK_SCORE) submissions. Closes audit finding I-1 (signal honesty) for
    ///      strict-mode jurisdictions while preserving the cheaper unsigned path for
    ///      jurisdictions that do not require provider attestation.
    ///
    ///      Initial values reflect each regime's traceability stance:
    ///      - EU AMLD6, UK MLR: unsigned acceptable (provider attestation layered off-chain)
    ///      - US BSA, Singapore, UAE VARA: signed required (regulator demands provider-signed evidence)
    ///
    ///      Changing this is a breaking-change for integrators in that jurisdiction;
    ///      it is intentionally hard-coded rather than admin-mutable. A future revision
    ///      may move it to a registry if jurisdiction policy diverges from this default.
    /// @param jurisdictionId The jurisdiction (0=EU, 1=US, 2=UK, 3=SG, 4=UAE)
    /// @return required Whether signed signals are required
    function requireSignedSignals(uint8 jurisdictionId) internal pure returns (bool required) {
        if (jurisdictionId == EU) return false;
        if (jurisdictionId == US) return true;
        if (jurisdictionId == UK) return false;
        if (jurisdictionId == SINGAPORE) return true;
        if (jurisdictionId == UAE) return true;
        revert InvalidJurisdiction(jurisdictionId);
    }

    /// @notice Minimum number of distinct providers required for a multi-signed
    ///         compliance proof (proof type 0x09) in this jurisdiction.
    /// @dev 1 means single-signer attestation is sufficient (the proof is then
    ///      operationally equivalent to 0x07). Values >= 2 force genuine M-of-N
    ///      corroboration. Stricter regimes (US BSA, Singapore MAS, UAE VARA)
    ///      demand >= 2 independent providers; permissive regimes (EU AMLD6,
    ///      UK MLR) accept 1.
    ///      Like `requireSignedSignals`, this is a regulatory parameter compiled
    ///      into the contract by design.
    /// @param jurisdictionId The jurisdiction (0=EU, 1=US, 2=UK, 3=SG, 4=UAE)
    /// @return floor Minimum M (1..MAX) required for multi-signed proofs
    function minMultiProviderThreshold(uint8 jurisdictionId) internal pure returns (uint8 floor) {
        if (jurisdictionId == EU) return 1;
        if (jurisdictionId == US) return 2;
        if (jurisdictionId == UK) return 1;
        if (jurisdictionId == SINGAPORE) return 2;
        if (jurisdictionId == UAE) return 2;
        revert InvalidJurisdiction(jurisdictionId);
    }
}
