// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes as T} from "../ASFTypes.sol";
import {ASFKeys} from "../libraries/ASFKeys.sol";
import {ASFRequirementLib as R} from "../libraries/ASFRequirementLib.sol";
import {IASFBindingRegistry} from "../interfaces/IASFBindingRegistry.sol";
import {ITaskTenderKernel} from "../interfaces/ITaskTenderKernel.sol";

/// @title  ASFTaskTenderAdapter — acceptance authority for token-bound task tenders that admits only
///         fulfillers who hold the required Safety Bindings
/// @notice Set this contract as a task's acceptance authority. For a pending, judged-path submission
///         anyone may call `judge`: the adapter looks up the fulfiller's own bindings (adopter == fulfiller,
///         subject == the fulfiller's account), evaluates the requirement through the registry and calls the
///         kernel's real `acceptFulfillment` or `rejectFulfillment`. A verdict of `Unknown` does neither:
///         the adapter reverts and the kernel's own judgment clock keeps governing, because a dependency
///         failure is not a pass and not a refusal.
///         The adapter never reads the deliverable; it applies the task's safety requirement as one
///         admission condition. Tasks that also need a judgment of the work combine this with a decision
///         mechanism (for example a collective decision adapter) in their own acceptance logic.
contract ASFTaskTenderAdapter {
    using R for R.Stored;

    uint256 private constant MAX_SCAN = 32;

    IASFBindingRegistry public immutable registry;
    ITaskTenderKernel public immutable task;
    R.Stored private _template;

    event Judged(
        uint256 indexed tokenId,
        uint256 indexed submissionId,
        address indexed fulfiller,
        T.Verdict verdict,
        bytes32[] bindingIds,
        T.Reason[] reasons
    );

    /// @param template_ Requirement whose clauses leave `adopter` and `subjectKey` at zero; the adapter fills
    ///        both with the fulfiller at judgment time so that only the fulfiller's own adoptions count. The
    ///        clauses may require interveners (for example the task publisher with the suspend right), so that a
    ///        suspension of the fulfiller's binding is not the fulfiller's own to lift.
    constructor(IASFBindingRegistry registry_, ITaskTenderKernel task_, T.RequirementSet memory template_) {
        require(address(registry_) != address(0) && address(task_) != address(0), "ASFTender: zero address");
        registry_.requirementId(template_);
        for (uint256 i = 0; i < template_.clauses.length; i++) {
            require(
                template_.clauses[i].adopter == address(0) && template_.clauses[i].subjectKey == bytes32(0),
                "ASFTender: template binds adopter or subject"
            );
        }
        registry = registry_;
        task = task_;
        _template.store(template_);
    }

    /// ERC-165: a judged authority (deliberately not a machine verifier).
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7;
    }

    function template() external view returns (T.RequirementSet memory) {
        return _template.load();
    }

    /// @notice The requirement as it applies to one fulfiller.
    function requirementFor(address fulfiller) public view returns (T.RequirementSet memory req) {
        req = _template.load();
        bytes32 key = ASFKeys.accountSubjectKey(fulfiller);
        for (uint256 i = 0; i < req.clauses.length; i++) {
            req.clauses[i].adopter = fulfiller;
            req.clauses[i].subjectKey = key;
        }
    }

    /// @notice Selects, per clause, the fulfiller's first currently satisfying binding (or, failing that, a
    ///         candidate whose reason explains the refusal), then evaluates the requirement.
    function evaluate(address fulfiller)
        public view returns (T.Verdict verdict, bytes32[] memory bindingIds, T.Reason[] memory reasons)
    {
        T.RequirementSet memory req = requirementFor(fulfiller);
        bytes32 key = ASFKeys.accountSubjectKey(fulfiller);
        uint256 n = registry.countBySubject(key, fulfiller);
        bytes32[] memory candidates = registry.bindingsBySubject(key, fulfiller, 0, n < MAX_SCAN ? n : MAX_SCAN);
        bindingIds = new bytes32[](req.clauses.length);
        for (uint256 c = 0; c < req.clauses.length; c++) {
            bytes32 fallbackId;
            for (uint256 i = 0; i < candidates.length; i++) {
                (T.Verdict v, T.Reason r,) = registry.checkBinding(candidates[i], req.clauses[c]);
                if (v == T.Verdict.Satisfied) { bindingIds[c] = candidates[i]; break; }
                if (r != T.Reason.SpecMismatch && fallbackId == bytes32(0)) fallbackId = candidates[i];
            }
            if (bindingIds[c] == bytes32(0)) bindingIds[c] = fallbackId;
        }
        (verdict, reasons,) = registry.check(req, bindingIds);
    }

    /// @notice Judges a pending submission by the fulfiller's safety bindings. Permissionless: every
    ///         parameter comes from the task and the registry, the caller chooses nothing.
    function judge(uint256 tokenId, uint256 submissionId) external returns (T.Verdict verdict) {
        require(task.acceptanceAuthorityOf(tokenId) == address(this), "ASFTender: not the acceptance authority");
        ITaskTenderKernel.Submission memory s = task.submissionOf(tokenId, submissionId);
        require(s.status == ITaskTenderKernel.SubmissionStatus.Pending, "ASFTender: not pending");
        require(!s.machineSettled, "ASFTender: machine-path submission");

        bytes32[] memory ids;
        T.Reason[] memory reasons;
        (verdict, ids, reasons) = evaluate(s.fulfiller);
        if (verdict == T.Verdict.Satisfied) {
            task.acceptFulfillment(tokenId, submissionId);
        } else if (verdict == T.Verdict.NotSatisfied) {
            task.rejectFulfillment(tokenId, submissionId);
        } else {
            revert("ASFTender: verdict unknown; the task clock governs");
        }
        emit Judged(tokenId, submissionId, s.fulfiller, verdict, ids, reasons);
    }
}
