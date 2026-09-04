// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPersistentIdentityPolicy
 * @notice Policy interface for namespace governance in the Persistent Identity Protocol.
 *
 *  The policy layer is separate from the identity layer. Each namespace
 *  operator defines their own rules for:
 *    - Who can mint (open, whitelist, moderator-only)
 *    - Pricing (free, fixed, AI-driven, auction)
 *    - Reclaim/rename authority
 *    - Unbinding authority
 *    - Reserved names
 *    - Transfer restrictions per tier
 *
 *  This interface defines the governance actions that a policy controller
 *  can perform on the identity contract. Implementations MAY restrict
 *  these actions to specific roles (e.g., Owner, Moderator).
 */
interface IPersistentIdentityPolicy {

    // ─── Events ───────────────────────────────────────────────────────

    /// @notice Emitted when a name's price is set on-chain
    event NamePriceSet(string name, uint256 price);

    /// @notice Emitted when a governance rename occurs
    event GovernanceRename(uint256 indexed tokenId, string oldName, string newName, string reason);

    // ─── Governance Actions ───────────────────────────────────────────

    /// @notice Unbind an identity (governance action, unlocks for transfer)
    /// @dev MUST clear bound address, URL record, and lock status
    /// @dev MUST emit IdentityUnbound
    /// @param tokenId The token ID to unbind
    function unbind(uint256 tokenId) external;

    /// @notice Rename an identity (governance action)
    /// @dev MUST update name mappings
    /// @dev MUST emit IdentityRenamed
    /// @param tokenId The token ID to rename
    /// @param newName The new name string
    function rename(uint256 tokenId, string calldata newName) external;

    /// @notice Set the on-chain price for a name
    /// @dev MUST only be callable by authorized policy controller
    /// @param name The name to price
    /// @param priceInWei The price in native token wei
    /// @param tier The tier classification
    function setNamePrice(string calldata name, uint256 priceInWei, uint8 tier) external;

    /// @notice Purchase and mint a name at the on-chain price
    /// @dev MUST verify msg.value matches the set price
    /// @dev MUST mint the token to msg.sender (unbound)
    /// @dev MUST clear the price listing after purchase
    /// @param name The name to purchase
    /// @return tokenId The minted token ID
    function purchaseMint(string calldata name) external payable returns (uint256 tokenId);

    // ─── Policy Queries ───────────────────────────────────────────────

    /// @notice Get the on-chain price for a name
    /// @param name The name to query
    /// @return The price in wei (0 = not listed)
    function namePrice(string calldata name) external view returns (uint256);

    /// @notice Get the treasury address where purchase funds are sent
    /// @return The treasury address
    function treasury() external view returns (address);
}
