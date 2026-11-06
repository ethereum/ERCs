// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import {ISwarmRegistry} from "../interfaces/ISwarmRegistry.sol";
import {ITaskTenderKernel} from "./interfaces/ITaskTenderKernel.sol";

/// @title  SwarmTenderAdapter — a swarm's acceptance authority read from a token-bound task tender
/// @notice Name this contract as the objective's `acceptanceAuthority` and bind the objective's
///         `obligation` to (this chain, the tender contract, the tender's tokenId). The swarm
///         account is the fulfiller of record on the tender. Anyone may `settle`: the adapter
///         reads the tender's own records and concludes the swarm ACHIEVED when the account's
///         submission is Accepted, ABANDONED when the tender is cancelled, FAILED when the
///         tender's settlement deadline has passed without acceptance. It derives everything from
///         the tender and the swarm record, never from the caller. The reward moves inside the
///         tender (to the account's credit); allocation inside the swarm is the account's business.
contract SwarmTenderAdapter {
    ISwarmRegistry    public immutable swarms;
    ITaskTenderKernel public immutable task;

    uint256 public constant NO_SUBMISSION = type(uint256).max;

    event Settled(bytes32 indexed swarmId, uint256 indexed tokenId, T.OutcomeType outcome, uint256 submissionId, bytes32 resultHash);

    constructor(ISwarmRegistry swarms_, ITaskTenderKernel task_) {
        require(address(swarms_) != address(0) && address(task_) != address(0), "SAITender: zero address");
        swarms = swarms_;
        task = task_;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) { return interfaceId == 0x01ffc9a7; }

    /// @param submissionId the swarm account's submission to check for acceptance, or NO_SUBMISSION
    ///        to settle on cancellation or expiry alone
    function settle(bytes32 swarmId, uint256 submissionId) external {
        T.Objective memory o = swarms.objectiveOf(swarmId);
        require(o.acceptanceAuthority == address(this), "SAITender: not the acceptance authority");
        require(o.obligation.chainId == block.chainid && o.obligation.target == address(task), "SAITender: not bound to this tender");
        uint256 tokenId = o.obligation.id;
        address account = swarms.getSwarm(swarmId).account;
        require(account != address(0), "SAITender: no swarm account");

        if (submissionId != NO_SUBMISSION) {
            ITaskTenderKernel.Submission memory s = task.submissionOf(tokenId, submissionId);
            require(s.fulfiller == account, "SAITender: not the swarm's submission");
            if (s.status == ITaskTenderKernel.SubmissionStatus.Accepted) {
                swarms.conclude(swarmId, T.OutcomeType.ACHIEVED, s.resultHash);
                emit Settled(swarmId, tokenId, T.OutcomeType.ACHIEVED, submissionId, s.resultHash);
                return;
            }
        }
        if (task.isTenderCancelled(tokenId)) {
            swarms.conclude(swarmId, T.OutcomeType.ABANDONED, bytes32(0));
            emit Settled(swarmId, tokenId, T.OutcomeType.ABANDONED, NO_SUBMISSION, bytes32(0));
            return;
        }
        ITaskTenderKernel.TenderTerms memory terms = task.tenderTermsOf(tokenId);
        if (terms.settleBy != 0 && block.timestamp > terms.settleBy) {
            swarms.conclude(swarmId, T.OutcomeType.FAILED, bytes32(0));
            emit Settled(swarmId, tokenId, T.OutcomeType.FAILED, NO_SUBMISSION, bytes32(0));
            return;
        }
        revert("SAITender: not settled");
    }
}
