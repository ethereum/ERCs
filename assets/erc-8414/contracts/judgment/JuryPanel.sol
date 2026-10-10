// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface ITenderSettlement {
    function acceptFulfillment(uint256 tokenId, uint256 submissionId) external;
    function rejectFulfillment(uint256 tokenId, uint256 submissionId) external;
}

/// @title  JuryPanel — K-of-N reference judging authority for judged tasks.
/// @notice The usable step between a single treasury signer and a full DAO: a fixed
///         juror set votes on each submission within a window; K approvals settle,
///         a blocking minority rejects, and a timed-out case defaults to rejection
///         (anyone may finalize). Set this contract as a task's acceptanceAuthority.
///         Governance evolution beyond this — staking, slashing, appeal courts,
///         nominated committees, bicameral DAOs — lives in future authority
///         contracts, swapped in via setAcceptanceAuthority; the token standard
///         never changes.
/// @dev    Deliberately does NOT implement ITaskVerifier: a panel is a judged
///         authority (accept/reject path), not a machine-settlement verifier.
contract JuryPanel {
    address[] public jurors;
    uint256 public immutable quorum;      // approvals needed to accept
    uint64  public immutable voteWindow;  // seconds from first vote to timeout

    struct CaseState {
        uint64  firstVoteAt; // 0 = no votes yet
        uint32  approvals;
        uint32  rejections;
        bool    closed;
    }

    // caseKey = keccak256(taskContract, tokenId, submissionId)
    mapping(bytes32 => CaseState) public caseOf;
    mapping(bytes32 => mapping(address => bool)) public voted;
    mapping(address => bool) public isJuror;

    event Voted(bytes32 indexed caseKey, address indexed juror, bool approve);
    event CaseClosed(bytes32 indexed caseKey, bool accepted);

    constructor(address[] memory jurors_, uint256 quorum_, uint64 voteWindow_) {
        require(jurors_.length > 0, "Jury: no jurors");
        require(quorum_ > 0 && quorum_ <= jurors_.length, "Jury: bad quorum");
        require(voteWindow_ > 0, "Jury: zero window");
        for (uint256 i = 0; i < jurors_.length; i++) {
            require(jurors_[i] != address(0) && !isJuror[jurors_[i]], "Jury: bad juror");
            isJuror[jurors_[i]] = true;
        }
        jurors = jurors_;
        quorum = quorum_;
        voteWindow = voteWindow_;
    }

    function caseKey(address taskContract, uint256 tokenId, uint256 submissionId)
        public pure returns (bytes32)
    {
        return keccak256(abi.encodePacked(taskContract, tokenId, submissionId));
    }

    /// @notice Cast a vote on a submission. First vote opens the window.
    ///         K approvals -> acceptFulfillment (settles, pays the fulfiller).
    ///         A blocking minority (rejections > N - K) -> rejectFulfillment.
    function vote(address taskContract, uint256 tokenId, uint256 submissionId, bool approve)
        external
    {
        require(isJuror[msg.sender], "Jury: not a juror");
        bytes32 k = caseKey(taskContract, tokenId, submissionId);
        CaseState storage c = caseOf[k];
        require(!c.closed, "Jury: case closed");
        if (c.firstVoteAt == 0) {
            c.firstVoteAt = uint64(block.timestamp);
        } else {
            require(block.timestamp <= c.firstVoteAt + voteWindow, "Jury: window elapsed");
        }
        require(!voted[k][msg.sender], "Jury: already voted");
        voted[k][msg.sender] = true;
        emit Voted(k, msg.sender, approve);

        if (approve) {
            c.approvals += 1;
            if (c.approvals >= quorum) {
                c.closed = true;
                emit CaseClosed(k, true);
                ITenderSettlement(taskContract).acceptFulfillment(tokenId, submissionId);
            }
        } else {
            c.rejections += 1;
            if (c.rejections > jurors.length - quorum) { // acceptance now impossible
                c.closed = true;
                emit CaseClosed(k, false);
                ITenderSettlement(taskContract).rejectFulfillment(tokenId, submissionId);
            }
        }
    }

    /// @notice Timeout default: a case with votes but no verdict inside the window
    ///         resolves to rejection; anyone may finalize. (The fulfiller may
    ///         resubmit — rejection is per-submission, never per-fulfiller.)
    function finalizeTimeout(address taskContract, uint256 tokenId, uint256 submissionId)
        external
    {
        bytes32 k = caseKey(taskContract, tokenId, submissionId);
        CaseState storage c = caseOf[k];
        require(!c.closed, "Jury: case closed");
        require(c.firstVoteAt != 0, "Jury: no votes");
        require(block.timestamp > c.firstVoteAt + voteWindow, "Jury: window still open");
        c.closed = true;
        emit CaseClosed(k, false);
        ITenderSettlement(taskContract).rejectFulfillment(tokenId, submissionId);
    }

    function jurorCount() external view returns (uint256) {
        return jurors.length;
    }
}
