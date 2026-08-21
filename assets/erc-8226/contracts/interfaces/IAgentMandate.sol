// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IAgentMandate is IERC165 {
    struct Mandate {
        address agent;
        uint48 validFrom;
        uint48 validUntil;
        address principal;
        bool revoked;
        address complianceProvider;
        bytes32 identityRef;
        address asset;
        uint256 maxTransactionValue;
        uint256 maxCumulativeValue;
        uint256 cumulativeUsed;
        bytes32 metadata;
    }

    /// @notice Parameters for grantMandate, bundled into a struct to avoid stack-too-deep.
    /// @param agent The address of the agent receiving the mandate.
    /// @param validFrom Unix timestamp from which the mandate is active.
    /// @param validUntil Unix timestamp after which the mandate expires.
    /// @param principal The address of the principal granting the mandate.
    /// @param complianceProvider Address of an IComplianceProvider. MUST be a non-zero address.
    /// @param identityRef Off-chain identity reference for the principal.
    /// @param asset Specific asset address.
    /// @param maxTransactionValue Per-transaction value cap.
    /// @param maxCumulativeValue Cumulative value cap over the mandate's lifetime.
    /// @param metadata Optional 32-byte pointer to off-chain metadata (e.g., legal-text content hash).
    /// @param actions Array of action labels.
    /// @param deadline Signature expiry timestamp (replay protection).
    struct GrantMandateParams {
        address agent;
        uint48 validFrom;
        uint48 validUntil;
        address principal;
        address complianceProvider;
        bytes32 identityRef;
        address asset;
        uint256 maxTransactionValue;
        uint256 maxCumulativeValue;
        bytes32 metadata;
        bytes32[] actions;
        uint256 deadline;
    }

    /// @notice Emitted when a mandate is granted.
    event MandateGranted(
        address indexed agent,
        address indexed principal,
        address complianceProvider,
        address asset,
        uint48 validFrom,
        uint48 validUntil,
        bytes32 metadata
    );

    /// @notice Emitted when an action is enabled on a mandate at grant time.
    event ActionEnabled(address indexed agent, address indexed principal, bytes32 indexed action);

    /// @notice Emitted when a mandate is revoked.
    event MandateRevoked(address indexed agent, address indexed principal, address revokedBy);

    /// @notice Emitted when a mandate's validity is extended.
    event MandateExtended(address indexed agent, address indexed principal, uint48 newValidUntil);

    /// @notice Emitted when an operator approval is set or revoked.
    event OperatorSet(address indexed principal, address indexed operator, bool approved);

    /// @notice Emitted when an agent executes an action recorded by a RAMS-aware token.
    event ExecutionRecorded(
        address indexed agent, address indexed principal, bytes32 indexed action, uint256 amount, uint256 cumulativeUsed
    );

    /// @notice Emitted when an agent is frozen. Freezing is restricted to authorized enforcer roles.
    event AgentFrozen(address indexed agent, address indexed enforcer);

    /// @notice Emitted when a freeze is lifted.
    event AgentUnfrozen(address indexed agent, address indexed enforcer);

    /// @notice Grants a mandate from a principal to an agent.
    /// @dev If `signature` is empty, msg.sender MUST equal params.principal. Otherwise the signature is verified
    ///      via SignatureChecker against the GrantMandate EIP-712 digest.
    /// @param params The mandate parameters.
    /// @param signature Principal signature (EIP-712, EIP-1271 supported).
    function grantMandate(GrantMandateParams calldata params, bytes calldata signature) external;

    /// @notice Revokes the active mandate for the given agent and principal.
    /// @dev Callable by the principal directly or by anyone with a valid principal signature. An approved operator MAY also call this.
    /// @param agent The agent address whose mandate is revoked.
    /// @param principal The principal address whose mandate is revoked.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal signature (EIP-712, EIP-1271 supported).
    function revokeMandate(address agent, address principal, uint256 deadline, bytes calldata signature) external;

    /// @notice Extends the validity of an existing mandate without resetting cumulativeUsed.
    /// @dev Callable by the principal directly or by anyone with a valid principal signature. An approved operator MAY also call this.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param newValidUntil New expiry timestamp. MUST be greater than the current validUntil.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal signature (EIP-712, EIP-1271 supported).
    function extendMandate(
        address agent,
        address principal,
        uint48 newValidUntil,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /// @notice Freezes an agent, halting all of its mandates. Restricted to authorized enforcer roles.
    /// @param agent The agent address to freeze.
    function freezeAgent(address agent) external;

    /// @notice Lifts a freeze on an agent.
    /// @param agent The agent address to unfreeze.
    function unfreezeAgent(address agent) external;

    /// @notice Sets or revokes operator approval for the principal.
    /// @dev Callable by the principal directly or by anyone with a valid principal signature.
    /// @param principal The principal granting/revoking operator status.
    /// @param operator The operator address being approved or revoked.
    /// @param approved True to approve, false to revoke.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal signature (EIP-712, EIP-1271 supported).
    function setOperator(address principal, address operator, bool approved, uint256 deadline, bytes calldata signature)
        external;

    /// @notice Records an agent-initiated execution. Called by RAMS-aware regulated tokens.
    /// @param agent The agent address.
    /// @param principal The principal on whose behalf the action is executed.
    /// @param action The action label being executed.
    /// @param amount The amount in the asset's base unit.
    function recordExecution(address agent, address principal, bytes32 action, uint256 amount) external;

    /// @notice Returns true if the agent can execute the action on the asset for the principal at the given amount.
    /// @dev Bundles asset, existence, validity, freeze, action, and cap checks into one call.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param asset The asset the action targets; MUST equal the mandate's `asset`.
    /// @param action The action label being checked.
    /// @param amount The amount to check, in the asset's base unit.
    /// @return True if the agent can execute the action at this amount.
    function canExecute(address agent, address principal, address asset, bytes32 action, uint256 amount)
        external
        view
        returns (bool);

    /// @notice Returns true if the action is enabled on the mandate.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param action The action label.
    /// @return True if the action is enabled.
    function isActionEnabled(address agent, address principal, bytes32 action) external view returns (bool);

    /// @notice Returns the full Mandate struct for the given agent and principal.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @return The Mandate struct.
    function getMandate(address agent, address principal) external view returns (Mandate memory);

    /// @notice Returns true if the operator is approved for the given principal.
    /// @param principal The principal address.
    /// @param operator The operator address.
    /// @return True if approved.
    function isOperator(address principal, address operator) external view returns (bool);

    /// @notice Returns true if the agent is frozen.
    /// @param agent The agent address.
    /// @return True if frozen.
    function isFrozen(address agent) external view returns (bool);

    /// @notice Returns the current nonce for a principal (used in signed operations).
    /// @param principal The principal address.
    /// @return The current nonce value.
    function nonces(address principal) external view returns (uint256);

    /// @notice Returns the EIP-712 domain separator.
    /// @return The domain separator hash.
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
