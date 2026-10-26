// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes as T} from "./ASFTypes.sol";
import {ASFErrors} from "./ASFErrors.sol";
import {ASFEvaluation} from "./libraries/ASFEvaluation.sol";
import {ASFLifecycle} from "./libraries/ASFLifecycle.sol";
import {IASFBindingRegistry} from "./interfaces/IASFBindingRegistry.sol";

/// @title  ASFBindingRegistry — reference implementation of the Safety Binding registry
/// @notice Records adoption relations and their lifecycle, indexes them by (subject, adopter) and
///         (scope, adopter), and offers a registry-level `check` that consumers can call before acting.
///         What it deliberately does not do: decide whether the adopter may speak for the subject or the
///         resource (consumers verify that against the permission source named in `authorityRef`),
///         evaluate any policy, or enforce anything by itself.
///         The evaluation (`check`, `checkBinding`) lives in the externally linked `ASFEvaluation` library and the
///         writes (`adopt`, `suspend`, `resume`, `terminate`) in `ASFLifecycle`; both run on this contract's
///         storage through DELEGATECALL. The split keeps the registry's deployed code within the per-transaction
///         gas cap of networks that meter code deposit heavily and changes neither the ABI nor the behaviour.
contract ASFBindingRegistry is IASFBindingRegistry {
    T.Store private _s;

    // ------------------------------------------------------------------------------ ERC-165

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IASFBindingRegistry).interfaceId;
    }

    // -------------------------------------------------------------------------------- adopt

    /// @dev `adopt` runs in the externally linked `ASFLifecycle` library on this contract's storage (Section 7,
    ///      registry rules 1 to 6); `msg.sender`, the adopter, and the events are the registry's.
    function adopt(T.BindingInput calldata input) external returns (bytes32 bindingId) {
        return ASFLifecycle.adopt(_s, input);
    }

    // ---------------------------------------------------------------------------- lifecycle

    /// @dev The three transitions run in the externally linked `ASFLifecycle` library on this contract's storage
    ///      (Section 8, including the standing stops of Section 8.5); `msg.sender` and the events are the registry's.
    function suspend(bytes32 bindingId, uint8 restrictions, bytes32 responseRef, bytes32 reasonRef) external {
        ASFLifecycle.suspend(_s, bindingId, restrictions, responseRef, reasonRef);
    }

    function resume(bytes32 bindingId, bytes32 reasonRef) external {
        ASFLifecycle.resume(_s, bindingId, reasonRef);
    }

    function terminate(bytes32 bindingId, bytes32 reasonRef) external {
        ASFLifecycle.terminate(_s, bindingId, reasonRef);
    }

    function setParamsLocator(bytes32 bindingId, string calldata locator) external {
        T.Binding storage b = _existing(bindingId);
        if (b.adopter != msg.sender) revert ASFErrors.NotAdopter();
        if (b.state == T.BindingState.Terminated) revert ASFErrors.InvalidState();
        b.paramsLocator = locator;
        emit BindingParamsLocatorUpdated(bindingId, locator);
    }

    // -------------------------------------------------------------------------------- views

    function computeBindingId(address adopter, T.BindingInput calldata input) external view returns (bytes32) {
        return ASFLifecycle.computeBindingId(adopter, input);
    }

    function bindingOf(bytes32 bindingId) external view returns (T.Binding memory) {
        return _existing(bindingId);
    }

    function intervenersOf(bytes32 bindingId) external view returns (T.Intervener[] memory) {
        _existing(bindingId);
        return _s.interveners[bindingId];
    }

    function rightsOf(bytes32 bindingId, address account) external view returns (uint8) {
        return ASFLifecycle.rightsOf(_s, bindingId, account);
    }

    function stopOf(address adopter, bytes32 subjectKey, address specRegistry, bytes32 specId, address intervener)
        external view returns (T.Stop memory)
    {
        return _s.stops[T.stopKey(adopter, subjectKey, specRegistry, specId, intervener)];
    }

    function countBySubject(bytes32 subjectKey, address adopter) external view returns (uint256) {
        return _s.bySubject[subjectKey][adopter].length;
    }

    function bindingsBySubject(bytes32 subjectKey, address adopter, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory)
    {
        return _slice(_s.bySubject[subjectKey][adopter], offset, limit);
    }

    function countByScope(bytes32 scopeKey, address adopter) external view returns (uint256) {
        return _s.byScope[scopeKey][adopter].length;
    }

    function bindingsByScope(bytes32 scopeKey, address adopter, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory)
    {
        return _slice(_s.byScope[scopeKey][adopter], offset, limit);
    }

    // -------------------------------------------------------------------------------- check

    /// @dev Both checks run in the externally linked evaluation library on this contract's storage; the calldata
    ///      after the selector is forwarded as is, so the registry carries no decoder of its own.
    function checkBinding(bytes32, T.Clause calldata)
        external view returns (T.Verdict verdict, T.Reason reason, uint8 restrictions)
    {
        return ASFEvaluation.checkBinding(_s, msg.data[4:]);
    }

    function check(T.RequirementSet calldata, bytes32[] calldata)
        external view returns (T.Verdict verdict, T.Reason[] memory reasons, uint8[] memory restrictions)
    {
        return ASFEvaluation.check(_s, msg.data[4:]);
    }

    function requirementId(T.RequirementSet calldata requirement) external pure returns (bytes32) {
        ASFEvaluation.validateRequirementCalldata(requirement);
        return keccak256(abi.encode(requirement));
    }

    // ----------------------------------------------------------------------------- internal

    function _existing(bytes32 bindingId) private view returns (T.Binding storage b) {
        b = _s.bindings[bindingId];
        if (b.state == T.BindingState.None) revert ASFErrors.UnknownBinding();
    }

    function _slice(bytes32[] storage list, uint256 offset, uint256 limit) private view returns (bytes32[] memory out) {
        uint256 len = list.length;
        if (offset >= len) return new bytes32[](0);
        uint256 end = offset + limit;
        if (limit == 0 || end > len) end = len;
        out = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) out[i - offset] = list[i];
    }
}
