// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {LaunchEscrow} from "./LaunchEscrow.sol";
import {LaunchAbuseRegistry} from "./LaunchAbuseRegistry.sol";
import {AbuseReport, ClaimStatus, ContainmentAction,
        ClaimNotOpen, ContestWindowClosed, NotAdjudicator,
        InsufficientScore, UnknownReport} from "./LaunchAbuseTypes.sol";
import {Containment} from "./Containment.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

// Time is the domain here: vesting schedules, freeze deadlines and refund
// windows are all measured in days. Timestamp comparison is the intended
// semantic, and validator drift of seconds cannot change any outcome.
// slither-disable-start timestamp
contract LaunchRemediation is ReentrancyGuard {
    uint8   public constant MIN_CLAIM_SCORE = 61;
    uint256 public constant MIN_CLAIM_BOND  = 0.1 ether;
    uint64  public constant CONTEST_WINDOW  = 72 hours;
    uint64  public constant BOND_COOLDOWN   = 30 days;
    uint16  public constant FEE_BPS         = 250; // 2.5% of restitution, funds adjudication
    /// @notice Share of a successful restitution paid to the detector whose
    ///         report supported the upheld claim.
    /// @dev Detection is what every other part of this rests on, and it is not
    ///      free: a detector posts slashable collateral, runs an indexing
    ///      pipeline and commits to chain-anchored evidence. Funding
    ///      adjudication and leaving detection unfunded would make forfeited
    ///      claimant bonds the only detector revenue, so a detector that was
    ///      never wrong would earn nothing. Never above FEE_BPS.
    uint16  public constant DETECTOR_FEE_BPS = 100; // 1% of restitution

    /// @notice Independent detectors required before a high-value claim opens.
    uint8 public constant MIN_CORROBORATION = 2;

    /// @dev Bond sizing is a deployment policy, not a property of the standard.
    ///      The right ratio depends on the loss distribution a venue actually
    ///      sees, which is why these are constructor parameters rather than
    ///      constants: a fixed fraction invented here would be a number nobody
    ///      measured, applied to every venue regardless of its risk.
    uint16  public immutable bondBps;
    uint256 public immutable minBond;
    /// @notice Escrowed value above which a claim requires corroboration.
    uint256 public immutable highValueThreshold;

    struct Claim {
        bytes32     launchId;
        bytes32     reportId;
        address     claimant;
        uint256     bond;
        uint256     award;
        uint64      openedAt;
        ClaimStatus status;
        bool        exists;
    }

    LaunchEscrow        public escrow;
    LaunchAbuseRegistry public registry;
    address public immutable adjudicator;
    address public immutable feeRecipient;
    address private immutable _deployer;

    mapping(bytes32 => Claim) internal _claims;
    /// @dev Several buyers may have grounds against the same launch, and the
    ///      first to file must not consume the only opportunity to claim. The
    ///      launch stays frozen while any claim is unresolved.
    mapping(bytes32 => uint256) public openClaims;
    /// @dev Value owed but not yet collected. A recipient that reverts on
    ///      receive must not be able to block the state transition that owes it:
    ///      a claimant refusing payment could otherwise deny the deployer the
    ///      bilateral `settle` exit and stop `expire` from ever resolving.
    ///      Resolution credits; collection is a separate pull.
    mapping(address => uint256) public withdrawable;
    /// @dev Reserved out of the bond at execution and left in the escrow until
    ///      the detector pulls it. Reserving rather than pushing keeps a
    ///      detector that cannot receive value from blocking the refund.
    mapping(bytes32 => uint256) public detectorReward;
    uint256 internal _claimNonce;

    event BondPosted(bytes32 indexed launchId, uint256 amount);
    event BondSlashed(bytes32 indexed launchId, uint256 amount, bytes32 claimId);
    event ClaimOpened(bytes32 indexed claimId, bytes32 indexed launchId, address claimant, uint256 bond);
    event ClaimContested(bytes32 indexed claimId, address respondent, string evidenceURI);
    event ClaimSettled(bytes32 indexed claimId, uint256 amount);
    event ClaimAdjudicated(bytes32 indexed claimId, ClaimStatus outcome, uint256 award);
    event RemedyExecuted(bytes32 indexed claimId, uint256 fromEscrow, uint256 fromBond);
    event ContainmentApplied(bytes32 indexed launchId, ContainmentAction action, uint64 until);
    event DetectorRewarded(bytes32 indexed claimId, address indexed detector, uint256 amount);
    event Credited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);

    modifier onlyAdjudicator() {
        if (msg.sender != adjudicator) revert NotAdjudicator(msg.sender);
        _;
    }

    constructor(
        address adjudicator_,
        address feeRecipient_,
        uint16  bondBps_,
        uint256 minBond_,
        uint256 highValueThreshold_
    ) {
        require(bondBps_ <= 10_000, "bondBps out of range");
        require(adjudicator_ != address(0) && feeRecipient_ != address(0), "zero address");
        adjudicator = adjudicator_;
        feeRecipient = feeRecipient_;
        bondBps = bondBps_;
        minBond = minBond_;
        highValueThreshold = highValueThreshold_;
        _deployer = msg.sender;
    }

    /// @dev Escrow and remediation reference each other, so the link is closed
    ///      once after both exist. It can never be repointed.
    function initialize(LaunchEscrow escrow_, LaunchAbuseRegistry registry_) external {
        require(msg.sender == _deployer, "not deployer");
        require(address(escrow_) != address(0) && address(registry_) != address(0), "zero address");
        require(address(escrow) == address(0), "already initialized");
        escrow = escrow_;
        registry = registry_;
    }

    // --- bonds --------------------------------------------------------------

    /// @notice Collateral a deployer must post for a stated target raise.
    /// @dev Scales with the raise rather than sitting at a nominal floor: a bond
    ///      smaller than the harm leaves buyers uncompensated in exactly the
    ///      cases that matter most. The ratio is a deployment parameter because
    ///      the defensible value comes from observed losses, not from a constant
    ///      chosen in a specification.
    function requiredBond(uint256 targetRaise) public view returns (uint256) {
        uint256 scaled = (targetRaise * bondBps) / 10_000;
        return scaled > minBond ? scaled : minBond;
    }

    function postBond(bytes32 launchId) external payable nonReentrant {
        escrow.topUpBond{value: msg.value}(launchId, msg.value);
        emit BondPosted(launchId, msg.value);
    }

    function bondOf(bytes32 launchId) external view returns (uint256) {
        return escrow.bondOf(launchId);
    }

    // --- claims -------------------------------------------------------------

    function openClaim(bytes32 launchId, bytes32 reportId, string calldata evidenceURI)
        external
        payable
        nonReentrant
        returns (bytes32)
    {
        return _openClaim(launchId, reportId, evidenceURI);
    }

    function _openClaim(bytes32 launchId, bytes32 reportId, string calldata evidenceURI)
        internal
        returns (bytes32 claimId)
    {
        require(msg.value >= MIN_CLAIM_BOND, "claim bond too small");
        if (!registry.isLive(reportId)) revert UnknownReport(reportId);
        require(registry.launchOf(reportId) == launchId, "report is for another launch");

        // Above the high-value threshold a single detector is not enough: one
        // detector colluding with one claimant could otherwise manufacture the
        // score needed to freeze a launch.
        uint256 atStake = escrow.escrowedProceeds(launchId) + escrow.bondOf(launchId);
        uint8 score;
        uint8 conf;
        uint256 backers;
        bytes32 top;
        if (atStake > highValueThreshold) {
            (score, conf, backers) = registry.corroboratedScore(launchId, MIN_CORROBORATION);
            require(backers >= MIN_CORROBORATION, "insufficient corroboration");
        } else {
            (score, conf, top) = registry.activeScore(launchId);
            require(top != bytes32(0), "no live report");
        }
        require(conf > 0, "report carries no confidence");
        if (score < MIN_CLAIM_SCORE) revert InsufficientScore(score, MIN_CLAIM_SCORE);

        claimId = keccak256(abi.encode(launchId, reportId, msg.sender, _claimNonce++));
        Claim storage c = _claims[claimId];
        c.launchId = launchId;
        c.reportId = reportId;
        c.claimant = msg.sender;
        c.bond = msg.value;
        c.openedAt = uint64(block.timestamp);
        c.status = ClaimStatus.Open;
        c.exists = true;

        // Freeze on the first open claim; later claims join the same freeze.
        if (openClaims[launchId]++ == 0 && !escrow.isRefunding(launchId)) {
            escrow.freezeLaunch(launchId, reportId);
        }

        emit ClaimOpened(claimId, launchId, msg.sender, msg.value);
        emit ContainmentApplied(launchId, ContainmentAction.Freeze, uint64(block.timestamp) + escrow.maxFreezeDuration());
        // evidenceURI is carried in the event log rather than storage.
        emit ClaimContested(claimId, address(0), evidenceURI);
    }

    /// @notice Register a report and open a claim in one transaction, so the
    ///         deployer cannot act between publication and freeze.
    function submitAndClaim(AbuseReport calldata report, string calldata evidenceURI)
        external
        payable
        nonReentrant
        returns (bytes32 reportId, bytes32 claimId)
    {
        reportId = registry.submitReportFor(report, msg.sender);
        claimId = _openClaim(report.launchId, reportId, evidenceURI);
    }

    function contest(bytes32 claimId, string calldata evidenceURI) external nonReentrant {
        Claim storage c = _claims[claimId];
        if (c.status != ClaimStatus.Open) revert ClaimNotOpen(claimId, c.status);
        require(msg.sender == escrow.deployerOf(c.launchId), "not the deployer");
        if (block.timestamp > c.openedAt + CONTEST_WINDOW) {
            revert ContestWindowClosed(claimId, c.openedAt + CONTEST_WINDOW);
        }
        c.status = ClaimStatus.Contested;
        emit ClaimContested(claimId, msg.sender, evidenceURI);
    }

    /// @notice Close a claim by agreement. Keeps the adjudicator from being both
    ///         a bottleneck and the only route to resolution.
    function settle(bytes32 claimId, uint256 amount) external payable nonReentrant {
        Claim storage c = _claims[claimId];
        if (c.status != ClaimStatus.Open && c.status != ClaimStatus.Contested) {
            revert ClaimNotOpen(claimId, c.status);
        }
        require(msg.sender == escrow.deployerOf(c.launchId), "not the deployer");
        require(msg.value == amount, "value mismatch");

        c.status = ClaimStatus.Settled;
        uint256 refund = amount + c.bond;
        c.bond = 0;
        _send(c.claimant, refund); // settlement plus returned bond, collected by pull
        _closeClaim(c.launchId);
        emit ClaimSettled(claimId, amount);
    }

    function adjudicate(bytes32 claimId, ClaimStatus outcome, uint256 award)
        external
        onlyAdjudicator
        nonReentrant
    {
        Claim storage c = _claims[claimId];
        if (c.status != ClaimStatus.Open && c.status != ClaimStatus.Contested) {
            revert ClaimNotOpen(claimId, c.status);
        }
        require(outcome == ClaimStatus.Upheld || outcome == ClaimStatus.Rejected, "bad outcome");

        c.status = outcome;
        c.award = award;

        if (outcome == ClaimStatus.Rejected) {
            // Forfeiture is what prices a frivolous freeze. Half compensates the
            // deployer, half funds the detector pool. The bond is cleared before
            // any external call: neither the escrow nor a recipient that
            // re-enters may observe a balance that has already been committed.
            uint256 forfeited = c.bond;
            c.bond = 0;
            uint256 half = forfeited / 2;
            _send(escrow.deployerOf(c.launchId), half);
            _send(address(registry), forfeited - half);
            _closeClaim(c.launchId);
        }
        emit ClaimAdjudicated(claimId, outcome, award);
    }

    function executeRemedy(bytes32 claimId) external nonReentrant returns (uint256 fromEscrow, uint256 fromBond) {
        Claim storage c = _claims[claimId];
        if (c.status != ClaimStatus.Upheld) revert ClaimNotOpen(claimId, c.status);

        c.status = ClaimStatus.Executed;
        if (openClaims[c.launchId] > 0) openClaims[c.launchId] -= 1;
        uint256 bond = c.bond;
        c.bond = 0;
        _send(c.claimant, bond); // successful claimant gets their bond back

        uint256 escrowed = escrow.escrowedProceeds(c.launchId);
        fromEscrow = escrowed > c.award ? c.award : escrowed;

        uint256 shortfall = c.award > fromEscrow ? c.award - fromEscrow : 0;
        uint256 available = escrow.bondOf(c.launchId);
        fromBond = shortfall > available ? available : shortfall;

        // The fee funds adjudication and is taken from bond, never from the
        // buyers' pool.
        uint256 fee = (fromBond * FEE_BPS) / 10_000;
        // The detector's share is taken the same way and from the same base, so
        // that both fall on the process that consumed them rather than on the
        // buyers being made whole.
        uint256 reward = (fromBond * DETECTOR_FEE_BPS) / 10_000;
        if (fee > 0) {
            escrow.releaseBond(c.launchId, feeRecipient, fee);
            fromBond -= fee;
        }
        if (reward > 0) {
            detectorReward[claimId] = reward;
            fromBond -= reward;
        }

        // A launch may face more than one upheld claim: the first opens the
        // pool, later ones top it up rather than reverting.
        if (escrow.isRefunding(c.launchId)) {
            escrow.augmentRefund(c.launchId, fromBond);
        } else {
            escrow.openRefund(c.launchId, fromBond);
        }

        emit BondSlashed(c.launchId, fromBond + fee, claimId);
        emit RemedyExecuted(claimId, fromEscrow, fromBond);
    }

    /// @notice Pull the detector's share of an executed remedy.
    /// @dev Paid to the detector recorded against the report the claim
    ///      referenced, never to the caller and never to whoever relayed an
    ///      atomic submission: the bond at risk was the detector's, and so is
    ///      the reward. Anyone may call this; only the detector is paid.
    function claimDetectorReward(bytes32 claimId) external nonReentrant returns (uint256 amount) {
        Claim storage c = _claims[claimId];
        if (c.status != ClaimStatus.Executed) revert ClaimNotOpen(claimId, c.status);

        amount = detectorReward[claimId];
        require(amount > 0, "nothing to pull");
        detectorReward[claimId] = 0;

        address detector = registry.detectorOf(c.reportId);
        require(detector != address(0), "no detector");

        escrow.releaseBond(c.launchId, detector, amount);
        emit DetectorRewarded(claimId, detector, amount);
    }

    /// @notice Exclude a deployer-linked buyer from the refund pool.
    function markLinked(bytes32 launchId, address account) external onlyAdjudicator nonReentrant {
        escrow.markLinked(launchId, account);
    }

    /// @notice Slash the detector whose report backed a claim, for a report
    ///         found to be false.
    /// @dev Deliberately not automatic on rejection. A claim can fail for
    ///      reasons that say nothing about the report: the claimant may lack
    ///      standing, or the conduct may be real but fall short of the remedy
    ///      sought. Slashing every rejection would punish accurate detectors for
    ///      other people's weak claims and drive detection out of the system.
    ///      Only a finding that the report itself was false should cost a bond.
    function slashReportingDetector(bytes32 claimId, uint256 amount) external onlyAdjudicator nonReentrant {
        Claim storage c = _claims[claimId];
        require(c.exists, "unknown claim");
        require(
            c.status == ClaimStatus.Rejected || c.status == ClaimStatus.Expired,
            "claim not resolved against the report"
        );

        address detector = registry.detectorOf(c.reportId);
        require(detector != address(0), "no detector");
        registry.slashDetector(detector, amount, claimId, escrow.deployerOf(c.launchId));
    }

    /// @notice A claim nobody adjudicated must not freeze a launch forever.
    function expire(bytes32 claimId) external nonReentrant {
        Claim storage c = _claims[claimId];
        if (c.status != ClaimStatus.Open && c.status != ClaimStatus.Contested) {
            revert ClaimNotOpen(claimId, c.status);
        }
        require(block.timestamp > c.openedAt + escrow.maxFreezeDuration(), "not yet expired");

        c.status = ClaimStatus.Expired;
        uint256 bond = c.bond;
        c.bond = 0;
        _send(c.claimant, bond);
        _closeClaim(c.launchId);
        emit ClaimAdjudicated(claimId, ClaimStatus.Expired, 0);
    }

    // --- views --------------------------------------------------------------

    function getClaim(bytes32 claimId)
        external
        view
        returns (bytes32 launchId, address claimant, ClaimStatus status, uint256 award)
    {
        Claim storage c = _claims[claimId];
        return (c.launchId, c.claimant, c.status, c.award);
    }

    function advisedAction(bytes32 launchId) external view returns (ContainmentAction) {
        (uint8 score, uint8 confidence, bytes32 reportId) = registry.activeScore(launchId);
        if (reportId == bytes32(0)) return ContainmentAction.None;
        return Containment.ladder(score, confidence);
    }

    function contestWindow() external pure returns (uint64) { return CONTEST_WINDOW; }
    function bondCooldown()  external pure returns (uint64) { return BOND_COOLDOWN; }
    function feeBps()         external pure returns (uint16) { return FEE_BPS; }
    function detectorFeeBps() external pure returns (uint16) { return DETECTOR_FEE_BPS; }

    /// @dev Unfreeze only when the last unresolved claim has closed. Releasing
    ///      on the first resolution would let a deployer clear one friendly
    ///      claim to escape every other.
    function _closeClaim(bytes32 launchId) internal {
        if (openClaims[launchId] > 0) openClaims[launchId] -= 1;
        if (openClaims[launchId] == 0 && !escrow.isRefunding(launchId)) {
            escrow.unfreeze(launchId);
        }
    }

    /// @dev Destinations are the claimant, the deployer or the registry, all
    ///      read from storage written at claim time.
    // slither-disable-next-line arbitrary-send-eth
    /// @dev Credits rather than transfers. Every payout in this contract goes to
    ///      a party with an interest in refusing it at the wrong moment, so no
    ///      state transition depends on a transfer succeeding.
    function _send(address to, uint256 amount) internal {
        if (!(amount > 0)) return;
        withdrawable[to] += amount;
        emit Credited(to, amount);
    }

    /// @notice Collect anything owed to the caller.
    function withdraw() external nonReentrant returns (uint256 amount) {
        amount = withdrawable[msg.sender];
        require(amount > 0, "nothing owed");
        withdrawable[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount);
        // slither-disable-next-line arbitrary-send-eth,low-level-calls
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "withdraw failed");
    }

    receive() external payable {}
}
// slither-disable-end timestamp
