// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";

/// @title  CompositeEligibility — a conjunction or disjunction of other modules (reference v0.3)
/// @notice `requireAll == true`: every child must return true; otherwise one suffices. Every child
///         is asked, and a child that cannot tell — it reverts or returns something other than a
///         boolean — decides nothing unless nothing else decides: a conjunction answers `false` if
///         any child answers `false`, a disjunction `true` if any child answers `true`, and
///         otherwise the composite reverts when a child could not tell, so that a registry
///         `challenge` reports the predicate as unevaluable rather than failed (ERC-8447 Section 6.4).
/// @dev    v0.3 (revision 2.3): v0.2 called the children in order and reverted with the first child
///         that reverted, so a pending child listed before a definite `false` hid that `false` from
///         a conjunction, and one listed before a definite `true` hid that `true` from a disjunction.
contract CompositeEligibility is IEligibility {
    IEligibility[] public modules;
    bool public immutable requireAll;

    constructor(IEligibility[] memory modules_, bool requireAll_) {
        require(modules_.length > 0, "Composite: no modules");
        for (uint256 i = 0; i < modules_.length; i++) {
            require(address(modules_[i]).code.length > 0, "Composite: module not contract");
            modules.push(modules_[i]);
        }
        requireAll = requireAll_;
    }

    function moduleCount() external view returns (uint256) { return modules.length; }

    function isEligible(bytes32 swarmId, bytes32 roleId, address account) external view returns (bool) {
        bool unknown;
        for (uint256 i = 0; i < modules.length; i++) {
            (bool ok, bytes memory ret) = address(modules[i]).staticcall(
                abi.encodeWithSelector(IEligibility.isEligible.selector, swarmId, roleId, account));
            if (!ok || ret.length != 32) { unknown = true; continue; }
            uint256 answer = abi.decode(ret, (uint256));
            if (answer > 1) { unknown = true; continue; }
            if (requireAll && answer == 0) return false;
            if (!requireAll && answer == 1) return true;
        }
        require(!unknown, "Composite: a module cannot tell");
        return requireAll;
    }
}
