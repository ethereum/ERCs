// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {RegistrationBoundary as RB} from "./RegistrationBoundary.sol";

/// @notice Collects logs with (block, tx, log) coordinates, as a coordinator's indexer
///         would receive them from eth_getLogs. Forge does not expose transaction and
///         log indices for logs recorded inside a test, so the coordinates are assigned
///         here: one `_nextTx` per transaction, logs numbered across the block
abstract contract BoundaryRecorder is Test {
    bytes[] internal _enc;
    uint64 internal _blk;
    uint32 internal _tx;
    uint32 internal _li;

    function _beginBlock(uint64 b) internal {
        _blk = b;
        _tx = 0;
        _li = 0;
    }

    function _nextTx() internal {
        _tx++;
    }

    function _push(address emitter, bytes32[] memory topics, bytes memory data) internal {
        _enc.push(abi.encode(RB.Log(emitter, topics, data, _blk, _tx, _li++)));
    }

    /// Appends every log recorded since the last call, in emission order
    function _pushRecorded() internal {
        Vm.Log[] memory ls = vm.getRecordedLogs();
        for (uint256 i = 0; i < ls.length; i++) {
            _push(ls[i].emitter, ls[i].topics, ls[i].data);
        }
    }

    function _history(uint64 fromBlock, uint64 toBlock) internal view returns (RB.History memory h) {
        uint256 n;
        for (uint256 i = 0; i < _enc.length; i++) {
            RB.Log memory l = abi.decode(_enc[i], (RB.Log));
            if (l.blockNumber >= fromBlock && l.blockNumber <= toBlock) n++;
        }
        h.fromBlock = fromBlock;
        h.toBlock = toBlock;
        h.logs = new RB.Log[](n);
        n = 0;
        for (uint256 i = 0; i < _enc.length; i++) {
            RB.Log memory l = abi.decode(_enc[i], (RB.Log));
            if (l.blockNumber >= fromBlock && l.blockNumber <= toBlock) h.logs[n++] = l;
        }
    }

    function _proof(bytes32 parent, string memory label) internal pure returns (RB.NameProof memory) {
        return RB.NameProof(true, parent, label);
    }

    function _node(bytes32 parent, string memory label) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(parent, keccak256(bytes(label))));
    }
}
