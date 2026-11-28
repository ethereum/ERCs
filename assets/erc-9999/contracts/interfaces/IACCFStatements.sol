// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes} from "./ACCFTypes.sol";

/// @title IACCFStatements
/// @notice Completeness Statements, evaluation policies and the derived view of cell completeness.
/// @dev    Timepoints are `uint48` values in the clock domain reported by `clock()` and `CLOCK_MODE()`.
interface IACCFStatements {
    event StatementIssued(
        bytes32 indexed statementId,
        bytes32 indexed unitId,
        bytes32 indexed profileId,
        address assessor,
        uint8 axis,
        ACCFTypes.Result result,
        uint256 coverage,
        uint256 dependencies,
        bytes32 dependencyDigest,
        bytes32 methodId,
        uint48 observedFrom,
        uint48 observedTo,
        uint48 validUntil,
        bytes32 evidenceHash,
        string evidenceURI,
        bytes32 supersedes
    );
    event EvidenceReferenced(
        bytes32 indexed statementId, address indexed adapter, address source, bytes32 recordId, bytes32 commitment
    );
    event StatementRevoked(bytes32 indexed statementId, address indexed assessor, bytes32 reasonHash);
    event PolicyRegistered(bytes32 indexed policyId, address indexed owner, bytes32 indexed profileId, ACCFTypes.PolicyInput policy);

    /// @notice Records a statement of the caller about one axis of one unit under one profile.
    function issue(ACCFTypes.StatementInput calldata input) external returns (bytes32 statementId);

    /// @notice Records several statements of the caller.
    function issueBatch(ACCFTypes.StatementInput[] calldata inputs) external returns (bytes32[] memory statementIds);

    /// @notice Revokes a statement. Its assessor only. The record is kept.
    function revoke(bytes32 statementId, bytes32 reasonHash) external;

    /// @notice Registers an immutable evaluation policy owned by the caller.
    function registerPolicy(ACCFTypes.PolicyInput calldata input) external returns (bytes32 policyId);

    function statementOf(bytes32 statementId) external view returns (ACCFTypes.Statement memory);
    function evidenceOf(bytes32 statementId) external view returns (ACCFTypes.EvidenceRef[] memory);

    /// @notice The latest statement of `assessor` that covers requirement `index`, or zero.
    function latestOf(bytes32 unitId, bytes32 profileId, address assessor, uint256 index) external view returns (bytes32);
    function policyOf(bytes32 policyId) external view returns (ACCFTypes.Policy memory);

    /// @notice Whether a statement can support a current judgment: not revoked, within its validity, with
    ///         unchanged dependencies and, when `liveEvidence` is set, with every referenced record still
    ///         supporting it. `flags` tells why not.
    function applicability(bytes32 statementId, bool liveEvidence) external view returns (bool applicable, uint32 flags);

    /// @notice The derived view of `unitId` under `policyId` at the current timepoint.
    function evaluate(bytes32 unitId, bytes32 policyId) external view returns (ACCFTypes.Evaluation memory);

    /// @notice `evaluate(unitId, policyId).cellComplete`.
    function isCellComplete(bytes32 unitId, bytes32 policyId) external view returns (bool);

    function units() external view returns (address);
    function profiles() external view returns (address);
}
