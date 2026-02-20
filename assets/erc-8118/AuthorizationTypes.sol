// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/**
 * @title AuthorizationTypes
 * @notice Shared type definitions for Agent Authorization Interface (ERC-XXXX)
 * @dev This library defines the core data structures used throughout the implementation.
 *
 * Storage Optimization:
 * - AuthorizationData is packed into a single 256-bit slot
 * - startTime and endTime use uint48 (sufficient until year 8.9 million)
 * - allowedCalls uses uint64 (sufficient for any practical usage limit)
 * - 96 bits reserved for future extensions
 */
library AuthorizationTypes {
    /**
     * @notice Packed authorization data stored for each principal-agent-selector tuple
     * @dev Total size: 256 bits (1 slot)
     *      - startTime:    48 bits (offset 0)   - max ~8.9 million years
     *      - endTime:      48 bits (offset 48)  - max ~8.9 million years
     *      - allowedCalls: 64 bits (offset 96)  - max ~18 quintillion calls
     *      - _reserved:    96 bits (offset 160) - for future use
     *
     * A value of 0 for startTime means "no start restriction" (immediately valid)
     * A value of 0 for endTime means "no expiry" (valid indefinitely)
     * A value of 0 for allowedCalls means "no authorization" (revoked/never granted)
     */
    struct AuthorizationData {
        uint48 startTime;
        uint48 endTime;
        uint64 allowedCalls;
        // 96 bits reserved for future use (automatically zero-initialized)
    }

    /**
     * @notice Check if authorization data represents an active authorization
     * @param data The authorization data to check
     * @return True if allowedCalls > 0 (authorization exists)
     */
    function exists(AuthorizationData storage data) internal view returns (bool) {
        return data.allowedCalls > 0;
    }

    /**
     * @notice Check if the authorization is valid at the current time
     * @param data The authorization data to check
     * @return True if within time bounds and has remaining calls
     */
    function isValid(AuthorizationData storage data) internal view returns (bool) {
        if (data.allowedCalls == 0) return false;

        uint256 currentTime = block.timestamp;

        // Check start time (0 means no restriction)
        if (data.startTime != 0 && currentTime < data.startTime) return false;

        // Check end time (0 means no expiry)
        if (data.endTime != 0 && currentTime > data.endTime) return false;

        return true;
    }

    /**
     * @notice Clear authorization data (revoke)
     * @param data The authorization data to clear
     */
    function clear(AuthorizationData storage data) internal {
        data.startTime = 0;
        data.endTime = 0;
        data.allowedCalls = 0;
    }
}
