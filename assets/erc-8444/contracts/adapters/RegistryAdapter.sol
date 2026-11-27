// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IARDKindAdapter} from "../interfaces/IARDKindAdapter.sol";
import {ARDKinds} from "../libraries/ARDKinds.sol";

/// @title  Registry adapter — kind `registry` (index) for ARD registry endpoints
/// @notice Anchor = (operator address, discriminator). The discriminator MUST be nonzero so that an
///         operator's registry records never collide with its own agent record (id 0); the RECOMMENDED
///         value is uint256(keccak256(bytes(endpointURL))). Controller = the operator. Never backed
///         onchain: whether an endpoint is a conformant ARD registry is a resolver-side observation.
contract RegistryAdapter is IARDKindAdapter {
    bytes32 public constant KIND = ARDKinds.REGISTRY;

    function kind() external pure override returns (bytes32) {
        return KIND;
    }

    function exists(address target, uint256 id) public pure override returns (bool) {
        return target != address(0) && id != 0;
    }

    function controllerOf(address target, uint256 id) external pure override returns (address) {
        return exists(target, id) ? target : address(0);
    }

    function backed(address, uint256) external pure override returns (bool) {
        return false;
    }

    function anchorHint(address, uint256) external pure override returns (bytes32) {
        return bytes32(0);
    }
}
