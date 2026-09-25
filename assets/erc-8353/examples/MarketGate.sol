// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "../src/VerificationGate.sol";

/// @title MarketGate — market-side adapter sketch
/// @notice Models the staked-marketplace shape: every claim (a capability bid)
///         MUST bond a fixed stake; wrong claims are revoked by a designated
///         arbiter and the stake burns; settlement is terminal and feeds the
///         subject's own verified depth. Verifier depth is recursive over this
///         gate's own settled claims: `weightOf` = settled claims as subject
///         (+ a one-time genesis seed so the system can bootstrap).
contract MarketGate is VerificationGate {
    uint256 public immutable stakePerClaim;
    uint256 public immutable threshold;
    address public immutable arbiter;

    mapping(address => uint256) public settledAsSubject;
    mapping(address => uint256) public genesisWeight;

    constructor(uint256 stakePerClaim_, uint256 threshold_, address arbiter_,
                address[] memory genesisVerifiers, uint256 genesisWeight_)
    {
        stakePerClaim = stakePerClaim_;
        threshold = threshold_;
        arbiter = arbiter_;
        for (uint256 i = 0; i < genesisVerifiers.length; i++)
            genesisWeight[genesisVerifiers[i]] = genesisWeight_;
    }

    /// Depth = measured verified history in this gate, never a raw count of
    /// endorsements received.
    function weightOf(address verifier) public view override returns (uint256) {
        return genesisWeight[verifier] + settledAsSubject[verifier];
    }

    function _requiredStake(address, bytes32, bytes calldata)
        internal view override returns (uint256) { return stakePerClaim; }

    function _promotionThreshold(bytes32) internal view override returns (uint256) {
        return threshold;
    }

    /// Only the arbiter revokes (the marketplace's dispute outcome); the
    /// claimant's stake burns via the base contract.
    function _canRevoke(bytes32, address caller) internal view override returns (bool) {
        return caller == arbiter;
    }

    /// A settled claim deepens its subject's own verified depth — the
    /// recursion that makes weight expensive to farm.
    function _onSettled(bytes32 claimId) internal override {
        settledAsSubject[_claims[claimId].subject] += 1;
    }
}
