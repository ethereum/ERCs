// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {IERC8118AgentAuthorizationBase} from "./IERC8118AgentAuthorizationBase.sol";

/**
 * @title IERC8118AgentAuthorizationUpdatable
 * @notice Optional extension interface for in-place authorization updates
 * @dev MAY be implemented for better user experience when modifying authorizations.
 *
 * This extension allows principals to update existing authorization parameters without
 * requiring a full revoke-and-reauthorize cycle. Key features:
 *
 * - Restrictions (reducing allowedCalls, shortening time window) do NOT require agent re-consent
 * - Escalations (increasing allowedCalls, extending time window) REQUIRE fresh agent signature
 * - Updates maintain the single-principal constraint
 *
 * ERC-165 Interface ID: 0xTBD (calculated when EIP number assigned)
 * Calculation: keccak256('updateAgentAuthorization(address,bytes4,uint256,uint256,uint256,uint256,bytes)')
 */
interface IERC8118AgentAuthorizationUpdatable is IERC8118AgentAuthorizationBase {
    // ============ Events ============

    /**
     * @notice Emitted when authorization parameters are updated
     * @param principal The principal who owns the authorization
     * @param agent The agent whose authorization was updated
     * @param selector The function selector being updated
     * @param newStartTime The new start timestamp
     * @param newEndTime The new end timestamp
     * @param newAllowedCalls The new allowed calls count
     */
    event AgentAuthorizationUpdated(
        address indexed principal,
        address indexed agent,
        bytes4 indexed selector,
        uint256 newStartTime,
        uint256 newEndTime,
        uint256 newAllowedCalls
    );

    // ============ Write Functions ============

    /**
     * @notice Update existing authorization parameters
     * @dev Signature requirements depend on whether this is a restriction or escalation:
     *
     *      RESTRICTION (no signature required):
     *      - Reducing allowedCalls (newAllowedCalls < current)
     *      - Shortening time window (newEndTime < current, or newStartTime > current)
     *
     *      ESCALATION (signature REQUIRED):
     *      - Increasing allowedCalls (newAllowedCalls > current)
     *      - Extending time window (newEndTime > current, or newStartTime < current)
     *
     *      Reverts if:
     *      - No authorization exists (NoAuthorizationExists)
     *      - newAllowedCalls is 0 (ZeroCallsNotAllowed) - use revokeAgent instead
     *      - block.timestamp > deadline (SignatureExpired)
     *      - Escalation attempted without valid signature (InvalidSignature)
     *
     * @param agent The agent address
     * @param selector The function selector
     * @param newStartTime New start timestamp
     * @param newEndTime New end timestamp
     * @param newAllowedCalls New call allowance (MUST be > 0)
     * @param deadline Signature expiry timestamp (for replay prevention)
     * @param signature Agent's EIP-712 consent signature (required for escalation, empty for restriction)
     */
    function updateAgentAuthorization(
        address agent,
        bytes4 selector,
        uint256 newStartTime,
        uint256 newEndTime,
        uint256 newAllowedCalls,
        uint256 deadline,
        bytes calldata signature
    ) external;
}
