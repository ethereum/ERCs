// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITransferOracle} from "../interfaces/ITransferOracle.sol";

contract MockTransferOracle is ITransferOracle {
    // --- Configurable State for canTransfer ---
    bool private _canTransferShouldRevert;
    string private _canTransferRevertMessage;
    bytes32 private _canTransferReturnProofId;
    bool private _canTransferCalled;
    address private _lastCalledToken;
    address private _lastCalledFrom;
    address private _lastCalledTo;
    uint256 private _lastCalledAmount;
    uint256 private _canTransferCallCount;

    // --- Event ---
    event CanTransferCalled(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    event ApproveTransferCalled(
        TransferApproval approval,
        bytes proof,
        bytes publicInputs
    );

    // --- Constructor ---
    constructor() {
        _canTransferReturnProofId = bytes32("defaultMockProofId");
    }

    // --- ITransferOracle Implementation ---

    function approveTransfer(
        TransferApproval calldata approval,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external override returns (bytes32 proofId) {
        // Basic mock: just emit event, can be extended if needed
        emit ApproveTransferCalled(approval, proof, publicInputs);
        return keccak256(abi.encodePacked(approval.sender, approval.recipient, approval.minAmt, block.timestamp)); // Dummy proofId
    }

    function canTransfer(
        address token,
        address from,
        address to,
        uint256 amount
    ) external override returns (bytes32 proofId) {
        _canTransferCalled = true;
        _canTransferCallCount++;
        _lastCalledToken = token;
        _lastCalledFrom = from;
        _lastCalledTo = to;
        _lastCalledAmount = amount;

        emit CanTransferCalled(token, from, to, amount);

        if (_canTransferShouldRevert) {
            revert(_canTransferRevertMessage);
        }
        return _canTransferReturnProofId;
    }

    // --- Mock Configuration Functions ---

    function setCanTransferResponse(bytes32 proofIdToReturn) external {
        _canTransferShouldRevert = false;
        _canTransferReturnProofId = proofIdToReturn;
    }

    function setCanTransferRevert(string calldata revertMessage) external {
        _canTransferShouldRevert = true;
        _canTransferRevertMessage = revertMessage;
    }

    function resetCanTransferState() external {
        _canTransferCalled = false;
        _canTransferCallCount = 0;
        _lastCalledToken = address(0);
        _lastCalledFrom = address(0);
        _lastCalledTo = address(0);
        _lastCalledAmount = 0;
        _canTransferShouldRevert = false;
        _canTransferReturnProofId = bytes32("defaultMockProofId");
    }

    // --- View Functions for Assertions ---

    function getCanTransferCalled() external view returns (bool) {
        return _canTransferCalled;
    }
    
    function getCanTransferCallCount() external view returns (uint256) {
        return _canTransferCallCount;
    }

    function getLastCanTransferParams() external view returns (address token, address from, address to, uint256 amount) {
        return (_lastCalledToken, _lastCalledFrom, _lastCalledTo, _lastCalledAmount);
    }
} 