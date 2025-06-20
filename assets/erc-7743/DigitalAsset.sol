// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MONFT.sol";
import "./IDigitalAsset.sol";

contract DigitAsset is MultiOwnerNFT, IDigitalAsset {
    struct DigitAssetInfo {
        uint256 assetId;
        string assetName;
        uint256 size;
        bytes32 fileHash;
        address provider;
        uint256 transferValue;
    }

    mapping(uint256 => DigitAssetInfo) private _assets;
    
    // Platform fee system
    uint256 private _platformFeeRatio; // Basis points (e.g., 250 = 2.5%)
    address private _platformFeeRecipient; // Address to receive platform fees
    
    uint256 public constant MAX_PLATFORM_FEE_RATIO = 1000; // 10% maximum platform fee

    // Events
    event AssetProvided(
        uint256 indexed assetId,
        uint256 indexed size,
        address indexed provider,
        bytes32 fileHash,
        uint256 transferValue
    );
    event AssetTransferred(
        address indexed from,
        address indexed to,
        uint256 indexed assetId,
        uint256 transferValue
    );
    event TransferValueUpdated(
        uint256 indexed assetId,
        uint256 oldTransferValue,
        uint256 newTransferValue
    );
    event ProviderFreeTransfer(
        uint256 indexed assetId,
        address indexed provider,
        address indexed to
    );
    event PlatformFeeUpdated(
        uint256 oldRatio,
        uint256 newRatio
    );
    event PlatformFeeRecipientUpdated(
        address oldRecipient,
        address newRecipient
    );
    event PlatformFeePaid(
        uint256 indexed assetId,
        address indexed payer,
        uint256 feeAmount
    );

    constructor() payable MultiOwnerNFT(msg.sender) {
        // Initialize platform fee recipient to the contract owner
        _platformFeeRecipient = msg.sender;
        _platformFeeRatio = 250; // Default 2.5% platform fee
    }

    function getAssetsTotalSupply() public view override returns (uint256) {
        return totalSupply();
    }

    function getAssetName(
        uint256 assetId
    ) public view override returns (string memory) {
        require(_exists(assetId), "Asset: Asset does not exist");
        return _assets[assetId].assetName;
    }

    function getAssetDetails(
        uint256 assetId
    ) public view override returns (AssetDetails memory) {
        require(_exists(assetId), "Asset: Asset does not exist");
        DigitAssetInfo storage asset = _assets[assetId];
        return
            AssetDetails({
                assetId: asset.assetId,
                assetName: asset.assetName,
                size: asset.size,
                fileHash: asset.fileHash,
                provider: asset.provider,
                transferValue: asset.transferValue
            });
    }

    // Direct minting by provider/author - the only minting method
    function provide(
        string memory assetName,
        uint256 size,
        bytes32 fileHash,
        uint256 transferValue
    ) external returns (uint256) {
        // Provider mints directly to themselves
        uint256 assetId = mintToken();
        _assets[assetId] = DigitAssetInfo({
            assetId: assetId,
            assetName: assetName,
            size: size,
            fileHash: fileHash,
            provider: msg.sender, // Caller is the provider
            transferValue: transferValue
        });
        emit AssetProvided(assetId, size, msg.sender, fileHash, transferValue);
        return assetId;
    }

    function setTransferValue(
        uint256 assetId,
        uint256 newTransferValue
    ) external {
        require(_exists(assetId), "Asset: Asset does not exist");
        DigitAssetInfo storage asset = _assets[assetId];
        require(
            msg.sender == asset.provider,
            "Only provider can update transfer value"
        );

        uint256 oldTransferValue = asset.transferValue;
        asset.transferValue = newTransferValue;

        emit TransferValueUpdated(assetId, oldTransferValue, newTransferValue);
    }

    // Platform fee management functions (only owner)
    function setPlatformFeeRatio(uint256 newRatio) external onlyOwner {
        require(newRatio <= MAX_PLATFORM_FEE_RATIO, "Platform fee ratio too high");
        
        uint256 oldRatio = _platformFeeRatio;
        _platformFeeRatio = newRatio;
        
        emit PlatformFeeUpdated(oldRatio, newRatio);
    }

    function setPlatformFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Platform fee recipient cannot be zero address");
        
        address oldRecipient = _platformFeeRecipient;
        _platformFeeRecipient = newRecipient;
        
        emit PlatformFeeRecipientUpdated(oldRecipient, newRecipient);
    }

    function getPlatformFeeRatio() external view returns (uint256) {
        return _platformFeeRatio;
    }

    function getPlatformFeeRecipient() external view returns (address) {
        return _platformFeeRecipient;
    }

    function calculatePlatformFee(uint256 transferValue) public view returns (uint256) {
        if (_platformFeeRatio == 0) return 0;
        return (transferValue * _platformFeeRatio) / 10000; // Basis points calculation
    }

    // Check if a transfer would be free for the caller
    function isTransferFreeForCaller(
        uint256 assetId,
        address caller
    ) external view returns (bool) {
        require(_exists(assetId), "Asset: Asset does not exist");
        DigitAssetInfo storage asset = _assets[assetId];
        
        // Transfer is free if caller is the provider or transfer value is 0
        return (caller == asset.provider || asset.transferValue == 0);
    }

    // Get the required payment amount for a transfer by a specific caller
    function getTransferCost(
        uint256 assetId,
        address caller
    ) external view returns (uint256) {
        require(_exists(assetId), "Asset: Asset does not exist");
        DigitAssetInfo storage asset = _assets[assetId];
        
        // No cost if caller is the provider
        if (caller == asset.provider) {
            return 0;
        }
        
        uint256 providerFee = asset.transferValue;
        uint256 platformFee = calculatePlatformFee(providerFee);
        
        return providerFee + platformFee;
    }

    // Get detailed breakdown of transfer costs
    function getTransferCostBreakdown(
        uint256 assetId,
        address caller
    ) external view returns (uint256 providerFee, uint256 platformFee, uint256 totalCost) {
        require(_exists(assetId), "Asset: Asset does not exist");
        DigitAssetInfo storage asset = _assets[assetId];
        
        // No cost if caller is the provider
        if (caller == asset.provider) {
            return (0, 0, 0);
        }
        
        providerFee = asset.transferValue;
        platformFee = calculatePlatformFee(providerFee);
        totalCost = providerFee + platformFee;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override {
        require(
            isOwner(tokenId, msg.sender), // Ensure that `msg.sender` is an owner
            "MO-NFT: Transfer from incorrect account"
        );
        require(to != address(0), "MO-NFT: Transfer to the zero address");

        // Standard ERC721 transfer - no payment required
        _transferWithoutPayment(from, to, tokenId);
    }

    // Payable version for transfers with royalty payments
    function transferFromWithPayment(
        address from,
        address to,
        uint256 tokenId
    ) public payable {
        require(
            isOwner(tokenId, msg.sender), // Ensure that `msg.sender` is an owner
            "MO-NFT: Transfer from incorrect account"
        );
        require(to != address(0), "MO-NFT: Transfer to the zero address");

        _transferWithProviderPayment(from, to, tokenId);
    }

    // Smart transfer function that automatically chooses free or paid transfer
    function smartTransfer(
        address from,
        address to,
        uint256 tokenId
    ) public payable {
        require(
            isOwner(tokenId, msg.sender), // Ensure that `msg.sender` is an owner
            "MO-NFT: Transfer from incorrect account"
        );
        require(to != address(0), "MO-NFT: Transfer to the zero address");

        // If sender is the provider or transfer value is 0, use free transfer
        if (msg.sender == _assets[tokenId].provider || _assets[tokenId].transferValue == 0) {
            _transferWithoutPayment(from, to, tokenId);
            
            // Return any sent ETH since no payment is needed
            if (msg.value > 0) {
                payable(msg.sender).transfer(msg.value);
            }
        } else {
            // Use paid transfer for non-providers
            _transferWithProviderPayment(from, to, tokenId);
        }
    }

    function _transferWithoutPayment(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        // Call the internal transfer function in MultiOwnerNFT
        _transfer(from, to, tokenId);

        emit AssetTransferred(from, to, tokenId, 0); // No payment made
    }

    function _transferWithProviderPayment(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        DigitAssetInfo storage asset = _assets[tokenId];

        // If the sender is the provider (original author), no payment required
        if (msg.sender == asset.provider) {
            // Provider transfers their own token - no fee required
            _transfer(from, to, tokenId);
            emit AssetTransferred(from, to, tokenId, 0); // No payment made
            emit ProviderFreeTransfer(tokenId, asset.provider, to);
            
            // Return any sent ETH back to provider since no payment is needed
            if (msg.value > 0) {
                payable(msg.sender).transfer(msg.value);
            }
            return;
        }

        // For non-provider transfers, calculate all fees
        uint256 providerFee = asset.transferValue;
        uint256 platformFee = calculatePlatformFee(providerFee);
        uint256 totalRequired = providerFee + platformFee;

        require(
            msg.value >= totalRequired,
            "Insufficient payment for provider royalty and platform fee"
        );

        // Pay provider from user's sent ETH (only if transfer value > 0)
        if (providerFee > 0) {
            payable(asset.provider).transfer(providerFee);
        }

        // Pay platform fee (only if platform fee > 0)
        if (platformFee > 0) {
            payable(_platformFeeRecipient).transfer(platformFee);
            emit PlatformFeePaid(tokenId, msg.sender, platformFee);
        }

        // Return excess ETH to sender if any
        if (msg.value > totalRequired) {
            payable(msg.sender).transfer(msg.value - totalRequired);
        }

        // Call the internal transfer function in MultiOwnerNFT
        _transfer(from, to, tokenId);

        emit AssetTransferred(from, to, tokenId, providerFee);
    }

    // Allow the contract to receive ETH to fund transfers
    receive() external payable {}
}
