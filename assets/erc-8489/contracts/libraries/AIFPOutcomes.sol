// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPOutcomes
/// @notice Four-valued verification outcomes and their composition rules.
///         UNDETERMINABLE and VERIFIER_ERROR are never folded into NOT_SATISFIED.
library AIFPOutcomes {
    uint8 internal constant SATISFIED = 0; // the condition holds under the evaluated version
    uint8 internal constant NOT_SATISFIED = 1; // the condition is shown not to hold
    uint8 internal constant UNDETERMINABLE = 2; // a necessary condition cannot be verified
    uint8 internal constant VERIFIER_ERROR = 3; // a verifier reverted, timed out or misbehaved

    /// @dev allOf precedence: NOT_SATISFIED > UNDETERMINABLE > VERIFIER_ERROR > SATISFIED.
    function allOf(uint8[] memory outcomes) internal pure returns (uint8) {
        require(outcomes.length != 0, "AIFP: empty allOf");
        bool undeterminable;
        bool verifierError;
        for (uint256 i = 0; i < outcomes.length; i++) {
            uint8 o = normalize(outcomes[i]);
            if (o == NOT_SATISFIED) return NOT_SATISFIED;
            if (o == UNDETERMINABLE) undeterminable = true;
            else if (o == VERIFIER_ERROR) verifierError = true;
        }
        if (undeterminable) return UNDETERMINABLE;
        if (verifierError) return VERIFIER_ERROR;
        return SATISFIED;
    }

    /// @dev anyOf precedence: SATISFIED > UNDETERMINABLE > VERIFIER_ERROR > NOT_SATISFIED.
    function anyOf(uint8[] memory outcomes) internal pure returns (uint8) {
        require(outcomes.length != 0, "AIFP: empty anyOf");
        bool undeterminable;
        bool verifierError;
        for (uint256 i = 0; i < outcomes.length; i++) {
            uint8 o = normalize(outcomes[i]);
            if (o == SATISFIED) return SATISFIED;
            if (o == UNDETERMINABLE) undeterminable = true;
            else if (o == VERIFIER_ERROR) verifierError = true;
        }
        if (undeterminable) return UNDETERMINABLE;
        if (verifierError) return VERIFIER_ERROR;
        return NOT_SATISFIED;
    }

    /// @dev Any value outside the four codes is a misbehaving verifier.
    function normalize(uint8 outcome) internal pure returns (uint8) {
        return outcome > VERIFIER_ERROR ? VERIFIER_ERROR : outcome;
    }
}
