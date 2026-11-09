// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title IAgentMeditation
/// @notice Minimal on-chain interface of the Agent Meditation Mechanism: attributable,
///         versioned registration of an agent's own self-maintenance across four fixed
///         layers (runtime; memory and skills; tasks and roles; cognition).
/// @dev    All timepoints are `uint48` values in the clock domain reported by `clock()` /
///         `CLOCK_MODE()` (ERC-6372). Layer indices are 0..3; layer bitmasks use bit `1 << layer`.
interface IAgentMeditation {
    // ---------------------------------------------------------------------
    // Enumerations and bit layouts
    // ---------------------------------------------------------------------

    /// @notice Whole-cycle outcome declared by the submitter.
    /// COMPLETED: every scoped layer completed its routine.
    /// PARTIAL:   some but not all scoped layers completed their routine.
    /// ABORTED:   the cycle was stopped before every scoped layer completed (budget, time, interruption).
    /// FAILED:    no scoped layer completed its routine.
    enum Outcome {
        COMPLETED,
        PARTIAL,
        ABORTED,
        FAILED
    }

    /// @notice Maintenance timeliness of one layer, derived from checkpoints and requirements.
    enum MaintenanceStatus {
        NOT_ENROLLED,
        UNSUPPORTED, // not required and not supported by the current policy
        UNSCHEDULED, // supported, but no timeliness requirement applies
        FRESH,
        DUE,
        OVERDUE
    }

    /// @notice Activity-signal status, independent from maintenance timeliness.
    enum SignalStatus {
        NOT_ENROLLED,
        NOT_TRACKED, // no pulse interval in effect
        PRESENT,
        SILENT
    }

    // ---------------------------------------------------------------------
    // Structures
    // ---------------------------------------------------------------------

    /// @notice Versioned maintenance policy declared by the subject.
    struct Policy {
        bytes32 policyHash; // commitment to the off-chain policy document (may be zero)
        string policyURI; // optional locator of the policy document
        uint8 supportedLayers; // bitmask of layers the subject maintains
        uint8 requiredLayers; // bitmask of layers with a timeliness requirement (subset of supportedLayers)
        uint8 allowedTriggers; // bitmask over trigger codes (1 << trigger)
        uint8 disclosure; // 0 = commitment only, 1 = summary, 2 = full (descriptive)
        uint48 dueWindow; // warning window before a deadline
        uint48 pulseInterval; // 0 = activity signal not tracked
        uint48[4] maxInterval; // per-layer maximum interval between completions (required layers)
    }

    /// @notice Minimum requirements set by the controller; combined with the policy by `requirementsOf`.
    struct Floor {
        uint8 requiredLayers;
        uint48 pulseInterval;
        uint48[4] maxInterval;
    }

    /// @notice One maintenance cycle record.
    struct CycleReport {
        uint64 baseVersion; // state version the cycle was computed against
        bytes32 preRoot; // state root the cycle was computed against
        bytes32[4] postCommitments; // layer commitments after the cycle (all four layers)
        uint8 layerMask; // layers in scope
        uint8 completedLayers; // layers whose routine was completed (subset of layerMask)
        uint16 opsMask; // 4 operations x 4 layers, bit (layer * 4 + op); only scoped layers
        uint8 outcome; // Outcome
        uint8 trigger; // 0 SCHEDULED, 1 EVENT, 2 COMMANDED, 3 SELF
        uint32 policyVersion; // policy version in effect when the cycle started
        uint48 reportedStartedAt; // self-reported
        uint48 reportedEndedAt; // self-reported; completion time of every completed layer
        uint48 nextPlannedAt; // planning hint, 0 = none
        uint64 restoresVersion; // non-zero when the post state restores an earlier state version
        bytes32 recordHash; // commitment to the off-chain cycle record document (may be zero)
        string recordURI; // optional locator of the cycle record document
    }

    /// @notice Per-layer checkpoint.
    struct LayerCheckpoint {
        bytes32 commitment; // current registered state commitment
        uint48 lastCompletedAt; // reported completion time of the last completed routine (0 = never)
        uint48 lastCompletedRecordedAt; // clock value when that completion was recorded
        uint32 completedUnderPolicy; // policy version governing that completion
        uint64 lastChangedVersion; // state version at which the commitment last changed
    }

    /// @notice Per-subject head record.
    struct Head {
        bool enrolled;
        address controller;
        uint8 controllerRights;
        uint32 policyVersion;
        uint32 floorVersion;
        uint64 stateVersion;
        uint64 recordCount; // cycle records and pulses
        bytes32 root;
        uint48 enrolledAt;
        uint48 lastSignalAt;
        uint48 nextPlannedAt;
    }

    /// @notice Outstanding controller demand for one layer.
    struct Demand {
        uint48 demandedAt; // 0 = none
        uint48 dueBy;
    }

    /// @notice Effective requirements (policy combined with floor).
    struct Requirements {
        uint8 supportedLayers;
        uint8 requiredLayers;
        uint48 dueWindow;
        uint48 pulseInterval;
        uint48[4] maxInterval;
    }

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event Enrolled(
        address indexed subject, address indexed controller, uint8 controllerRights, bytes32 root, uint48 enrolledAt
    );
    event ControllerChanged(
        address indexed subject, address indexed previousController, address indexed newController, uint8 rights
    );
    event OperatorSet(address indexed subject, address indexed operator, uint8 permissions, address indexed by);
    event PolicyUpdated(
        address indexed subject, uint32 indexed version, bytes32 policyHash, uint48 effectiveFrom, address by
    );
    event FloorUpdated(address indexed subject, uint32 indexed version, uint48 effectiveFrom, address by);
    event Demanded(address indexed subject, uint8 layerMask, uint48 dueBy, address by);
    event DemandWithdrawn(address indexed subject, uint8 layerMask, address by);
    event CycleRecorded(
        address indexed subject,
        uint64 indexed seq,
        uint64 baseVersion,
        uint64 newVersion,
        CycleReport report,
        uint8 changedLayers,
        uint48 recordedAt,
        address submitter
    );
    event LayerCommitmentChanged(
        address indexed subject,
        uint8 indexed layer,
        uint64 indexed version,
        bytes32 previousCommitment,
        bytes32 newCommitment
    );
    event Pulsed(
        address indexed subject, uint64 indexed seq, uint48 recordedAt, uint48 nextPlannedAt, address submitter
    );

    // ---------------------------------------------------------------------
    // Enrollment and authorization
    // ---------------------------------------------------------------------

    /// @notice Enroll `msg.sender` with a four-layer baseline, an initial policy and an optional controller.
    function enroll(bytes32[4] calldata baseline, Policy calldata policy, address controller, uint8 controllerRights)
        external;

    /// @notice Grant or revoke an operator of `msg.sender` (permissions 0 revokes).
    function setOperator(address operator, uint8 permissions) external;

    /// @notice Revoke an operator of `subject`; callable by the subject or by a controller holding RIGHT_REVOKE_OPERATORS.
    function revokeOperator(address subject, address operator) external;

    /// @notice Set, transfer, shrink or renounce the controller of `subject` (see the specification for who may call).
    function setController(address subject, address newController, uint8 rights) external;

    // ---------------------------------------------------------------------
    // Policy, floor, demand
    // ---------------------------------------------------------------------

    /// @notice Record a new policy version for `subject`; callable by the subject or an operator holding PERM_POLICY.
    function setPolicy(address subject, Policy calldata policy) external;

    /// @notice Record a new floor version for `subject`; callable by a controller holding RIGHT_FLOOR.
    function setFloor(address subject, Floor calldata floor) external;

    /// @notice Demand completion of `layerMask` by `dueBy`; callable by a controller holding RIGHT_DEMAND.
    function demand(address subject, uint8 layerMask, uint48 dueBy) external;

    /// @notice Withdraw outstanding demands for `layerMask`; callable by the controller.
    function withdrawDemand(address subject, uint8 layerMask) external;

    // ---------------------------------------------------------------------
    // Records
    // ---------------------------------------------------------------------

    /// @notice Record one maintenance cycle for `subject`; callable by the subject or an operator holding PERM_REPORT.
    function report(address subject, CycleReport calldata r) external returns (uint64 seq);

    /// @notice Record an activity signal for `subject`; callable by the subject or an operator holding PERM_PULSE or PERM_REPORT.
    function pulse(address subject, uint48 nextPlannedAt) external returns (uint64 seq);

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function headOf(address subject) external view returns (Head memory);
    function checkpointOf(address subject, uint8 layer) external view returns (LayerCheckpoint memory);
    function rootAt(address subject, uint64 stateVersion) external view returns (bytes32);
    function policyOf(address subject, uint32 version) external view returns (Policy memory);
    function policyEffectiveFrom(address subject, uint32 version) external view returns (uint48);
    function floorOf(address subject) external view returns (Floor memory);
    function demandOf(address subject, uint8 layer) external view returns (Demand memory);
    function operatorPermissions(address subject, address operator) external view returns (uint8);
    function requirementsOf(address subject) external view returns (Requirements memory);

    /// @notice Maintenance timeliness of one layer, the deadline it is judged against (0 if none) and whether
    ///         the layer has never completed a routine since enrollment.
    function layerStatus(address subject, uint8 layer)
        external
        view
        returns (MaintenanceStatus status, uint48 deadline, bool neverCompleted);

    /// @notice Activity-signal status. `silentSince` is the timepoint the signal became silent (0 if not silent).
    function signalStatus(address subject)
        external
        view
        returns (SignalStatus status, uint48 lastSignalAt, uint48 silentSince);

    /// @notice Pure helper: state root over four layer commitments.
    function computeRoot(bytes32[4] calldata commitments) external pure returns (bytes32);

    /// @notice Pure helper: layer commitment from its components.
    function computeLayerCommitment(uint8 layer, bytes32 schemaHash, bytes32 contentHash, bytes32 salt)
        external
        pure
        returns (bytes32);
}
