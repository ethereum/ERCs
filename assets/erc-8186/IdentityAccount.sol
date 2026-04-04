// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IIdentityAccount} from "./IIdentityAccount.sol";
import {IReclaimableIdentityAccount} from "./IReclaimableIdentityAccount.sol";

/// @title IdentityAccount — Reference Implementation
/// @notice Minimal account: registered owner may `execute` arbitrary calls.
///         Includes optional reclaim support through IReclaimableIdentityAccount:
///         while unclaimed (before first claim or after revocation), a
///         configured `reclaimTo` may `execute` after `reclaimableAfter`.
///         Deployed as a proxy by the AccountFactory.
contract IdentityAccount is IIdentityAccount, IReclaimableIdentityAccount {
    address public registry;
    bytes32 public id;
    address public reclaimTo;
    uint256 public reclaimableAfter;
    bool private _initialized;

    function initialize(address registry_, bytes32 id_) external {
        require(!_initialized, "already initialized");
        _initialized = true;
        registry = registry_;
        id = id_;
    }

    function execute(address target, bytes calldata data, uint256 value)
        external
        returns (bytes memory)
    {
        (bool ok, bytes memory ownerData) = registry.staticcall(
            abi.encodeWithSignature("ownerOf(bytes32)", id)
        );
        require(ok, "registry call failed");
        address owner = abi.decode(ownerData, (address));

        bool asOwner = (owner == msg.sender);
        bool asReclaim = (
            owner == address(0) &&
            reclaimTo != address(0) &&
            msg.sender == reclaimTo &&
            block.timestamp > reclaimableAfter
        );
        require(asOwner || asReclaim, "not authorized");

        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "call failed");
        return result;
    }

    /// @notice Set (or update) the reclaim address and deadline.
    /// @dev    Not part of IIdentityAccount — this is an implementation extension.
    ///         First caller sets it. After that, only reclaimTo can update.
    ///         Only callable while the identity is unclaimed.
    function setReclaim(address reclaimTo_, uint256 reclaimableAfter_) external {
        require(
            reclaimTo == address(0) || msg.sender == reclaimTo,
            "not authorized"
        );

        (bool ok, bytes memory ownerData) = registry.staticcall(
            abi.encodeWithSignature("ownerOf(bytes32)", id)
        );
        require(ok, "registry call failed");
        address owner = abi.decode(ownerData, (address));
        require(owner == address(0), "already claimed");
        require(reclaimableAfter_ > block.timestamp, "deadline in past");

        reclaimTo = reclaimTo_;
        reclaimableAfter = reclaimableAfter_;

        emit ReclaimSet(id, reclaimTo_, reclaimableAfter_);
    }

    receive() external payable {}
}
