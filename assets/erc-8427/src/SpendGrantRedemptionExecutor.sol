// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {ISpendGrantRegistry, SpendGrant, SpendGrantError, Reason} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";
import {SpendGrantExecutor} from "./SpendGrantExecutor.sol";
import {SpendGrantRedemptionEnforcer} from "./SpendGrantRedemptionEnforcer.sol";

/// @notice An executor that also accepts spends redeemed through an ERC-7710 delegation manager.
/// @dev The caller decides the shape:
/// - The caller is the grant's delegate: a direct call. The EVM authenticated it and it is the
///   authorizer, whatever drove that account to call; a sub-delegation it granted is its own access
///   control.
/// - The caller is the grant's principal, performing an ERC-7710 execution. It is authorized only by a
///   record the trusted enforcer wrote for this exact spend and this account, naming the redeemer the
///   manager authenticated. Taking the record clears it, before `consume` and before movement. No record
///   is a revert with UNAUTHORIZED_DELEGATE.
/// - Any other caller is rejected with UNAUTHORIZED_DELEGATE before any record is consulted.
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
        // The record path is for the principal's own account performing an ERC-7710 execution. Any other
        // caller, such as an intermediate delegator in the chain, has no standing on it, whatever records
        // exist: a record it could use would turn the delegate's one redemption into a second spend.
        if (msg.sender != grant.principal) revert SpendGrantError(Reason.UNAUTHORIZED_DELEGATE);
        bytes32 grantHash = SpendGrantHash.digest(block.chainid, address(REGISTRY), grant);
        address redeemer = ENFORCER.take(msg.sender, grantHash, asset, amount, recipient);
        // No record is no authorization. Reject here rather than pass an address nobody authenticated.
        if (redeemer == address(0)) revert SpendGrantError(Reason.UNAUTHORIZED_DELEGATE);
        return redeemer;
    }
}
