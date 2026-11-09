// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPRoles
/// @notice Role bits of a role binding. Each bit is granted, suspended and revoked separately;
///         there is no "member" flag. Bits 11..15 are reserved for future versions of the paradigm.
library AIFPRoles {
    uint16 internal constant DISCOVER = 1 << 0; // may learn that the channel exists
    uint16 internal constant OBSERVE = 1 << 1; // may read objects within the scope
    uint16 internal constant SUBMIT = 1 << 2; // may publish or submit new objects
    uint16 internal constant RESPOND = 1 << 3; // may respond to existing objects
    uint16 internal constant MODIFY = 1 << 4; // may modify shared objects (blackboard)
    uint16 internal constant MANAGE_ADMISSION = 1 << 5; // may grant, suspend, revoke role bindings
    uint16 internal constant MANAGE_ORDER = 1 << 6; // may sequence contributions
    uint16 internal constant MANAGE_REMOVE = 1 << 7; // may remove objects from provision
    uint16 internal constant MANAGE_RULES = 1 << 8; // may adopt paradigm versions and declare bindings
    uint16 internal constant REDISTRIBUTE = 1 << 9; // may forward, quote or derive outside the channel
    uint16 internal constant MANAGE_DISCLOSURE = 1 << 10; // may record disclosures and restrictions

    uint16 internal constant ALL_DEFINED = (1 << 11) - 1;

    /// @dev True when exactly one defined role bit is set.
    function isSingle(uint16 roles) internal pure returns (bool) {
        return roles != 0 && (roles & (roles - 1)) == 0 && (roles & ~ALL_DEFINED) == 0;
    }

    /// @dev True when every set bit is a defined role bit.
    function isDefined(uint16 roles) internal pure returns (bool) {
        return roles != 0 && (roles & ~ALL_DEFINED) == 0;
    }
}
