// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

/// @title Ownable2Step -- Two-step ownership transfer with 48-hour acceptance window
/// @dev Inheriting contracts get owner, pendingOwner, onlyOwner modifier, and transfer logic.
abstract contract Ownable2Step {
    address public owner;
    address public pendingOwner;
    uint256 internal _ownershipTransferDeadline;

    error Unauthorized();
    error NotPendingOwner();
    error ZeroAddress();
    error OwnershipTransferExpired();

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferCancelled(address indexed cancelledOwner);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    /// @notice Begin two-step ownership transfer (48 hour acceptance window)
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        if (pendingOwner != address(0)) {
            emit OwnershipTransferCancelled(pendingOwner);
        }
        pendingOwner = newOwner;
        _ownershipTransferDeadline = block.timestamp + 48 hours;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Accept ownership transfer (must be within 48 hours of initiation)
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        if (block.timestamp > _ownershipTransferDeadline) revert OwnershipTransferExpired();
        address old = owner;
        owner = msg.sender;
        pendingOwner = address(0);
        _ownershipTransferDeadline = 0;
        emit OwnershipTransferred(old, msg.sender);
    }
}
