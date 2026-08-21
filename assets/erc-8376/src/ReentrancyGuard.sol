// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title Minimal non-reentrancy lock.
/// @notice Every externally reachable function that moves value or mutates
///         accounting takes this lock. The contracts follow checks-effects-
///         interactions as well, but this codebase custodies buyer funds across
///         many launches in one contract, so a single ordering slip would let
///         one launch spend another's balance. The lock is the backstop that
///         does not depend on getting every ordering right.
abstract contract ReentrancyGuard {
    uint256 private constant _UNLOCKED = 1;
    uint256 private constant _LOCKED = 2;
    uint256 private _state = _UNLOCKED;

    error Reentrancy();

    modifier nonReentrant() {
        if (_state == _LOCKED) revert Reentrancy();
        _state = _LOCKED;
        _;
        _state = _UNLOCKED;
    }
}
