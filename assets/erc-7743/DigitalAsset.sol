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

    constructor() payable MultiOwnerNFT(msg.sender) {}

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

    function provide(
        string memory assetName,
        uint256 size,
        bytes32 fileHash,
        address provider,
        uint256 transferValue,
        address mintTo
    ) external returns (uint256) {
        uint256 assetId = mintTokenTo(mintTo);
        _assets[assetId] = DigitAssetInfo({
            assetId: assetId,
            assetName: assetName,
            size: size,
            fileHash: fileHash,
            provider: provider,
            transferValue: transferValue
        });
        emit AssetProvided(assetId, size, provider, fileHash, transferValue);
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
        
        return asset.transferValue;
    }

    function _transferWithoutPayment(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        // Call the internal transfer function in MultiOwnerNFT
        _transfer(from, to, tokenId);

        DigitAssetInfo storage asset = _assets[tokenId];
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

        // For non-provider transfers, require payment
        require(
            msg.value >= asset.transferValue,
            "Insufficient payment for provider royalty"
        );

        // Pay provider from user's sent ETH (only if transfer value > 0)
        if (asset.transferValue > 0) {
            payable(asset.provider).transfer(asset.transferValue);
        }

        // Return excess ETH to sender if any
        if (msg.value > asset.transferValue) {
            payable(msg.sender).transfer(msg.value - asset.transferValue);
        }

        // Call the internal transfer function in MultiOwnerNFT
        _transfer(from, to, tokenId);

        emit AssetTransferred(from, to, tokenId, asset.transferValue);
    }

    // Allow the contract to receive ETH to fund transfers
    receive() external payable {}
}
