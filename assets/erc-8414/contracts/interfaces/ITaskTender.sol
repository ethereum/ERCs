// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  Token-Bound Task Tenders — tender interface (TASK-KERNEL v3.0), own ERC-165 id.
/// @notice The reverse-asset layer: per-token bounty vault, immutable terms, bounded
///         and optionally epoch-paced completion, machine or judged settlement, refund.
///         The kernel enforces arithmetic (counting, pacing, solvency, deadlines,
///         authority); the acceptance authority enforces semantics.
///
///         v3.0 closes the free-look asymmetry of the demand side. A Pending
///         submission RESERVES one completion slot and one reward: the reserved
///         reward cannot be refunded, cancelled away, or out-competed, and if the
///         judge neither accepts nor rejects within `judgmentWindow`, the fulfiller
///         claims it. Silence by the party holding the money is no longer free.
interface ITaskTender {
    struct TenderTerms {
        address asset;                  // reward asset; address(0) = chain-native currency
        uint256 rewardPerCompletion;    // paid per accepted completion; MUST be > 0
        uint64  maxCompletions;         // completion bound; 0 = unbounded
        uint64  submitBy;               // unix seconds; no submissions after; 0 = none
        uint64  settleBy;               // unix seconds; no settlements after, refunds unlock; 0 = none
        uint64  epochLength;            // seconds per epoch; 0 = no cadence
        uint64  maxCompletionsPerEpoch; // per-epoch settlement bound; MUST be 0 iff epochLength == 0
        uint64  judgmentWindow;         // seconds a judge has to rule on a submission; MUST be > 0
    }

    enum SubmissionStatus { Pending, Accepted, Rejected }

    struct Submission {
        address          fulfiller;   // address of record; MAY be a team splitter or rights contract
        bytes32          resultHash;  // deliverable commitment; opaque except per acceptance/delivery profile
        uint64           taskVersion; // binding version cited at submission time
        uint64           submittedAt; // block timestamp; starts the judgment clock, and lets
                                      // verifiers require a minimum age against front-running
        bool             machineSettled; // whether the acceptance authority declared
                                      // ITaskVerifier WHEN THIS DELIVERY WAS MADE. Routing
                                      // the deadline off a snapshot rather than off the live
                                      // slot is what stops a demander escaping the deadline
                                      // by swapping the judge after receiving the work.
        SubmissionStatus status;
    }

    event TenderFunded(uint256 indexed tokenId, address indexed funder,
                       uint256 amount, uint256 escrowBalance);
    event TenderCancelled(uint256 indexed tokenId);
    event EscrowReclaimed(uint256 indexed tokenId, address indexed funder, uint256 amount);
    event ResidualReclaimed(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event AcceptanceAuthorityChanged(uint256 indexed tokenId,
                                     address indexed previousAuthority,
                                     address indexed newAuthority);
    event FulfillmentSubmitted(uint256 indexed tokenId, uint256 indexed submissionId,
                               address indexed fulfiller, bytes32 resultHash,
                               string resultURI, uint64 taskVersion);
    event FulfillmentAccepted(uint256 indexed tokenId, uint256 indexed submissionId,
                              address indexed fulfiller, uint256 reward);
    event FulfillmentRejected(uint256 indexed tokenId, uint256 indexed submissionId);
    /// @notice Emitted before `FulfillmentRejected` when a machine-path submission is
    ///         released for never having produced a valid proof, so that an observer
    ///         can tell an expiry from a judge's ruling.
    event SubmissionReleased(uint256 indexed tokenId, uint256 indexed submissionId,
                             uint64 deadline);
    /// @notice Emitted when an accepted payout could not be delivered and was credited
    ///         to the fulfiller instead. The settlement still stands; the money waits.
    event PayoutCredited(uint256 indexed tokenId, uint256 indexed submissionId,
                         address indexed fulfiller, uint256 amount);
    event PayoutWithdrawn(uint256 indexed tokenId, address indexed account, uint256 amount);
    /// @notice Emitted immediately before `FulfillmentAccepted` when the acceptance
    ///         came from the judgment deadline rather than from a judge, so that an
    ///         observer can tell a ruling from a default.
    event FulfillmentClaimedUnjudged(uint256 indexed tokenId, uint256 indexed submissionId,
                                     address indexed fulfiller, uint64 deadline);

    /// @notice The token's bounty vault: a distinct per-token account, visible to
    ///         anyone, spendable by no one, released only through settlement/refund.
    function vaultOf(uint256 tokenId) external view returns (address);
    function tenderTermsOf(uint256 tokenId) external view returns (TenderTerms memory);
    function acceptanceAuthorityOf(uint256 tokenId) external view returns (address);
    /// @notice MUST equal the vault's live balance in the tender asset.
    function escrowBalanceOf(uint256 tokenId) external view returns (uint256);
    /// @notice Submissions currently Pending: each reserves a slot and a reward.
    function pendingOf(uint256 tokenId) external view returns (uint64);
    /// @notice `pendingOf * rewardPerCompletion`, clamped to the vault balance: the
    ///         part of the escrow that is spoken for and cannot be refunded.
    function lockedEscrowOf(uint256 tokenId) external view returns (uint256);
    function completionsOf(uint256 tokenId) external view returns (uint64);
    function completionsInEpochOf(uint256 tokenId, uint64 epoch) external view returns (uint64);
    function isTenderCancelled(uint256 tokenId) external view returns (bool);
    function submissionCountOf(uint256 tokenId) external view returns (uint256);
    function submissionOf(uint256 tokenId, uint256 submissionId)
        external view returns (Submission memory);

    /// @notice Fund the tender's vault. Callable by anyone (bounty pooling), attributed
    ///         for refunds. Direct transfers to the vault count as unattributed gifts.
    function fundTask(uint256 tokenId, uint256 amount) external payable;

    /// @notice Record a fulfillment commitment. Permissionless at this layer, but a
    ///         submission RESERVES a slot and a reward: it reverts unless the tender
    ///         has an unreserved slot and the vault can cover every Pending reward.
    function submitFulfillment(uint256 tokenId, bytes32 resultHash, string calldata resultURI)
        external returns (uint256 submissionId);

    /// @notice Judged settlement path. Only the acceptance authority.
    function acceptFulfillment(uint256 tokenId, uint256 submissionId) external;

    /// @notice Machine settlement path: callable by ANYONE when the acceptance
    ///         authority declares ITaskVerifier via ERC-165. Reverts unless the
    ///         verifier returns true; a failed verification is NOT a rejection.
    function settleFulfillment(uint256 tokenId, uint256 submissionId, bytes calldata proof) external;

    /// @notice Terminal per submission; judged path only; moves no assets. Releases
    ///         the submission's reserved slot and reward.
    function rejectFulfillment(uint256 tokenId, uint256 submissionId) external;

    /// @notice Default judgment. On the JUDGED path only, once `judgmentWindow`
    ///         seconds have passed since submission with no ruling, the reserved
    ///         reward becomes payable to the fulfiller. Permissionless, and
    ///         deliberately immune to cancellation and to `settleBy`: neither
    ///         walking away nor waiting out the clock may strip work already
    ///         delivered. This is what makes a judge's silence cost money.
    function claimUnjudged(uint256 tokenId, uint256 submissionId) external;

    /// @notice Amount owed to `account` because an accepted payout could not be
    ///         delivered to it.
    function creditOf(uint256 tokenId, address account) external view returns (uint256);

    /// @notice Pull a credited payout. Permissionless; the money only ever reaches the
    ///         account it belongs to. Settlement never depends on a recipient being
    ///         willing to receive, so an unreceivable fulfiller can no longer wedge a
    ///         submission and freeze the refunds queued behind it.
    function withdrawCredit(uint256 tokenId, address account) external;

    /// @notice Machine path only: release a submission that never produced a valid
    ///         proof, once `judgmentWindow` has passed, freeing its reserved slot and
    ///         reward. Permissionless. Without it, junk submissions would freeze a
    ///         machine-settled tender forever, since no judge exists to reject them.
    function releaseExpired(uint256 tokenId, uint256 submissionId) external;

    /// @notice Transfer the judgment right. Zero address forbidden.
    function setAcceptanceAuthority(uint256 tokenId, address newAuthority) external;

    /// @notice Irreversibly stop the tender taking new work (update authority only).
    ///         Submissions already Pending survive: they stay judgeable, claimable,
    ///         and their rewards stay locked against refund.
    function cancelTask(uint256 tokenId) external;

    /// @notice Reclaim a funder's pro-rata share of the remaining ATTRIBUTED pool.
    ///         Only when cancelled, or after a nonzero settleBy has passed, and only
    ///         once no submission is still Pending.
    function reclaimEscrow(uint256 tokenId) external;

    /// @notice Reclaim the vault's residual — unattributed gifts and rounding dust —
    ///         to the token OWNER. Same gate as reclaimEscrow. Rewards consume gifts
    ///         before attributed funds, so the residual is whatever gifting the
    ///         completed work did not spend.
    function reclaimResidual(uint256 tokenId) external;
}
