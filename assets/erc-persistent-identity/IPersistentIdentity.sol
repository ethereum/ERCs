// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPersistentIdentity
 * @notice Core interface for the Persistent Identity Protocol (PIP).
 *
 *  A Persistent Identity Token is an ERC-721 token that represents a
 *  human-readable, on-chain identity bound to an EVM address. Once bound,
 *  the token becomes soulbound (non-transferable) until explicitly unbound
 *  by a governance action.
 *
 *  Key properties:
 *    - Human-readable name mapped to a token ID
 *    - Token ID mapped to a bound EVM address (spatial binding)
 *    - Binding locks the token (soulbound behavior)
 *    - Unbinding requires governance/moderator action
 *    - Optional URL record per identity
 *    - Lifecycle events for all state changes
 */
interface IPersistentIdentity {

    // ─── Enums ────────────────────────────────────────────────────────

    /// @notice Identity tier classification
    enum Tier { Reserved, Standard, Basic }

    // ─── Events ───────────────────────────────────────────────────────

    /// @notice Emitted when a new identity is minted
    event IdentityMinted(
        uint256 indexed tokenId,
        string name,
        Tier tier,
        address indexed to,
        address boundAddress
    );

    /// @notice Emitted when an identity is bound to an address
    event IdentityBound(
        uint256 indexed tokenId,
        address indexed boundAddress
    );

    /// @notice Emitted when an identity is unbound (unlocked for transfer)
    event IdentityUnbound(uint256 indexed tokenId);

    /// @notice Emitted when an identity name is changed by governance
    event IdentityRenamed(
        uint256 indexed tokenId,
        string oldName,
        string newName
    );

    /// @notice Emitted when a URL record is set
    event UrlRecordSet(
        uint256 indexed tokenId,
        string url
    );

    // ─── Errors ───────────────────────────────────────────────────────

    /// @notice The name is already registered
    error NameAlreadyRegistered(string name);

    /// @notice The name string is empty
    error EmptyName();

    /// @notice Caller is not the token owner
    error NotTokenOwner();

    /// @notice Token is bound and cannot be transferred
    error IdentityBoundLocked();

    /// @notice Identity must be bound before this action
    error IdentityNotBound();

    // ─── Name Resolution ──────────────────────────────────────────────

    /// @notice Check if a name is registered
    /// @param name The human-readable name
    /// @return True if the name has been minted
    function nameRegistered(string calldata name) external view returns (bool);

    /// @notice Get the token ID for a registered name
    /// @param name The human-readable name
    /// @return tokenId The token ID (reverts if not registered)
    function tokenOfName(string calldata name) external view returns (uint256);

    /// @notice Get the name for a token ID
    /// @param tokenId The token ID
    /// @return name The human-readable name
    function nameOf(uint256 tokenId) external view returns (string memory);

    // ─── Address Binding ──────────────────────────────────────────────

    /// @notice Get the bound address for a token
    /// @param tokenId The token ID
    /// @return The bound EVM address (zero address if unbound)
    function boundAddress(uint256 tokenId) external view returns (address);

    /// @notice Check if a token is bound (and therefore locked)
    /// @param tokenId The token ID
    /// @return True if the token is bound to an address
    function isBound(uint256 tokenId) external view returns (bool);

    /// @notice Bind the token to the caller's address
    /// @dev MUST set the bound address to msg.sender
    /// @dev MUST lock the token (prevent transfers)
    /// @dev MUST emit IdentityBound
    /// @param tokenId The token ID (caller must be owner)
    function bind(uint256 tokenId) external;

    // ─── URL Record ───────────────────────────────────────────────────

    /// @notice Get the URL record for a token
    /// @param tokenId The token ID
    /// @return The URL string (empty if not set)
    function urlRecord(uint256 tokenId) external view returns (string memory);

    /// @notice Set the URL record for a bound token
    /// @dev MUST require the token to be bound
    /// @dev MUST require caller to be token owner
    /// @dev MUST emit UrlRecordSet
    /// @param tokenId The token ID
    /// @param url The URL to set
    function setUrlRecord(uint256 tokenId, string calldata url) external;

    // ─── Identity Metadata ────────────────────────────────────────────

    /// @notice Get the tier of a token
    /// @param tokenId The token ID
    /// @return The tier classification
    function tierOf(uint256 tokenId) external view returns (Tier);

    /// @notice Get the total number of identities minted
    /// @return The count of minted tokens
    function totalMinted() external view returns (uint256);
}
