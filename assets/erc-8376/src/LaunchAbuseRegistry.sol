// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ILaunchAbuseRegistry} from "./ILaunchAbuseRegistry.sol";
import {
    AbuseReport,
    Patterns,
    UnknownExtensionSchema,
    BASE_VECTOR_VERSION,
    UnknownReport,
    ReportAlreadyRetracted,
    DetectorNotBonded,
    InvalidSignalVector,
    NotRemediation,
    UnsupportedVectorVersion,
    OutcomeSignalNotPermitted
} from "./LaunchAbuseTypes.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";


/// @title Reference detection registry.
/// @notice A report is a bonded claim by an accountable party, never a fact.
///         Bonding is what makes a false report cost something; chain-anchored
///         evidence is what makes one provable.
// Report freshness is a time window by definition, so timestamp comparison is
// the intended semantic, not an approximation of block height. Miner drift of a
// few seconds cannot meaningfully change whether a 30-day report is stale.
// slither-disable-start timestamp
contract LaunchAbuseRegistry is ILaunchAbuseRegistry, ReentrancyGuard {
    uint256 public constant MIN_DETECTOR_BOND = 1 ether;
    uint64  public constant MAX_REPORT_AGE    = 30 days;
    uint32  public constant OPENING_BLOCKS    = 20;
    /// @dev Bounds the scan in `activeScore` so a launch cannot be made
    ///      unqueryable by flooding it with reports.
    uint256 public constant SCAN_LIMIT = 64;

    struct Stored {
        AbuseReport report;
        address detector;
        uint64  submittedAt;
        bool    retracted;
        bool    exists;
    }

    address public immutable remediation;

    mapping(bytes32 => Stored)    internal _reports;
    mapping(bytes32 => bytes32[]) internal _byLaunch;
    mapping(address => uint256)   public   detectorBond;
    /// @dev A detector's authority is its key. Letting the key that signs
    ///      submissions be separate from the one holding the bond means a hot
    ///      key compromise is survivable: rotate the submitter and the bond,
    ///      the history and the reputation all stay where they were.
    mapping(address => address)   public   submitterOf;
    mapping(address => address)   public   detectorOfSubmitter;
    /// @dev Nominated but not yet accepted. A nomination is not authority.
    mapping(address => address)   public   pendingSubmitter;
    /// @dev Forfeited claimant bonds, held for distribution to detectors.
    uint256 public detectorPool;

    constructor(address remediation_) {
        require(remediation_ != address(0), "zero address");
        remediation = remediation_;
    }

    // --- detector bonding ---------------------------------------------------

    function bondDetector() external payable nonReentrant {
        detectorBond[msg.sender] += msg.value;
        emit DetectorBonded(msg.sender, msg.value);
    }

    /// @dev `call` is the recommended transfer method; the function is
    ///      nonReentrant and clears the bond before paying.
    // slither-disable-next-line low-level-calls
    function slashDetector(address detector, uint256 amount, bytes32 claimId, address to) external nonReentrant {
        if (msg.sender != remediation) revert NotRemediation(msg.sender);
        require(to != address(0), "zero recipient");
        require(detectorBond[detector] >= amount, "bond exceeded");
        detectorBond[detector] -= amount;
        emit DetectorSlashed(detector, amount, claimId);
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "slash transfer failed");
    }

    /// @notice Authorize a hot key to submit on the caller's behalf.
    /// @dev Pass the zero address to revoke. Rotation is the same call with a
    ///      new key, so a compromised submitter is retired without touching the
    ///      bond or losing the detector's record.
    /// @notice Nominate a hot key to submit on the caller's behalf, or clear
    ///         the nomination and any binding with the zero address.
    /// @dev The nomination binds nothing until the nominee accepts. Writing the
    ///      binding here would let a bonded detector name an address that has
    ///      not yet bonded and take everything it later submits: the reports
    ///      would be attributed to the captor, the rewards paid to the captor,
    ///      and the address could not even retract its own work. Revocation
    ///      stays one-sided, because a detector must be able to retire a key it
    ///      no longer trusts without asking the key.
    function setSubmitter(address submitter) external nonReentrant {
        require(detectorBond[msg.sender] >= MIN_DETECTOR_BOND, "not bonded");

        address prev = submitterOf[msg.sender];
        if (prev != address(0)) delete detectorOfSubmitter[prev];

        submitterOf[msg.sender] = submitter;
        pendingSubmitter[submitter] = msg.sender;
        emit SubmitterSet(msg.sender, submitter);
    }

    /// @notice Accept a nomination to submit on a detector's behalf.
    /// @dev Caller-side half of the binding. An address that is itself a bonded
    ///      detector cannot become one, since its own bond would stop being the
    ///      one at risk for what it publishes.
    function acceptSubmitter(address detector) external nonReentrant {
        require(pendingSubmitter[msg.sender] == detector, "not nominated");
        require(submitterOf[detector] == msg.sender, "nomination withdrawn");
        require(detectorOfSubmitter[msg.sender] == address(0), "already bound");
        require(detectorBond[msg.sender] == 0, "submitter is itself a detector");

        delete pendingSubmitter[msg.sender];
        detectorOfSubmitter[msg.sender] = detector;
        emit SubmitterAccepted(detector, msg.sender);
    }

    /// @notice The detector a caller submits as: itself, or whoever authorized it.
    function principalOf(address caller) public view returns (address) {
        address d = detectorOfSubmitter[caller];
        return d == address(0) ? caller : d;
    }

    // --- reports ------------------------------------------------------------

    function submitReport(AbuseReport calldata report) external nonReentrant returns (bytes32 reportId) {
        return _submit(report, principalOf(msg.sender));
    }

    /// @notice Submit on behalf of `detector`, for the atomic submit-and-claim
    ///         path where the remediation contract is the immediate caller.
    /// @dev Without this the report would be attributed to the remediation
    ///      contract: its bond would be the one at risk, `slashReportingDetector`
    ///      would slash the wrong party, and corroboration would count every
    ///      atomic claim as the same single detector. Accountability has to
    ///      follow the detector, not the transport.
    function submitReportFor(AbuseReport calldata report, address detector)
        external
        nonReentrant
        returns (bytes32 reportId)
    {
        if (msg.sender != remediation) revert NotRemediation(msg.sender);
        return _submit(report, principalOf(detector));
    }

    function _submit(AbuseReport calldata report, address detector)
        internal
        returns (bytes32 reportId)
    {
        uint256 held = detectorBond[detector];
        if (held < MIN_DETECTOR_BOND) revert DetectorNotBonded(detector, held, MIN_DETECTOR_BOND);

        _validate(report);

        reportId = keccak256(abi.encode(report, detector));
        require(!_reports[reportId].exists, "duplicate report");

        Stored storage s = _reports[reportId];
        s.report = report;
        s.detector = detector;
        s.submittedAt = uint64(block.timestamp);
        s.exists = true;

        _byLaunch[report.launchId].push(reportId);

        emit AbuseReported(
            reportId, report.launchId, report.patternId, detector,
            report.abuseScore, report.confidence
        );
    }

    function _validate(AbuseReport calldata r) internal pure {
        // A vector of an unknown version cannot be read, and reading it as
        // version 1 would silently misinterpret every field that moved.
        if (r.vectorVersion != BASE_VECTOR_VERSION) {
            revert UnsupportedVectorVersion(r.vectorVersion, BASE_VECTOR_VERSION);
        }
        // Schema and payload travel together. A schema with nothing under it
        // claims a reading that was never made; a payload with no schema is
        // bytes nobody can decode.
        if ((r.extensionSchema == bytes32(0)) != (r.extensionSignals.length == 0)) {
            revert InvalidSignalVector();
        }
        if (r.abuseScore > 100 || r.confidence > 100) revert InvalidSignalVector();
        // A pattern whose weight sits in an extension cannot be scored without
        // one, and a report that omits it would be evaluated on whatever base
        // signal the profile happens to share.
        if (r.patternId == Patterns.IMPERSONATION && r.extensionSchema == bytes32(0)) {
            revert UnknownExtensionSchema(bytes32(0));
        }
        if (r.windowEnd < r.launchedAt) revert InvalidSignalVector();
        if (r.evidenceRoot == bytes32(0)) revert InvalidSignalVector();
        if (r.launchId == bytes32(0)) revert InvalidSignalVector();
        if (r.deployer == address(0)) revert InvalidSignalVector();
        // The conduct-only rule is structural: `SignalVector` carries no outcome
        // field, so there is nothing to reject here. An implementation that
        // extends the vector MUST reject outcome inputs with
        // OutcomeSignalNotPermitted.
    }

    function retractReport(bytes32 reportId, string calldata reason) external nonReentrant {
        Stored storage s = _reports[reportId];
        if (!s.exists) revert UnknownReport(reportId);
        require(principalOf(msg.sender) == s.detector, "not detector");
        if (s.retracted) revert ReportAlreadyRetracted(reportId);

        s.retracted = true;
        emit ReportRetracted(reportId, reason);
    }

    function getReport(bytes32 reportId)
        external
        view
        returns (AbuseReport memory report, address detector, uint64 submittedAt)
    {
        Stored storage s = _reports[reportId];
        if (!s.exists) revert UnknownReport(reportId);
        return (s.report, s.detector, s.submittedAt);
    }

    /// @notice Highest-scoring live report for a launch.
    /// @dev Scans backwards from the newest report, so a launch stays queryable
    ///      even if older reports accumulate beyond the scan limit.
    function activeScore(bytes32 launchId)
        public
        view
        returns (uint8 abuseScore, uint8 confidence, bytes32 reportId)
    {
        bytes32[] storage list = _byLaunch[launchId];
        uint256 n = list.length;
        uint256 scanned = 0;

        for (uint256 i = n; i > 0 && scanned < SCAN_LIMIT; --i) {
            ++scanned;
            bytes32 rid = list[i - 1];
            Stored storage s = _reports[rid];
            if (s.retracted) continue;
            if (block.timestamp > uint256(s.report.windowEnd) + MAX_REPORT_AGE) continue;
            if (s.report.abuseScore > abuseScore) {
                abuseScore = s.report.abuseScore;
                confidence = s.report.confidence;
                reportId = rid;
            }
        }
    }

    /// @notice The highest score that at least `minDetectors` independent
    ///         detectors each support with a live report.
    /// @dev A single detector's word is one accountable opinion, not a fact. For
    ///      high-value claims a deployment should require agreement, because a
    ///      detector colluding with a claimant can otherwise manufacture the
    ///      score needed to freeze a launch. Each detector contributes only its
    ///      own best report, so one party cannot corroborate itself by
    ///      publishing repeatedly.
    /// @return score the level at which corroboration holds, 0 if it does not
    /// @return confidence the confidence attached to the marginal report
    /// @return distinct how many independent detectors were seen
    function corroboratedScore(bytes32 launchId, uint8 minDetectors)
        public
        view
        returns (uint8 score, uint8 confidence, uint256 distinct)
    {
        if (minDetectors == 0) {
            (uint8 s, uint8 c, ) = activeScore(launchId);
            return (s, c, 0);
        }

        bytes32[] storage list = _byLaunch[launchId];
        address[] memory dets  = new address[](SCAN_LIMIT);
        uint8[]   memory best  = new uint8[](SCAN_LIMIT);
        uint8[]   memory confs = new uint8[](SCAN_LIMIT);

        uint256 scanned = 0;
        for (uint256 i = list.length; i > 0 && scanned < SCAN_LIMIT; --i) {
            ++scanned;
            Stored storage s = _reports[list[i - 1]];
            if (s.retracted) continue;
            if (block.timestamp > uint256(s.report.windowEnd) + MAX_REPORT_AGE) continue;

            uint256 j = 0;
            bool seen = false;
            for (j = 0; j < distinct; ++j) {
                if (dets[j] == s.detector) { seen = true; break; }
            }
            if (!seen) {
                dets[distinct]  = s.detector;
                best[distinct]  = s.report.abuseScore;
                confs[distinct] = s.report.confidence;
                ++distinct;
            } else if (s.report.abuseScore > best[j]) {
                best[j]  = s.report.abuseScore;
                confs[j] = s.report.confidence;
            }
        }

        if (distinct < minDetectors) return (0, 0, distinct);

        // Take the minDetectors-th highest: the level all of them clear.
        for (uint256 k = 0; k < minDetectors; ++k) {
            uint256 top = 0;
            for (uint256 j = 1; j < distinct; ++j) {
                if (best[j] > best[top]) top = j;
            }
            score = best[top];
            confidence = confs[top];
            best[top] = 0;
        }
    }

    function isLive(bytes32 reportId) external view returns (bool) {
        Stored storage s = _reports[reportId];
        return s.exists && !s.retracted && block.timestamp <= uint256(s.report.windowEnd) + MAX_REPORT_AGE;
    }

    function detectorOf(bytes32 reportId) external view returns (address) {
        return _reports[reportId].detector;
    }

    function launchOf(bytes32 reportId) external view returns (bytes32) {
        return _reports[reportId].report.launchId;
    }

    function reportCount(bytes32 launchId) external view returns (uint256) {
        return _byLaunch[launchId].length;
    }

    function minDetectorBond() external pure returns (uint256) { return MIN_DETECTOR_BOND; }
    function maxReportAge()    external pure returns (uint64)  { return MAX_REPORT_AGE; }
    function openingBlocks()   external pure returns (uint32)  { return OPENING_BLOCKS; }

/// @notice Fund the pool that forfeited claimant bonds flow into.
    /// @dev The remediation contract pays in here on a rejected claim. Value
    ///      arriving with no way to account for it would sit unreachable, so
    ///      the pool is an explicit balance and the event is what makes its
    ///      growth observable.
    function fundDetectorPool() external payable {
        detectorPool += msg.value;
        emit DetectorPoolFunded(msg.sender, msg.value);
    }

    receive() external payable {}
}
// slither-disable-end timestamp
