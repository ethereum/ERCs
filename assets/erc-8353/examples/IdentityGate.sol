// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "../src/VerificationGate.sol";

/// @notice External verified-depth source (e.g. an identity registry's
///         verification tier). Per the draft, the source must itself satisfy
///         no-self-assignment or the gate's guarantee is void.
interface IDepthOracle {
    function depthOf(address account) external view returns (uint256);
}

/// @title IdentityGate — identity-side adapter sketch
/// @notice Models the credential-registry shape: an issuer offers an
///         attestation about a subject; no stake anywhere (zero-stake gates
///         conform); endorsement weight is the endorser's identity-
///         verification depth read from an external oracle; claims typically
///         remain in Verified — revocable by the issuer indefinitely — and
///         `settle` is the deliberate, terminal point of no return.
contract IdentityGate is VerificationGate {
    IDepthOracle public immutable depthOracle;
    uint256 public immutable threshold;

    constructor(IDepthOracle oracle, uint256 threshold_) {
        depthOracle = oracle;
        threshold = threshold_;
    }

    /// Anonymous endorsers (depth 0) weigh nothing, however many there are.
    function weightOf(address verifier) public view override returns (uint256) {
        return depthOracle.depthOf(verifier);
    }

    function _promotionThreshold(bytes32) internal view override returns (uint256) {
        return threshold;
    }

    // _requiredStake stays 0; _canRevoke/_canSettle stay offerer-only —
    // the issuer controls both revocation and finalization.
}
