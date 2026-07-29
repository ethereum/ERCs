// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {BlockHeader} from "@solarity/solidity-lib/libs/bitcoin/BlockHeader.sol";
import {TxMerkleProof} from "@solarity/solidity-lib/libs/bitcoin/TxMerkleProof.sol";
import {EndianConverter} from "@solarity/solidity-lib/libs/utils/EndianConverter.sol";

import {LibSort} from "solady/src/utils/LibSort.sol";

import {TargetsHelper} from "./libs/TargetsHelper.sol";

import {ISPVGateway} from "./interfaces/ISPVGateway.sol";

contract SPVGateway is ISPVGateway, Initializable {
    using BlockHeader for bytes;
    using TargetsHelper for bytes32;
    using EndianConverter for bytes32;

    uint8 public constant MEDIAN_PAST_BLOCKS = 11;

    bytes32 public constant SPV_GATEWAY_STORAGE_SLOT =
        keccak256("spv.gateway.spv.gateway.storage");

    struct SPVGatewayStorage {
        mapping(bytes32 => BlockData) blocksData;
        mapping(uint256 => bytes32) blocksHeightToBlockHash;
        bytes32 mainchainHead;
        uint256 lastEpochCumulativeWork;
    }

    modifier broadcastMainchainUpdateEvent() {
        bytes32 currentMainchain = getMainchainHead();
        _;
        bytes32 newMainchainHead = getMainchainHead();

        if (currentMainchain != newMainchainHead) {
            emit MainchainHeadUpdated(getBlockHeight(newMainchainHead), newMainchainHead);
        }
    }

    function __SPVGateway_init() external initializer {
        BlockHeader.HeaderData memory genesisBlockHeader = BlockHeader.HeaderData({
            version: 1,
            prevBlockHash: bytes32(0),
            merkleRoot: 0x4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b,
            time: 1231006505,
            bits: 0x1d00ffff,
            nonce: 2083236893
        });
        bytes32 genesisBlockHash = 0x000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f;

        _addBlock(genesisBlockHeader, genesisBlockHash, 0);

        emit MainchainHeadUpdated(0, genesisBlockHash);
    }

    function __SPVGateway_init(
        bytes calldata blockHeaderRaw,
        uint64 blockHeight,
        uint256 cumulativeWork
    ) external initializer {
        (BlockHeader.HeaderData memory blockHeader, bytes32 blockHash) = _parseBlockHeaderRaw(
            blockHeaderRaw
        );

        require(
            blockHeight == 0 || TargetsHelper.isTargetAdjustmentBlock(blockHeight),
            InvalidInitialBlockHeight(blockHeight)
        );

        _addBlock(blockHeader, blockHash, blockHeight);
        _getSPVGatewayStorage().lastEpochCumulativeWork = cumulativeWork;

        emit MainchainHeadUpdated(blockHeight, blockHash);
    }

    function _getSPVGatewayStorage() private pure returns (SPVGatewayStorage storage _spvs) {
        bytes32 slot = SPV_GATEWAY_STORAGE_SLOT;

        assembly {
            _spvs.slot := slot
        }
    }

    /// @inheritdoc ISPVGateway
    function addBlockHeaderBatch(
        bytes[] calldata blockHeaderRawArray
    ) external broadcastMainchainUpdateEvent {
        (
            BlockHeader.HeaderData[] memory blockHeaders,
            bytes32[] memory blockHashes
        ) = _parseBlockHeadersRaw(blockHeaderRawArray);

        uint64 firstBlockHeight = getBlockHeight(blockHeaders[0].prevBlockHash) + 1;
        bytes32 currentTarget = getBlockTarget(blockHeaders[0].prevBlockHash);

        for (uint64 i = 0; i < blockHeaderRawArray.length; ++i) {
            uint64 currentBlockHeight = firstBlockHeight + i;

            currentTarget = _updateLastEpochCumulativeWork(currentTarget, currentBlockHeight);

            uint32 medianTime;

            if (i < MEDIAN_PAST_BLOCKS) {
                medianTime = _getStorageMedianTime(blockHeaders[i], currentBlockHeight);
            } else {
                medianTime = _getMemoryMedianTime(blockHeaders, i);
            }

            _validateBlockRules(blockHeaders[i], blockHashes[i], currentTarget, medianTime);

            _addBlock(blockHeaders[i], blockHashes[i], currentBlockHeight);
        }
    }

    /// @inheritdoc ISPVGateway
    function addBlockHeader(
        bytes calldata blockHeaderRaw
    ) external broadcastMainchainUpdateEvent {
        (BlockHeader.HeaderData memory blockHeader, bytes32 blockHash) = _parseBlockHeaderRaw(
            blockHeaderRaw
        );

        require(
            blockExists(blockHeader.prevBlockHash),
            PrevBlockDoesNotExist(blockHeader.prevBlockHash)
        );

        uint64 blockHeight = getBlockHeight(blockHeader.prevBlockHash) + 1;
        bytes32 currentTarget = getBlockTarget(blockHeader.prevBlockHash);

        currentTarget = _updateLastEpochCumulativeWork(currentTarget, blockHeight);

        _validateBlockRules(
            blockHeader,
            blockHash,
            currentTarget,
            _getStorageMedianTime(blockHeader, blockHeight)
        );

        _addBlock(blockHeader, blockHash, blockHeight);
    }

    /// @inheritdoc ISPVGateway
    function checkTxInclusion(
        bytes32[] calldata merkleProof,
        bytes32 blockHash,
        bytes32 txId,
        uint256 txIndex,
        uint256 minConfirmationsCount
    ) external view returns (bool) {
        (bool isInMainchain, uint256 confirmationsCount) = getBlockStatus(blockHash);

        if (!isInMainchain || confirmationsCount < minConfirmationsCount) {
            return false;
        }

        bytes32 leRoot = getBlockMerkleRoot(blockHash).bytes32BEtoLE();

        return TxMerkleProof.verify(merkleProof, leRoot, txId, txIndex);
    }

    /// @inheritdoc ISPVGateway
    function getMainchainHead() public view returns (bytes32) {
        return _getSPVGatewayStorage().mainchainHead;
    }

    /// @inheritdoc ISPVGateway
    function getMainchainHeight() public view returns (uint64) {
        return getBlockHeight(_getSPVGatewayStorage().mainchainHead);
    }

    /// @inheritdoc ISPVGateway
    function getBlockInfo(bytes32 blockHash) external view returns (BlockInfo memory blockInfo) {
        if (!blockExists(blockHash)) {
            return blockInfo;
        }

        BlockData memory blockData = getBlockData(blockHash);

        blockInfo = BlockInfo({
            mainBlockData: blockData,
            isInMainchain: isInMainchain(blockHash),
            cumulativeWork: _getBlockCumulativeWork(blockData.blockHeight, blockHash)
        });
    }

    /// @inheritdoc ISPVContract
    function getBlockHeader(
        bytes32 blockHash
    ) public view returns (BlockHeader.HeaderData memory) {
        BlockData storage blockData = _getSPVContractStorage().blocksData[blockHash];

        return
            BlockHeader.HeaderData({
                version: blockData.version,
                prevBlockHash: blockData.prevBlockHash,
                merkleRoot: blockData.merkleRoot,
                time: blockData.time,
                bits: blockData.bits,
                nonce: blockData.nonce
            });
    }

    /// @inheritdoc ISPVGateway
    function getBlockStatus(bytes32 blockHash) public view returns (bool, uint64) {
        if (!isInMainchain(blockHash)) {
            return (false, 0);
        }

        return (true, getMainchainHeight() - getBlockHeight(blockHash));
    }

    /// @inheritdoc ISPVGateway
    function getBlockMerkleRoot(bytes32 blockHash) public view returns (bytes32) {
        return _getSPVContractStorage().blocksData[blockHash].merkleRoot;
    }

    /// @inheritdoc ISPVGateway
    function getBlockData(bytes32 blockHash) public view returns (BlockData memory) {
        return _getSPVGatewayStorage().blocksData[blockHash];
    }

    /// @inheritdoc ISPVGateway
    function getBlockHeight(bytes32 blockHash) public view returns (uint64) {
        return _getSPVGatewayStorage().blocksData[blockHash].blockHeight;
    }

    /// @inheritdoc ISPVGateway
    function getBlockHash(uint64 blockHeight) public view returns (bytes32) {
        return _getSPVGatewayStorage().blocksHeightToBlockHash[blockHeight];
    }

    /// @inheritdoc ISPVGateway
    function getBlockTarget(bytes32 blockHash) public view returns (bytes32) {
        return TargetsHelper.bitsToTarget(_getSPVContractStorage().blocksData[blockHash].bits);
    }

    /// @inheritdoc ISPVGateway
    function getLastEpochCumulativeWork() public view returns (uint256) {
        return _getSPVGatewayStorage().lastEpochCumulativeWork;
    }

    /// @inheritdoc ISPVGateway
    function blockExists(bytes32 blockHash) public view returns (bool) {
        return _getBlockHeaderTime(blockHash) > 0;
    }

    /// @inheritdoc ISPVGateway
    function isInMainchain(bytes32 blockHash) public view returns (bool) {
        return getBlockHash(getBlockHeight(blockHash)) == blockHash;
    }

    function _addBlock(
        BlockHeader.HeaderData memory blockHeader,
        bytes32 blockHash,
        uint64 blockHeight
    ) internal {
        SPVGatewayStorage storage $ = _getSPVGatewayStorage();

        $.blocksData[blockHash_] = BlockData({
            prevBlockHash: blockHeader.prevBlockHash,
            merkleRoot: blockHeader.merkleRoot,
            version: blockHeader.version,
            time: blockHeader.time,
            nonce: blockHeader.nonce,
            bits: blockHeader.bits,
            blockHeight: blockHeight
        });

        _updateMainchainHead(blockHeader, blockHash, blockHeight);

        emit BlockHeaderAdded(blockHeight, blockHash);
    }

    function _updateMainchainHead(
        BlockHeader.HeaderData memory blockHeader,
        bytes32 blockHash,
        uint64 blockHeight
    ) internal {
        SPVGatewayStorage storage $ = _getSPVGatewayStorage();

        bytes32 mainchainHead = $.mainchainHead;

        if (blockHeader.prevBlockHash == mainchainHead || mainchainHead == 0) {
            $.mainchainHead = blockHash;
            $.blocksHeightToBlockHash[blockHeight] = blockHash;

            return;
        }

        uint256 mainchainCumulativeWork = _getBlockCumulativeWork(
            getBlockHeight(mainchainHead),
            mainchainHead
        );
        uint256 newBlockCumulativeWork = _getBlockCumulativeWork(blockHeight, blockHash);

        if (newBlockCumulativeWork > mainchainCumulativeWork) {
            $.mainchainHead = blockHash;
            $.blocksHeightToBlockHash[blockHeight] = blockHash;

            bytes32 prevBlockHash = blockHeader.prevBlockHash;
            uint64 prevBlockHeight = blockHeight - 1;

            do {
                $.blocksHeightToBlockHash[prevBlockHeight] = prevBlockHash;

                prevBlockHash = _getSPVContractStorage().blocksData[prevBlockHash].prevBlockHash;

                unchecked {
                    --prevBlockHeight;
                }
            } while (getBlockHash(prevBlockHeight) != prevBlockHash && prevBlockHash != 0);
        }
    }

    function _updateLastEpochCumulativeWork(
        bytes32 currentTarget,
        uint64 blockHeight
    ) internal returns (bytes32) {
        SPVGatewayStorage storage $ = _getSPVGatewayStorage();

        if (TargetsHelper.isTargetAdjustmentBlock(blockHeight)) {
            $.lastEpochCumulativeWork += TargetsHelper.countEpochCumulativeWork(currentTarget);

            uint32 epochStartTime = _getBlockHeaderTime(
                getBlockHash(blockHeight - TargetsHelper.DIFFICULTY_ADJUSTMENT_INTERVAL)
            );
            uint32 epochEndTime = _getBlockHeaderTime(getBlockHash(blockHeight - 1));
            uint32 passedTime = epochEndTime - epochStartTime;

            currentTarget = TargetsHelper.countNewRoundedTarget(currentTarget, passedTime);
        }

        return currentTarget;
    }

    function _parseBlockHeadersRaw(
        bytes[] calldata blockHeaderRawArray
    )
        internal
        view
        returns (BlockHeader.HeaderData[] memory blockHeaders, bytes32[] memory blockHashes)
    {
        require(blockHeaderRawArray.length > 0, EmptyBlockHeaderArray());

        blockHeaders = new BlockHeader.HeaderData[](blockHeaderRawArray.length);
        blockHashes = new bytes32[](blockHeaderRawArray.length);

        for (uint256 i = 0; i < blockHeaderRawArray.length; ++i) {
            (blockHeaders[i], blockHashes[i]) = _parseBlockHeaderRaw(blockHeaderRawArray[i]);

            if (i == 0) {
                require(
                    blockExists(blockHeaders[i].prevBlockHash),
                    PrevBlockDoesNotExist(blockHeaders[i].prevBlockHash)
                );
            } else {
                require(
                    blockHeaders[i].prevBlockHash == blockHashes[i - 1],
                    InvalidBlockHeadersOrder()
                );
            }
        }
    }

    function _parseBlockHeaderRaw(
        bytes calldata blockHeaderRaw
    ) internal view returns (BlockHeader.HeaderData memory blockHeader, bytes32 blockHash) {
        (blockHeader, blockHash) = blockHeaderRaw.parseBlockHeader(true);

        _onlyNonExistingBlock(blockHash);
    }

    function _getStorageMedianTime(
        BlockHeader.HeaderData memory blockHeader,
        uint64 blockHeight
    ) internal view returns (uint32) {
        if (blockHeight == 1) {
            return blockHeader.time;
        }

        bytes32 toBlockHash = blockHeader.prevBlockHash;

        if (blockHeight - 1 < MEDIAN_PAST_BLOCKS) {
            return _getBlockHeaderTime(toBlockHash);
        }

        uint256[] memory blocksTime = new uint256[](MEDIAN_PAST_BLOCKS);
        bool needsSort;

        for (uint256 i = MEDIAN_PAST_BLOCKS; i > 0; --i) {
            uint32 currentTime = _getBlockHeaderTime(toBlockHash);

            blocksTime[i - 1] = currentTime;
            toBlockHash = _getSPVContractStorage().blocksData[toBlockHash].prevBlockHash;

            if (i < MEDIAN_PAST_BLOCKS && currentTime > blocksTime[i]) {
                needsSort = true;
            }
        }

        return _getMedianTime(blocksTime, needsSort);
    }

    function _getMemoryMedianTime(
        BlockHeader.HeaderData[] memory blockHeaders,
        uint64 to
    ) internal pure returns (uint32) {
        if (blockHeaders.length < MEDIAN_PAST_BLOCKS) {
            return 0;
        }

        uint256[] memory blocksTime = new uint256[](MEDIAN_PAST_BLOCKS);
        bool needsSort;

        for (uint256 i = 0; i < MEDIAN_PAST_BLOCKS; ++i) {
            uint32 currentTime = blockHeaders[to - MEDIAN_PAST_BLOCKS + i].time;

            blocksTime[i] = currentTime;

            if (i > 0 && currentTime < blocksTime[i - 1]) {
                needsSort = true;
            }
        }

        return _getMedianTime(blocksTime, needsSort);
    }

    function _getBlockCumulativeWork(
        uint64 blockHeight,
        bytes32 blockHash
    ) internal view returns (uint256) {
        uint256 currentEpochCumulativeWork_ = getBlockTarget(blockHash).countCumulativeWork(
            TargetsHelper.getEpochBlockNumber(blockHeight) + 1
        );

        return _getSPVGatewayStorage().lastEpochCumulativeWork + currentEpochCumulativeWork_;
    }

    function _getBlockHeaderTime(bytes32 blockHash) internal view returns (uint32) {
        return _getSPVContractStorage().blocksData[blockHash].time;
    }

    function _onlyNonExistingBlock(bytes32 blockHash) internal view {
        require(!blockExists(blockHash), BlockAlreadyExists(blockHash));
    }

    function _validateBlockRules(
        BlockHeader.HeaderData memory blockHeader,
        bytes32 blockHash,
        bytes32 target,
        uint32 medianTime
    ) internal pure {
        bytes32 blockTarget = TargetsHelper.bitsToTarget(blockHeader.bits);

        require(target == blockTarget, InvalidTarget(blockTarget, target));
        require(blockHash <= blockTarget, InvalidBlockHash(blockHash, blockTarget));
        require(
            blockHeader.time >= medianTime,
            InvalidBlockTime(blockHeader.time, medianTime)
        );
    }

    function _getMedianTime(
        uint256[] memory blocksTime,
        bool needsSort
    ) internal pure returns (uint32) {
        if (needsSort) {
            LibSort.insertionSort(blocksTime);
        }

        return uint32(blocksTime[MEDIAN_PAST_BLOCKS / 2]);
    }
}
