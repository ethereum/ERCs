// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ITaskToken} from "./interfaces/ITaskToken.sol";
import {ITaskTender} from "./interfaces/ITaskTender.sol";
import {ITaskVerifier} from "./interfaces/ITaskVerifier.sol";
import {IOnchainTaskDocument} from "./interfaces/IOnchainTaskDocument.sol";
import {TaskVault} from "./TaskVault.sol";

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IERC165Probe {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title  TaskToken — reference implementation of Token-Bound Task Tenders
///         (TASK-KERNEL v3.0). Self-contained minimal ERC-721 + all interfaces,
///         deploying one locked TaskVault per token.
/// @notice Reference quality: favors clarity and 1:1 spec traceability over gas.
contract TaskToken is ITaskToken, ITaskTender, IOnchainTaskDocument {

    // ---------------------------------------------------------------- ERC-721 core
    string public name;
    string public symbol;

    mapping(uint256 => address) private _owner;
    mapping(address => uint256) private _balance;
    mapping(uint256 => address) private _tokenApproval;
    mapping(address => mapping(address => bool)) private _operatorApproval;

    // -------------------------------------------------------------- Task binding
    mapping(uint256 => TaskBinding) private _binding;
    mapping(uint256 => string)  private _taskURI;         // transport hint, outside identity
    mapping(uint256 => address) private _updateAuthority; // publication right, outside ownership
    mapping(uint256 => bool)    private _frozen;

    // -------------------------------------------------------------- Tender layer
    mapping(uint256 => TenderTerms)  private _terms;               // immutable after mint
    mapping(uint256 => TaskVault)    private _vault;               // per-token locked bounty vault
    mapping(uint256 => address)      private _acceptanceAuthority; // judgment right
    mapping(uint256 => bool)         private _cancelled;
    mapping(uint256 => uint64)       private _completions;
    mapping(uint256 => mapping(uint64 => uint64)) private _epochCompletions;
    mapping(uint256 => uint256)      private _submissionCount;
    mapping(uint256 => mapping(uint256 => Submission)) private _submissions;
    // v3.0 reservation: every Pending submission holds one completion slot and one
    // reward. Reserved rewards are unrefundable and uncancellable — the demand side
    // cannot take back money that delivered work is already waiting on.
    mapping(uint256 => uint64)       private _pending;
    // A settlement must never depend on the recipient being willing to receive. When a
    // payout fails the amount is credited here and stays in the vault until pulled; it
    // is owed money, so it is excluded from everything distributable.
    mapping(uint256 => mapping(address => uint256)) private _credit;
    mapping(uint256 => uint256)      private _creditTotal;
    // Refunds are computed against a snapshot taken at the first reclaim, so the order
    // in which funders show up cannot change what any of them receives.
    mapping(uint256 => uint256)      private _refundPool;
    mapping(uint256 => uint256)      private _refundDenom;
    mapping(uint256 => bool)         private _refundOpen;
    // refund accounting: attributed contributions, pro-rata reclaim over the
    // ATTRIBUTED pool only. Rewards consume unattributed gifts before attributed
    // funds; residual gifts + dust go to the token owner (reclaimResidual).
    mapping(uint256 => mapping(address => uint256)) private _contributed;
    mapping(uint256 => uint256) private _totalOutstanding; // sum of not-yet-reclaimed contributions
    mapping(uint256 => uint256) private _attributedPool;   // attributed funds not yet paid out or refunded

    // -------------------------------------------- On-chain document (optional ext)
    mapping(uint256 => bytes) private _document;    // plaintext primary document
    mapping(uint256 => bool)  private _hasDocument; // monotone: false -> true only

    uint256 public nextId = 1;
    uint256 private _entered = 1; // reentrancy guard for funding/settlement/refund paths

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    // =============================================================== modifiers
    modifier exists(uint256 tokenId) {
        require(_owner[tokenId] != address(0), "TaskToken: nonexistent token");
        _;
    }

    /// Publication powers belong to the update authority alone. ERC-721 owner,
    /// approved, and operators MUST NOT reach these functions (approval-leakage rule).
    modifier onlyUpdateAuthority(uint256 tokenId) {
        require(msg.sender == _updateAuthority[tokenId], "TaskToken: not publisher");
        _;
    }

    /// Judgment powers belong to the acceptance authority alone.
    modifier onlyAcceptanceAuthority(uint256 tokenId) {
        require(msg.sender == _acceptanceAuthority[tokenId], "TaskToken: not judge");
        _;
    }

    modifier nonReentrant() {
        require(_entered == 1, "TaskToken: reentrancy");
        _entered = 2;
        _;
        _entered = 1;
    }

    // =============================================================== ERC-165
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7                              // ERC-165
            || id == 0x80ac58cd                              // ERC-721
            || id == 0x5b5e139f                              // ERC-721 Metadata
            || id == type(ITaskToken).interfaceId
            || id == type(ITaskTender).interfaceId
            || id == type(IOnchainTaskDocument).interfaceId;
    }

    // =============================================================== mint
    /// @notice Mint a new task token. Binding, vault, and tender fully populated;
    ///         placeholder minting is impossible. Terms are immutable thereafter.
    ///         Deploys the token's locked bounty vault. Emits TaskUpdated (version 1)
    ///         and both genesis authority events so the event stream is complete history.
    function mintTask(
        address to,
        address updateAuthority_,
        address acceptanceAuthority_,
        bytes32 tdHash,
        bytes32 taskHash,
        string calldata taskURI_,
        TenderTerms calldata terms
    ) external returns (uint256 tokenId) {
        require(to != address(0), "TaskToken: mint to zero");
        require(updateAuthority_ != address(0), "TaskToken: zero publisher");
        require(acceptanceAuthority_ != address(0), "TaskToken: zero judge");
        require(tdHash != bytes32(0) && taskHash != bytes32(0), "TaskToken: zero hash");
        require(bytes(taskURI_).length != 0, "TaskToken: empty taskURI");
        require(terms.rewardPerCompletion > 0, "TaskToken: zero reward");
        if (terms.submitBy != 0 && terms.settleBy != 0) {
            require(terms.settleBy >= terms.submitBy, "TaskToken: settleBy < submitBy");
        }
        // epoch pacing: both zero (off) or both nonzero (standing tender)
        require(
            (terms.epochLength == 0) == (terms.maxCompletionsPerEpoch == 0),
            "TaskToken: bad epoch fields"
        );
        // Judgment must have a deadline. Required even when the tender mints with a
        // verifier in the judgment slot, because that slot is transferable: any
        // machine-settled tender can become judged later, and a judged tender with
        // no deadline is a tender with no obligation.
        require(terms.judgmentWindow > 0, "TaskToken: zero judgmentWindow");

        tokenId = nextId++;
        _owner[tokenId] = to;
        _balance[to] += 1;
        emit Transfer(address(0), to, tokenId);

        _binding[tokenId] = TaskBinding(tdHash, taskHash, 1);
        _taskURI[tokenId] = taskURI_;
        _updateAuthority[tokenId] = updateAuthority_;
        _acceptanceAuthority[tokenId] = acceptanceAuthority_;
        _terms[tokenId] = terms;
        _vault[tokenId] = new TaskVault(); // the money lives IN the token

        emit TaskUpdated(tokenId, tdHash, taskHash, 1);
        emit TaskUpdateAuthorityChanged(tokenId, address(0), updateAuthority_);
        emit AcceptanceAuthorityChanged(tokenId, address(0), acceptanceAuthority_);
    }

    // =============================================================== ITaskToken views
    function taskOf(uint256 tokenId) external view exists(tokenId) returns (TaskBinding memory) {
        return _binding[tokenId];
    }

    function taskURI(uint256 tokenId) external view exists(tokenId) returns (string memory) {
        return _taskURI[tokenId];
    }

    function updateAuthorityOf(uint256 tokenId) external view exists(tokenId) returns (address) {
        return _updateAuthority[tokenId];
    }

    function isTaskFrozen(uint256 tokenId) external view exists(tokenId) returns (bool) {
        return _frozen[tokenId];
    }

    // =============================================================== ITaskToken mutations
    function updateTask(uint256 tokenId, bytes32 tdHash, bytes32 taskHash)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        // On-chain document consistency: when a copy exists and tdHash would change,
        // the update MUST go through updateTaskWithDocument (atomic doc+binding).
        require(
            !_hasDocument[tokenId] || tdHash == _binding[tokenId].tdHash,
            "TaskToken: use doc update"
        );
        _applyUpdate(tokenId, tdHash, taskHash);
    }

    function _applyUpdate(uint256 tokenId, bytes32 tdHash, bytes32 taskHash) private {
        require(!_frozen[tokenId], "TaskToken: frozen");
        require(tdHash != bytes32(0) && taskHash != bytes32(0), "TaskToken: zero hash");
        TaskBinding storage b = _binding[tokenId];
        require(taskHash != b.taskHash, "TaskToken: taskHash must differ");
        // uint64 overflow reverts natively under solc >= 0.8 (append-only guarantee)
        b.tdHash = tdHash;
        b.taskHash = taskHash;
        b.version += 1;
        emit TaskUpdated(tokenId, tdHash, taskHash, b.version);
    }

    /// Transport is outside identity: never changes version; allowed while frozen.
    function setTaskURI(uint256 tokenId, string calldata taskURI_)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(bytes(taskURI_).length != 0, "TaskToken: empty taskURI");
        _taskURI[tokenId] = taskURI_;
        emit TaskURIUpdated(tokenId, taskURI_);
    }

    /// Zero authority is forbidden: walking away from a live tender is expressed
    /// by cancelTask or by deadlines, never by burning the authority.
    function setUpdateAuthority(uint256 tokenId, address newAuthority)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(newAuthority != address(0), "TaskToken: zero authority");
        address prev = _updateAuthority[tokenId];
        _updateAuthority[tokenId] = newAuthority;
        emit TaskUpdateAuthorityChanged(tokenId, prev, newAuthority);
    }

    /// Irreversible: binds content (hashes, version), not transport, not the tender.
    /// A frozen tender is a BINDING tender — freezing typically begins a task's
    /// active life (freeze, fund, let fulfillers work against immovable spec).
    function freezeTask(uint256 tokenId)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(!_frozen[tokenId], "TaskToken: already frozen");
        _frozen[tokenId] = true;
        emit TaskFrozen(tokenId);
    }

    // =============================================================== ITaskTender views
    function vaultOf(uint256 tokenId) external view exists(tokenId) returns (address) {
        return address(_vault[tokenId]);
    }

    function tenderTermsOf(uint256 tokenId) external view exists(tokenId) returns (TenderTerms memory) {
        return _terms[tokenId];
    }

    function acceptanceAuthorityOf(uint256 tokenId) external view exists(tokenId) returns (address) {
        return _acceptanceAuthority[tokenId];
    }

    /// Escrow IS the vault's live balance: solvency is a fact, not a ledger claim.
    function escrowBalanceOf(uint256 tokenId) public view exists(tokenId) returns (uint256) {
        address vault = address(_vault[tokenId]);
        address asset = _terms[tokenId].asset;
        return asset == address(0) ? vault.balance : IERC20Minimal(asset).balanceOf(vault);
    }

    /// The vault balance minus amounts already owed to a fulfiller whose payout could
    /// not be delivered. Everything that allocates escrow measures against this, never
    /// against the raw balance: credited money is spent, it merely has not moved yet.
    function _available(uint256 tokenId) private view returns (uint256) {
        uint256 bal = escrowBalanceOf(tokenId);
        uint256 owed = _creditTotal[tokenId];
        return bal > owed ? bal - owed : 0;
    }

    /// Amount owed to `account` on this token because a payout could not be delivered.
    function creditOf(uint256 tokenId, address account)
        external view exists(tokenId) returns (uint256)
    {
        return _credit[tokenId][account];
    }

    /// Pull a credited payout. Permissionless: the money only ever goes to its owner.
    function withdrawCredit(uint256 tokenId, address account)
        external exists(tokenId) nonReentrant
    {
        uint256 amount = _credit[tokenId][account];
        require(amount > 0, "TaskToken: nothing credited");
        _credit[tokenId][account] = 0;
        _creditTotal[tokenId] -= amount;
        emit PayoutWithdrawn(tokenId, account, amount);
        _vault[tokenId].payout(_terms[tokenId].asset, account, amount);
    }

    /// Submissions awaiting judgment. Each one reserves a slot and a reward.
    function pendingOf(uint256 tokenId) public view exists(tokenId) returns (uint64) {
        return _pending[tokenId];
    }

    /// The spoken-for part of the escrow: what delivered work is already owed.
    /// Clamped to the live balance so a nonstandard asset cannot underflow it.
    function lockedEscrowOf(uint256 tokenId) public view exists(tokenId) returns (uint256) {
        uint256 locked = uint256(_pending[tokenId]) * _terms[tokenId].rewardPerCompletion;
        uint256 bal = _available(tokenId);
        return locked > bal ? bal : locked;
    }

    function completionsOf(uint256 tokenId) external view exists(tokenId) returns (uint64) {
        return _completions[tokenId];
    }

    function completionsInEpochOf(uint256 tokenId, uint64 epoch)
        external view exists(tokenId) returns (uint64)
    {
        return _epochCompletions[tokenId][epoch];
    }

    function isTenderCancelled(uint256 tokenId) external view exists(tokenId) returns (bool) {
        return _cancelled[tokenId];
    }

    function submissionCountOf(uint256 tokenId) external view exists(tokenId) returns (uint256) {
        return _submissionCount[tokenId];
    }

    function submissionOf(uint256 tokenId, uint256 submissionId)
        external view exists(tokenId) returns (Submission memory)
    {
        require(submissionId >= 1 && submissionId <= _submissionCount[tokenId],
                "TaskToken: nonexistent submission");
        return _submissions[tokenId][submissionId];
    }

    // =============================================================== funding
    /// Anyone may fund (bounty pooling); every fundTask deposit lands in the VAULT
    /// and is attributed for refunds. Direct transfers to the vault also count as
    /// escrow (live-balance reads) but are unattributed gifts.
    function fundTask(uint256 tokenId, uint256 amount)
        external payable exists(tokenId) nonReentrant
    {
        require(!_cancelled[tokenId], "TaskToken: cancelled");
        // Once the first funder has reclaimed, the pro-rata ratio is frozen. Money
        // arriving after that would be divided by a denominator taken before it
        // existed, so a late funder would reclaim less than it put in and the shortfall
        // would sit in the vault with no claimant. Funding closes with the snapshot.
        require(!_refundOpen[tokenId], "TaskToken: refunding");
        require(amount > 0, "TaskToken: zero amount");
        address asset = _terms[tokenId].asset;
        address payable vault = payable(address(_vault[tokenId]));
        uint256 credited;
        if (asset == address(0)) {
            require(msg.value == amount, "TaskToken: msg.value != amount");
            (bool ok, ) = vault.call{value: amount}("");
            require(ok, "TaskToken: vault deposit failed");
            credited = amount;
        } else {
            require(msg.value == 0, "TaskToken: native value");
            IERC20Minimal t = IERC20Minimal(asset);
            uint256 before = t.balanceOf(vault);
            require(t.transferFrom(msg.sender, vault, amount), "TaskToken: transferFrom failed");
            credited = t.balanceOf(vault) - before; // fee-on-transfer tolerance
            require(credited > 0, "TaskToken: nothing received");
        }
        _contributed[tokenId][msg.sender] += credited;
        _totalOutstanding[tokenId] += credited;
        _attributedPool[tokenId] += credited;
        emit TenderFunded(tokenId, msg.sender, credited, escrowBalanceOf(tokenId));
    }

    // =============================================================== submission
    /// Permissionless at this layer: eligibility narrowing belongs to acceptance
    /// and companion bidding standards. Records the cited binding version so any
    /// observer can reconstruct exactly which specification a completion fulfilled.
    function submitFulfillment(uint256 tokenId, bytes32 resultHash, string calldata resultURI)
        external exists(tokenId) returns (uint256 submissionId)
    {
        require(!_cancelled[tokenId], "TaskToken: cancelled");
        require(resultHash != bytes32(0), "TaskToken: zero resultHash");
        TenderTerms storage t = _terms[tokenId];
        require(t.submitBy == 0 || block.timestamp <= t.submitBy, "TaskToken: past submitBy");
        // never accept work into a tender that can no longer settle it
        require(t.settleBy == 0 || block.timestamp <= t.settleBy, "TaskToken: past settleBy");
        // a slot is reserved from the moment work is delivered, not from acceptance:
        // otherwise a judge could exhaust the bound with other completions and starve
        // a submission it is sitting on.
        require(t.maxCompletions == 0 ||
                uint256(_completions[tokenId]) + _pending[tokenId] < t.maxCompletions,
                "TaskToken: completions exhausted");
        // and the reward is reserved with it: the vault must be able to pay every
        // Pending submission at once before it may take on one more.
        require(_available(tokenId) >= (uint256(_pending[tokenId]) + 1) * t.rewardPerCompletion,
                "TaskToken: escrow too low");

        submissionId = ++_submissionCount[tokenId];
        uint64 v = _binding[tokenId].version;
        // Snapshot the settlement mode as it stands for THIS delivery. Reading the live
        // authority later would let a demander receive the work and then swap the
        // judgment slot to escape the deadline in either direction.
        _submissions[tokenId][submissionId] = Submission(
            msg.sender, resultHash, v, uint64(block.timestamp),
            _declaresVerifier(_acceptanceAuthority[tokenId]), SubmissionStatus.Pending);
        _pending[tokenId] += 1;
        emit FulfillmentSubmitted(tokenId, submissionId, msg.sender, resultHash, resultURI, v);
    }

    // =============================================================== settlement
    /// Common preconditions for both settlement paths. Returns the submission.
    function _settleChecks(uint256 tokenId, uint256 submissionId)
        private view returns (Submission storage s, TenderTerms storage t)
    {
        // NOTE: cancellation is deliberately NOT checked here. Cancelling stops new
        // work; it does not strip work already delivered. Submissions Pending at
        // cancellation stay judgeable, settleable, and claimable.
        t = _terms[tokenId];
        require(t.settleBy == 0 || block.timestamp <= t.settleBy, "TaskToken: past settleBy");
        require(t.maxCompletions == 0 || _completions[tokenId] < t.maxCompletions,
                "TaskToken: completions exhausted");
        if (t.epochLength != 0) {
            uint64 epoch = uint64(block.timestamp / t.epochLength);
            require(_epochCompletions[tokenId][epoch] < t.maxCompletionsPerEpoch,
                    "TaskToken: epoch exhausted");
        }
        require(submissionId >= 1 && submissionId <= _submissionCount[tokenId],
                "TaskToken: nonexistent submission");
        s = _submissions[tokenId][submissionId];
        require(s.status == SubmissionStatus.Pending, "TaskToken: not pending");
        require(_available(tokenId) >= t.rewardPerCompletion, "TaskToken: insolvent vault");
    }

    /// Common effects: status, counts, gift-first escrow accounting, payout from
    /// the vault, event. Effects strictly precede the asset transfer.
    function _settleEffects(uint256 tokenId, uint256 submissionId,
                            Submission storage s, TenderTerms storage t) private {
        s.status = SubmissionStatus.Accepted;
        _completions[tokenId] += 1;
        _pending[tokenId] -= 1; // the reservation is consumed by the payout below
        if (t.epochLength != 0) {
            _epochCompletions[tokenId][uint64(block.timestamp / t.epochLength)] += 1;
        }
        // gift-first consumption: rewards spend unattributed gifts before the
        // attributed pool, maximizing what funders can later reclaim.
        uint256 reward = t.rewardPerCompletion;
        uint256 pool = _clampedPool(tokenId);
        uint256 gift = _available(tokenId) - pool;
        if (reward > gift) {
            _attributedPool[tokenId] = pool - (reward - gift);
        } else {
            _attributedPool[tokenId] = pool; // write back the clamp; gifts covered it all
        }
        emit FulfillmentAccepted(tokenId, submissionId, s.fulfiller, reward);
        if (!_vault[tokenId].tryPayout(t.asset, s.fulfiller, reward)) {
            // The recipient will not take it. The settlement still stands -- the work
            // was accepted and the money is spent -- and the amount waits in the vault
            // for its owner to pull. Reverting here would let an unreceivable fulfiller
            // wedge the submission forever and freeze every refund queued behind it.
            _credit[tokenId][s.fulfiller] += reward;
            _creditTotal[tokenId] += reward;
            emit PayoutCredited(tokenId, submissionId, s.fulfiller, reward);
        }
    }

    /// The attributed pool can never exceed the vault's live balance (guards
    /// nonstandard-asset drift); clamp before any accounting that reads it.
    function _clampedPool(uint256 tokenId) private view returns (uint256) {
        uint256 pool = _attributedPool[tokenId];
        uint256 bal = _available(tokenId);
        return pool > bal ? bal : pool;
    }

    /// Judged path: only the acceptance authority.
    function acceptFulfillment(uint256 tokenId, uint256 submissionId)
        external exists(tokenId) onlyAcceptanceAuthority(tokenId) nonReentrant
    {
        (Submission storage s, TenderTerms storage t) = _settleChecks(tokenId, submissionId);
        _settleEffects(tokenId, submissionId, s, t);
    }

    /// Machine path: callable by ANYONE (typically the fulfiller, self-serving the
    /// payout) when the acceptance authority declares ITaskVerifier via ERC-165.
    /// A failed verification is NOT a rejection: the submission stays Pending.
    function settleFulfillment(uint256 tokenId, uint256 submissionId, bytes calldata proof)
        external exists(tokenId) nonReentrant
    {
        address auth = _acceptanceAuthority[tokenId];
        require(_declaresVerifier(auth), "TaskToken: not a verifier");
        (Submission storage s, TenderTerms storage t) = _settleChecks(tokenId, submissionId);
        require(
            ITaskVerifier(auth).verifyFulfillment(
                address(this), tokenId, submissionId, s.fulfiller, s.resultHash, proof
            ),
            "TaskToken: verification failed"
        );
        _settleEffects(tokenId, submissionId, s, t);
    }

    function _declaresVerifier(address auth) private view returns (bool) {
        if (auth.code.length == 0) return false;
        try IERC165Probe(auth).supportsInterface(type(ITaskVerifier).interfaceId)
            returns (bool ok) { return ok; } catch { return false; }
    }

    /// Terminal per submission (no equivocation: a rejected submission can never
    /// later be accepted or settled); judged path only; moves no assets.
    function rejectFulfillment(uint256 tokenId, uint256 submissionId)
        external exists(tokenId) onlyAcceptanceAuthority(tokenId)
    {
        // rejecting stays available after cancellation: a judge that walks away
        // still has to say so, on the record, for work it has already received.
        require(submissionId >= 1 && submissionId <= _submissionCount[tokenId],
                "TaskToken: nonexistent submission");
        Submission storage s = _submissions[tokenId][submissionId];
        require(s.status == SubmissionStatus.Pending, "TaskToken: not pending");
        // The right to refuse expires exactly when the right to claim begins. Without
        // this a judge could stay silent for the whole window and then front-run the
        // claim with a refusal, which makes the deadline worthless -- and worse under
        // pacing, where a queued claim waits out a whole epoch in the open.
        require(block.timestamp <= uint256(s.submittedAt) + _terms[tokenId].judgmentWindow,
                "TaskToken: window closed");
        s.status = SubmissionStatus.Rejected;
        _pending[tokenId] -= 1; // releases the reserved slot and reward
        emit FulfillmentRejected(tokenId, submissionId);
    }

    /// Default judgment. On the JUDGED path only: once judgmentWindow seconds have
    /// passed with no ruling, the fulfiller takes the reward that its submission
    /// reserved. Permissionless, and immune to cancellation and to settleBy — the
    /// two levers a demander could otherwise pull to keep both the work and the
    /// money. Silence is now the most expensive thing a judge can do.
    function claimUnjudged(uint256 tokenId, uint256 submissionId)
        external exists(tokenId) nonReentrant
    {
        require(submissionId >= 1 && submissionId <= _submissionCount[tokenId],
                "TaskToken: nonexistent submission");
        Submission storage s = _submissions[tokenId][submissionId];
        require(!s.machineSettled,
                "TaskToken: machine-path delivery");
        require(s.status == SubmissionStatus.Pending, "TaskToken: not pending");
        TenderTerms storage t = _terms[tokenId];
        uint256 deadline = uint256(s.submittedAt) + t.judgmentWindow;
        require(block.timestamp > deadline, "TaskToken: window open");
        // A default is still a settlement, so it is still paced. Skipping this would
        // let a provider deliver a whole standing tender's worth of work at once and,
        // on the judge's silence, drain the entire budget inside a single epoch —
        // exactly the drain the cadence exists to prevent. The claim is not lost, only
        // queued: it becomes available in the next epoch.
        if (t.epochLength != 0) {
            uint64 epoch = uint64(block.timestamp / t.epochLength);
            require(_epochCompletions[tokenId][epoch] < t.maxCompletionsPerEpoch,
                    "TaskToken: epoch exhausted");
        }
        // _available, not the raw balance: a credited payout is already spoken for, and
        // paying a default claim out of it would leave the credit unbacked.
        require(_available(tokenId) >= t.rewardPerCompletion, "TaskToken: insolvent vault");
        emit FulfillmentClaimedUnjudged(tokenId, submissionId, s.fulfiller, uint64(deadline));
        _settleEffects(tokenId, submissionId, s, t);
    }

    /// Machine-path counterpart to claimUnjudged. A submission whose proof never
    /// verified would otherwise squat its reservation forever: there is no judge to
    /// reject it, and the default claim is refused on this path. Without a release,
    /// anyone could brick a machine-settled tender by filling every slot with junk
    /// and freezing the vault permanently. After the same window, anyone may release
    /// it; a solver who was merely slow simply submits again.
    function releaseExpired(uint256 tokenId, uint256 submissionId)
        external exists(tokenId)
    {
        require(submissionId >= 1 && submissionId <= _submissionCount[tokenId],
                "TaskToken: nonexistent submission");
        Submission storage s = _submissions[tokenId][submissionId];
        require(s.machineSettled,
                "TaskToken: judged-path delivery");
        require(s.status == SubmissionStatus.Pending, "TaskToken: not pending");
        uint256 deadline = uint256(s.submittedAt) + _terms[tokenId].judgmentWindow;
        require(block.timestamp > deadline, "TaskToken: window open");
        s.status = SubmissionStatus.Rejected;
        _pending[tokenId] -= 1;
        emit SubmissionReleased(tokenId, submissionId, uint64(deadline));
        emit FulfillmentRejected(tokenId, submissionId);
    }

    /// Judgment is a separately transferable right; zero forbidden (mirror rule).
    function setAcceptanceAuthority(uint256 tokenId, address newAuthority)
        external exists(tokenId) onlyAcceptanceAuthority(tokenId)
    {
        require(newAuthority != address(0), "TaskToken: zero authority");
        address prev = _acceptanceAuthority[tokenId];
        _acceptanceAuthority[tokenId] = newAuthority;
        emit AcceptanceAuthorityChanged(tokenId, prev, newAuthority);
    }

    // =============================================================== cancel & reclaim
    /// Irreversible tender termination (update authority only). A tender act,
    /// not a binding act: tdHash/taskHash/version/frozen unchanged.
    function cancelTask(uint256 tokenId)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(!_cancelled[tokenId], "TaskToken: already cancelled");
        _cancelled[tokenId] = true;
        emit TenderCancelled(tokenId);
    }

    /// Pro-rata reclaim over the ATTRIBUTED pool only: contributed * pool /
    /// totalOutstanding. Unattributed gifts never flow to funders — they belong
    /// to the token owner (reclaimResidual). Floors in the funder's disfavor;
    /// dust joins the residual.
    function reclaimEscrow(uint256 tokenId)
        external exists(tokenId) nonReentrant
    {
        TenderTerms storage t = _terms[tokenId];
        _requireRefundable(tokenId, t);
        uint256 contributed = _contributed[tokenId][msg.sender];
        require(contributed > 0, "TaskToken: nothing to reclaim");
        // Snapshot the pool and the denominator at the FIRST reclaim. Recomputing them
        // per caller made every funder's share depend on the order people showed up in.
        if (!_refundOpen[tokenId]) {
            _refundOpen[tokenId] = true;
            _refundPool[tokenId] = _clampedPool(tokenId);
            _refundDenom[tokenId] = _totalOutstanding[tokenId];
        }
        uint256 refund = contributed * _refundPool[tokenId] / _refundDenom[tokenId];

        // effects
        _contributed[tokenId][msg.sender] = 0;
        _totalOutstanding[tokenId] -= contributed;
        // flooring dust stays behind and joins the owner's residual
        _attributedPool[tokenId] = _attributedPool[tokenId] > refund
            ? _attributedPool[tokenId] - refund : 0;
        // ...but only if the pool is actually released when the last funder leaves.
        // Otherwise the dust stays inside the attributed pool, reclaimResidual keeps
        // subtracting it, and it is locked in the vault forever instead of accruing to
        // the owner as this contract and the standard both promise.
        if (_totalOutstanding[tokenId] == 0) _attributedPool[tokenId] = 0;
        emit EscrowReclaimed(tokenId, msg.sender, refund);

        // interaction
        if (refund > 0) _vault[tokenId].payout(t.asset, msg.sender, refund);
    }

    /// The residual — unattributed gifts plus rounding dust — goes to the token
    /// OWNER: gifts were given to the bounty, not lent to it, and whatever the
    /// completed work did not spend accrues to the holder of the tender asset.
    function reclaimResidual(uint256 tokenId)
        external exists(tokenId) nonReentrant
    {
        TenderTerms storage t = _terms[tokenId];
        _requireRefundable(tokenId, t);
        address owner_ = ownerOf(tokenId);
        require(msg.sender == owner_, "TaskToken: not token owner");
        uint256 residual = _available(tokenId) - _clampedPool(tokenId);
        require(residual > 0, "TaskToken: no residual");
        emit ResidualReclaimed(tokenId, owner_, residual);
        _vault[tokenId].payout(t.asset, owner_, residual);
    }

    function _requireRefundable(uint256 tokenId, TenderTerms storage t) private view {
        require(
            _cancelled[tokenId] || (t.settleBy != 0 && block.timestamp > t.settleBy),
            "TaskToken: tender still live"
        );
        // Nothing leaves the vault while delivered work is still undecided. The wait
        // is bounded: every Pending submission becomes claimable by its fulfiller at
        // submittedAt + judgmentWindow, so funders can always be made whole eventually.
        require(_pending[tokenId] == 0, "TaskToken: pending outstanding");
    }

    // =============================================================== IOnchainTaskDocument
    function hasOnchainTaskDocument(uint256 tokenId)
        external view exists(tokenId) returns (bool)
    {
        return _hasDocument[tokenId];
    }

    function taskDocument(uint256 tokenId)
        external view exists(tokenId) returns (bytes memory)
    {
        require(_hasDocument[tokenId], "TaskToken: no on-chain document");
        return _document[tokenId];
    }

    /// Disclosure without a version change: document must be the current committed
    /// plaintext. Restricted to the update authority — publishing on-chain is an
    /// irreversible disclosure decision, i.e. a publication act.
    function publishTaskDocument(uint256 tokenId, bytes calldata document)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        require(sha256(document) == _binding[tokenId].tdHash, "TaskToken: doc != tdHash");
        _document[tokenId] = document;
        _hasDocument[tokenId] = true; // monotone; never unset anywhere
        emit TaskDocumentPublished(tokenId, _binding[tokenId].tdHash);
    }

    /// Atomic document+binding update: tdHash computed in-contract, making the
    /// doc/hash-agreement invariant structural rather than procedural.
    function updateTaskWithDocument(uint256 tokenId, bytes calldata document, bytes32 taskHash)
        external exists(tokenId) onlyUpdateAuthority(tokenId)
    {
        bytes32 tdHash = sha256(document);
        _applyUpdate(tokenId, tdHash, taskHash);
        _document[tokenId] = document;
        _hasDocument[tokenId] = true; // may transition false -> true; never back
        emit TaskDocumentPublished(tokenId, tdHash);
    }

    // =============================================================== ERC-721 (minimal)
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address a) external view returns (uint256) {
        require(a != address(0), "TaskToken: zero address");
        return _balance[a];
    }

    function ownerOf(uint256 tokenId) public view exists(tokenId) returns (address) {
        return _owner[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        require(msg.sender == o || _operatorApproval[o][msg.sender], "TaskToken: not authorized");
        _tokenApproval[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view exists(tokenId) returns (address) {
        return _tokenApproval[tokenId];
    }

    function setApprovalForAll(address op, bool ok) external {
        _operatorApproval[msg.sender][op] = ok;
        emit ApprovalForAll(msg.sender, op, ok);
    }

    function isApprovedForAll(address o, address op) external view returns (bool) {
        return _operatorApproval[o][op];
    }

    /// NOTE: ERC-721 transfer moves the ASSET — vault included, since the vault is
    /// keyed to the tokenId. It never touches the update authority OR the acceptance
    /// authority — buyers must inspect updateAuthorityOf, acceptanceAuthorityOf,
    /// isTaskFrozen, isTenderCancelled.
    function transferFrom(address from, address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        require(o == from, "TaskToken: wrong from");
        require(to != address(0), "TaskToken: zero to");
        require(
            msg.sender == o || msg.sender == _tokenApproval[tokenId] || _operatorApproval[o][msg.sender],
            "TaskToken: not authorized"
        );
        delete _tokenApproval[tokenId];
        _balance[from] -= 1;
        _balance[to] += 1;
        _owner[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length != 0) {
            (bool ok, bytes memory ret) = to.call(
                abi.encodeWithSignature(
                    "onERC721Received(address,address,uint256,bytes)", msg.sender, from, tokenId, data
                )
            );
            require(ok && ret.length >= 32 && bytes4(ret) == 0x150b7a02, "TaskToken: unsafe receiver");
        }
    }

    /// Display convention only; MUST NOT be used for verification (spec rule).
    function tokenURI(uint256 tokenId) external view exists(tokenId) returns (string memory) {
        return _taskURI[tokenId]; // reference impl mirrors the transport hint for wallets
    }
}
