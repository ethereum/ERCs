// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {AgentAuthorizationBase} from "./AgentAuthorizationBase.sol";
import {IERC8118AgentAuthorizationUpdatable} from "./interfaces/IERC8118AgentAuthorizationUpdatable.sol";
import {AuthorizationTypes} from "./libraries/AuthorizationTypes.sol";
import {AuthorizationErrors} from "./libraries/AuthorizationErrors.sol";

/**
 * @title AgentAuthorizationUpdatable
 * @notice Reference implementation with in-place authorization update support
 * @dev Extends AgentAuthorizationBase with the optional update extension.
 *
 * Update Rules:
 * - RESTRICTION (no signature required): reducing calls, shortening time window
 * - ESCALATION (signature required): increasing calls, extending time window
 *
 * This allows principals to modify existing authorizations without a full
 * revoke-and-reauthorize cycle, improving UX for long-running agent sessions.
 *
 * @custom:security-contact security@world3.ai
 */
abstract contract AgentAuthorizationUpdatable is AgentAuthorizationBase, IERC8118AgentAuthorizationUpdatable {
    using AuthorizationTypes for AuthorizationTypes.AuthorizationData;

    // ============ Constructor ============

    /**
     * @notice Initialize the contract with EIP-712 domain parameters
     * @param name_ The contract name for EIP-712 domain
     * @param version_ The contract version for EIP-712 domain
     */
    constructor(string memory name_, string memory version_) AgentAuthorizationBase(name_, version_) {}

    // ============ External Write Functions ============

    /// @inheritdoc IERC8118AgentAuthorizationUpdatable
    function updateAgentAuthorization(
        address agent,
        bytes4 selector,
        uint256 newStartTime,
        uint256 newEndTime,
        uint256 newAllowedCalls,
        uint256 deadline,
        bytes calldata signature
    ) external {
        address principal = msg.sender;

        // Validate new allowedCalls
        if (newAllowedCalls == 0) {
            revert AuthorizationErrors.ZeroCallsNotAllowed();
        }

        // Check deadline for replay prevention
        if (block.timestamp > deadline) {
            revert AuthorizationErrors.SignatureExpired();
        }

        // Bounds checks to prevent silent truncation
        if (newStartTime > type(uint48).max || newEndTime > type(uint48).max) {
            revert AuthorizationErrors.ValueExceedsBounds();
        }
        if (newAllowedCalls > type(uint64).max) {
            revert AuthorizationErrors.ValueExceedsBounds();
        }

        // Get current authorization
        AuthorizationTypes.AuthorizationData storage data = _authorizations[principal][agent][selector];

        if (!data.exists()) {
            revert AuthorizationErrors.NoAuthorizationExists();
        }

        // Determine if this is an escalation
        bool isEscalation = _isEscalation(
            data.startTime,
            data.endTime,
            data.allowedCalls,
            uint48(newStartTime),
            uint48(newEndTime),
            uint64(newAllowedCalls)
        );

        // Require signature for escalation
        if (isEscalation) {
            _verifyAgentConsent(principal, agent, selector, newStartTime, newEndTime, newAllowedCalls, deadline, signature);

            // Increment nonce after successful signature verification
            unchecked {
                ++_nonces[agent];
            }
        }

        // Update authorization
        data.startTime = uint48(newStartTime);
        data.endTime = uint48(newEndTime);
        data.allowedCalls = uint64(newAllowedCalls);

        emit AgentAuthorizationUpdated(principal, agent, selector, newStartTime, newEndTime, newAllowedCalls);
    }

    // ============ ERC-165 Support ============

    /// @inheritdoc AgentAuthorizationBase
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC8118AgentAuthorizationUpdatable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    // ============ Internal Functions ============

    /**
     * @notice Determine if an update constitutes an escalation
     * @dev Escalation occurs when:
     *      - newAllowedCalls > currentAllowedCalls
     *      - newEndTime > currentEndTime (when currentEndTime != 0)
     *      - newStartTime < currentStartTime (when currentStartTime != 0)
     *      - newEndTime == 0 when currentEndTime != 0 (removing expiry = escalation)
     *
     * @param currentStart Current start time
     * @param currentEnd Current end time
     * @param currentCalls Current allowed calls
     * @param newStart New start time
     * @param newEnd New end time
     * @param newCalls New allowed calls
     * @return True if this is an escalation requiring signature
     */
    function _isEscalation(
        uint48 currentStart,
        uint48 currentEnd,
        uint64 currentCalls,
        uint48 newStart,
        uint48 newEnd,
        uint64 newCalls
    ) internal pure returns (bool) {
        // Increasing allowed calls is always escalation
        if (newCalls > currentCalls) return true;

        // Extending end time is escalation (unless current was "no expiry")
        // If current end is 0 (no expiry), any non-zero end is a restriction
        // If current end is non-zero, setting to 0 (no expiry) is escalation
        if (currentEnd != 0 && (newEnd == 0 || newEnd > currentEnd)) return true;

        // Moving start time earlier is escalation (unless current was "immediate")
        // If current start is 0 (immediate), any non-zero start is a restriction
        // If current start is non-zero, setting to 0 (immediate) is escalation
        if (currentStart != 0 && (newStart == 0 || newStart < currentStart)) return true;

        return false;
    }
}
