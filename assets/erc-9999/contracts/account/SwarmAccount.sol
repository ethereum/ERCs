// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import {ISwarmRegistry} from "../interfaces/ISwarmRegistry.sol";
import {ISwarmAccount} from "../interfaces/ISwarmAccount.sol";

/// @title  SwarmAccount — the minimal account a swarm acts and holds value through (reference v0.2)
/// @notice Bound to exactly one swarm of one registry instance. Anyone the registry reports as
///         authorized for the REPRESENT decision point may `execute` arbitrary calls from this
///         account: submit a fulfillment to a tender, withdraw credit, pay members, hold assets.
///         How value is allocated is the charter's rule, performed through `execute`; the account
///         itself keeps no formula. Native currency and tokens can be received; nothing leaves
///         without an authorized `execute`.
contract SwarmAccount is ISwarmAccount {
    ISwarmRegistry private immutable _registry;
    bytes32 private immutable _swarmId;

    event Executed(address indexed by, address indexed target, uint256 value, bytes data, bytes result);

    error SwarmAccount_NotRepresentative();
    error SwarmAccount_CallFailed(bytes reason);

    constructor(ISwarmRegistry registry_, bytes32 swarmId_) {
        require(address(registry_) != address(0) && swarmId_ != bytes32(0), "SwarmAccount: zero");
        _registry = registry_;
        _swarmId = swarmId_;
    }

    function swarmId() external view returns (bytes32) { return _swarmId; }
    function registry() external view returns (address) { return address(_registry); }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISwarmAccount).interfaceId || interfaceId == 0x01ffc9a7;
    }

    receive() external payable {}

    /// Acts for the swarm. Only an account the registry currently reports as authorized for
    /// REPRESENT may call; the registry's current ledger is the only source of that answer.
    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory result) {
        if (!_registry.isAuthorized(_swarmId, T.DecisionPoint.REPRESENT, msg.sender)) revert SwarmAccount_NotRepresentative();
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) revert SwarmAccount_CallFailed(result);
        emit Executed(msg.sender, target, value, data, result);
    }
}
