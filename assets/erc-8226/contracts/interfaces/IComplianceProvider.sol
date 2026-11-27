// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IComplianceProvider is IERC165 {
    enum ReasonCode {
        COMPLIANT, // 0
        KYC_EXPIRED, // 1
        AML_FLAG, // 2
        NOT_ACCREDITED, // 3
        NOT_QUALIFIED, // 4
        JURISDICTION_BLOCKED, // 5
        IDENTITY_NOT_FOUND, // 6
        ATTESTATION_REVOKED, // 7
        OTHER // 8
    }

    /// @notice Emitted when a principal is granted eligibility.
    event PrincipalGranted(address indexed principal, bytes32 indexed identityRef);

    /// @notice Emitted when a previously eligible principal is revoked.
    event PrincipalRevoked(address indexed principal, bytes32 indexed identityRef, ReasonCode reason);

    /// @notice Grants eligibility to a principal.
    /// @param principal The on-chain address of the principal.
    /// @param identityRef An off-chain identity reference (e.g., keccak256 of a Decentralized Identifier (DID) or attestation ID).
    /// @param expiresAt Unix timestamp at which the eligibility ends. 0 means no expiry.
    function grantPrincipal(address principal, bytes32 identityRef, uint48 expiresAt) external;

    /// @notice Revokes a principal's eligibility.
    /// @param principal The on-chain address of the principal.
    /// @param reason The reason for revocation.
    function revokePrincipal(address principal, ReasonCode reason) external;

    /// @notice Returns eligibility of a principal.
    /// @param principal The on-chain address of the principal.
    /// @param identityRef An off-chain identity reference (e.g., keccak256 of a Decentralized Identifier (DID) or attestation ID).
    /// @return eligible True if the principal is compliant.
    /// @return reason Reason code. MUST be COMPLIANT when eligible is true.
    /// @return expiresAt Unix timestamp at which the eligibility ends. 0 means no expiry when eligible is true; when
    ///         eligible is false the value carries no meaning, so consumers MUST read eligible and reason first.
    function checkPrincipal(address principal, bytes32 identityRef)
        external
        view
        returns (bool eligible, ReasonCode reason, uint48 expiresAt);
}
