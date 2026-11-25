// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";

/// @title  CompositeEligibility — a conjunction or disjunction of other modules (reference v0.2)
/// @notice `requireAll == true`: every child must return true; otherwise one suffices. A child
///         that reverts makes this module revert as well, so a registry `challenge` reports the
///         predicate as unevaluable rather than failed.
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
        for (uint256 i = 0; i < modules.length; i++) {
            bool ok = modules[i].isEligible(swarmId, roleId, account);
            if (requireAll && !ok) return false;
            if (!requireAll && ok) return true;
        }
        return requireAll;
    }
}
