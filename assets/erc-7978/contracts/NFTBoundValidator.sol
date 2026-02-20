// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./interfaces/INFTBoundValidator.sol";

/**
 * @title NFTBoundValidator
 * @dev Abstract validator that checks NFT ownership for authorization
 * @notice Validates signatures and user operations based on NFAT ownership
 */
abstract contract NFTBoundValidator is INFTBoundValidator {
    using ECDSA for bytes32;

    // Mapping from account to NFAT details
    mapping(address => NFATInfo) private _nfatInfo;
    
    struct NFATInfo {
        address nftContract;
        uint256 tokenId;
        bool initialized;
    }

    /**
     * @notice Initialize validator for an account
     * @param account The account address
     * @param data abi.encode(nftContract, tokenId)
     */
    function onInstall(bytes calldata data) external override {
        (address nftContract, uint256 tokenId) = abi.decode(data, (address, uint256));
        
        _nfatInfo[msg.sender] = NFATInfo({
            nftContract: nftContract,
            tokenId: tokenId,
            initialized: true
        });
        
        emit ValidatorInitialized(msg.sender, nftContract, tokenId);
    }

    /**
     * @notice Prevent uninstallation of the validator
     */
    function onUninstall(bytes calldata) external pure override {
        revert ValidatorCannotBeUninstalled();
    }

    /**
     * @notice Check if module is initialized for account
     */
    function isInitialized(address account) external view override returns (bool) {
        return _nfatInfo[account].initialized;
    }

    /**
     * @notice Validates a user operation
     * @param userOp The user operation
     * @param userOpHash The hash of the user operation
     * @return validationData ERC-4337 validation data
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external view override returns (uint256 validationData) {
        NFATInfo memory nfatInfo = _nfatInfo[userOp.sender];
        if (!nfatInfo.initialized) return 1; // Invalid
        
        // Get current NFT owner
        address nftOwner;
        try IERC721(nfatInfo.nftContract).ownerOf(nfatInfo.tokenId) returns (address owner) {
            nftOwner = owner;
        } catch {
            return 1; // Invalid if NFT doesn't exist
        }
        
        // Validate signature against NFT owner
        address signer = _validateSignature(userOpHash, userOp.signature);
        
        return signer == nftOwner ? 0 : 1;
    }

    /**
     * @notice Validates a signature according to ERC-1271
     * @param sender The address of the sender
     * @param hash The hash of the data
     * @param signature The signature
     * @return magicValue ERC-1271 magic value
     */
    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) external view override returns (bytes4 magicValue) {
        NFATInfo memory nfatInfo = _nfatInfo[sender];
        if (!nfatInfo.initialized) return 0xffffffff;
        
        // Get current NFT owner
        address nftOwner;
        try IERC721(nfatInfo.nftContract).ownerOf(nfatInfo.tokenId) returns (address owner) {
            nftOwner = owner;
        } catch {
            return 0xffffffff;
        }
        
        // Validate signature against NFT owner
        address signer = _validateSignature(hash, signature);
        
        return signer == nftOwner ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    /**
     * @notice Returns the NFAT that controls an account
     * @param account The account address
     * @return nftContract The NFAT contract address
     * @return tokenId The controlling NFAT token ID
     */
    function getNFAT(address account) 
        external 
        view 
        override 
        returns (address nftContract, uint256 tokenId) 
    {
        NFATInfo memory nfatInfo = _nfatInfo[account];
        if (!nfatInfo.initialized) revert InvalidTokenId();
        
        return (nfatInfo.nftContract, nfatInfo.tokenId);
    }

    /**
     * @notice Validate signature - to be implemented by concrete validators
     * @param hash The hash to validate
     * @param signature The signature
     * @return signer The recovered signer address
     */
    function _validateSignature(bytes32 hash, bytes calldata signature) 
        internal 
        view 
        virtual 
        returns (address signer);

    /**
     * @notice Return module type
     */
    function isModuleType(uint256 typeID) external pure override returns (bool) {
        return typeID == 1; // MODULE_TYPE_VALIDATOR = 1 (ERC-7579)
    }
}

/**
 * @title ECDSANFTBoundValidator
 * @dev Concrete implementation using ECDSA signature validation
 */
contract ECDSANFTBoundValidator is NFTBoundValidator {
    /**
     * @notice Validate ECDSA signature
     * @param hash The hash to validate
     * @param signature The ECDSA signature
     * @return signer The recovered signer address
     */
    function _validateSignature(bytes32 hash, bytes calldata signature) 
        internal 
        pure 
        override 
        returns (address signer) 
    {
        return hash.recover(signature);
    }
}