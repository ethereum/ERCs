// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPersistentIdentityResolver
 * @notice Resolution interface for looking up identity data by name.
 *
 *  Provides convenience functions for resolving a human-readable name
 *  to its associated on-chain data in a single call. Implementations
 *  MAY be on the same contract as IPersistentIdentity or on a separate
 *  resolver contract.
 */
interface IPersistentIdentityResolver {

    /// @notice Resolve a name to its bound address
    /// @param name The human-readable name
    /// @return The bound EVM address (zero if unbound or not registered)
    function resolveAddress(string calldata name) external view returns (address);

    /// @notice Resolve a name to its URL record
    /// @param name The human-readable name
    /// @return The URL string (empty if not set or not registered)
    function resolveUrl(string calldata name) external view returns (string memory);

    /// @notice Resolve a name to its full identity record
    /// @param name The human-readable name
    /// @return tokenId The token ID
    /// @return owner The current token owner
    /// @return boundAddr The bound address
    /// @return bound Whether the identity is bound
    /// @return url The URL record
    /// @return tier The tier classification
    function resolveIdentity(string calldata name) external view returns (
        uint256 tokenId,
        address owner,
        address boundAddr,
        bool bound,
        string memory url,
        uint8 tier
    );
}
