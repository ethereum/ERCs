// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

interface IPresignReportAnchor {
    event ReportAnchored(
        address indexed source, bytes32 indexed subjectDigest, bytes32 indexed reportHash, string reportURI
    );

    function anchor(bytes32 subjectDigest, bytes32 reportHash, string calldata reportURI) external;
    function anchoredAt(address source, bytes32 reportHash) external view returns (uint64 timestamp, uint64 blockNumber);
}
