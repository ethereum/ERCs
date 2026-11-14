// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @notice Canonical action envelope that `Verdict.actionCommitment` commits to.
/// @dev This preimage is NORMATIVE. Both the on-chain guarded contract and the proving
/// program MUST hash this exact struct, in this exact field order, or a proof that is valid
/// in-circuit will fail on-chain (and vice-versa). `chainId` + `domainId` are included for
/// domain separation — a commitment cannot be replayed across chains or policy domains.
/// Modelled on the way ERC-4337 canonicalises the UserOperation hash.
struct PolicyAction {
    uint256 chainId; // cross-chain replay separation
    bytes32 domainId; // cross-domain replay separation
    uint256 agentId; // ERC-8004 Identity Registry token id
    address target; // call target
    uint256 value; // wei forwarded
    bytes32 callDataHash; // keccak256(callData)
    uint256 actionNonce; // monotonic, per (domain, agent)
}

library PolicyActionLib {
    /// @notice The canonical action commitment. The proving program recomputes this as a
    /// keccak256 over the identical field ordering; do not change the encoding without
    /// re-issuing every proof.
    function commit(PolicyAction memory a) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(a.chainId, a.domainId, a.agentId, a.target, a.value, a.callDataHash, a.actionNonce)
        );
    }
}
