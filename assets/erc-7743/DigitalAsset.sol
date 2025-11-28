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
        uint256 transferValue
    ) external returns (uint256) {
        uint256 assetId = mintToken();
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

        _transferWithProviderPayment(from, to, tokenId);
    }

    function _transferWithProviderPayment(
        address from,
        address to,
        uint256 tokenId
    ) internal {
        DigitAssetInfo storage asset = _assets[tokenId];

        // Pay the provider the transferValue for this asset
        require(
            address(this).balance >= asset.transferValue,
            "Insufficient contract balance for provider payment"
        );
        payable(asset.provider).transfer(asset.transferValue);

        // Call the internal transfer function in MultiOwnerNFT
        _transfer(from, to, tokenId);

        emit AssetTransferred(from, to, tokenId, asset.transferValue);
    }

    // Allow the contract to receive ETH to fund transfers
    receive() external payable {}
}
