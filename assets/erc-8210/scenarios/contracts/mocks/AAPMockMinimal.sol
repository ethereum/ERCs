// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../interfaces/IAAP.sol";
import "../interfaces/IERC20.sol";

/// @title Minimal AAP mock — only the functions exercised by the three
///        reference scenarios.  This is NOT the full ERC-8210 implementation.
contract AAPMockMinimal is IAAP {
    IERC20  public token;
    address public reviewer;

    uint256 private _nextClaimId;
    mapping(uint256 => Claim) private _claims;

    constructor(address _token, address _reviewer) {
        token    = IERC20(_token);
        reviewer = _reviewer;
    }

    // ── Core ───────────────────────────────────────────────────────────

    function fileClaim(
        uint256 amount,
        bytes32 evidenceHash,
        bytes32 upstream
    ) external override returns (uint256 claimId) {
        claimId = _nextClaimId++;
        _claims[claimId] = Claim({
            claimant:     msg.sender,
            amount:       amount,
            status:       ClaimStatus.Filed,
            evidenceHash: evidenceHash,
            upstream:     upstream
        });
        emit ClaimFiled(claimId, msg.sender, amount, evidenceHash);
    }

    function reviewClaim(
        uint256 claimId,
        Verdict verdict,
        bytes32 reason
    ) external override {
        require(msg.sender == reviewer, "AAP: not reviewer");
        Claim storage c = _claims[claimId];
        require(c.status == ClaimStatus.Filed, "AAP: not filed");

        if (verdict == Verdict.Approve) {
            c.status = ClaimStatus.Approved;
            token.transfer(c.claimant, c.amount);
        } else {
            c.status = ClaimStatus.Rejected;
        }
        emit ClaimReviewed(claimId, verdict, reason);
    }

    function getClaim(uint256 claimId) external view override returns (Claim memory) {
        return _claims[claimId];
    }
}
