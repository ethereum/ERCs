---
eip: <to be assigned>
title: Time-Delayed Access Control
description: Provides time-delayed role management in access control, where role grants and revocations take effect after a configurable delay, providing a defense window against privilege escalation.
author: Jeff Fei (@77eff) <j.fei@ant-intl.com>, Kenny Kung (@kennyk10) <kenny.kung@ant-intl.com>, Shulei (@baishuo13) <shulei.shu@ant-intl.com>
discussions-to: https://ethereum-magicians.org/t/erc-xxxx-time-delayed-access-control/28741
status: Draft
type: Standards Track
category: ERC
created: 2026-06-17
requires: 165
---

## Abstract

This ERC introduces a minimal interface for time-delayed role management in smart contract access control systems. A "delayed role activation" is a role change (grant or revocation) that enters a pending state for a configurable delay period before taking effect at a predetermined activation time. 

The proposal defines three functional modules: a delay configuration module for setting per-role grant and revoke delay parameters, an effective role evaluation module that determines whether an account holds a role by comparing the current block timestamp against stored activation and revocation timestamps, and a delay query module for retrieving the current delay configuration. Together, these modules enable automatic activation of pending role changes at the point of permission evaluation, providing protocol operators a response window to detect and cancel unauthorized privilege role changes before they take effect.

## Motivation

The risk of improper access control has become one of the most devastating attack vectors in Ethereum. When an attacker gains unauthorized access to a privileged account — whether through key compromise, operational error, insider threat, or social engineering — they can immediately grant themselves any privilege role, execute malicious actions, and revoke legitimate holders to prevent defensive response. All of this can occur within a single transaction, leaving zero response time for defenders.

Existing partial solutions address time delays at different abstraction levels but leave the role permission layer unprotected. The missing security layer is delaying who can hold a role, not just what a role-holder can do. This proposal provides that layer by introducing configurable waiting periods between role change initiation and automatic activation, giving defenders time to detect, verify, and cancel unauthorized changes before they take effect.

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

Every contract compliant with this ERC MUST implement the `ITimeDelayedAccessControl` interface. Contracts SHOULD also implement [ERC-165](./eip-165.md) to support interface detection.

### Core Interface

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title Time-Delayed Access Control Interface
/// @notice Interface for role-based access control with time-delayed grant and revocation.
/// @dev Implementations MUST implement ERC-165 interface detection.
///      Role grants and revocations are subject to configurable delays: a grant takes effect
///      only after the grant delay has elapsed, and a revocation takes effect only after the
///      revoke delay has elapsed. This provides a safety window for stakeholders to react
///      to privilege changes.
interface ITimeDelayedAccessControl {

    // ── Events ──

    /// @notice Emitted when delay parameters for a role are changed.
    /// @param role The role identifier.
    /// @param previousGrantDelay The previous grant delay in seconds.
    /// @param previousRevokeDelay The previous revoke delay in seconds.
    /// @param newGrantDelay The new grant delay in seconds.
    /// @param newRevokeDelay The new revoke delay in seconds.
    event RoleDelayChanged(
        bytes32 indexed role,
        uint256 previousGrantDelay,
        uint256 previousRevokeDelay,
        uint256 newGrantDelay,
        uint256 newRevokeDelay
    );

    /// @notice Emitted when a role grant is scheduled.
    /// @param role The role identifier.
    /// @param account The address of the account affected by the change.
    /// @param effectTime The timestamp when the change automatically takes effect.
    /// @param scheduler The address that initiated the schedule.
    event RoleGrantScheduled(
        bytes32 indexed role,
        address indexed account,
        uint256 effectTime,
        address scheduler
    );

    /// @notice Emitted when a scheduled role change is cancelled before taking effect.
    /// @param role The role identifier.
    /// @param account The address of the account affected by the cancelled change.
    /// @param canceller The address that cancelled the change.
    event RoleGrantCancelled(
        bytes32 indexed role,
        address indexed account,
        address canceller
    );

    /// @notice Emitted when a role revoke is scheduled.
    /// @param role The role identifier.
    /// @param account The address of the account affected by the change.
    /// @param effectTime The timestamp when the change automatically takes effect.
    /// @param scheduler The address that initiated the schedule.
    event RoleRevokeScheduled(
        bytes32 indexed role,
        address indexed account,
        uint256 effectTime,
        address scheduler
    );


    /// @notice Emitted when a scheduled role revocation is cancelled before taking effect.
    /// @param role The role identifier.
    /// @param account The address of the account affected by the cancelled revocation.
    /// @param canceller The address that cancelled the revocation.
    event RoleRevokeCancelled(
        bytes32 indexed role,
        address indexed account,
        address canceller
    );

    // ── Configuration ──

    /// @notice Sets the delay parameters for a role.
    /// @dev MUST require the caller to hold the admin role for the given role.
    ///      MUST revert when `role == getRoleAdmin(role)` (self-admin role) to prevent
    ///      delay bypass by compromised key holders.
    /// @param role The role whose delay is being modified.
    /// @param grantDelay New grant delay in seconds. MUST be greater than 0.
    /// @param revokeDelay New revoke delay in seconds. MUST be greater than 0.
    function setRoleDelay(bytes32 role, uint256 grantDelay, uint256 revokeDelay) external;

    // ── Queries ──

    /// @notice Returns the effective delay configuration for a role.
    /// @param role The role identifier to query.
    /// @return grantDelay The grant delay in seconds. Returns 0 if the role has not been configured.
    /// @return revokeDelay The revoke delay in seconds. Returns 0 if the role has not been configured.
    function getRoleDelay(bytes32 role) external view returns (uint256 grantDelay, uint256 revokeDelay);

    /// @notice Returns the effective role state for an account, considering
    /// pending delayed changes that have auto-activated.
    /// @dev This is the canonical way to check whether an account holds a role
    ///      in a delayed activation system.
    /// @param role The role identifier to check.
    /// @param account The address of the account to check.
    /// @return Whether the account effectively holds the role.
    function hasEffectiveRole(bytes32 role, address account) external view returns (bool);
}
```

### Behavioral Requirements

#### Delay Configuration

1. The `setRoleDelay` function MUST restrict access to accounts holding a privileged role (e.g., the target role's admin) through an access-control check.

2. A role MUST NOT set its own delay. The `setRoleDelay` function MUST revert on such self-administered roles to prevent bypassing the time-delay mechanism. The delay parameters for self-admin roles can only be set during contract construction via internal functions (e.g., `_setRoleDelay`).

3. The `grantDelay` and `revokeDelay` parameters are independent. A role MAY have different delay values for grant and revocation operations.

4. A delay value of `0` is reserved as the uninitialized state for any role that has not been explicitly configured. Valid delay values MUST be greater than `0`.

5. The delay applicable to granting or revoking a role is determined by the delay configuration of its admin role. This creates a natural hierarchical structure where the delay for granting/revoking a role is controlled by its admin's delay configuration.

#### Role State Transitions

1. The system SHOULD NOT grant a role if a pending change exists or if the account already holds the role. When granted, the role MUST take effect at `activationTime = block.timestamp + config.grantDelay`.

2. The system SHOULD NOT revoke a role if a pending change exists or if the account does not currently hold the role. When revoked, the role MUST take effect at `revokingTime = block.timestamp + config.revokeDelay`.

3. Implementations MUST prevent scheduling a new change while a pending change exists for the same `(role, account)` pair. This prevents conflicting scheduled changes and ensures clean state transitions.

4. Cancellation MUST be permitted before the scheduled time. Once a change has taken effect, it cannot be cancelled through the cancellation mechanism.

5. Once the scheduled time has passed and the change has not been cancelled, all state queries MUST reflect the change as effective. 

#### Effective Role Query

1. The `hasEffectiveRole` function MUST return the effective role state by evaluating the stored activation and revocation timestamps against `block.timestamp`.

2. The `hasEffectiveRole` function is the canonical query for role state in a time-delayed system. All permission checks in the protected contract SHOULD use `hasEffectiveRole` rather than querying the underlying RBAC directly.

#### Event Emission

1. The `RoleDelayChanged` event MUST be emitted when `setRoleDelay` is called.

2. The `RoleGrantScheduled` event MUST be emitted when a role grant is scheduled.

3. The `RoleRevokeScheduled` event MUST be emitted when a role revocation is scheduled.

4. The `RoleGrantCancelled` event MUST be emitted when a scheduled grant is cancelled.

5. The `RoleRevokeCancelled` event MUST be emitted when a scheduled revocation is cancelled.

## Rationale

### Relationship with ERC-8083 (Time-Bound Access Control)

This proposal and [ERC-8083](./eip-8083.md) are complementary standards that address different time dimensions of access control. Each standard can be used independently, or they can be combined for complete bidirectional time-based access control:

| Dimension | ERC-8083 | This ERC |
|-----------|----------|----------|
| Controls | Role expiration (when a role stops being valid) | Role change activation (when a pending change takes effect) |
| Direction | Forward-looking: sets an expiry deadline | Backward-looking: sets a delay before activation |
| Canonical query | `hasActiveRole(role, account)` | `hasEffectiveRole(role, account)` |
| Threat addressed | Stale/orphaned roles not revoked after term ends | Privilege escalation through compromised keys |
| Time parameter | `expiryTimestamp` (absolute deadline) | `activationTimestamp` (computed: `block.timestamp + delay`) |

Both standards follow the same minimalist design philosophy: a single configuration function, a single canonical query, and event emission for observability.

When used independently, this ERC provides defense against privilege escalation through configurable activation delays. When combined with ERC-8083, a contract uses `hasEffectiveRole` to determine whether a pending change has activated, and `hasActiveRole` to determine whether the role has not yet expired. 

### Auto-Activation Design

This proposal uses an auto-activation pattern where the effective state is computed at query time by comparing the scheduled activation timestamp against `block.timestamp`. No execution step is required:

- **Deterministic effective time**: `activationTime = schedulingTimestamp + delay`. No ambiguity.
- **No execution race condition**: No execution step exists for anyone to front-run.
- **No second step**: After scheduling, the only possible action is cancellation (before `activationTime`). After `activationTime`, the change is already effective.
- **Query-based state**: `hasEffectiveRole` computes the effective state by comparing the scheduled change against `block.timestamp`. No storage update at the exact activation moment is needed.

An alternative two-step pattern (schedule + execute) was considered but not adopted. The auto-activation pattern is simpler and sufficient for the use case.

### Admin-Centric Delay Lookup

The delay for granting/revoking a role is looked up from the admin role's configuration rather than `_roleDelays the target role's configuration. This design creates a natural hierarchical structure:

- An admin role's delay configuration controls how quickly it can grant/revoke its subordinate roles
- Changes to the admin role itself are governed by its own admin's delay configuration
- For a self-admin role, the delay is self-referential but restricted

This approach simplifies the security model: protecting a role hierarchy requires configuring delays only on the admin roles, not on every subordinate role individually.

### Self-Admin Delay Restriction

This restriction prevents a self-administered role (such as `DEFAULT_ADMIN_ROLE`) from modifying its own delay parameters through the public `setRoleDelay` function. This is essential because:

- Without this restriction, a compromised admin key could call `setRoleDelay(DEFAULT_ADMIN_ROLE, ...)` to reduce the delay to the minimum allowed value, then grant the role to an attacker address with a drastically shortened defense window
- With this restriction, the delay parameters for the self-admin role are immutable after construction, ensuring the defense window cannot be eliminated
- The delay parameters for self-admin roles are set during contract construction via the internal `_setRoleDelay` function, which bypasses the restriction

### Separate Grant and Revoke Delays

Grant and revoke operations carry different risk profiles. Granting `DEFAULT_ADMIN_ROLE` is high-risk requiring a long delay; revoking it from a compromised account is defensive where a shorter delay may be justified. Separate delays also close the "instant-revoke then wait-out-grant" attack vector: without an independent revoke delay, an attacker could immediately revoke a defender's admin role and then wait out the grant delay for their own malicious grant.

### Per-Role Opt-In Design

Delayed activation is configurable per-role rather than mandatory for all roles. Not all roles benefit from delays: `PAUSER_ROLE` may need immediate activation for emergency response, and initialization-only roles have no need for delays after deployment. Per-role opt-in allows protocols to apply delays where they add security value.

## Backwards Compatibility

This proposal is designed as an opt-in extension that does not conflict with existing RBAC implementations:

- **RBAC compatibility**: The `hasEffectiveRole` function provides the canonical way to query role state.
- **ERC-8083 compatibility**: This proposal is fully compatible with ERC-8083. A contract may implement both standards independently or in combination. `hasEffectiveRole` and `hasActiveRole` are independent queries addressing orthogonal time dimensions.
- **ERC-165 compatibility**: Implementations support ERC-165 interface detection for both `ITimeDelayedAccessControl` and `IAccessControl`.
- **No storage layout conflict**: The proposal can use new storage mappings (e.g., `_roleDelays`, `_roleActivationTimestamp`, `_roleRevokingTimestamp`) alongside the existing `AccessControl` storage, without modifying the underlying storage layout.

## Reference Implementation

### Implementation

The implementation is based on OpenZeppelin's AccessControl contract. Developers can also implement this ERC independently.

```solidity
// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import { AccessControl } from "./AccessControl.sol";
import { ITimeDelayedAccessControl } from "./ITimeDelayedAccessControl.sol";

/// @title TimeDelayedAccessControl
/// @notice Implementation of {ITimeDelayedAccessControl} with time-delayed role grant and revocation.
/// @dev Extends {AccessControl} so that role grants and revocations are subject to configurable
///      delays. A granted role does not become effective until its grant delay elapses, and a
///      revoked role remains effective until its revoke delay elapses. This provides a safety
///      window for stakeholders to react to privilege changes.
contract TimeDelayedAccessControl is ITimeDelayedAccessControl, AccessControl {

    /// @dev Stores the grant and revoke delay configuration for a role.
    /// @param grantDelay The delay in seconds before a grant takes effect.
    /// @param revokeDelay The delay in seconds before a revocation takes effect.
    struct DelayConfig {
        uint256 grantDelay;
        uint256 revokeDelay;
    }

    /// @dev Represents a pending update to a role's delay configuration.
    /// @param newGrantDelay The new grant delay that will take effect.
    /// @param newRevokeDelay The new revoke delay that will take effect.
    /// @param activationTime The timestamp when the delay update takes effect.
    /// @param exists Whether a pending delay update exists.
    struct PendingDelayUpdate {
        uint256 newGrantDelay;
        uint256 newRevokeDelay;
        uint256 activationTime;
        bool exists;
    }

    /// @dev Maps role identifiers to their delay configuration.
    mapping(bytes32 => DelayConfig) private _roleDelays;

    /// @dev Maps role identifiers and accounts to the timestamp when the grant becomes effective.
    mapping(bytes32 => mapping(address => uint256)) internal _roleActivationTimestamp;

    /// @dev Maps role identifiers and accounts to the timestamp when the revocation takes effect.
    ///      If this value is in the future, the account still effectively holds the role
    ///      despite having been revoked in the underlying {AccessControl}.
    mapping(bytes32 => mapping(address => uint256)) internal _roleRevokingTimestamp;

    /// @dev Sets the grant and revoke delay configuration for a role.
    ///      Emits a {RoleDelayChanged} event.
    /// @param role The role identifier whose delay is being modified.
    /// @param grantDelay The new grant delay in seconds.
    /// @param revokeDelay The new revoke delay in seconds.
    function _setRoleDelay(bytes32 role, uint256 grantDelay, uint256 revokeDelay) internal virtual {
        DelayConfig memory current = _roleDelays[role];
        uint256 oldGrantDelay = current.grantDelay;
        uint256 oldRevokeDelay = current.revokeDelay;

        _roleDelays[role] = DelayConfig(grantDelay, revokeDelay);

        emit RoleDelayChanged(
            role,
            oldGrantDelay,
            oldRevokeDelay,
            grantDelay,
            revokeDelay
        );
    }

    /// @dev Reverts when attempting to set the delay for a role whose admin role is itself.
    ///      This prevents a compromised key holder from clearing delays to bypass the time-delay mechanism.
    error CannotSetSelfAdminDelay();

    /// @dev Reverts when attempting to set a delay value of 0, which is reserved as the uninitialized state.
    error InvalidDelay();

    /// @inheritdoc ITimeDelayedAccessControl
    function setRoleDelay(bytes32 role, uint256 grantDelay, uint256 revokeDelay)
        external override virtual onlyRole(getRoleAdmin(role))
    {
        // Disallow setting delay for a role whose admin is itself, preventing a compromised
        // key holder from clearing delays to bypass the time-delay mechanism.
        if (role == getRoleAdmin(role)) revert CannotSetSelfAdminDelay();

        // Disallow zero delay values, as 0 is reserved for the uninitialized mapping default.
        if (grantDelay == 0 || revokeDelay == 0) revert InvalidDelay();

        _setRoleDelay(role, grantDelay, revokeDelay);
    }

    /// @inheritdoc ITimeDelayedAccessControl
    function getRoleDelay(bytes32 role)
        external view override virtual returns (uint256 grantDelay, uint256 revokeDelay)
    {
        DelayConfig memory config = _roleDelays[role];
        return (config.grantDelay, config.revokeDelay);
    }

    /// @inheritdoc ITimeDelayedAccessControl
    /// @dev A role is considered effectively held when either:
    ///      1. The account has been granted the role AND the grant delay has elapsed, OR
    ///      2. The account has been revoked the role BUT the revoke delay has NOT yet elapsed
    ///      (the account retains privileges during the revocation grace period).
    function hasEffectiveRole(bytes32 role, address account)
        public view virtual returns (bool)
    {
        uint256 activationTime = _roleActivationTimestamp[role][account];
        bool roleActived = activationTime != 0 && activationTime <= block.timestamp;

        uint256 revokingTime = _roleRevokingTimestamp[role][account];
        bool roleRevoked = revokingTime != 0 && revokingTime <= block.timestamp;

        return roleActived && !roleRevoked;
    }

    /// @dev Returns `true` if this contract implements the interface defined by `interfaceId`.
    ///      Overrides {AccessControl.hasRole} to use {hasEffectiveRole} as the canonical role check.
    ///      In this implementation, `hasRole` is equivalent to `hasEffectiveRole`.
    function hasRole(bytes32 role, address account) public view override virtual returns (bool) {
        return hasEffectiveRole(role, account);
    }

    /// @dev Returns `true` if there is a pending (not yet effective) role change for the account.
    ///      A pending change exists when the activation or revoking timestamp is in the future.
    /// @param role The role identifier.
    /// @param account The address of the account to check.
    /// @return Whether a pending role change exists.
    function _existsPendingRoleChange(bytes32 role, address account) internal view virtual returns (bool) {
        return (block.timestamp < _roleActivationTimestamp[role][account]) ||
            (block.timestamp < _roleRevokingTimestamp[role][account]);
    }

    /// @dev Overrides {AccessControl._grantRole} to apply delayed activation.
    ///      If no pending change exists and the account does not already hold the role effectively,
    ///      schedules a grant with the configured delay. Clears any previous revocation timestamp.
    ///      Emits a {RoleGrantScheduled} event.
    /// @param role The role identifier.
    /// @param account The address of the account to grant the role to.
    /// @return Whether the grant was scheduled.
    function _grantRole(bytes32 role, address account) internal override virtual returns(bool) {
        if (!_existsPendingRoleChange(role, account) && !hasEffectiveRole(role, account)) {
            bytes32 adminRole = getRoleAdmin(role);
            DelayConfig memory config = _roleDelays[adminRole];

            // Clear any previous revocation so the new grant can take effect
            _roleRevokingTimestamp[role][account] = 0;

            uint256 activationTime = block.timestamp + config.grantDelay;
            _roleActivationTimestamp[role][account] = activationTime;

            emit RoleGrantScheduled(role, account, activationTime, msg.sender);
            return true;
        } else {
            return false;
        }
    }

    /// @dev Overrides {AccessControl._revokeRole} to apply delayed revocation.
    ///      If no pending change exists and the account currently holds the role effectively,
    ///      schedules a revocation with the configured delay.
    ///      Emits a {RoleRevokeScheduled} event.
    /// @param role The role identifier.
    /// @param account The address of the account to revoke the role from.
    /// @return Whether the revocation was scheduled.
    function _revokeRole(bytes32 role, address account) internal override virtual returns(bool) {
        if (!_existsPendingRoleChange(role, account)  && hasEffectiveRole(role, account)) {
            bytes32 adminRole = getRoleAdmin(role);
            DelayConfig memory config = _roleDelays[adminRole];

            uint256 revokingTime = block.timestamp + config.revokeDelay;
            _roleRevokingTimestamp[role][account] = revokingTime;

            emit RoleRevokeScheduled(role, account, revokingTime, msg.sender);
            return true;
        } else {
            return false;
        }
    }

    /// @dev Reverts when attempting to cancel a role change that is not in a pending state.
    error NoPendingRoleGrant();

    /// @dev Reverts when attempting to cancel a role revocation that is not in a pending state.
    error NoPendingRoleRevoke();

    /// @notice Cancels a pending scheduled role grant before it takes effect.
    /// @dev Resets the activation timestamp to 0 to prevent the grant from ever becoming effective.
    ///      Only accounts with the role's admin role can cancel scheduled grants.
    ///      Emits a {RoleGrantCancelled} event.
    /// @param role The role identifier.
    /// @param account The address of the account whose scheduled grant is being cancelled.
    function cancelScheduledRoleGrant(
        bytes32 role,
        address account
    ) external virtual onlyRole(getRoleAdmin(role)) {
        // Must have a pending grant (activation timestamp in the future)
        if (_roleActivationTimestamp[role][account] <= block.timestamp) revert NoPendingRoleGrant();

        _roleActivationTimestamp[role][account] = 0;

        emit RoleGrantCancelled(role, account, msg.sender);
    }

    /// @notice Cancels a pending scheduled role revocation before it takes effect.
    /// @dev Resets the revoking timestamp to 0 to restore the account's role.
    ///      Only accounts with the role's admin role can cancel scheduled revocations.
    ///      Emits a {RoleRevokeCancelled} event.
    /// @param role The role identifier.
    /// @param account The address of the account whose scheduled revocation is being cancelled.
    function cancelScheduledRoleRevoke(
        bytes32 role,
        address account
    ) external virtual onlyRole(getRoleAdmin(role)) {
        // Must have a pending revoke (revoking timestamp in the future)
        if (_roleRevokingTimestamp[role][account] <= block.timestamp) revert NoPendingRoleRevoke();

        _roleRevokingTimestamp[role][account] = 0;

        emit RoleRevokeCancelled(role, account, msg.sender);
    }

    /// @dev Returns true if this contract implements the interface defined by `interfaceId`.
    ///      Supports {ITimeDelayedAccessControl} and inherited interfaces.
    function supportsInterface(bytes4 interfaceId) public view override virtual returns (bool) {
        return interfaceId == this.supportsInterface.selector ||
            interfaceId == type(ITimeDelayedAccessControl).interfaceId || super.supportsInterface(interfaceId);
    }
}
```

## Security Considerations

### Admin Role Compromise

If all holders of the admin role for a delayed role are compromised, the delay provides limited defense — the attacker can cancel any pending defensive changes and schedule new ones. Protocols are advised to distribute admin roles across multiple independent accounts and consider multi-sig requirements for admin operations on security-critical roles.

### Permanent Root Roles

Root or default admin roles are advised to be assigned permanent activation timestamps during construction rather than through the delayed `grantRole` flow. This ensures the root admin is immediately effective at deployment while still benefiting from delay protection for subsequent grants.

### Cancellation Front-Running

An attacker observing a legitimate `cancelScheduledRoleRevoke` transaction in the mempool could front-run with malicious actions before the cancellation takes effect. This is a known limitation of public mempools. Implementations are advised to recommend commit-reveal patterns or private transaction relay for high-value role changes.

### Timestamp Variability and Safety Margins

Ethereum block timestamps are determined by validators and can deviate from real-world time. Malicious or accidental manipulation could lead to premature role activations or unintended delays in revocation. Contracts managing high-value permissions or time-sensitive roles are advised to incorporate safety margins to mitigate timestamp variances. For short-duration delays, larger margins are recommended to account for potential network congestion or delays.

### L2 Timestamp Manipulation

On Optimistic Rollups, sequencers can influence `block.timestamp` within known bounds (approximately 1 hour for major L2 networks). Implementations deployed on L2s are advised to set delays at least 2x the maximum timestamp deviation. For L2s with 1-hour drift windows, the practical minimum delay is at least 2 hours.

### Pending Change State Transitions

The pending change guard prevents conflicting scheduled changes but creates a state dependency: a new change cannot be scheduled until the pending change is either cancelled or completed. Implementations should document this behavior clearly. In particular:

- A pending grant blocks subsequent grants AND revocations for the same `(role, account)` pair
- A pending revocation blocks subsequent revocations AND grants for the same `(role, account)` pair
- To reverse a pending change, the admin must cancel it first, then schedule the opposite change

### Underlying RBAC Desynchronization

When inheriting from an existing AccessControl implementation, consistency must be ensured, and rigorous code auditing is required. Implementations are advised to clearly document that `hasRole`/`hasEffectiveRole` is the authoritative query.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).