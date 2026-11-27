// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IRegistryAnchor} from "./interfaces/IRegistryAnchor.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title RegistryAnchor
/// @notice Reference implementation of the ERC-8320 asset side. An asset inherits this to approve the
///         registries that hold claims about it. Registry approval is gated to the owner.
contract RegistryAnchor is IRegistryAnchor, ERC165, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Set of registries this asset currently approves.
    EnumerableSet.AddressSet private _approvedRegistries;

    constructor(address owner_) Ownable(owner_) {}

    /// @inheritdoc IRegistryAnchor
    function setRegistry(address registry, bool approved) external onlyOwner {
        if (approved) {
            _approvedRegistries.add(registry);
        } else {
            _approvedRegistries.remove(registry);
        }
        emit RegistrySet(registry, address(this), approved);
    }

    /// @inheritdoc IRegistryAnchor
    function getRegistries() external view returns (address[] memory) {
        return _approvedRegistries.values();
    }

    /// @inheritdoc IRegistryAnchor
    function isRegistryApproved(address registry) external view returns (bool) {
        return _approvedRegistries.contains(registry);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IRegistryAnchor).interfaceId || super.supportsInterface(interfaceId);
    }
}
