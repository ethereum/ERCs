// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "../INFATFactory.sol";
import "../INFTBoundValidator.sol";

// Interface for ERC-7579 module management
interface IModuleManager {
    function listModules(uint256 moduleTypeId) external view returns (address[] memory);
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata data) external;
}

/**
 * @title NFATFactory
 * @dev Abstract factory that delegates to ERC-7579 account factories
 * @notice Mints NFATs and initializes wallets with NFT-bound validators
 */
abstract contract NFATFactory is ERC721, INFATFactory {
    uint256 private _currentTokenId;
    
    // Core components
    address public immutable nftBoundValidator;
    
    // Mappings
    mapping(uint256 => address) private _tokenToWallet;
    mapping(address => uint256) private _walletToToken;
    mapping(uint256 => bool) private _isDeployed;

    constructor(
        string memory name, 
        string memory symbol,
        address _validator
    ) ERC721(name, symbol) {
        nftBoundValidator = _validator;
        _currentTokenId = 1;
    }

    /**
     * @notice Mints a new NFAT and deploys its associated NBA
     * @param walletData abi.encode(walletFactory, initCalldata, extraSalt)
     * @return tokenId The ID of the minted NFAT
     * @return wallet The address of the deployed NBA
     */
    function mint(bytes calldata walletData)
        external
        payable
        override
        returns (uint256 tokenId, address wallet)
    {
        tokenId = _currentTokenId++;
        
        // Deploy wallet using external factory
        wallet = _deployWallet(tokenId, walletData);
        
        // Initialize with NFT-bound validator
        _initializeValidator(wallet, tokenId);
        
        // Store mappings
        _tokenToWallet[tokenId] = wallet;
        _walletToToken[wallet] = tokenId;
        _isDeployed[tokenId] = true;
        
        // Mint NFT
        _mint(msg.sender, tokenId);
        
        // Forward startup gas
        if (msg.value > 0) {
            payable(wallet).transfer(msg.value);
        }
        
        emit AccountCreated(tokenId, wallet, msg.sender);
        return (tokenId, wallet);
    }

    /**
     * @notice Computes the NBA address for a given token ID
     * @dev Must be implemented by concrete factories
     * @dev MUST use salt formula: keccak256(abi.encode(address(this), tokenId, block.chainid, extraSalt))
     */
    function getAccountAddress(uint256 tokenId) 
        public 
        view 
        virtual 
        override 
        returns (address);

    /**
     * @notice Returns the NFAT token ID associated with an NBA address
     */
    function getTokenId(address wallet) external view override returns (uint256) {
        uint256 tokenId = _walletToToken[wallet];
        if (tokenId == 0) revert InvalidTokenId();
        return tokenId;
    }

    /**
     * @notice Returns whether an NBA has been deployed for a token ID
     */
    function isAccountDeployed(uint256 tokenId) external view override returns (bool) {
        return _isDeployed[tokenId];
    }

    /**
     * @notice Returns token URI with embedded wallet address
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);
        
        address wallet = _tokenToWallet[tokenId];
        
        return string(abi.encodePacked(
            '{"name":"NFAT #', _toString(tokenId), '",',
            '"description":"Non-Fungible Account Token",',
            '"attributes":[{"trait_type":"Account Address","value":"', _toHexString(wallet), '"}]}'
        ));
    }

    /**
     * @notice Override transfer to implement self-transfer lock and module reset
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override {
        // Prevent self-transfer
        if (to == _tokenToWallet[tokenId]) {
            revert SelfTransferNotAllowed();
        }
        
        // Reset modules on ownership change (except mint)
        if (from != address(0) && to != address(0)) {
            _resetModules(_tokenToWallet[tokenId]);
        }
        
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @notice Deploy wallet using external ERC-7579 factory
     * @dev Must be implemented by concrete factories
     */
    function _deployWallet(uint256 tokenId, bytes calldata walletData) 
        internal 
        virtual 
        returns (address wallet);

    /**
     * @notice Initialize wallet with NFT-bound validator
     * @dev Must be implemented by concrete factories
     */
    function _initializeValidator(address wallet, uint256 tokenId) 
        internal 
        virtual;

    /**
     * @notice Reset all modules except the NFT-bound validator
     * @dev Should uninstall all modules except the immutable validator
     */
    function _resetModules(address wallet) internal virtual {
        try IModuleManager(wallet).listModules(1) returns (address[] memory validators) {
            for (uint256 i = 0; i < validators.length; i++) {
                if (validators[i] != nftBoundValidator) {
                    try IModuleManager(wallet).uninstallModule(1, validators[i], "") {
                        // Module uninstalled successfully
                    } catch {
                        // Skip modules that cannot be uninstalled
                    }
                }
            }
        } catch {
            // Wallet doesn't support module enumeration
        }
        
        // Also reset other module types (executors, hooks, fallbacks)
        for (uint256 moduleType = 2; moduleType <= 4; moduleType++) {
            try IModuleManager(wallet).listModules(moduleType) returns (address[] memory modules) {
                for (uint256 i = 0; i < modules.length; i++) {
                    try IModuleManager(wallet).uninstallModule(moduleType, modules[i], "") {
                        // Module uninstalled successfully
                    } catch {
                        // Skip modules that cannot be uninstalled
                    }
                }
            } catch {
                // Module type not supported or enumeration failed
            }
        }
    }

    /**
     * @notice Check interface support
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(INFATFactory).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // Helper functions
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }

    function _toHexString(address addr) internal pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        
        for (uint256 i = 0; i < 20; i++) {
            uint256 value = uint256(uint160(addr)) >> (8 * (19 - i));
            buffer[2 + i * 2] = _toHexChar(uint8(value >> 4));
            buffer[3 + i * 2] = _toHexChar(uint8(value & 0x0f));
        }
        
        return string(buffer);
    }

    function _toHexChar(uint8 value) internal pure returns (bytes1) {
        return value < 10 ? bytes1(uint8(48 + value)) : bytes1(uint8(87 + value));
    }
}