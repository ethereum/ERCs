// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../interfaces/IAAP.sol";
import "../interfaces/IERC20.sol";

/// @title AAPMockMinimal — Minimal ERC-8210 implementation for reference scenarios.
/// @notice Implements the subset of ERC-8210 v1 needed by the three scenarios in
///         this folder. Behaves identically to the canonical spec for the covered
///         operations but omits features not exercised by the scenarios (e.g.
///         release/expire flows, account pausing, settlement asset management).
///
///         This mock is NOT a substitute for a production AAP implementation.
///         It exists solely to validate that the composition patterns demonstrated
///         in the scenarios remain expressible through the canonical spec interface.
contract AAPMockMinimal is IAAP {
    IERC20  public token;
    address public resolver;

    // ─────────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────────

    struct Account {
        uint256 totalFunded;
        uint256 availableAmount;
        uint256 lockedAmount;
        uint256 paidOutAmount;
    }

    mapping(address => Account)      private _accounts;
    mapping(bytes32 => JobAssurance) private _assurances;
    mapping(bytes32 => Claim)        private _claims;
    mapping(address => uint256)      private _assuranceNonce;
    uint256 private _claimNonce;

    /// @notice Hash of the evidence bytes payload, keyed by claimId.
    /// @dev    Mirrors the canonical reference implementation. Scenarios verify
    ///         that the encoded evidence (which carries upstream references,
    ///         slash record references, or offchain scoring CIDs) is faithfully
    ///         hashed and stored on chain.
    mapping(bytes32 => bytes32) public evidenceHashes;

    constructor(address _token, address _resolver) {
        token    = IERC20(_token);
        resolver = _resolver;
    }

    // ─────────────────────────────────────────────────────────────────
    // AssuranceAccount lifecycle
    // ─────────────────────────────────────────────────────────────────

    function depositAssurance(uint256 amount) external override {
        require(amount > 0, "AAP: amount is 0");
        token.transferFrom(msg.sender, address(this), amount);

        Account storage acct = _accounts[msg.sender];
        acct.totalFunded     += amount;
        acct.availableAmount += amount;
    }

    // ─────────────────────────────────────────────────────────────────
    // JobAssurance lifecycle
    // ─────────────────────────────────────────────────────────────────

    function commitToJob(
        bytes32 jobId,
        CoverageType coverageType,
        address beneficiary,
        uint256 amount,
        uint64 expiry
    ) external override returns (bytes32 assuranceId) {
        require(amount > 0, "AAP: amount is 0");
        require(beneficiary != address(0), "AAP: zero beneficiary");
        require(expiry > block.timestamp, "AAP: expiry in the past");

        Account storage acct = _accounts[msg.sender];
        require(acct.availableAmount >= amount, "AAP: insufficient available");

        // Generate collision-resistant assuranceId (matches spec ID generation pattern)
        assuranceId = keccak256(abi.encodePacked(
            "AAP_ASSURANCE",
            msg.sender,
            jobId,
            uint8(coverageType),
            _assuranceNonce[msg.sender]++
        ));

        // Reserve funds
        acct.availableAmount -= amount;
        acct.lockedAmount    += amount;

        _assurances[assuranceId] = JobAssurance({
            assuranceId:     assuranceId,
            assuredAgent:    msg.sender,
            beneficiary:     beneficiary,
            coveredJob:      jobId,
            coverageType:    coverageType,
            committedAmount: amount,
            expiry:          expiry,
            chainId:         block.chainid,
            claimId:         bytes32(0),
            state:           AssuranceState.Active
        });

        emit AssuranceCommitted(assuranceId, msg.sender, jobId, beneficiary, coverageType, amount, expiry);
    }

    // ─────────────────────────────────────────────────────────────────
    // Claim lifecycle
    // ─────────────────────────────────────────────────────────────────

    function fileClaim(
        bytes32 assuranceId,
        uint256 requestedAmount,
        bytes calldata evidence
    ) external override returns (bytes32 claimId) {
        JobAssurance storage ja = _assurances[assuranceId];
        require(ja.state == AssuranceState.Active, "AAP: assurance not Active");
        require(ja.beneficiary == msg.sender, "AAP: caller is not beneficiary");
        require(requestedAmount > 0, "AAP: requestedAmount is 0");
        require(requestedAmount <= ja.committedAmount, "AAP: exceeds committedAmount");

        claimId = keccak256(abi.encodePacked(
            "AAP_CLAIM",
            assuranceId,
            _claimNonce++
        ));

        // Store evidence hash on chain. The opaque `evidence` bytes can carry
        // any composition payload (upstream refs, slash record hashes, scoring
        // CIDs) without expanding the spec interface.
        evidenceHashes[claimId] = keccak256(evidence);

        ja.state   = AssuranceState.Claimed;
        ja.claimId = claimId;

        _claims[claimId] = Claim({
            claimId:         claimId,
            assuranceId:     assuranceId,
            beneficiary:     msg.sender,
            requestedAmount: requestedAmount,
            approvedAmount:  0,
            state:           ClaimState.Filed,
            filedAt:         uint64(block.timestamp),
            resolvedAt:      0
        });

        emit ClaimFiled(claimId, assuranceId, msg.sender, requestedAmount);
    }

    function resolveClaim(
        bytes32 claimId,
        bool approved,
        uint256 approvedAmount,
        bytes calldata /*reason*/
    ) external override {
        require(msg.sender == resolver, "AAP: caller is not resolver");
        Claim storage claim = _claims[claimId];
        require(claim.state == ClaimState.Filed, "AAP: claim not Filed");

        JobAssurance storage ja = _assurances[claim.assuranceId];
        claim.resolvedAt = uint64(block.timestamp);

        if (approved) {
            require(approvedAmount > 0, "AAP: approvedAmount is 0");
            require(approvedAmount <= claim.requestedAmount, "AAP: exceeds requested");
            require(approvedAmount <= ja.committedAmount, "AAP: exceeds committed");
            claim.approvedAmount = approvedAmount;
            claim.state          = ClaimState.Approved;
        } else {
            claim.approvedAmount = 0;
            claim.state          = ClaimState.Denied;
            ja.state             = AssuranceState.Active;
        }

        emit ClaimResolved(claimId, claim.assuranceId, approved, claim.approvedAmount, msg.sender);
    }

    function payout(bytes32 claimId) external override {
        Claim storage claim = _claims[claimId];
        require(claim.state == ClaimState.Approved, "AAP: claim not Approved");

        JobAssurance storage ja   = _assurances[claim.assuranceId];
        Account      storage acct = _accounts[ja.assuredAgent];

        uint256 amt = claim.approvedAmount;
        require(acct.lockedAmount >= amt, "AAP: insufficient locked");

        acct.lockedAmount  -= amt;
        acct.paidOutAmount += amt;
        claim.state        = ClaimState.Paid;
        ja.state           = AssuranceState.Paid;

        token.transfer(claim.beneficiary, amt);

        emit ClaimPaid(claimId, claim.assuranceId, claim.beneficiary, amt);
    }

    // ─────────────────────────────────────────────────────────────────
    // Views
    // ─────────────────────────────────────────────────────────────────

    function getJobAssurance(bytes32 assuranceId) external view override returns (JobAssurance memory) {
        return _assurances[assuranceId];
    }

    function getClaim(bytes32 claimId) external view override returns (Claim memory) {
        return _claims[claimId];
    }
}
