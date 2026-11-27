// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {Ownable2Step} from "./Ownable2Step.sol";

/// @title AccessControl -- Role-based access control on top of Ownable2Step
/// @notice Three operational roles plus the meta-admin owner. Splits privileged actions
///         so a single key compromise does not unlock the full admin surface.
///
///         Role assignment:
///         - GUARDIAN: incident response. Pause/unpause (global + per-proof-type),
///           revoke verifier versions, deny providers. NEVER touches funds or registries.
///         - REGISTRAR: registry curation. Add/revoke merkle roots, reporting thresholds,
///           and provider publishers. NEVER updates the active config or pauses.
///         - CONFIG: config curation. Update provider config, attestation TTL, propose
///           verifier upgrades, register provider expansions. NEVER pauses.
///
///         The owner is the only role that can grant/revoke other roles, and implicitly
///         holds every operational role for backwards compatibility with single-key setups.
///         Production deployments are expected to grant operational roles to a Safe + EOAs
///         and rotate the owner key behind a slower governance path.
abstract contract AccessControl is Ownable2Step {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN");
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG");

    mapping(bytes32 role => mapping(address account => bool granted)) internal _roles;

    error NotRole(bytes32 role, address account);
    error AlreadyHasRole(bytes32 role, address account);
    error DoesNotHaveRole(bytes32 role, address account);
    error InvalidRole(bytes32 role);

    event RoleGranted(bytes32 indexed role, address indexed account);
    event RoleRevoked(bytes32 indexed role, address indexed account);

    modifier onlyRole(bytes32 role) {
        if (!_hasRole(role, msg.sender)) revert NotRole(role, msg.sender);
        _;
    }

    /// @notice Owner implicitly satisfies every role; explicit grants override for non-owner accounts.
    function _hasRole(bytes32 role, address account) internal view returns (bool) {
        return account == owner || _roles[role][account];
    }

    /// @notice Check whether an account holds a role (or is the owner).
    function hasRole(bytes32 role, address account) external view returns (bool) {
        return _hasRole(role, account);
    }

    /// @notice Grant a role to an account. Owner-only.
    /// @dev Granting a role the account already has reverts; this catches accidental double-grants
    ///      that could otherwise mask a typo'd address.
    function grantRole(bytes32 role, address account) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        if (!_isValidRole(role)) revert InvalidRole(role);
        if (_roles[role][account]) revert AlreadyHasRole(role, account);
        _roles[role][account] = true;
        emit RoleGranted(role, account);
    }

    /// @notice Revoke a role from an account. Owner-only. Owner's implicit roles cannot be revoked.
    function revokeRole(bytes32 role, address account) external onlyOwner {
        if (!_isValidRole(role)) revert InvalidRole(role);
        if (!_roles[role][account]) revert DoesNotHaveRole(role, account);
        _roles[role][account] = false;
        emit RoleRevoked(role, account);
    }

    function _isValidRole(bytes32 role) internal pure returns (bool) {
        return role == GUARDIAN_ROLE || role == REGISTRAR_ROLE || role == CONFIG_ROLE;
    }
}
