// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IIdentityAccount} from "./IIdentityAccount.sol";

/// @title IdentityAccount — Reference Implementation
/// @notice Minimal account that allows the registered owner to execute
///         arbitrary calls. Deployed as a proxy by the AccountFactory.
contract IdentityAccount is IIdentityAccount {
    address public registry;
    bytes32 public id;
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
        require(owner == msg.sender, "not owner");

        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "call failed");
        return result;
    }

    receive() external payable {}
}
