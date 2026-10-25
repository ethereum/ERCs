// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ASFTypes as T} from "../ASFTypes.sol";
import {ASFRequirementLib as R} from "../libraries/ASFRequirementLib.sol";
import {IASFBindingRegistry} from "../interfaces/IASFBindingRegistry.sol";

/// @title  ASFGuardedAccount — example consumer: an account whose operator may only act while the
///         required Safety Bindings are satisfied
/// @notice Illustrates the consumer rules of the framework on the wallet path:
///         * the requirement is fixed at deployment; neither the operator nor the owner can swap it for a
///           looser one, and there is no execution path that skips the check;
///         * the owner (the principal) chooses which bindings are presented, the registry decides whether
///           they satisfy the requirement at execution time;
///         * completability: while every failing clause is a suspension whose response requirements include
///           `RESTRICT_DERISK_ONLY` and not `RESTRICT_FULL_STOP`, calls the owner listed as de-risking actions
///           (repay, cancel, unwind) still go through; everything else stops.
///         A production account would be an account-abstraction module; the logic is the same.
contract ASFGuardedAccount {
    using R for R.Stored;

    IASFBindingRegistry public immutable registry;
    address public immutable owner;
    address public operator;

    R.Stored private _requirement;
    bytes32[] private _bindingIds;
    mapping(address => mapping(bytes4 => bool)) public deriskAllowed;

    event BindingsPresented(bytes32[] bindingIds);
    event DeriskAllowedSet(address target, bytes4 selector, bool allowed);
    event Executed(address indexed target, uint256 value, bytes4 selector, bool underDerisk);

    error NotOwner();
    error NotOperator();
    error BindingNotSatisfied(T.Verdict verdict, T.Reason[] reasons);
    error CallFailed(bytes data);

    constructor(IASFBindingRegistry registry_, address owner_, address operator_, T.RequirementSet memory requirement_) {
        require(address(registry_) != address(0) && owner_ != address(0), "ASFGuarded: zero address");
        registry_.requirementId(requirement_); // reverts for malformed requirement sets
        registry = registry_;
        owner = owner_;
        operator = operator_;
        _requirement.store(requirement_);
    }

    receive() external payable {}

    // ---------------------------------------------------------------------------- owner

    function setOperator(address operator_) external {
        if (msg.sender != owner) revert NotOwner();
        operator = operator_;
    }

    function presentBindings(bytes32[] calldata bindingIds) external {
        if (msg.sender != owner) revert NotOwner();
        _bindingIds = bindingIds;
        emit BindingsPresented(bindingIds);
    }

    function setDeriskAllowed(address target, bytes4 selector, bool allowed) external {
        if (msg.sender != owner) revert NotOwner();
        deriskAllowed[target][selector] = allowed;
        emit DeriskAllowedSet(target, selector, allowed);
    }

    // -------------------------------------------------------------------------- operator

    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory ret) {
        if (msg.sender != operator) revert NotOperator();
        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        bool underDerisk = _gate(target, selector);
        bool ok;
        (ok, ret) = target.call{value: value}(data);
        if (!ok) revert CallFailed(ret);
        emit Executed(target, value, selector, underDerisk);
    }

    // ----------------------------------------------------------------------------- views

    function requirement() external view returns (T.RequirementSet memory) {
        return _requirement.load();
    }

    function presentedBindings() external view returns (bytes32[] memory) {
        return _bindingIds;
    }

    /// @notice The verdict the account would act on right now.
    function status() external view returns (T.Verdict verdict, T.Reason[] memory reasons) {
        return registry.check(_requirement.load(), _bindingIds);
    }

    // -------------------------------------------------------------------------- internal

    function _gate(address target, bytes4 selector) private view returns (bool underDerisk) {
        T.RequirementSet memory req = _requirement.load();
        (T.Verdict verdict, T.Reason[] memory reasons) = registry.check(req, _bindingIds);
        if (verdict == T.Verdict.Satisfied) return false;
        if (verdict == T.Verdict.NotSatisfied && deriskAllowed[target][selector] && _onlyDeriskSuspensions(reasons)) {
            return true;
        }
        revert BindingNotSatisfied(verdict, reasons);
    }

    /// Every failing clause is a suspension that keeps de-risking open and does not stop everything.
    function _onlyDeriskSuspensions(T.Reason[] memory reasons) private view returns (bool) {
        if (_bindingIds.length != reasons.length) return false;
        for (uint256 i = 0; i < reasons.length; i++) {
            if (reasons[i] == T.Reason.None) continue;
            if (reasons[i] != T.Reason.Suspended) return false;
            uint8 r = registry.bindingOf(_bindingIds[i]).restrictions;
            if (r & T.RESTRICT_DERISK_ONLY == 0 || r & T.RESTRICT_FULL_STOP != 0) return false;
        }
        return true;
    }
}
