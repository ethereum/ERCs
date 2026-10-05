// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {SpendGrant} from "./SpendGrantTypes.sol";
import {SpendGrantHash} from "./SpendGrantHash.sol";
import {SpendGrantExecutor} from "./SpendGrantExecutor.sol";

/// @notice Caveat enforcer for an ERC-7710 delegation manager. It records, for one transaction, who
/// redeemed a delegation whose execution is a `spend` on one executor, so that executor can pass the
/// redeemer to `consume` as `authorizer`.
///
/// @dev Why a record: on a redemption the delegate calls the manager, the manager validates the chain
/// and calls the hooks of every caveat with the redeemer, and the root delegator's account then
/// performs the execution. The executor is called by that account, not by the manager and not by the
/// redeemer, and the manager keeps no redeemer anyone can read back. A caveat hook is the only place
/// the redeemer is known, so this one writes it down for the executor.
///
/// The record is keyed on the exact spend (grant hash under the executor's registry, asset, amount,
/// recipient) and on the account that will perform the execution, so another call in the same
/// transaction cannot borrow it. It lives in transient storage (EIP-1153), so it cannot outlive the
/// transaction. Only the executor can read it, and reading clears it, so one record yields at most one
/// `consume`. Only the trusted manager can write it: a record anyone could write would let anyone name
/// any redeemer.
///
/// Place the caveat on the delegation whose delegator performs the execution, the root of the chain;
/// a record bound to any other account is never read. Single-call, default-exec mode only: a batch or
/// a try-mode execution is rejected, so a failed execution cannot leave a record in place.
///
/// The redeemer is recorded as it is. The comparison with `grant.delegate` is the registry's: a
/// sub-delegate, or the caller of a delegation open to any delegate, is recorded as itself and rejected
/// by `consume` with UNAUTHORIZED_DELEGATE.
contract SpendGrantRedemptionEnforcer {
    error ZeroAddress();
    error NotManager();
    error NotExecutor();
    error UnsupportedMode();
    error MalformedExecution();
    error WrongTarget();
    error NonzeroValue();
    error WrongCall();

    /// @dev ERC-7579 single execution: 20 bytes target, 32 bytes value, then at least a 4-byte selector.
    uint256 internal constant MIN_EXECUTION_LENGTH = 20 + 32 + 4;

    address internal immutable MANAGER;
    address internal immutable EXECUTOR;
    address internal immutable REGISTRY;

    constructor(address manager_, address executor_, address registry_) {
        if (manager_ == address(0) || executor_ == address(0) || registry_ == address(0)) revert ZeroAddress();
        MANAGER = manager_;
        EXECUTOR = executor_;
        REGISTRY = registry_;
    }

    /// @notice The delegation manager whose hook calls are trusted.
    function manager() external view returns (address) {
        return MANAGER;
    }

    /// @notice The only contract that may read records.
    function executor() external view returns (address) {
        return EXECUTOR;
    }

    /// @notice The registry under which grant hashes are computed.
    function registry() external view returns (address) {
        return REGISTRY;
    }

    /// @notice ERC-7710 hook the manager runs before the execution tied to this delegation.
    /// @param mode ERC-7579 mode: byte 0 is the call type (0x00 single), byte 1 the exec type (0x00 default).
    /// @param executionCalldata ERC-7579 single execution: 20 bytes target, 32 bytes value, then call data.
    /// @param delegator The delegator of the delegation carrying this caveat; its account performs the execution.
    /// @param redeemer The caller of `redeemDelegations`, which the manager authenticated.
    function beforeHook(
        bytes calldata,
        bytes calldata,
        bytes32 mode,
        bytes calldata executionCalldata,
        bytes32,
        address delegator,
        address redeemer
    ) external {
        if (msg.sender != MANAGER) revert NotManager();
        if (mode[0] != 0x00 || mode[1] != 0x00) revert UnsupportedMode();
        if (executionCalldata.length < MIN_EXECUTION_LENGTH) revert MalformedExecution();

        address target = address(bytes20(executionCalldata[:20]));
        uint256 value = uint256(bytes32(executionCalldata[20:52]));
        bytes calldata callData = executionCalldata[52:];
        if (target != EXECUTOR) revert WrongTarget();
        if (value != 0) revert NonzeroValue();
        if (bytes4(callData[:4]) != SpendGrantExecutor.spend.selector) revert WrongCall();

        (SpendGrant memory grant,, address asset, uint256 amount, address recipient) =
            abi.decode(callData[4:], (SpendGrant, bytes, address, uint256, address));
        bytes32 key = _key(delegator, SpendGrantHash.digest(block.chainid, REGISTRY, grant), asset, amount, recipient);
        assembly {
            tstore(key, redeemer)
        }
    }

    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
        pure
    {}

    function afterHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
        pure
    {}

    function afterAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
        external
        pure
    {}

    /// @notice Reads and clears the record for this spend, so it authorizes at most one `consume`.
    /// @dev Executor only. `executingAccount` is the executor's caller. Returns zero when nothing is recorded.
    function take(address executingAccount, bytes32 grantHash, address asset, uint256 amount, address recipient)
        external
        returns (address redeemer)
    {
        if (msg.sender != EXECUTOR) revert NotExecutor();
        bytes32 key = _key(executingAccount, grantHash, asset, amount, recipient);
        assembly {
            redeemer := tload(key)
            tstore(key, 0)
        }
    }

    /// @notice The redeemer currently recorded for this spend, or zero. Observation only.
    function recorded(address executingAccount, bytes32 grantHash, address asset, uint256 amount, address recipient)
        external
        view
        returns (address redeemer)
    {
        bytes32 key = _key(executingAccount, grantHash, asset, amount, recipient);
        assembly {
            redeemer := tload(key)
        }
    }

    function _key(address executingAccount, bytes32 grantHash, address asset, uint256 amount, address recipient)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(executingAccount, grantHash, asset, amount, recipient));
    }
}
