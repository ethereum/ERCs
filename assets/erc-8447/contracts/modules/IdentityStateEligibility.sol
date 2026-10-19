// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";
import {IAddressAnchoredIdentity} from "./interfaces/IAddressAnchoredIdentity.sol";

/// @title  IdentityStateEligibility — a member's address-anchored identity must be ACTIVE
///         (reference v0.2)
/// @notice Reads an address-anchored agent identity registry: the account's identity must be in
///         its ACTIVE state (bound to a live agent and within its liveness window). A STALE or
///         RETIRED identity makes a later `challenge` suspend the member.
contract IdentityStateEligibility is IEligibility {
    uint8 public constant ACTIVE = 1;

    IAddressAnchoredIdentity public immutable identities;

    constructor(IAddressAnchoredIdentity identities_) {
        require(address(identities_) != address(0), "IdentityState: zero registry");
        identities = identities_;
    }

    function isEligible(bytes32, bytes32, address account) external view returns (bool) {
        return identities.state(account) == ACTIVE;
    }
}
