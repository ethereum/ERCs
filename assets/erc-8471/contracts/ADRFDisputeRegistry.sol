// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFErrors as E} from "./ADRFErrors.sol";
import {ADRFStorage, ADRFEvents, ADRFModule} from "./modules/ADRFModule.sol";
import {IADRFDisputeRegistry as I} from "./interfaces/IADRFDisputeRegistry.sol";
import {IADRFPolicyRegistry} from "./interfaces/IADRFPolicyRegistry.sol";

/// @title  ADRFDisputeRegistry — AI Dispute Resolution Framework, dispute registry (reference kernel)
/// @notice Non-upgradeable. Holds the normative record of bindings, cases, findings, round decisions,
///         rulings, enactment reports and leads, and exposes the whole of IADRFDisputeRegistry at one address.
///         Admission is an algorithmic check of the five criteria (identifiable object and event, accountable
///         respondent, pre-declared norm, available method, open window) against what the obligation source
///         attests; effect authority comes only from the binding; the registry never moves funds and never
///         executes an effect.
///
///         The record is this contract's storage. Its functions are implemented by six modules that share the
///         storage layout (`ADRFStorage`) and that this contract runs by delegatecall with the original calldata
///         and sender, so that every entry is written and read under this one address: the binding module
///         (bindings and their reads, acceptance, withdrawal), the filing module (filing and admission, Sections 5
///         and 6 of the proposal), the resolution module (the answer, the resolution of sub-questions and reviews,
///         Section 8), the decision module (round decisions and finality, Section 9), the record module (the case
///         reads, the evidence commitments, the enactment log and the leads) and the outcome module (the reads of
///         sub-questions, findings, round decisions, rulings and enactment reports). The modules are fixed at construction and
///         cannot be replaced; a module refuses to run on its own storage and must have been built for this
///         registry's policy registry. The split keeps every deployable unit well within the per-transaction gas
///         limits of current networks and changes neither the interface, nor any identifier, nor the record;
///         ERC-165, ERC-6372 and the interface identifier are answered here.
contract ADRFDisputeRegistry is ADRFStorage, ADRFEvents {
    IADRFPolicyRegistry public immutable policies;
    address public immutable bindingModule;
    address public immutable filingModule;
    address public immutable resolutionModule;
    address public immutable decisionModule;
    address public immutable recordModule;
    address public immutable outcomeModule;

    constructor(IADRFPolicyRegistry policies_, address binding_, address filing_, address resolution_, address decision_, address record_, address outcome_) {
        policies = policies_;
        bindingModule = checkModule(binding_, policies_);
        filingModule = checkModule(filing_, policies_);
        resolutionModule = checkModule(resolution_, policies_);
        decisionModule = checkModule(decision_, policies_);
        recordModule = checkModule(record_, policies_);
        outcomeModule = checkModule(outcome_, policies_);
    }

    /// A module must exist and must have been built for this policy registry.
    function checkModule(address module, IADRFPolicyRegistry policies_) private view returns (address) {
        if (module.code.length == 0 || ADRFModule(module).policies() != policies_) revert E.ADRF_InvalidModule(module);
        return module;
    }

    // ------------------------------------------------------------------ routing

    /// Runs the function of IADRFDisputeRegistry named by the selector in the module that holds it, on this
    /// contract's storage, with the original calldata and `msg.sender`; its return data or revert data is passed
    /// back unchanged. Unknown selectors revert; no ether is accepted.
    fallback() external {
        address module = moduleOf(msg.sig);
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), module, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /// The module that implements a function of IADRFDisputeRegistry; reverts for any other selector.
    function moduleOf(bytes4 selector) public view returns (address) {
        if (
            selector == I.bind.selector || selector == I.revokeBinding.selector || selector == I.accept.selector
                || selector == I.expireAcceptance.selector || selector == I.withdraw.selector || selector == I.getBinding.selector
                || selector == I.isAuthorizedEffect.selector || selector == I.isExecutor.selector || selector == I.isBeneficiary.selector
        ) return bindingModule;
        if (selector == I.file.selector || selector == I.fileAdvisory.selector) return filingModule;
        if (
            selector == I.answer.selector || selector == I.resolveFormal.selector || selector == I.resolveEvidenced.selector
                || selector == I.openJudgment.selector || selector == I.recordJudgedFinding.selector || selector == I.requestReview.selector
        ) return resolutionModule;
        if (
            selector == I.applySilence.selector || selector == I.decide.selector || selector == I.expireDecision.selector
                || selector == I.finalize.selector || selector == I.enforceDeadline.selector
        ) return decisionModule;
        if (
            selector == I.submitEvidence.selector || selector == I.reportEnactment.selector || selector == I.reportLead.selector
                || selector == I.getCase.selector || selector == I.getClock.selector || selector == I.activeCaseOf.selector
                || selector == I.finalCaseOf.selector || selector == I.exclusivityKeyOf.selector || selector == I.objectKeyOf.selector
        ) return recordModule;
        if (
            selector == I.getSubQuestion.selector || selector == I.getFinding.selector || selector == I.getRound.selector
                || selector == I.getRuling.selector || selector == I.getEnactment.selector
        ) return outcomeModule;
        revert E.ADRF_UnknownFunction(selector);
    }

    // ------------------------------------------------------------------ ERC-165 and clock (ERC-6372)

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(I).interfaceId;
    }

    function clock() external view returns (uint48) {
        return uint48(block.timestamp);
    }

    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=timestamp";
    }
}
