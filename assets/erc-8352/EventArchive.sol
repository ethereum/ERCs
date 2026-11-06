// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IEventArchive} from "./interfaces/IEventArchive.sol";

/// @dev Abstract Cross-Chain Event Archive. Per eventId: version 0 = not archived, 1 = original,
/// +1 per amendment. Write path is internal and unguarded.
abstract contract EventArchive is IEventArchive {
  mapping(bytes32 recordKey => uint256 version) private _versions;

  function _recordKey(uint256 sourceChainId, bytes32 sourceTxHash, uint256 sourceLogIndex)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(abi.encode(sourceChainId, sourceTxHash, sourceLogIndex));
  }

  function _archiveEvent(
    uint256 sourceChainId,
    bytes32 sourceTxHash,
    address sourceAddress,
    uint256 sourceLogIndex,
    uint256 sourceBlockNumber,
    bytes memory payload
  ) internal virtual {
    bytes32 key = _recordKey(sourceChainId, sourceTxHash, sourceLogIndex);

    uint256 newVersion = _versions[key] + 1;
    _versions[key] = newVersion;

    emit EventArchived(
      sourceChainId, sourceTxHash, sourceAddress, sourceLogIndex, sourceBlockNumber, newVersion, payload
    );
  }

  /// @inheritdoc IEventArchive
  function isArchived(uint256 sourceChainId, bytes32 sourceTxHash, uint256 sourceLogIndex)
    public
    view
    virtual
    returns (bool)
  {
    return _versions[_recordKey(sourceChainId, sourceTxHash, sourceLogIndex)] != 0;
  }

  /// @inheritdoc IEventArchive
  function latestVersion(uint256 sourceChainId, bytes32 sourceTxHash, uint256 sourceLogIndex)
    public
    view
    virtual
    returns (uint256)
  {
    return _versions[_recordKey(sourceChainId, sourceTxHash, sourceLogIndex)];
  }
}
