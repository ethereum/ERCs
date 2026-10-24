// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title AuthorizationErrors
 * @notice Custom error definitions for Agent Authorization Interface (ERC-XXXX)
 * @dev Custom errors are more gas-efficient than require strings and provide
 *      structured error data for better debugging and client-side handling.
 *
 * Error Categories:
 * - Input validation errors (InvalidAgentAddress, InvalidSelector, ZeroCallsNotAllowed)
 * - Signature errors (SignatureExpired, InvalidSignature)
 * - State errors (AgentAlreadyBound, NoAuthorizationExists, NotAuthorized)
 */
library AuthorizationErrors {
    // ============ Input Validation Errors ============

    /// @notice Thrown when the agent address is zero
    /// @dev Prevents authorization to the zero address which would be unrecoverable
    error InvalidAgentAddress();

    /// @notice Thrown when the function selector is zero (0x00000000)
    /// @dev Wildcard authorization is explicitly prohibited for security reasons.
    ///      Each function must be authorized individually.
    error InvalidSelector();

    /// @notice Thrown when allowedCalls is set to zero
    /// @dev Use revokeAgent() to remove authorization instead of setting calls to zero.
    ///      This prevents confusion between "no authorization" and "zero remaining calls".
    error ZeroCallsNotAllowed();

    /// @notice Thrown when a timestamp or call count exceeds storage bounds
    /// @dev startTime and endTime must fit in uint48 (max ~8.9 million years from epoch).
    ///      allowedCalls must fit in uint64 (max ~18 quintillion calls).
    error ValueExceedsBounds();

    // ============ Signature Errors ============

    /// @notice Thrown when the signature deadline has passed
    /// @dev Signatures include a deadline to prevent replay attacks across time.
    ///      The deadline must be >= block.timestamp when the transaction is mined.
    error SignatureExpired();

    /// @notice Thrown when the agent consent signature is invalid
    /// @dev The signature must be:
    ///      - For EOA: Valid ECDSA signature over EIP-712 typed data
    ///      - For contract: Valid EIP-1271 signature (isValidSignature returns magic value)
    error InvalidSignature();

    // ============ State Errors ============

    /// @notice Thrown when attempting to authorize an agent already bound to a different principal
    /// @dev The single-principal constraint prevents agents from serving multiple principals
    ///      simultaneously within the same contract. The existing principal must revoke all
    ///      authorizations before the agent can be bound to a new principal.
    error AgentAlreadyBound();

    /// @notice Thrown when attempting to revoke or update a non-existent authorization
    /// @dev Ensures revoke/update operations are idempotent-safe by failing on
    ///      non-existent authorizations rather than silently succeeding.
    error NoAuthorizationExists();

    /// @notice Thrown when an unauthorized agent attempts to execute a protected function
    /// @dev Indicates the agent either:
    ///      - Has no authorization for the specific function selector
    ///      - Authorization has expired (outside time window)
    ///      - Authorization has no remaining calls
    error NotAuthorized();
}
