// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IVerifiedComputing {
    enum NodeStatus {
        None,
        Active,
        Removed
    }

    enum JobStatus {
        None,
        Submitted,
        Completed,
        Canceled
    }

    struct Job {
        uint256 fileId;
        uint256 bidAmount;
        JobStatus status;
        uint256 addedTimestamp;
        address ownerAddress;
        address nodeAddress;
    }

    struct Node {
        NodeStatus status;
        string url;
        uint256 amount;
        uint256 withdrawnAmount;
        EnumerableSet.UintSet jobIdsList;
        string publicKey;
    }

    struct NodeInfo {
        address nodeAddress;
        string url;
        NodeStatus status;
        uint256 amount;
        uint256 jobsCount;
        string publicKey;
    }

    function version() external pure returns (uint256);

    function pause() external;
    function unpause() external;

    // Fee operations

    function nodeFee() external view returns (uint256);
    function updateNodeFee(uint256 newNodeFee) external;

    // Node operations

    function nodeList() external view returns (address[] memory);
    function nodeListAt(uint256 index) external view returns (NodeInfo memory);
    function nodesCount() external view returns (uint256);

    function activeNodesCount() external view returns (uint256);
    function activeNodeList() external view returns (address[] memory);
    function activeNodeListAt(uint256 index) external view returns (NodeInfo memory);

    function getNode(address nodeAddress) external view returns (NodeInfo memory);
    function addNode(address nodeAddress, string memory url, string memory publicKey) external;
    function removeNode(address nodeAddress) external;
    function isNode(address nodeAddress) external view returns (bool);

    // Proof operations

    function requestProof(uint256 fileId) external payable;

    function submitJob(uint256 fileId) external payable;
    function completeJob(uint256 jobId) external;
    function fileJobIds(uint256 fileId) external view returns (uint256[] memory);
    function jobsCount() external view returns (uint256);
    function getJob(uint256 jobId) external view returns (Job memory);

    function claim() external;
}
