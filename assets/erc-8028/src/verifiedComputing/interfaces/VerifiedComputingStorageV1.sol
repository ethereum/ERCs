// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.13;

import "./IVerifiedComputing.sol";

/**
 * @title Storage for VerifiedComputing
 * @notice For future upgrades, do not change VerifiedComputingV1. Create a new
 * contract which implements VerifiedComputingV1
 */
abstract contract VerifiedComputingStorageV1 is IVerifiedComputing {
    uint256 public override jobsCount;
    mapping(uint256 jobId => Job job) internal _jobs;

    EnumerableSet.AddressSet internal _nodeList;
    EnumerableSet.AddressSet internal _activeNodeList;
    mapping(address nodeAddress => Node node) internal _nodes;

    uint256 public override nodeFee;

    mapping(uint256 fileId => EnumerableSet.UintSet jobId) internal _fileJobsIds;
}
