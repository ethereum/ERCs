// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IOpmlLib.sol";
contract MockOpmlLib is IOpmlLib {
    uint256 public currentRequestId;
    mapping (uint256 => bytes) public requestIdToOutput;

    function initOpmlRequest(bytes calldata input)
        external
        override
        returns (uint256 requestId)
    {
        return currentRequestId++;
    }

    function uploadResult(uint256 requestId, bytes calldata output)
        external
        override
    {
        requestIdToOutput[requestId] = output;
    }

    function startChallenge(uint256 requestId, bytes32 finalState)
        external
        override
        returns (uint256 challengeId)
    {
        return 0;
    }

    function respondState(uint256 challengeId, bytes32 stateHash)
        external
        override
    {}

    function proposeState(uint256 challengeId, bytes32 stateHash)
        external
        override
    {}

    function assertStateTransition(uint256 challengeId) external override {}

    function isFinalized(uint256 requestId)
        external
        view
        override
        returns (bool)
    {
        return true;
    }

    function getOutput(uint256 requestId)
        external
        view
        override
        returns (bytes memory output)
    {
        return requestIdToOutput[requestId];
    }
}