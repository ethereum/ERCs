// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import {IValidator} from "kernel/src/interfaces/IERC7579Modules.sol";

/**
 * @title INFTBoundValidator
 * @dev Interface for NFT-Bound Validator module
 * @notice Validator that authorizes actions only for the current NFAT owner
 */
interface INFTBoundValidator is IValidator {
    /// @notice Emitted when a validator is initialized for an NBA
    event ValidatorInitialized(
        address indexed account,
        address indexed nftContract,
        uint256 indexed tokenId
    );

    /// @notice Error thrown when signature validation fails
    error InvalidSignature();

    /// @notice Error thrown when the signer is not the NFAT owner
    error NotNFATOwner();

    /// @notice Error thrown when trying to uninstall the validator
    error ValidatorCannotBeUninstalled();

    /// @notice Emitted when validator implementation is upgraded
    event ValidatorUpgraded(address indexed oldImplementation, address indexed newImplementation);

    /**
     * @notice Validates that the transaction signer owns the controlling NFAT
     * @dev MUST check current NFAT ownership
     * @dev MUST support ERC-4337 validation flow
     * @dev Accepts a UserOperation or ERC‑1271 signature only when ownerOf(tokenId) == signer
     * @param userOp The user operation to validate
     * @param userOpHash The hash of the user operation
     * @return validationData ERC-4337 validation data (0 for success)
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external returns (uint256 validationData);

    /**
     * @notice Validates a signature according to ERC-1271
     * @dev MUST check that the signer owns the controlling NFAT
     * @param sender The address of the sender
     * @param hash The hash of the data to validate
     * @param signature The signature to validate
     * @return magicValue ERC-1271 magic value (0x1626ba7e) if valid, 0xffffffff if invalid
     */
    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4 magicValue);

    /**
     * @notice Returns the NFAT that controls this NBA
     * @param account The NBA address
     * @return nftContract The NFAT contract address
     * @return tokenId The controlling NFAT token ID
     */
    function getNFAT(
        address account
    ) external view returns (address nftContract, uint256 tokenId);
}
