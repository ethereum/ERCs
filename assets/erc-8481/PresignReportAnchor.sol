// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IPresignReportAnchor} from "./IPresignReportAnchor.sol";

/// Records first publication per caller/report. It does not verify report contents,
/// signatures, source identity, or canonicality; those remain consumer checks.
/// Deploy this variant only where block.number is the chain's own block number.
contract PresignReportAnchor is IPresignReportAnchor {
    error ZeroHash();
    error URITooLong();
    error ClockOverflow();

    struct FirstAnchor {
        uint64 timestamp;
        uint64 blockNumber;
        bool exists;
    }

    mapping(address => mapping(bytes32 => FirstAnchor)) private first;

    function anchor(bytes32 subjectDigest, bytes32 reportHash, string calldata reportURI) external {
        if (subjectDigest == bytes32(0) || reportHash == bytes32(0)) revert ZeroHash();
        if (bytes(reportURI).length > 512) revert URITooLong();
        FirstAnchor storage record = first[msg.sender][reportHash];
        if (!record.exists) {
            uint256 localBlock = _localBlockNumber();
            if (block.timestamp > type(uint64).max || localBlock > type(uint64).max) revert ClockOverflow();
            record.timestamp = uint64(block.timestamp);
            record.blockNumber = uint64(localBlock);
            record.exists = true;
        }
        emit ReportAnchored(msg.sender, subjectDigest, reportHash, reportURI);
    }

    function anchoredAt(address source, bytes32 reportHash)
        external
        view
        returns (uint64 timestamp, uint64 blockNumber)
    {
        FirstAnchor storage record = first[source][reportHash];
        return (record.timestamp, record.blockNumber);
    }

    function _localBlockNumber() internal view virtual returns (uint256) {
        return block.number;
    }
}

interface IArbSysBlockNumber {
    function arbBlockNumber() external view returns (uint256);
}

/// Use on Arbitrum chains, where block.number approximates an L1 block number.
/// No fallback: an unavailable ArbSys must not silently record the wrong clock.
contract ArbitrumPresignReportAnchor is PresignReportAnchor {
    function _localBlockNumber() internal view override returns (uint256) {
        return IArbSysBlockNumber(address(100)).arbBlockNumber();
    }
}
