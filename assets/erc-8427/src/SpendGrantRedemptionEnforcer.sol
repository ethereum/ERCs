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
/// Whose record: only the grant's principal's. The manager calls the hook once per delegation that
/// carries this caveat, each time with that delegation's own delegator, so a chain could produce a
/// record for every hop. A record for any account other than the principal is never written: the
/// executor accepts the record path only when the principal's own account is its caller, and a record
/// keyed on an intermediate delegator would let that delegator, or anyone who can drive its account
/// later in the transaction, spend again on the delegate's one redemption. A caveat attached by any
/// other delegator is therefore inert.
///
/// The record is keyed on the exact spend (grant hash under the executor's registry, asset, amount,
/// recipient) and on the principal, lives in transient storage (EIP-1153) so it cannot outlive the
/// transaction, is readable only by the executor, is cleared when read so one record yields at most one
/// `consume`, and is cleared again by afterHook so nothing untaken survives the redemption. Only the
/// trusted manager can write it; a record anyone could write would let anyone name any redeemer.
///
/// Single-call, default-exec mode only, with every other mode byte zero: a batch, a try-mode or a
/// vendor-mode execution is rejected, so a failed execution cannot leave a record in place.
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
        // Fail at deployment, not at first use, on a chain without EIP-1153.
        assembly ("memory-safe") {
            tstore(0, 1)
            if iszero(eq(tload(0), 1)) { revert(0, 0) }
            tstore(0, 0)
        }
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
    /// @param mode ERC-7579 mode; only all-zero (single call, default exec, no vendor selector) is accepted.
    /// @param executionCalldata ERC-7579 single execution: 20 bytes target, 32 bytes value, then call data.
    /// @param delegator The delegator of the delegation carrying this caveat. A record is written only
    /// when it is the grant's principal, whose account performs the execution on the record path.
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
        (bytes32 key, address principal) = _record(mode, executionCalldata, delegator);
        if (delegator != principal) return;
        assembly ("memory-safe") {
            tstore(key, redeemer)
        }
    }

    /// @notice ERC-7710 hook the manager runs after the execution. Clears whatever beforeHook wrote and the
    /// executor did not take, so no record outlives the redemption it was written for.
    function afterHook(
        bytes calldata,
        bytes calldata,
        bytes32 mode,
        bytes calldata executionCalldata,
        bytes32,
        address delegator,
        address
    ) external {
        if (msg.sender != MANAGER) revert NotManager();
        (bytes32 key, address principal) = _record(mode, executionCalldata, delegator);
        if (delegator != principal) return;
        assembly ("memory-safe") {
            tstore(key, 0)
        }
    }

    function beforeAllHook(bytes calldata, bytes calldata, bytes32, bytes calldata, bytes32, address, address)
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
        assembly ("memory-safe") {
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
        assembly ("memory-safe") {
            redeemer := tload(key)
        }
    }

    /// @dev Validates the mode and the execution, which must be a `spend` call on the executor with no
    /// value, and derives the record key for `delegator` together with the grant's principal.
    function _record(bytes32 mode, bytes calldata executionCalldata, address delegator)
        internal
        view
        returns (bytes32 key, address principal)
    {
        if (mode != bytes32(0)) revert UnsupportedMode();
        if (executionCalldata.length < MIN_EXECUTION_LENGTH) revert MalformedExecution();

        address target = address(bytes20(executionCalldata[:20]));
        uint256 value = uint256(bytes32(executionCalldata[20:52]));
        bytes calldata callData = executionCalldata[52:];
        if (target != EXECUTOR) revert WrongTarget();
        if (value != 0) revert NonzeroValue();
        if (bytes4(callData[:4]) != SpendGrantExecutor.spend.selector) revert WrongCall();

        (SpendGrant memory grant,, address asset, uint256 amount, address recipient) =
            abi.decode(callData[4:], (SpendGrant, bytes, address, uint256, address));
        principal = grant.principal;
        key = _key(delegator, SpendGrantHash.digest(block.chainid, REGISTRY, grant), asset, amount, recipient);
    }

    function _key(address executingAccount, bytes32 grantHash, address asset, uint256 amount, address recipient)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(executingAccount, grantHash, asset, amount, recipient));
    }
}
