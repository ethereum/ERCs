// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title FHE Interaction Framework: authorizer of a policy version
/// @notice Answers, for one policy version of one scope, whether a subject holds a capability.
/// How the answer is reached (a table of grants, a membership list, a credential, a proof, a
/// decision of a group) is the authorizer's own business. The ledger asks and never assumes.
interface IFHEIFAuthorizer {
    /// @notice Whether `subject` holds `capability` over objects of `classId` with respect to `resource`.
    /// @param scopeId The activity scope.
    /// @param policyVersion The policy version the answer is given for.
    /// @param subject The account asked about. For a release open to everybody it is the public audience address.
    /// @param capability One of the capability identifiers.
    /// @param classId The class of the object concerned, or zero when no object is concerned.
    /// @param resource The program hash for operation capabilities, the view identifier for disclosure
    /// capabilities, the record kind for anchoring, or zero.
    function isAuthorized(
        bytes32 scopeId,
        uint64 policyVersion,
        address subject,
        bytes32 capability,
        bytes32 classId,
        bytes32 resource
    ) external view returns (bool);

    /// @notice How many separate approvals a release of `viewId` over an object of `classId` to
    /// `audience` needs before it is authorized. Zero means none.
    function requiredApprovals(bytes32 scopeId, uint64 policyVersion, bytes32 classId, bytes32 viewId, address audience)
        external
        view
        returns (uint256);
}
