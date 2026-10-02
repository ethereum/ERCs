// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

/// @title Cross-Chain Event Archive: optional writer extension.
interface IEventArchiveWriter {
  function archiveEvent(
    uint256 sourceChainId,
    bytes32 sourceTxHash,
    address sourceAddress,
    uint256 sourceLogIndex,
    uint256 sourceBlockNumber,
    bytes calldata payload
  ) external;
}
