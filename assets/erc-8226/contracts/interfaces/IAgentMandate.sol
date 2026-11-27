// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IAgentMandate is IERC165 {
    /// @notice Reason a canExecute check passed or failed. OK means the action may execute.
    /// @dev The listed reasons are the normative check set. OTHER is only for implementation-specific
    ///      checks not covered here, and MUST NOT stand in for one of the listed reasons.
    ///      The reasons are listed in the order canExecute checks them. A future revision adds new reasons at the end.
    enum MandateReason {
        OK,
        NONEXISTENT,
        AGENT_FROZEN,
        PRINCIPAL_FROZEN,
        NOT_YET_VALID,
        EXPIRED,
        REVOKED,
        ACTION_NOT_ENABLED,
        CONSTRAINT_FAILED,
        NO_LIMIT,
        OVER_TX_CAP,
        OVER_CUMULATIVE_CAP,
        OTHER
    }

    /// @notice Reverts recordExecution, and any gate, with the reason of the first failing check.
    error MandateBlocked(MandateReason reason);

    /// @notice How a constraint compares a calldata parameter with its value.
    enum Check {
        EQUALS,
        NOT_EQUALS,
        AT_MOST,
        AT_LEAST
    }

    /// @notice A rule on one parameter of an action's calldata. Several EQUALS constraints on the same index pass
    ///         if any of them matches. All other constraints must pass.
    /// @param index Index of the 32-byte calldata word after the selector.
    /// @param check The comparison.
    /// @param value The value the word is compared with. AT_MOST and AT_LEAST compare it as uint256.
    struct Constraint {
        uint8 index;
        Check check;
        bytes32 value;
    }

    /// @notice An enabled action and the constraints on its calldata.
    struct Action {
        bytes32 action;
        Constraint[] constraints;
    }

    /// @notice The side of a balance change that a limit counts: what leaves the principal's account, or what
    ///         enters it.
    enum Direction {
        OUTFLOW,
        INFLOW
    }

    /// @notice The budget of one asset in one direction, in its base unit, shared by every action of the mandate.
    /// @param cumulativeUsed Starting value at grant. 0 for a new budget.
    struct Limit {
        address asset;
        Direction direction;
        uint256 maxTransactionValue;
        uint256 maxCumulativeValue;
        uint256 cumulativeUsed;
    }

    /// @notice An amount of one asset that an execution moves in one direction.
    struct Flow {
        address asset;
        Direction direction;
        uint256 amount;
    }

    struct Mandate {
        address agent;
        uint48 validFrom;
        uint48 validUntil;
        address principal;
        bool revoked;
        address complianceProvider;
        bytes32 identityRef;
        address target;
        bytes32 metadata;
    }

    /// @notice Parameters for grantMandate, bundled into a struct to avoid stack-too-deep.
    /// @param agent The address of the agent receiving the mandate.
    /// @param validFrom Unix timestamp from which the mandate is active.
    /// @param validUntil Unix timestamp after which the mandate expires.
    /// @param principal The address of the principal granting the mandate.
    /// @param complianceProvider Address of an IComplianceProvider. MUST be a non-zero address.
    /// @param identityRef Off-chain identity reference for the principal.
    /// @param target The contract the agent calls.
    /// @param actions The enabled actions, each with its constraints.
    /// @param limits One budget per asset and direction. An amount with no limit on its asset and direction fails.
    /// @param metadata Optional 32-byte pointer to off-chain metadata (e.g., legal-text content hash).
    /// @param deadline Signature expiry timestamp (replay protection).
    struct GrantMandateParams {
        address agent;
        uint48 validFrom;
        uint48 validUntil;
        address principal;
        address complianceProvider;
        bytes32 identityRef;
        address target;
        Action[] actions;
        Limit[] limits;
        bytes32 metadata;
        uint256 deadline;
    }

    /// @notice Emitted when a mandate is granted.
    event MandateGranted(
        address indexed agent,
        address indexed principal,
        address indexed target,
        address complianceProvider,
        uint48 validFrom,
        uint48 validUntil,
        bytes32 metadata
    );

    /// @notice Emitted when an action is enabled on a mandate at grant time.
    event ActionEnabled(address indexed agent, address indexed principal, bytes32 indexed action, address target);

    /// @notice Emitted for each limit of a mandate at grant time.
    event LimitSet(
        address indexed agent,
        address indexed principal,
        address indexed asset,
        address target,
        Direction direction,
        uint256 maxTransactionValue,
        uint256 maxCumulativeValue,
        uint256 cumulativeUsed
    );

    /// @notice Emitted when a mandate is revoked.
    event MandateRevoked(address indexed agent, address indexed principal, address indexed target, address revokedBy);

    /// @notice Emitted when a mandate's validity is extended.
    event MandateExtended(
        address indexed agent, address indexed principal, address indexed target, uint48 newValidUntil
    );

    /// @notice Emitted when an operator approval is set or revoked.
    event OperatorSet(address indexed principal, address indexed operator, bool approved);

    /// @notice Emitted for each amount an execution moves.
    event ExecutionRecorded(
        address indexed agent,
        address indexed principal,
        bytes32 indexed action,
        address target,
        address asset,
        Direction direction,
        uint256 amount,
        uint256 cumulativeUsed
    );

    /// @notice Emitted when an agent is frozen. Freezing is restricted to authorized enforcer roles.
    event AgentFrozen(address indexed agent, address indexed enforcer);

    /// @notice Emitted when a freeze is lifted.
    event AgentUnfrozen(address indexed agent, address indexed enforcer);

    /// @notice Emitted when a principal is frozen. Freezing is restricted to authorized enforcer roles.
    event PrincipalFrozen(address indexed principal, address indexed enforcer);

    /// @notice Emitted when a freeze on a principal is lifted.
    event PrincipalUnfrozen(address indexed principal, address indexed enforcer);

    /// @notice Grants a mandate from a principal to an agent.
    /// @dev If `signature` is empty, msg.sender MUST be params.principal or an approved operator of it. Otherwise the
    ///      GrantMandate EIP-712 digest MUST be signed by the principal (ERC-1271 supported) or by an approved operator.
    /// @param params The mandate parameters.
    /// @param signature Principal or operator signature (EIP-712).
    function grantMandate(GrantMandateParams calldata params, bytes calldata signature) external;

    /// @notice Revokes the active mandate for the given agent, principal and target.
    /// @dev Callable by the principal or an approved operator, directly or by signature.
    /// @param agent The agent address whose mandate is revoked.
    /// @param principal The principal address whose mandate is revoked.
    /// @param target The target of the mandate being revoked.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal or operator signature (EIP-712).
    function revokeMandate(address agent, address principal, address target, uint256 deadline, bytes calldata signature)
        external;

    /// @notice Extends the validity of an existing mandate without resetting cumulativeUsed.
    /// @dev Callable by the principal or an approved operator, directly or by signature.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param target The target of the mandate being extended.
    /// @param newValidUntil New expiry timestamp. MUST be greater than the current validUntil.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal or operator signature (EIP-712).
    function extendMandate(
        address agent,
        address principal,
        address target,
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

    /// @notice Freezes a principal, halting every mandate granted by that principal. Restricted to authorized
    ///         enforcer roles.
    /// @dev Reversible and keyed by principal alone, so it needs no enumeration of the principal's agents and
    ///      also covers mandates granted while the freeze is in place. It does not revoke: revocation stays with
    ///      the principal, so an enforcer cannot destroy a delegation the principal wants to keep.
    /// @param principal The principal address to freeze.
    function freezePrincipal(address principal) external;

    /// @notice Lifts a freeze on a principal.
    /// @param principal The principal address to unfreeze.
    function unfreezePrincipal(address principal) external;

    /// @notice Sets or revokes operator approval for the principal. An operator can do everything the principal can
    ///         on its mandates, except set operators.
    /// @dev Callable by the principal, directly or by signature. An enforcer can call it directly, but only to remove
    ///      an operator.
    /// @param principal The principal granting/revoking operator status.
    /// @param operator The operator address being approved or revoked.
    /// @param approved True to approve, false to revoke.
    /// @param deadline Signature expiry timestamp.
    /// @param signature Principal signature (EIP-712, ERC-1271 supported).
    function setOperator(address principal, address operator, bool approved, uint256 deadline, bytes calldata signature)
        external;

    /// @notice Records an agent-initiated execution and adds each flow to the cumulativeUsed of its limit.
    /// @param agent The agent address.
    /// @param principal The principal on whose behalf the action is executed.
    /// @param target The target of the mandate. When the caller is the target, it MUST pass its own address.
    /// @param action The action label being executed.
    /// @param data The calldata the constraints are checked against.
    /// @param flows The amounts the execution moves, each asset and direction at most once.
    function recordExecution(
        address agent,
        address principal,
        address target,
        bytes32 action,
        bytes calldata data,
        Flow[] calldata flows
    ) external;

    /// @notice Returns whether the agent can execute the action on the target for the principal, and the reason.
    /// @dev Bundles existence, validity, agent and principal freeze, action, constraint and limit checks.
    /// @param agent The agent address.
    /// @param principal The principal address.
    /// @param target The contract the action calls; selects the mandate.
    /// @param action The action label being checked.
    /// @param data The calldata the constraints are checked against.
    /// @param flows The amounts to check, each asset and direction at most once.
    /// @return ok True if the agent can execute the action.
    /// @return reason MandateReason.OK when ok is true, otherwise the first failing check.
    function canExecute(
        address agent,
        address principal,
        address target,
        bytes32 action,
        bytes calldata data,
        Flow[] calldata flows
    ) external view returns (bool ok, MandateReason reason);

    /// @notice Returns true if the action is enabled on the mandate.
    function isActionEnabled(address agent, address principal, address target, bytes32 action)
        external
        view
        returns (bool);

    /// @notice Returns the Mandate struct for the given agent, principal and target.
    function getMandate(address agent, address principal, address target) external view returns (Mandate memory);

    /// @notice Returns the enabled actions of the mandate.
    function getActions(address agent, address principal, address target) external view returns (bytes32[] memory);

    /// @notice Returns the limits of the mandate, with their cumulativeUsed.
    function getLimits(address agent, address principal, address target) external view returns (Limit[] memory);

    /// @notice Returns the constraints of an enabled action.
    function getConstraints(address agent, address principal, address target, bytes32 action)
        external
        view
        returns (Constraint[] memory);

    /// @notice Returns true if the operator is approved for the given principal.
    /// @param principal The principal address.
    /// @param operator The operator address.
    /// @return True if approved.
    function isOperator(address principal, address operator) external view returns (bool);

    /// @notice Returns true if the agent is frozen.
    /// @param agent The agent address.
    /// @return True if frozen.
    function isAgentFrozen(address agent) external view returns (bool);

    /// @notice Returns true if the principal is frozen.
    /// @param principal The principal address.
    /// @return True if frozen.
    function isPrincipalFrozen(address principal) external view returns (bool);

    /// @notice Returns the current nonce for a principal (used in signed operations).
    /// @param principal The principal address.
    /// @return The current nonce value.
    function nonces(address principal) external view returns (uint256);

    /// @notice Returns the EIP-712 domain separator.
    /// @return The domain separator hash.
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
