// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.4;

/**
    @title Soulbound, Multi-Token standard.
    @notice Interface of the EIP-5516
    Note: The ERC-165 identifier for this interface is 0x45b253ba.
 */

interface IERC5516 {
    /**
     * @dev Emitted when `issuer` creates a new soulbound token and distributes it to `recipients[]`.
     *
     * @param tokenId The unique identifier of the newly created token.
     * @param issuer The address of the entity that issued the credential.
     * @param recipients Array of addresses that received the soulbound token.
     * @param metadataURI URI pointing to the token metadata (e.g., IPFS hash).
     */
    event Issued(
        uint256 indexed tokenId,
        address indexed issuer,
        address[] recipients,
        string metadataURI
    );

    /**
     * @dev Emitted when `who` voluntarily renounces their soulbound token under `tokenId`.
     *
     * @param tokenId The unique identifier of the renounced token.
     * @param who The address that renounced ownership of the token.
     */
    event Renounced(uint256 indexed tokenId, address indexed who);

    /**
     * @dev Issues a new soulbound token to multiple recipients.
     *
     * Creates a unique token identifier and distributes it to all addresses in `recipients[]`.
     * The token is non-transferable after issuance.
     *
     * Requirements:
     * - `recipients[]` MUST NOT be empty.
     * - All addresses in `recipients[]` MUST be non-zero.
     * - All addresses in `recipients[]` MUST NOT already own a token under the generated `tokenId`.
     * - Caller MUST be an authorized issuer.
     *
     * Emits an {Issued} event.
     *
     * @param recipients Array of addresses that will receive the soulbound token.
     * @param metadataURI URI pointing to the token metadata (IPFS, Arweave, HTTP, etc.).
     * @return tokenId The unique identifier of the newly created token.
     */
    function issue(
        address[] memory recipients,
        string calldata metadataURI
    ) external returns (uint256 tokenId);

    /**
     * @dev Allows the token holder to voluntarily renounce their soulbound token.
     *
     * Once renounced, the holder no longer owns the token and cannot reclaim it.
     * This action is irreversible.
     *
     * Requirements:
     * - Caller MUST own the token under `tokenId`.
     * - `tokenId` MUST exist.
     *
     * Emits a {Renounced} event.
     *
     * @param tokenId The unique identifier of the token to renounce.
     */
    function renounce(uint256 tokenId) external;

    /**
     * @dev Checks if a given address owns a specific soulbound token.
     *
     * @param who The address to check ownership for.
     * @param tokenId The unique identifier of the token.
     * @return True if `who` owns the token under `tokenId`, false otherwise.
     */
    function has(address who, uint256 tokenId) external view returns (bool);

    /**
     * @dev Returns the URI for a given token ID.
     *
     * The URI typically points to a JSON file containing token metadata.
     * This may be an IPFS hash, Arweave transaction ID, or HTTP URL.
     *
     * Requirements:
     * - `tokenId` MUST exist.
     *
     * @param tokenId The unique identifier of the token.
     * @return The complete URI string for the token metadata.
     */
    function uri(uint256 tokenId) external view returns (string memory);
}
