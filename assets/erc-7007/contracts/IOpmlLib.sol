// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IOpmlLib {
    function initOpmlRequest(bytes calldata input) external returns (uint256 requestId); // we can construct the initialState using the input, can replace input with prompt (string)
	function uploadResult(uint256 requestId, bytes calldata output) external;
	function startChallenge(uint256 requestId, bytes32 finalState) external returns (uint256 challengeId);
	function respondState(uint256 challengeId, bytes32 stateHash) external;
	function proposeState(uint256 challengeId, bytes32 stateHash) external;
	function assertStateTransition(uint256 challengeId) external;
    function isFinalized(uint256 requestId) external view returns (bool);
	function getOutput(uint256 requestId) external view returns (bytes memory output);
}