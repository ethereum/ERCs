// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {ISpendGrantRegistry, SpendGrant} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";
import {SpendGrantExecutor} from "./SpendGrantExecutor.sol";
import {SpendGrantRedemptionEnforcer} from "./SpendGrantRedemptionEnforcer.sol";

/// @notice An executor that also accepts spends redeemed through an ERC-7710 delegation manager.
/// @dev The caller decides the shape:
/// - The caller is the grant's delegate: a direct call. The EVM authenticated it and it is the
///   authorizer, whatever drove that account to call; a sub-delegation it granted is its own access
///   control.
/// - Any other caller is an account performing a redemption. It is authorized only by a record the
///   trusted enforcer wrote for this exact spend and this caller, naming the redeemer the manager
///   authenticated. Taking the record clears it, before `consume` and before movement. No record
///   resolves to address(0), which `consume` rejects with UNAUTHORIZED_DELEGATE.
contract SpendGrantRedemptionExecutor is SpendGrantExecutor {
    error EnforcerMismatch();

    SpendGrantRedemptionEnforcer internal immutable ENFORCER;

    constructor(ISpendGrantRegistry registry_, SpendGrantRedemptionEnforcer enforcer_) SpendGrantExecutor(registry_) {
        if (enforcer_.executor() != address(this) || enforcer_.registry() != address(registry_)) {
            revert EnforcerMismatch();
        }
        ENFORCER = enforcer_;
    }

    function enforcer() external view returns (SpendGrantRedemptionEnforcer) {
        return ENFORCER;
    }

    function _authorizer(SpendGrant calldata grant, address asset, uint256 amount, address recipient)
        internal
        override
        returns (address)
    {
        if (msg.sender == grant.delegate) return msg.sender;
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(REGISTRY), grant);
        return ENFORCER.take(msg.sender, grantHash, asset, amount, recipient);
    }
}
