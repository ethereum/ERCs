// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDigitalAsset {
    function getAssetsTotalSupply() external view returns (uint256);
    function getAssetName(uint256 assetId) external view returns (string memory);
    function getAssetDetails(uint256 assetId) external view returns (AssetDetails memory);

    // Define the structure here as well if you wish to use it as a return type
    struct AssetDetails {
        uint256 assetId;
        string assetName;
        uint256 size;
        bytes32 fileHash;
        address provider;
        uint256 transferValue;
    }
}