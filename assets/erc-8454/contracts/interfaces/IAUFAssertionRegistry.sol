// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {AssertionInput, Assertion, AssertionKind, ValuationCore, ObservationCore} from "../AUFTypes.sol";

/// @title AIFi Assertion Registry interface (Section 11)
/// @notice Records characterizations, observations, valuation receipts and extension assertions about
///         Unit versions under one envelope, plus content-addressed descriptors (methods, profiles, schemas).
interface IAUFAssertionRegistry {
    event DescriptorRegistered(
        bytes32 indexed descriptorHash, bytes32 indexed descriptorKind, address indexed publisher, string uri
    );
    event Asserted(
        bytes32 indexed assertionId,
        uint256 indexed unitId,
        uint32 indexed version,
        AssertionKind kind,
        address asserter,
        bytes32 profileId,
        bytes32 contentHash,
        bool byController
    );
    event ValuationAsserted(
        bytes32 indexed assertionId,
        uint256 indexed unitId,
        bytes32 indexed methodId,
        bytes32 interestId,
        uint8 resultKind,
        int256 value,
        bytes32 denominationId,
        uint64 asOf
    );
    event ObservationAsserted(
        bytes32 indexed assertionId, uint256 indexed unitId, bytes32 snapshotHash, uint64 windowStart, uint64 windowEnd
    );
    event Revoked(bytes32 indexed assertionId, address indexed asserter);
    event Superseded(bytes32 indexed assertionId, bytes32 indexed supersededBy);

    function unitRegistry() external view returns (address);

    /// @notice Registers a content-addressed descriptor (method, profile, schema). Write-once per hash.
    function registerDescriptor(bytes32 descriptorHash, bytes32 descriptorKind, string calldata uri) external;
    function descriptorOf(bytes32 descriptorHash)
        external
        view
        returns (address publisher, bytes32 descriptorKind, uint64 registeredAt, string memory uri);

    /// @notice Records an assertion made by msg.sender.
    function assertStatement(AssertionInput calldata input) external returns (bytes32 assertionId);

    /// @notice Records an assertion signed under EIP-712 by `asserter` (EOA or ERC-1271 contract).
    function assertStatementBySig(AssertionInput calldata input, address asserter, uint256 deadline, bytes calldata signature)
        external
        returns (bytes32 assertionId);

    /// @notice Revokes an active assertion. Only its asserter.
    function revoke(bytes32 assertionId) external;

    function assertionOf(bytes32 assertionId) external view returns (Assertion memory);
    function valuationCoreOf(bytes32 assertionId) external view returns (ValuationCore memory);
    function observationCoreOf(bytes32 assertionId) external view returns (ObservationCore memory);
    function assertionCount(uint256 unitId, uint32 version) external view returns (uint256);
    function assertionAt(uint256 unitId, uint32 version, uint256 index) external view returns (bytes32);
    function nonces(address asserter) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
