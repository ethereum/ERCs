// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IKYATypes} from "./IKYATypes.sol";

/// @title ERC-KYA Registry (Assertions)
/// @notice Records and resolves KYA Assertions — conclusions about a subject under a scheme.
interface IKYARegistry is IKYATypes {
    event Asserted(
        bytes32 indexed assertionId,
        bytes32 indexed subjectKey,
        bytes32 indexed schemeId,
        address issuer,
        uint8 level,
        bytes32 claimDigest,
        uint64 expiresAt,
        string evidenceURI,
        bytes32 evidenceHash,
        bytes32 anchor
    );
    event Revoked(bytes32 indexed assertionId, bytes32 indexed subjectKey, address indexed revoker, uint16 reasonCode);
    event Superseded(bytes32 indexed previousAssertionId, bytes32 indexed newAssertionId);

    function getSchemeRegistry() external view returns (address);

    /// @notice ATTESTED mode. Caller is the issuer. Reverts if scheme.mode != ATTESTED.
    function attest(
        Subject calldata subject,
        bytes32 schemeId,
        uint8 level,
        bytes32 claimDigest,
        uint64 expiresAt,
        string calldata evidenceURI,
        bytes32 evidenceHash
    ) external returns (bytes32 assertionId);

    /// @notice PROVED mode (ZK-KYA). Anyone may relay; admission is decided by scheme.verifier.
    ///         Recorded issuer == verifier address (the admitting party, NOT the hidden fact issuer);
    ///         anchor == verifier-reported trust anchor; evidenceHash == keccak256(publicInputs).
    function attestWithProof(
        Subject calldata subject,
        bytes32 schemeId,
        bytes calldata publicInputs,
        bytes calldata proof,
        string calldata evidenceURI
    ) external returns (bytes32 assertionId);

    /// @notice Revoke an ACTIVE assertion. Callable by its issuer or the scheme controller.
    function revoke(bytes32 assertionId, uint16 reasonCode) external;

    function getAssertion(bytes32 assertionId) external view returns (Assertion memory);

    /// @notice The latest assertion recorded by `issuer` for (subjectKey, schemeId), or 0x0.
    function latestAssertion(bytes32 subjectKey, bytes32 schemeId, address issuer) external view returns (bytes32);

    /// @notice Ordered-Level Profile resolution: highest ACTIVE, unexpired level among `issuers`
    ///         (ties: latest issuedAt). For schemes that are not ordered, the returned assertion is
    ///         simply the latest valid one and `level` MUST be ignored by callers.
    ///         Reverts KYA_EmptyIssuers if `issuers` is empty. Returns level 0 / id 0x0 when none.
    function resolve(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)
        external
        view
        returns (uint8 level, uint64 expiresAt, bytes32 assertionId);

    function check(Subject calldata subject, bytes32 schemeId, uint8 minLevel, address[] calldata issuers)
        external
        view
        returns (bool);

    function isNullifierUsed(bytes32 schemeId, bytes32 nullifier) external view returns (bool);

    /// @notice Pure helper: keccak256(abi.encode(subjectType, subjectData)).
    function subjectKeyOf(Subject calldata subject) external pure returns (bytes32);
}
