// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAccountFactory} from "./IAccountFactory.sol";
import {IdentityAccount} from "./IdentityAccount.sol";

/// @title AccountFactory — Reference Implementation
/// @notice Deploys one minimal proxy per identifier at a deterministic address.
///         Uses a simple CREATE2 clone pattern. Production implementations may
///         use BeaconProxy for upgradeability.
///         The reclaim policy is fixed at factory deployment: every account
///         this factory deploys is configured with the same `reclaimTo` and
///         a deadline of deployment time + `reclaimDelay`, regardless of who
///         calls `deployAccount`. Set `reclaimTo_` to address(0) to disable
///         reclaim for all accounts.
contract AccountFactory is IAccountFactory {
    address public immutable registry;
    address public immutable implementation;
    address public immutable reclaimTo;
    uint256 public immutable reclaimDelay;

    constructor(address registry_, address reclaimTo_, uint256 reclaimDelay_) {
        registry = registry_;
        reclaimTo = reclaimTo_;
        reclaimDelay = reclaimDelay_;
        implementation = address(new IdentityAccount());
    }

    function predictAddress(bytes32 id) public view returns (address) {
        bytes32 initCodeHash = keccak256(_creationCode(id));
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), id, initCodeHash
        )))));
    }

    function deployAccount(bytes32 id) public returns (address account) {
        account = predictAddress(id);
        if (account.code.length > 0) return account; // idempotent
        bytes memory code = _creationCode(id);
        assembly {
            account := create2(0, add(code, 0x20), mload(code), id)
        }
        require(account != address(0), "deploy failed");

        uint256 reclaimableAfter =
            reclaimTo == address(0) ? 0 : block.timestamp + reclaimDelay;
        IdentityAccount(payable(account)).initialize(registry, id, reclaimTo, reclaimableAfter);

        emit AccountDeployed(id, account);
    }

    /// @dev Minimal clone creation code (EIP-1167).
    function _creationCode(bytes32) private view returns (bytes memory) {
        address impl = implementation;
        return abi.encodePacked(
            hex"3d602d80600a3d3981f3363d3d373d3d3d363d73",
            impl,
            hex"5af43d82803e903d91602b57fd5bf3"
        );
    }
}
