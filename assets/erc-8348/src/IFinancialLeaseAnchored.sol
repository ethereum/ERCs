// SPDX-License-Identifier: CC0-1.0
// src/IFinancialLeaseAnchored.sol
pragma solidity ^0.8.24;

/// @notice Optional extension (ERC-165) that binds a lease to a titled asset
///         in an ERC-8325 registry, with no cross-registry ambiguity.
interface IFinancialLeaseAnchored {
    /// @return chainId  EIP-155 chain ID of the registry (uint256, NOT a
    ///                  CAIP-2 string like "eip155:1")
    /// @return registry address of the ERC-8325 registry
    /// @return anchorId identifier of the anchor within that registry
    function assetAnchor(uint256 leaseId) external view returns (uint256 chainId, address registry, bytes32 anchorId);
}
