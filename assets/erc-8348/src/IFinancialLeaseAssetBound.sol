// SPDX-License-Identifier: CC0-1.0
// src/IFinancialLeaseAssetBound.sol
pragma solidity ^0.8.24;

/// @notice Optional extension (ERC-165) for leases where the leased asset
///         itself is tokenized and held in escrow by the lease contract.
///         Contracts implementing this extension MUST hold the bound asset
///         in escrow while status is Active, InArrears or InDefault.
interface IFinancialLeaseAssetBound {
    enum AssetStandard {
        ERC721,
        ERC1155,
        ERC20
    }

    function boundAsset(uint256 leaseId)
        external
        view
        returns (address token, uint256 tokenId, uint256 amount, AssetStandard std);
    function canSettleAsset(uint256 leaseId, address to) external view returns (bool);

    event AssetEscrowed(uint256 indexed leaseId, address token, uint256 tokenId);
    event AssetSettled(uint256 indexed leaseId, address indexed to);
    event AssetReleased(uint256 indexed leaseId, address indexed to);
}
