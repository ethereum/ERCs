// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title ChainidTools library
 * @notice This library provides helper to convert uint256 chainid provided by block.chainid to uint32
 *         chainid used across this DataIndex implementation
 */
library ChainidTools {
    /// @dev Error thrown when chainid is not supported
    error UnsupportedChain(uint256 chainId);

    /// @dev Error thrown when chainid is not the current chain
    error UnexpectedChain(uint32 expected, uint32 requested);

    /**
     * @dev Converts block.chainid to uint32 chainid
     * @return uint32 chainid
     */
    function chainid() internal view returns (uint32) {
        if (block.chainid <= type(uint32).max) {
            return uint32(block.chainid);
        }
        revert UnsupportedChain(block.chainid);
    }

    /**
     * @dev Requires current chain to be the same as requested
     * @param chainId Requested chain ID
     */
    function requireCurrentChain(uint32 chainId) internal view {
        uint32 currentChain = chainid();
        if (currentChain != chainId) revert UnexpectedChain(currentChain, chainId);
    }
}