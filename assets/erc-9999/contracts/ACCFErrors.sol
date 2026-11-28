// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title ACCFErrors
/// @notice Errors of the ACCF reference contracts.
interface ACCFErrors {
    // units
    error UnknownUnit(bytes32 unitId);
    error NotAuthorized(bytes32 unitId, address account);
    error Retired(bytes32 unitId);
    error InvalidEntries();
    error InvalidState();
    error InvalidKind(uint8 kind);
    error InvalidRank();
    error DescriptorRequired();
    error DetailsRequired();
    error NothingChanged();
    error UnexpectedChange();
    error OutstandingRelations(bytes32 unitId);
    error ProposalNotOpen(bytes32 proposalId);
    error TermsMismatch();
    error NotMember(bytes32 groupId, bytes32 memberId);
    error AlreadyMember(bytes32 groupId, bytes32 memberId);
    error DerivationNotPermitted(bytes32 unitId);
    error DerivationLimit(bytes32 unitId, uint8 limit);
    error AllowanceWidened(uint8 limit);
    error AlreadyClaimed(bytes32 key, bytes32 unitId);
    error NotClaimed(bytes32 key, bytes32 unitId);
    error InvalidClaimKey(bytes32 key);
    error AccountNotApproved(bytes32 unitId, address account);
    error InvalidExpiry();
    error InvalidAddress();
    error SameUnit();

    // profiles
    error UnknownProfile(bytes32 profileId);
    error ProfileExists(bytes32 profileId);
    error InvalidRequirement(uint256 index);
    error TooManyRequirements();
    error BaselineClassMissing(uint8 classId);
    error BaselineDependencyOmitted(uint256 index, uint8 classId);
    error BaselineConditional(uint256 index, uint8 classId);
    error CoverageOffAxis(uint256 coverage);
    error NotPublisher(bytes32 profileId, address caller);

    // statements and policies
    error UnknownStatement(bytes32 statementId);
    error UnknownPolicy(bytes32 policyId);
    error InsufficientGas();
    error EmptyCoverage();
    error DependencyOmitted(uint256 required, uint256 given);
    error InvalidDependencies(uint256 dependencies);
    error NotApplicableRefused();
    error EntryMissing(uint256 missing);
    error InvalidWindow();
    error WindowPrecedesUnit(uint48 observedFrom, uint48 bornAt);
    error StateChanged(bytes32 expectedDigest, bytes32 currentDigest);
    error InvalidValidity();
    error TooManyReferences();
    error InvalidSupersedes(bytes32 statementId);
    error NotAssessor(bytes32 statementId, address caller);
    error AlreadyRevoked(bytes32 statementId);
    error InvalidPolicy();
}
