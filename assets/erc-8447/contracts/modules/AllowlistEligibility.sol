// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEligibility} from "../interfaces/IEligibility.sol";

/// @title  AllowlistEligibility — an owner-curated list of eligible accounts (reference v0.2)
/// @notice The simplest module: a role is open to the accounts the owner lists. Removing an
///         account makes any `challenge` of it suspend the member.
contract AllowlistEligibility is IEligibility {
    address public owner;
    mapping(address => bool) public allowed;

    event Allowed(address indexed account, bool allowed);
    event OwnerChanged(address indexed previous, address indexed next);

    constructor(address owner_) {
        owner = owner_;
        emit OwnerChanged(address(0), owner_);
    }

    function setAllowed(address account, bool value) external {
        require(msg.sender == owner, "Allowlist: not owner");
        allowed[account] = value;
        emit Allowed(account, value);
    }

    function setOwner(address next) external {
        require(msg.sender == owner, "Allowlist: not owner");
        emit OwnerChanged(owner, next);
        owner = next;
    }

    function isEligible(bytes32, bytes32, address account) external view returns (bool) {
        return allowed[account];
    }
}
