// SPDX-License-Identifier: CC0-1.0
// src/IFinancialLeaseAnchored.sol
pragma solidity ^0.8.24;

/// @notice Extensión opcional (ERC-165) que vincula un lease a un activo
///         titulado en un registro ERC-8325, sin ambigüedad cross-registry.
interface IFinancialLeaseAnchored {
    /// @return chainId  EIP-155 chain ID of the registry (uint256, NOT a
    ///                  CAIP-2 string like "eip155:1")
    /// @return registry dirección del registro ERC-8325
    /// @return anchorId identificador del ancla dentro de ese registro
    function assetAnchor(uint256 leaseId) external view returns (uint256 chainId, address registry, bytes32 anchorId);
}
