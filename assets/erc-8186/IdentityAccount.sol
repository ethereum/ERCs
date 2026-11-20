// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IIdentityAccount} from "./IIdentityAccount.sol";
import {IReclaimableIdentityAccount} from "./IReclaimableIdentityAccount.sol";

/// @title IdentityAccount — Reference Implementation
/// @notice Minimal account: registered owner may `execute` arbitrary calls.
///         Supports factory-bound reclaim: while unclaimed and past
///         `reclaimableAfter`, the factory-configured `reclaimTo` may
///         `execute`. Deployed as a proxy by the AccountFactory, which
///         fixes the reclaim configuration at deployment.
contract IdentityAccount is IIdentityAccount, IReclaimableIdentityAccount {
    address public registry;
    bytes32 public id;
    address public reclaimTo;
    uint256 public reclaimableAfter;
    bool private _initialized;

    function initialize(
        address registry_,
        bytes32 id_,
        address reclaimTo_,
        uint256 reclaimableAfter_
    ) external {
        require(!_initialized, "already initialized");
        _initialized = true;
        registry = registry_;
        id = id_;
        reclaimTo = reclaimTo_;
        reclaimableAfter = reclaimableAfter_;
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

    /// @notice ERC-165 introspection.
    /// @dev    Covers IIdentityAccount, the reclaim extension, ERC-165
    ///         itself, and the ERC-721 / ERC-1155 token receiver interfaces.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IIdentityAccount).interfaceId ||
            interfaceId == type(IReclaimableIdentityAccount).interfaceId ||
            interfaceId == 0x01ffc9a7 || // ERC-165
            interfaceId == 0x150b7a02 || // ERC-721 TokenReceiver
            interfaceId == 0x4e2312e0;   // ERC-1155 TokenReceiver
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }
}
