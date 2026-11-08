// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {IAgentMeditation} from "./IAgentMeditation.sol";
import {IERC165} from "./IERC165.sol";
import {IERC6372} from "./IERC6372.sol";

/// @title AgentMeditationRegistry
/// @notice Reference implementation of the Agent Meditation Mechanism kernel.
/// @dev    Single clock domain: `mode=timestamp`. Storage keeps one head record, four layer
///         checkpoints, policy/floor versions and the root of every state version per subject;
///         full cycle records are emitted as events.
contract AgentMeditationRegistry is IAgentMeditation, IERC165, IERC6372 {
    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    uint8 public constant LAYER_RUNTIME = 0;
    uint8 public constant LAYER_MEMORY_SKILLS = 1;
    uint8 public constant LAYER_TASKS_ROLES = 2;
    uint8 public constant LAYER_COGNITION = 3;
    uint8 public constant ALL_LAYERS = 0x0F;

    uint8 public constant OP_CLEAN = 0;
    uint8 public constant OP_REPAIR = 1;
    uint8 public constant OP_UPDATE = 2;
    uint8 public constant OP_ITERATE = 3;

    uint8 public constant TRIGGER_SCHEDULED = 0;
    uint8 public constant TRIGGER_EVENT = 1;
    uint8 public constant TRIGGER_COMMANDED = 2;
    uint8 public constant TRIGGER_SELF = 3;
    uint8 public constant ALL_TRIGGERS = 0x0F;

    uint8 public constant RIGHT_FLOOR = 1;
    uint8 public constant RIGHT_DEMAND = 2;
    uint8 public constant RIGHT_REVOKE_OPERATORS = 4;
    uint8 public constant ALL_RIGHTS = 0x07;

    uint8 public constant PERM_REPORT = 1;
    uint8 public constant PERM_PULSE = 2;
    uint8 public constant PERM_POLICY = 4;
    uint8 public constant ALL_PERMISSIONS = 0x07;

    uint8 public constant DISCLOSURE_COMMITMENT = 0;
    uint8 public constant DISCLOSURE_SUMMARY = 1;
    uint8 public constant DISCLOSURE_FULL = 2;

    /// @dev Domain tags of the commitment format.
    bytes32 public constant TAG_LAYER_COMMITMENT = keccak256("AgentMeditationMechanism/LayerCommitment/v1");
    bytes32 public constant TAG_STATE_ROOT = keccak256("AgentMeditationMechanism/StateRoot/v1");

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotEnrolled();
    error AlreadyEnrolled();
    error Unauthorized();
    error InvalidLayer();
    error InvalidPolicy();
    error InvalidFloor();
    error InvalidController();
    error InvalidDemand();
    error InvalidLayerMask();
    error InvalidCompletedLayers();
    error InvalidOpsMask();
    error InvalidOutcome();
    error InvalidTrigger();
    error TriggerNotAllowed();
    error LayerNotSupported();
    error PolicyVersionNotGoverning();
    error BaseVersionMismatch();
    error PreRootMismatch();
    error UnscopedLayerChanged(uint8 layer);
    error InvalidTimeOrder();
    error CompletionNotMonotonic(uint8 layer);
    error InvalidRestore();

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    mapping(address => Head) internal _heads;
    mapping(address => LayerCheckpoint[4]) internal _checkpoints;
    mapping(address => mapping(uint64 => bytes32)) internal _rootAt;
    mapping(address => mapping(uint32 => Policy)) internal _policies;
    mapping(address => mapping(uint32 => uint48)) internal _policyEffectiveFrom;
    mapping(address => Floor) internal _floors;
    mapping(address => Demand[4]) internal _demands;
    mapping(address => mapping(address => uint8)) internal _operators;

    // ---------------------------------------------------------------------
    // ERC-165 / ERC-6372
    // ---------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAgentMeditation).interfaceId || interfaceId == type(IERC6372).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    function clock() public view virtual override returns (uint48) {
        return uint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure virtual override returns (string memory) {
        return "mode=timestamp";
    }

    // ---------------------------------------------------------------------
    // Enrollment and authorization
    // ---------------------------------------------------------------------

    /// @inheritdoc IAgentMeditation
    function enroll(bytes32[4] calldata baseline, Policy calldata policy, address controller, uint8 controllerRights)
        external
        override
    {
        address subject = msg.sender;
        Head storage h = _heads[subject];
        if (h.enrolled) revert AlreadyEnrolled();
        _validatePolicy(policy);
        if (controller == address(0)) {
            if (controllerRights != 0) revert InvalidController();
        } else {
            if (controller == subject || controllerRights & ~ALL_RIGHTS != 0) revert InvalidController();
        }

        uint48 now_ = clock();
        bytes32 root = _root(baseline);

        h.enrolled = true;
        h.controller = controller;
        h.controllerRights = controllerRights;
        h.policyVersion = 1;
        h.stateVersion = 1;
        h.root = root;
        h.enrolledAt = now_;
        h.lastSignalAt = now_;

        LayerCheckpoint[4] storage cps = _checkpoints[subject];
        for (uint8 i = 0; i < 4; i++) {
            cps[i].commitment = baseline[i];
            cps[i].lastChangedVersion = 1;
        }
        _rootAt[subject][1] = root;
        _policies[subject][1] = policy;
        _policyEffectiveFrom[subject][1] = now_;

        emit Enrolled(subject, controller, controllerRights, root, now_);
        emit PolicyUpdated(subject, 1, policy.policyHash, now_, subject);
    }

    /// @inheritdoc IAgentMeditation
    function setOperator(address operator, uint8 permissions) external override {
        address subject = msg.sender;
        if (!_heads[subject].enrolled) revert NotEnrolled();
        if (operator == address(0) || operator == subject || permissions & ~ALL_PERMISSIONS != 0) {
            revert Unauthorized();
        }
        _operators[subject][operator] = permissions;
        emit OperatorSet(subject, operator, permissions, subject);
    }

    /// @inheritdoc IAgentMeditation
    function revokeOperator(address subject, address operator) external override {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        bool allowed = msg.sender == subject
            || (msg.sender == h.controller
                && h.controller != address(0)
                && h.controllerRights & RIGHT_REVOKE_OPERATORS != 0);
        if (!allowed) revert Unauthorized();
        _operators[subject][operator] = 0;
        emit OperatorSet(subject, operator, 0, msg.sender);
    }

    /// @inheritdoc IAgentMeditation
    /// @dev Rules: with no controller set, the subject may appoint one with any rights. With a controller set,
    ///      only the controller may transfer (rights must be a subset of its own), shrink its rights, or renounce
    ///      (newController == address(0), rights == 0).
    function setController(address subject, address newController, uint8 rights) external override {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        if (rights & ~ALL_RIGHTS != 0) revert InvalidController();
        if (newController == subject) revert InvalidController();
        if (newController == address(0) && rights != 0) revert InvalidController();
        if (newController != address(0) && rights == 0) revert InvalidController();

        address previous = h.controller;
        if (previous == address(0)) {
            if (msg.sender != subject) revert Unauthorized();
            if (newController == address(0)) revert InvalidController();
        } else {
            if (msg.sender != previous) revert Unauthorized();
            if (rights & ~h.controllerRights != 0) revert InvalidController();
        }
        h.controller = newController;
        h.controllerRights = rights;
        emit ControllerChanged(subject, previous, newController, rights);
    }

    // ---------------------------------------------------------------------
    // Policy, floor, demand
    // ---------------------------------------------------------------------

    /// @inheritdoc IAgentMeditation
    function setPolicy(address subject, Policy calldata policy) external override {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        if (msg.sender != subject && _operators[subject][msg.sender] & PERM_POLICY == 0) revert Unauthorized();
        _validatePolicy(policy);
        uint32 version = h.policyVersion + 1;
        uint48 now_ = clock();
        h.policyVersion = version;
        _policies[subject][version] = policy;
        _policyEffectiveFrom[subject][version] = now_;
        emit PolicyUpdated(subject, version, policy.policyHash, now_, msg.sender);
    }

    /// @inheritdoc IAgentMeditation
    function setFloor(address subject, Floor calldata floor) external override {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        if (msg.sender != h.controller || h.controller == address(0) || h.controllerRights & RIGHT_FLOOR == 0) {
            revert Unauthorized();
        }
        if (floor.requiredLayers & ~ALL_LAYERS != 0) revert InvalidFloor();
        for (uint8 i = 0; i < 4; i++) {
            if (floor.requiredLayers & (1 << i) != 0 && floor.maxInterval[i] == 0) revert InvalidFloor();
        }
        uint32 version = h.floorVersion + 1;
        h.floorVersion = version;
        _floors[subject] = floor;
        emit FloorUpdated(subject, version, clock(), msg.sender);
    }

    /// @inheritdoc IAgentMeditation
    function demand(address subject, uint8 layerMask, uint48 dueBy) external override {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        if (msg.sender != h.controller || h.controller == address(0) || h.controllerRights & RIGHT_DEMAND == 0) {
            revert Unauthorized();
        }
        if (layerMask == 0 || layerMask & ~ALL_LAYERS != 0) revert InvalidLayerMask();
        uint48 now_ = clock();
        if (dueBy <= now_) revert InvalidDemand();
        Demand[4] storage ds = _demands[subject];
        for (uint8 i = 0; i < 4; i++) {
            if (layerMask & (1 << i) != 0) {
                ds[i] = Demand({demandedAt: now_, dueBy: dueBy});
            }
        }
        emit Demanded(subject, layerMask, dueBy, msg.sender);
    }

    /// @inheritdoc IAgentMeditation
    function withdrawDemand(address subject, uint8 layerMask) external override {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        if (msg.sender != h.controller || h.controller == address(0)) revert Unauthorized();
        if (layerMask == 0 || layerMask & ~ALL_LAYERS != 0) revert InvalidLayerMask();
        Demand[4] storage ds = _demands[subject];
        for (uint8 i = 0; i < 4; i++) {
            if (layerMask & (1 << i) != 0) {
                delete ds[i];
            }
        }
        emit DemandWithdrawn(subject, layerMask, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Records
    // ---------------------------------------------------------------------

    /// @inheritdoc IAgentMeditation
    function report(address subject, CycleReport calldata r) external override returns (uint64 seq) {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        if (msg.sender != subject && _operators[subject][msg.sender] & PERM_REPORT == 0) revert Unauthorized();

        uint48 now_ = clock();
        _checkShape(r);
        _checkGoverningPolicy(subject, h, r);
        _checkLinkage(h, r);

        if (!(r.reportedStartedAt <= r.reportedEndedAt && r.reportedEndedAt <= now_)) revert InvalidTimeOrder();

        LayerCheckpoint[4] storage cps = _checkpoints[subject];
        uint8 changed = 0;
        for (uint8 i = 0; i < 4; i++) {
            bool scoped = r.layerMask & (1 << i) != 0;
            bool differs = r.postCommitments[i] != cps[i].commitment;
            if (!scoped && differs) revert UnscopedLayerChanged(i);
            if (differs) changed |= uint8(1 << i);
            if (r.completedLayers & (1 << i) != 0 && r.reportedEndedAt <= cps[i].lastCompletedAt) {
                revert CompletionNotMonotonic(i);
            }
        }

        bytes32 newRoot = _root(r.postCommitments);
        if (r.restoresVersion != 0) {
            if (r.restoresVersion >= h.stateVersion || _rootAt[subject][r.restoresVersion] != newRoot) {
                revert InvalidRestore();
            }
        }

        uint64 newVersion = h.stateVersion;
        if (changed != 0) {
            newVersion = h.stateVersion + 1;
            h.stateVersion = newVersion;
            h.root = newRoot;
            _rootAt[subject][newVersion] = newRoot;
        }

        Demand[4] storage ds = _demands[subject];
        for (uint8 i = 0; i < 4; i++) {
            if (changed & (1 << i) != 0) {
                bytes32 previous = cps[i].commitment;
                cps[i].commitment = r.postCommitments[i];
                cps[i].lastChangedVersion = newVersion;
                emit LayerCommitmentChanged(subject, i, newVersion, previous, r.postCommitments[i]);
            }
            if (r.completedLayers & (1 << i) != 0) {
                cps[i].lastCompletedAt = r.reportedEndedAt;
                cps[i].lastCompletedRecordedAt = now_;
                cps[i].completedUnderPolicy = r.policyVersion;
                if (ds[i].demandedAt != 0 && r.reportedEndedAt >= ds[i].demandedAt) {
                    delete ds[i];
                }
            }
        }

        seq = ++h.recordCount;
        h.lastSignalAt = now_;
        h.nextPlannedAt = r.nextPlannedAt;

        emit CycleRecorded(subject, seq, r.baseVersion, newVersion, r, changed, now_, msg.sender);
    }

    /// @inheritdoc IAgentMeditation
    function pulse(address subject, uint48 nextPlannedAt) external override returns (uint64 seq) {
        Head storage h = _heads[subject];
        if (!h.enrolled) revert NotEnrolled();
        if (msg.sender != subject && _operators[subject][msg.sender] & (PERM_PULSE | PERM_REPORT) == 0) {
            revert Unauthorized();
        }
        uint48 now_ = clock();
        seq = ++h.recordCount;
        h.lastSignalAt = now_;
        h.nextPlannedAt = nextPlannedAt;
        emit Pulsed(subject, seq, now_, nextPlannedAt, msg.sender);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function headOf(address subject) external view override returns (Head memory) {
        return _heads[subject];
    }

    function checkpointOf(address subject, uint8 layer) external view override returns (LayerCheckpoint memory) {
        if (layer > 3) revert InvalidLayer();
        return _checkpoints[subject][layer];
    }

    function rootAt(address subject, uint64 stateVersion) external view override returns (bytes32) {
        return _rootAt[subject][stateVersion];
    }

    function policyOf(address subject, uint32 version) external view override returns (Policy memory) {
        return _policies[subject][version];
    }

    function policyEffectiveFrom(address subject, uint32 version) external view override returns (uint48) {
        return _policyEffectiveFrom[subject][version];
    }

    function floorOf(address subject) external view override returns (Floor memory) {
        return _floors[subject];
    }

    function demandOf(address subject, uint8 layer) external view override returns (Demand memory) {
        if (layer > 3) revert InvalidLayer();
        return _demands[subject][layer];
    }

    function operatorPermissions(address subject, address operator) external view override returns (uint8) {
        return _operators[subject][operator];
    }

    /// @inheritdoc IAgentMeditation
    function requirementsOf(address subject) public view override returns (Requirements memory req) {
        Head storage h = _heads[subject];
        if (!h.enrolled) return req;
        Policy storage p = _policies[subject][h.policyVersion];
        Floor storage f = _floors[subject];
        req.supportedLayers = p.supportedLayers;
        req.requiredLayers = p.requiredLayers | f.requiredLayers;
        req.dueWindow = p.dueWindow;
        req.pulseInterval = _minNonZero(p.pulseInterval, f.pulseInterval);
        for (uint8 i = 0; i < 4; i++) {
            uint48 a = p.requiredLayers & (1 << i) != 0 ? p.maxInterval[i] : 0;
            uint48 b = f.requiredLayers & (1 << i) != 0 ? f.maxInterval[i] : 0;
            req.maxInterval[i] = _minNonZero(a, b);
        }
    }

    /// @inheritdoc IAgentMeditation
    function layerStatus(address subject, uint8 layer)
        external
        view
        override
        returns (MaintenanceStatus status, uint48 deadline, bool neverCompleted)
    {
        if (layer > 3) revert InvalidLayer();
        Head storage h = _heads[subject];
        if (!h.enrolled) return (MaintenanceStatus.NOT_ENROLLED, 0, true);
        Requirements memory req = requirementsOf(subject);
        LayerCheckpoint storage cp = _checkpoints[subject][layer];
        neverCompleted = cp.lastCompletedAt == 0;
        if (req.requiredLayers & (1 << layer) == 0) {
            status =
                req.supportedLayers & (1 << layer) != 0 ? MaintenanceStatus.UNSCHEDULED : MaintenanceStatus.UNSUPPORTED;
            return (status, 0, neverCompleted);
        }
        uint48 anchor = neverCompleted ? h.enrolledAt : cp.lastCompletedAt;
        deadline = _saturatingAdd(anchor, req.maxInterval[layer]);
        Demand storage d = _demands[subject][layer];
        if (d.demandedAt != 0 && d.dueBy < deadline) deadline = d.dueBy;
        uint48 now_ = clock();
        if (now_ >= deadline) {
            status = MaintenanceStatus.OVERDUE;
        } else if (_saturatingAdd(now_, req.dueWindow) >= deadline) {
            status = MaintenanceStatus.DUE;
        } else {
            status = MaintenanceStatus.FRESH;
        }
    }

    /// @inheritdoc IAgentMeditation
    function signalStatus(address subject)
        external
        view
        override
        returns (SignalStatus status, uint48 lastSignalAt, uint48 silentSince)
    {
        Head storage h = _heads[subject];
        if (!h.enrolled) return (SignalStatus.NOT_ENROLLED, 0, 0);
        lastSignalAt = h.lastSignalAt;
        Requirements memory req = requirementsOf(subject);
        if (req.pulseInterval == 0) return (SignalStatus.NOT_TRACKED, lastSignalAt, 0);
        uint48 boundary = _saturatingAdd(lastSignalAt, req.pulseInterval);
        if (clock() > boundary) return (SignalStatus.SILENT, lastSignalAt, boundary);
        return (SignalStatus.PRESENT, lastSignalAt, 0);
    }

    /// @inheritdoc IAgentMeditation
    function computeRoot(bytes32[4] calldata commitments) external pure override returns (bytes32) {
        return _root(commitments);
    }

    /// @inheritdoc IAgentMeditation
    function computeLayerCommitment(uint8 layer, bytes32 schemaHash, bytes32 contentHash, bytes32 salt)
        external
        pure
        override
        returns (bytes32)
    {
        if (layer > 3) revert InvalidLayer();
        return keccak256(abi.encode(TAG_LAYER_COMMITMENT, layer, schemaHash, contentHash, salt));
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _root(bytes32[4] memory c) internal pure returns (bytes32) {
        return keccak256(abi.encode(TAG_STATE_ROOT, c[0], c[1], c[2], c[3]));
    }

    function _validatePolicy(Policy calldata p) internal pure {
        if (p.supportedLayers == 0 || p.supportedLayers & ~ALL_LAYERS != 0) revert InvalidPolicy();
        if (p.requiredLayers & ~p.supportedLayers != 0) revert InvalidPolicy();
        if (p.allowedTriggers == 0 || p.allowedTriggers & ~ALL_TRIGGERS != 0) revert InvalidPolicy();
        if (p.disclosure > DISCLOSURE_FULL) revert InvalidPolicy();
        for (uint8 i = 0; i < 4; i++) {
            if (p.requiredLayers & (1 << i) != 0 && p.maxInterval[i] == 0) revert InvalidPolicy();
        }
    }

    function _checkShape(CycleReport calldata r) internal pure {
        if (r.layerMask == 0 || r.layerMask & ~ALL_LAYERS != 0) revert InvalidLayerMask();
        if (r.completedLayers & ~r.layerMask != 0) revert InvalidCompletedLayers();
        for (uint8 i = 0; i < 4; i++) {
            if (r.layerMask & (1 << i) == 0 && (r.opsMask >> (i * 4)) & 0x0F != 0) revert InvalidOpsMask();
        }
        if (r.trigger > TRIGGER_SELF) revert InvalidTrigger();
        if (r.outcome > uint8(Outcome.FAILED)) revert InvalidOutcome();
        Outcome o = Outcome(r.outcome);
        if (o == Outcome.COMPLETED && r.completedLayers != r.layerMask) revert InvalidOutcome();
        if (o == Outcome.PARTIAL && (r.completedLayers == 0 || r.completedLayers == r.layerMask)) {
            revert InvalidOutcome();
        }
        if (o == Outcome.ABORTED && r.completedLayers == r.layerMask) revert InvalidOutcome();
        if (o == Outcome.FAILED && r.completedLayers != 0) revert InvalidOutcome();
    }

    function _checkGoverningPolicy(address subject, Head storage h, CycleReport calldata r) internal view {
        uint32 pv = r.policyVersion;
        if (pv == 0 || pv > h.policyVersion) revert PolicyVersionNotGoverning();
        if (_policyEffectiveFrom[subject][pv] > r.reportedStartedAt) revert PolicyVersionNotGoverning();
        if (pv < h.policyVersion && _policyEffectiveFrom[subject][pv + 1] <= r.reportedStartedAt) {
            revert PolicyVersionNotGoverning();
        }
        Policy storage p = _policies[subject][pv];
        if (r.layerMask & ~p.supportedLayers != 0) revert LayerNotSupported();
        if (p.allowedTriggers & (1 << r.trigger) == 0) revert TriggerNotAllowed();
    }

    function _checkLinkage(Head storage h, CycleReport calldata r) internal view {
        if (r.baseVersion != h.stateVersion) revert BaseVersionMismatch();
        if (r.preRoot != h.root) revert PreRootMismatch();
    }

    function _minNonZero(uint48 a, uint48 b) internal pure returns (uint48) {
        if (a == 0) return b;
        if (b == 0) return a;
        return a < b ? a : b;
    }

    function _saturatingAdd(uint48 a, uint48 b) internal pure returns (uint48) {
        unchecked {
            uint48 c = a + b;
            return c < a ? type(uint48).max : c;
        }
    }
}
