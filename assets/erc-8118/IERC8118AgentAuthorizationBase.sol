// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title IERC8118AgentAuthorizationBase
 * @notice Standard interface for secure, time-bound, and usage-limited delegation
 *         of on-chain actions to autonomous agents.
 * @dev MUST be implemented by contracts supporting agent delegation.
 *
 * This interface defines the core authorization mechanism where:
 * - Principals delegate specific function permissions to agents
 * - Agents must cryptographically consent to being authorized (EIP-712)
 * - Each agent can only serve one principal at a time (single-principal constraint)
 * - Authorizations are scoped by function selector, time bounds, and usage limits
 *
 * ERC-165 Interface ID: 0xTBD (calculated when EIP number assigned)
 * Calculation: XOR of all function selectors including DOMAIN_SEPARATOR()
 */
interface IERC8118AgentAuthorizationBase {
    // ============ Events ============

    /**
     * @notice Emitted when an agent is authorized for a specific function
     * @param principal The address delegating authority
     * @param agent The address receiving permission
     * @param selector The function selector being authorized
     * @param startTime Earliest timestamp the authorization is valid (0 = immediate)
     * @param endTime Latest timestamp the authorization is valid (0 = no expiry)
     * @param allowedCalls Number of times the agent can call the function
     */
    event AgentAuthorized(
        address indexed principal,
        address indexed agent,
        bytes4 indexed selector,
        uint256 startTime,
        uint256 endTime,
        uint256 allowedCalls
    );

    /**
     * @notice Emitted when an authorization is revoked (manual or auto-revoke)
     * @param principal The principal who owned the authorization
     * @param agent The agent whose permission was revoked
     * @param selector The function selector that was revoked
     */
    event AgentRevoked(
        address indexed principal,
        address indexed agent,
        bytes4 indexed selector
    );

    // ============ Errors ============

    /// @notice Thrown when the agent address is zero
    error InvalidAgentAddress();

    /// @notice Thrown when the selector is zero (wildcard authorization not permitted)
    error InvalidSelector();

    /// @notice Thrown when allowedCalls is set to zero (use revoke instead)
    error ZeroCallsNotAllowed();

    /// @notice Thrown when timestamp or call count exceeds packed storage bounds (uint48/uint64)
    error ValueExceedsBounds();

    /// @notice Thrown when the signature deadline has passed
    error SignatureExpired();

    /// @notice Thrown when the agent consent signature is invalid
    error InvalidSignature();

    /// @notice Thrown when attempting to authorize an agent already bound to another principal
    error AgentAlreadyBound();

    /// @notice Thrown when attempting to revoke a non-existent authorization
    error NoAuthorizationExists();

    /// @notice Thrown when an unauthorized agent attempts to execute a protected function
    error NotAuthorized();

    // ============ Write Functions ============

    /**
     * @notice Authorize an agent to call a specific function on behalf of the caller
     * @dev The agent MUST sign an EIP-712 consent message. Reverts if:
     *      - agent is zero address (InvalidAgentAddress)
     *      - selector is 0x00000000 (InvalidSelector)
     *      - allowedCalls is 0 (ZeroCallsNotAllowed)
     *      - startTime/endTime > type(uint48).max or allowedCalls > type(uint64).max (ValueExceedsBounds)
     *      - block.timestamp > deadline (SignatureExpired)
     *      - signature is invalid (InvalidSignature)
     *      - agent is bound to different principal (AgentAlreadyBound)
     *
     * @param agent The agent address to authorize
     * @param selector The function selector (MUST NOT be 0x00000000)
     * @param startTime Earliest valid timestamp (0 = no restriction)
     * @param endTime Latest valid timestamp (0 = no expiry)
     * @param allowedCalls Number of allowed calls (MUST be > 0)
     * @param deadline Signature expiry timestamp for replay prevention
     * @param signature Agent's EIP-712 typed data consent signature
     */
    function authorizeAgent(
        address agent,
        bytes4 selector,
        uint256 startTime,
        uint256 endTime,
        uint256 allowedCalls,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /**
     * @notice Batch authorize multiple agent-function pairs in a single transaction
     * @dev Each authorization in the batch MUST satisfy the same requirements as authorizeAgent.
     *      Reverts entirely if any single authorization fails.
     *
     * @param batch Array of BatchAuthorization structs containing authorization parameters
     */
    function batchAuthorizeAgent(BatchAuthorization[] calldata batch) external;

    /**
     * @notice Revoke an agent's authorization for a specific function
     * @dev Only the principal (msg.sender) who created the authorization can revoke it.
     *      Reverts if no authorization exists (NoAuthorizationExists).
     *      If this was the agent's last authorization from this principal, the agent is unbound.
     *
     * @param agent The agent address to revoke
     * @param selector The function selector to revoke authorization for
     */
    function revokeAgent(address agent, bytes4 selector) external;

    /**
     * @notice Batch revoke multiple function authorizations for a single agent
     * @dev More gas-efficient than multiple revokeAgent calls.
     *      Reverts if any selector has no authorization (NoAuthorizationExists).
     *
     * @param agent The agent address
     * @param selectors Array of function selectors to revoke
     */
    function batchRevokeAgent(address agent, bytes4[] calldata selectors) external;

    // ============ View Functions ============

    /**
     * @notice Check if an agent is currently authorized to call a function for a principal
     * @dev Returns true only if:
     *      - Authorization exists
     *      - Current time is within [startTime, endTime] bounds
     *      - remainingCalls > 0
     *
     * @param principal The principal address
     * @param agent The agent address
     * @param selector The function selector
     * @return True if the agent is authorized at the current block.timestamp
     */
    function isAuthorizedAgent(
        address principal,
        address agent,
        bytes4 selector
    ) external view returns (bool);

    /**
     * @notice Get the full authorization parameters for an agent-function pair
     * @param principal The principal address
     * @param agent The agent address
     * @param selector The function selector
     * @return startTime The start timestamp (0 = no restriction)
     * @return endTime The end timestamp (0 = no expiry)
     * @return remainingCalls The remaining number of allowed calls
     */
    function getAgentAuthorization(
        address principal,
        address agent,
        bytes4 selector
    ) external view returns (uint256 startTime, uint256 endTime, uint256 remainingCalls);

    /**
     * @notice Get the principal that an agent is currently bound to
     * @dev Due to the single-principal constraint, each agent can only serve one principal
     *      at a time within a contract instance.
     *
     * @param agent The agent address
     * @return The principal address (address(0) if the agent is not bound)
     */
    function principalOf(address agent) external view returns (address);

    /**
     * @notice Get the current nonce for an agent's consent signatures
     * @dev Nonces are incremented after each successful authorization to prevent replay attacks.
     *
     * @param agent The agent address
     * @return The current nonce value
     */
    function nonces(address agent) external view returns (uint256);

    /**
     * @notice Get the EIP-712 domain separator for signature verification
     * @dev Required for EIP-5267/ERC-2612 compatibility and off-chain signature construction.
     *      The domain separator is computed as:
     *      keccak256(abi.encode(
     *          keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
     *          keccak256(bytes(name)),
     *          keccak256(bytes(version)),
     *          chainId,
     *          address(this)
     *      ))
     *
     * @return The domain separator hash used in EIP-712 signatures
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

/**
 * @notice Parameters for batch authorization operations
 * @dev Used in batchAuthorizeAgent to authorize multiple agent-function pairs
 */
struct BatchAuthorization {
    address agent;
    bytes4 selector;
    uint256 startTime;
    uint256 endTime;
    uint256 allowedCalls;
    uint256 deadline;
    bytes signature;
}
