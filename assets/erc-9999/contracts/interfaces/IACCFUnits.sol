// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes} from "./ACCFTypes.sol";

/// @title IACCFUnits
/// @notice Cell Records, manifest commitments, control relations, exclusive claims and Transition Records.
/// @dev    Timepoints are `uint48` values in the clock domain reported by `clock()` and `CLOCK_MODE()`.
interface IACCFUnits {
    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event UnitRegistered(
        bytes32 indexed unitId,
        bytes32 indexed subjectKey,
        address indexed controller,
        bytes32 subjectType,
        bytes subjectData,
        bytes32 kind,
        uint8 rank,
        bytes32 parent,
        bytes32 lineageCommitment
    );
    event DescriptorSet(bytes32 indexed unitId, uint32 boundaryVersion, bytes32 descriptorHash, string descriptorURI);
    event EntrySet(bytes32 indexed unitId, uint8 indexed entry, bytes32 entryHash, uint32 revision);
    event RelationSet(bytes32 indexed unitId, uint8 indexed entry, uint256 dependencies);
    event ManifestSet(bytes32 indexed unitId, uint32 manifestVersion, bytes32 manifestRoot, string manifestURI);
    event Transitioned(
        bytes32 indexed transitionId,
        bytes32 indexed unitId,
        uint8 indexed kind,
        bytes32 counterpart,
        address actor,
        uint256 changed,
        ACCFTypes.OperatingState state,
        bytes32 detailsHash,
        string detailsURI
    );
    event RecoverySet(bytes32 indexed unitId, address recovery);
    event AuthorizationRevised(bytes32 indexed unitId, uint32 authorizationRevision, uint48 authorizationExpiry);
    event OperatorSet(bytes32 indexed unitId, address indexed operator, uint256 scopes, uint48 validUntil);
    event ControlProposed(
        bytes32 indexed unitId, address indexed newController, address proposer, bytes32 detailsHash, string detailsURI, uint48 expiry
    );
    event ControlProposalCancelled(bytes32 indexed unitId);
    event DerivationAllowanceSet(bytes32 indexed unitId, ACCFTypes.DerivationAllowance allowance);
    event DerivationGranted(bytes32 indexed parentId, bytes32 indexed childId, uint256 budget, bytes32[] claims);
    event SuccessionProposed(
        bytes32 indexed proposalId, bytes32 indexed predecessorId, bytes32 indexed successorId, ACCFTypes.SuccessionTerms terms
    );
    event MembershipProposed(
        bytes32 indexed proposalId,
        bytes32 indexed groupId,
        bytes32 indexed memberId,
        bool byGroup,
        bytes32 termsHash,
        string termsURI,
        uint48 expiry
    );
    event ProposalCancelled(bytes32 indexed proposalId);
    event MembershipChanged(bytes32 indexed groupId, bytes32 indexed memberId, bool member, bool memberAffected);
    event AccountApproved(bytes32 indexed unitId, address indexed account, bool approved);
    event Claimed(bytes32 indexed unitId, bytes32 indexed key);
    event Released(bytes32 indexed unitId, bytes32 indexed key);
    event ClaimMoved(bytes32 indexed fromUnitId, bytes32 indexed toUnitId, bytes32 indexed key);

    // ---------------------------------------------------------------------
    // Registration and single-unit transitions
    // ---------------------------------------------------------------------

    /// @notice Registers a unit controlled by the caller. Registration states nothing about completeness.
    function register(ACCFTypes.UnitInput calldata input) external returns (bytes32 unitId);

    /// @notice Records a migration, repair, upgrade, suspension, resumption, boundary change, retirement or
    ///         extension transition of `unitId` and applies its changes. The caller needs the scope of the kind
    ///         and the scope of every change: entries or relations, descriptor, operating state. Retirement and
    ///         extension kinds are for the controller only. Every entry listed advances its revision, also when
    ///         its commitment is unchanged or restored to an earlier value.
    function transition(bytes32 unitId, ACCFTypes.TransitionInput calldata input) external returns (bytes32 transitionId);

    // ---------------------------------------------------------------------
    // Control relation
    // ---------------------------------------------------------------------

    /// @notice Names the authority of the pre-agreed recovery rule. Controller only. Advances the authorization
    ///         revision.
    function setRecovery(bytes32 unitId, address recovery) external;

    /// @notice Grants `operator` the given scopes until `validUntil`; zero scopes revoke. Controller only.
    ///         Advances the authorization revision. Every grant ends when the control relation changes.
    function setOperator(bytes32 unitId, address operator, uint256 scopes, uint48 validUntil) external;

    /// @notice Proposes a new controller. Controller or recovery authority.
    function proposeControl(
        bytes32 unitId,
        address newController,
        bytes32 detailsHash,
        string calldata detailsURI,
        uint48 expiry
    ) external;

    /// @notice Withdraws the open control proposal. Controller or recovery authority.
    function cancelControl(bytes32 unitId) external;

    /// @notice Accepts control. Proposed controller only. A non-zero `descriptorHash` also changes the boundary.
    function acceptControl(bytes32 unitId, bytes32 descriptorHash, string calldata descriptorURI)
        external
        returns (bytes32 transitionId);

    // ---------------------------------------------------------------------
    // Derivation
    // ---------------------------------------------------------------------

    /// @notice Declares whether and within which limits `unitId` may be derived from. Controller only.
    ///         Limits inherited from the lineage cannot be widened. Advances the authorization revision.
    function setDerivationAllowance(bytes32 unitId, ACCFTypes.DerivationAllowance calldata allowance) external;

    /// @notice Derives a new unit from `parentId`. The caller is authorized for the parent and becomes the
    ///         controller of the child. The child receives no statement, no history and no claim it is not granted.
    function derive(bytes32 parentId, ACCFTypes.UnitInput calldata child, ACCFTypes.DerivationTerms calldata terms)
        external
        returns (bytes32 childId, bytes32 transitionId);

    // ---------------------------------------------------------------------
    // Succession
    // ---------------------------------------------------------------------

    /// @notice Offers the succession of `predecessorId` by `successorId` under `terms`. Predecessor side.
    function proposeSuccession(bytes32 predecessorId, bytes32 successorId, ACCFTypes.SuccessionTerms calldata terms)
        external
        returns (bytes32 proposalId);

    /// @notice Accepts a succession with the terms it was offered under. Successor side.
    function acceptSuccession(
        bytes32 proposalId,
        ACCFTypes.SuccessionTerms calldata terms,
        bytes32 successorDescriptorHash,
        string calldata successorDescriptorURI
    ) external returns (bytes32 transitionId);

    // ---------------------------------------------------------------------
    // Composition
    // ---------------------------------------------------------------------

    /// @notice Proposes that `memberId` joins `groupId`. `byGroup` tells which side the caller acts for.
    ///         `memberAffected` is read from the member side only: it declares that the membership changes the
    ///         member's resources, permissions, duties or key dependencies.
    function proposeMembership(
        bytes32 groupId,
        bytes32 memberId,
        bool byGroup,
        bool memberAffected,
        bytes32 termsHash,
        string calldata termsURI,
        uint48 expiry
    ) external returns (bytes32 proposalId);

    /// @notice Accepts a membership proposal for the other side. The group's boundary version advances; the
    ///         member's advances when the member side declared itself affected. The declaration is kept with
    ///         the membership.
    function acceptMembership(bytes32 proposalId, bool memberAffected) external returns (bytes32 transitionId);

    /// @notice Changes the member's declaration that the membership affects it. Member side. The member's
    ///         boundary version advances, so its conclusions that depend on the boundary are assessed again.
    function setMembershipDependency(
        bytes32 groupId,
        bytes32 memberId,
        bool memberAffected,
        bytes32 detailsHash,
        string calldata detailsURI
    ) external returns (bytes32 transitionId);

    /// @notice Ends a membership. Either side. The member's boundary version advances when the kept declaration
    ///         or the member side's call says the membership affects it.
    function endMembership(
        bytes32 groupId,
        bytes32 memberId,
        bool byGroup,
        bool memberAffected,
        bytes32 detailsHash,
        string calldata detailsURI
    ) external returns (bytes32 transitionId);

    /// @notice Withdraws an open succession or membership proposal. Proposing side.
    function cancelProposal(bytes32 proposalId) external;

    // ---------------------------------------------------------------------
    // Exclusive claims
    // ---------------------------------------------------------------------

    /// @notice Allows or disallows `account` to place itself inside the boundary of `unitId`. An approval holds
    ///         under the control version it was given in. Advances the authorization revision.
    function approveAccount(bytes32 unitId, address account, bool approved) external;

    /// @notice The caller places itself inside the boundary of `unitId`. An account is inside one boundary at most.
    function claimAccount(bytes32 unitId) external;

    /// @notice Declares that the resource identified by `key` is inside the boundary of `unitId`.
    function claimResource(bytes32 unitId, bytes32 key) external;

    /// @notice Releases a claim of `unitId`.
    function release(bytes32 unitId, bytes32 key) external;

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function exists(bytes32 unitId) external view returns (bool);
    function unitOf(bytes32 unitId) external view returns (ACCFTypes.Unit memory);
    function entryOf(bytes32 unitId, uint8 entry) external view returns (bytes32);

    /// @notice Revision of an entry: it advances whenever a transition sets or reconfirms the entry.
    function revisionOf(bytes32 unitId, uint8 entry) external view returns (uint32);

    /// @notice Dependency mask that `entry` was declared to depend on.
    function relationOf(bytes32 unitId, uint8 entry) external view returns (uint256);

    /// @notice `mask` closed under the declared relations of `unitId`'s entries.
    function dependencyClosure(bytes32 unitId, uint256 mask) external view returns (uint256);

    /// @notice Digest of the current values of everything the closure of `mask` names for `unitId`.
    function dependencyDigest(bytes32 unitId, uint256 mask) external view returns (bytes32);

    /// @notice Whether `account` may act for `unitId` within `scope` now.
    function isAuthorized(bytes32 unitId, address account, uint256 scope) external view returns (bool);
    function operatorOf(bytes32 unitId, address operator) external view returns (uint256 scopes, uint48 validUntil);
    function pendingControlOf(bytes32 unitId) external view returns (address newController, uint48 expiry);
    function derivationOf(bytes32 unitId) external view returns (ACCFTypes.Derivation memory);

    /// @notice Whether a derivation from `unitId` granting `budget` is permitted by the recorded authorization now.
    function derivationPermitted(bytes32 unitId, uint256 budget) external view returns (bool);
    function isMember(bytes32 groupId, bytes32 memberId) external view returns (bool);
    function membershipOf(bytes32 groupId, bytes32 memberId) external view returns (bool member, bool memberAffected);
    function claimantOf(bytes32 key) external view returns (bytes32 unitId);
    function isAccountOf(bytes32 unitId, address account) external view returns (bool);
    function accountKey(address account) external pure returns (bytes32);
    function transitionOf(bytes32 transitionId) external view returns (ACCFTypes.Transition memory);
    function transitionCount(bytes32 unitId) external view returns (uint256);
    function transitionAt(bytes32 unitId, uint256 index) external view returns (bytes32 transitionId);

}
