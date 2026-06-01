// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title INFATFactory
 * @dev Interface for Non-Fungible Account Token Factory
 * @notice Factory contract that mints NFATs and deploys their associated NBA wallets
 */
interface INFATFactory is IERC721 {
    /// @notice Emitted when a new NFAT and its associated NBA are created
    event AccountCreated(
        uint256 indexed tokenId,
        address indexed wallet,
        address indexed owner
    );

    /// @notice Error thrown when invalid token ID is provided
    error InvalidTokenId();

    /// @notice Error thrown when wallet deployment fails
    error AccountDeploymentFailed();

    /// @notice Error thrown when trying to transfer NFAT to its own wallet
    error SelfTransferNotAllowed();

    /// @notice Emitted when factory implementation is upgraded
    event FactoryUpgraded(address indexed oldImplementation, address indexed newImplementation);

    /**
     * @notice Mints a new NFAT and deploys its associated NBA
     * @dev MUST deploy NBA using CREATE2 for deterministic addresses
     * @dev MUST initialize the NBA with the NFT Bound Validator
     * @dev MUST emit AccountCreated event
     * @param walletData Deployment configuration:
     *   - empty bytes: deploy embedded wallet byte‑code with custom logic
     *   - abi.encode(walletFactory, initCalldata, extraSalt): delegate creation to walletFactory
     * @return tokenId The ID of the minted NFAT
     * @return wallet The address of the deployed NBA
     */
    function mint(bytes calldata walletData)
        external
        payable
        returns (uint256 tokenId, address wallet);

    /**
     * @notice Computes the NBA address for a given token ID
     * @dev MUST return the same address whether deployed or not
     * @param tokenId The NFAT token ID
     * @return The deterministic NBA address
     */
    function getAccountAddress(uint256 tokenId) external view returns (address);

    /**
     * @notice Returns the NFAT token ID associated with an NBA address
     * @param wallet The NBA address
     * @return The associated NFAT token ID (or revert if not found)
     */
    function getTokenId(address wallet) external view returns (uint256);

    /**
     * @notice Returns whether an NBA has been deployed for a token ID
     * @param tokenId The NFAT token ID
     * @return True if the NBA is deployed
     */
    function isAccountDeployed(uint256 tokenId) external view returns (bool);
}