// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SAITypes as T} from "../SAITypes.sol";
import {ISwarmRegistry} from "../interfaces/ISwarmRegistry.sol";
import {ISwarmAccount} from "../interfaces/ISwarmAccount.sol";

/// @title  SwarmAccount — the minimal account a swarm acts and holds value through (reference v0.3)
/// @notice Bound to exactly one swarm of one registry instance. While the swarm lives, anyone the
///         registry reports as authorized for the REPRESENT decision point may `execute` arbitrary
///         calls from this account: submit a fulfillment to a tender, withdraw credit, pay members,
///         hold assets. How value is allocated is the charter's rule, performed through `execute`;
///         the account itself keeps no formula.
///
///         Dissolution: the registry authorizes nobody in a dissolved swarm, so `execute` stops for
///         every kind of representative. What is left is reachable only through `recover`, by the
///         recovery address — set at deployment or, while the swarm lives, by a representative. A
///         zero recovery address means whatever is left stays; that is a choice the deployer makes
///         in the open, and the same choice for every kind of REPRESENT authority.
contract SwarmAccount is ISwarmAccount {
    ISwarmRegistry private immutable _registry;
    bytes32 private immutable _swarmId;
    address private _recovery;

    event Executed(address indexed by, address indexed target, uint256 value, bytes data, bytes result);
    event Recovered(address indexed by, address indexed target, uint256 value, bytes data, bytes result);
    event RecoveryAddressSet(address indexed previous, address indexed next, address by);

    error SwarmAccount_NotRepresentative();
    error SwarmAccount_NotRecovery();
    error SwarmAccount_NotDissolved();
    error SwarmAccount_Dissolved();
    error SwarmAccount_CallFailed(bytes reason);

    constructor(ISwarmRegistry registry_, bytes32 swarmId_, address recovery_) {
        require(address(registry_) != address(0) && swarmId_ != bytes32(0), "SwarmAccount: zero");
        _registry = registry_;
        _swarmId = swarmId_;
        _recovery = recovery_;
        emit RecoveryAddressSet(address(0), recovery_, msg.sender);
    }

    function swarmId() external view returns (bytes32) { return _swarmId; }
    function registry() external view returns (address) { return address(_registry); }
    function recoveryAddress() external view returns (address) { return _recovery; }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISwarmAccount).interfaceId || interfaceId == 0x01ffc9a7;
    }

    receive() external payable {}

    function _dissolved() private view returns (bool) {
        return _registry.getSwarm(_swarmId).state == T.LifecycleState.DISSOLVED;
    }

    /// Acts for the swarm. Only an account the registry currently reports as authorized for
    /// REPRESENT may call; the registry's current ledger is the only source of that answer, and it
    /// reports nobody once the swarm is dissolved.
    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory result) {
        if (!_registry.isAuthorized(_swarmId, T.DecisionPoint.REPRESENT, msg.sender)) revert SwarmAccount_NotRepresentative();
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) revert SwarmAccount_CallFailed(result);
        emit Executed(msg.sender, target, value, data, result);
    }

    /// Names who may act after dissolution. A representative may set it at any time before the
    /// swarm is dissolved; after that the rule is frozen with the swarm.
    function setRecoveryAddress(address recovery_) external {
        if (_dissolved()) revert SwarmAccount_Dissolved();
        if (!_registry.isAuthorized(_swarmId, T.DecisionPoint.REPRESENT, msg.sender)) revert SwarmAccount_NotRepresentative();
        emit RecoveryAddressSet(_recovery, recovery_, msg.sender);
        _recovery = recovery_;
    }

    /// The only path out of the account once the swarm is DISSOLVED, open to the recovery address
    /// alone, whatever kind of authority REPRESENT was.
    function recover(address target, uint256 value, bytes calldata data) external returns (bytes memory result) {
        if (!_dissolved()) revert SwarmAccount_NotDissolved();
        if (msg.sender != _recovery || _recovery == address(0)) revert SwarmAccount_NotRecovery();
        bool ok;
        (ok, result) = target.call{value: value}(data);
        if (!ok) revert SwarmAccount_CallFailed(result);
        emit Recovered(msg.sender, target, value, data, result);
    }
}
