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

    // Direct minting by provider/author - the only minting method
    function provide(
        string memory assetName,
        uint256 size,
        bytes32 fileHash,
        uint256 transferValue
    ) external returns (uint256);

    // Platform fee management
    function setPlatformFeeRatio(uint256 newRatio) external;
    function setPlatformFeeRecipient(address newRecipient) external;
    function getPlatformFeeRatio() external view returns (uint256);
    function getPlatformFeeRecipient() external view returns (address);
    function calculatePlatformFee(uint256 transferValue) external view returns (uint256);
    function getTransferCostBreakdown(uint256 assetId, address caller) 
        external view returns (uint256 providerFee, uint256 platformFee, uint256 totalCost);
}