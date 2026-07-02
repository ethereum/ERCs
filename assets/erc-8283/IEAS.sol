// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ---------------------------------------------------------------------------
// Some EAS types from ethereum-attestation-service/eas-contracts
// ---------------------------------------------------------------------------

struct Signature {
    uint8   v;
    bytes32 r;
    bytes32 s;
}

struct AttestationRequestData {
    address recipient;
    uint64  expirationTime;
    bool    revocable;
    bytes32 refUID;
    bytes   data;
    uint256 value;
}

struct MultiDelegatedAttestationRequest {
    bytes32                    schema;
    AttestationRequestData[]   data;
    Signature[]                signatures;
    address                    attester;
    uint64                     deadline;
}

struct RevocationRequestData {
    bytes32 uid;
    uint256 value;
}

struct MultiDelegatedRevocationRequest {
    bytes32                   schema;
    RevocationRequestData[]   data;
    Signature[]               signatures;
    address                   revoker;
    uint64                    deadline;
}

/// @dev Minimal EAS interface required by the registry.
interface IEAS {
    struct Attestation {
        bytes32 uid;
        bytes32 schema;
        uint64  time;
        uint64  expirationTime;
        uint64  revocationTime;
        bytes32 refUID;
        address attester;
        address recipient;
        bool    revocable;
        bytes   data;
    }

    function getAttestation(bytes32 uid)
    external view returns (Attestation memory);

    function multiAttestByDelegation(
        MultiDelegatedAttestationRequest[] calldata multiDelegatedRequests
    ) external payable returns (bytes32[] memory);

    function multiRevokeByDelegation(
        MultiDelegatedRevocationRequest[] calldata multiDelegatedRequests
    ) external payable;

    /// @notice Records the revocation of an off-chain attestation UID by the caller.
    /// @param data The off-chain attestation UID to revoke.
    /// @return The revocation timestamp.
    function revokeOffchain(bytes32 data) external returns (uint64);

    /// @notice Returns the timestamp at which the given revoker revoked the given
    ///         off-chain attestation UID, or 0 if it has not been revoked.
    function getRevokeOffchain(address revoker, bytes32 data) external view returns (uint64);
}
