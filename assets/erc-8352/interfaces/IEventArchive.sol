// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title Cross-Chain Event Archive: mandatory core.
interface IEventArchive {
  event EventArchived(
    uint256 indexed sourceChainId,
    bytes32 indexed sourceTxHash,
    address indexed sourceAddress,
    uint256 sourceLogIndex,
    uint256 sourceBlockNumber,
    uint256 version,
    bytes payload
  );

  function isArchived(uint256 sourceChainId, bytes32 sourceTxHash, uint256 sourceLogIndex) external view returns (bool);

  function latestVersion(uint256 sourceChainId, bytes32 sourceTxHash, uint256 sourceLogIndex)
    external
    view
    returns (uint256);
}
