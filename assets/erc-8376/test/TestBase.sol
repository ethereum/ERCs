// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @dev Minimal cheatcode surface, so the asset folder needs no external
///      dependencies and can be compiled straight from this directory.
interface Vm {
    function warp(uint256) external;
    function chainId(uint256) external;
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function deal(address, uint256) external;
    function expectRevert() external;
    function expectRevert(bytes4) external;
    /// @dev Matches on the selector alone, for errors carrying arguments.
    function expectPartialRevert(bytes4) external;
}

contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function assertEq(uint256 a, uint256 b, string memory reason) internal pure {
        if (a != b) revert(reason);
    }

    function assertTrue(bool cond, string memory reason) internal pure {
        if (!cond) revert(reason);
    }

    function assertLt(uint256 a, uint256 b, string memory reason) internal pure {
        if (a >= b) revert(reason);
    }

    function assertLe(uint256 a, uint256 b, string memory reason) internal pure {
        if (a > b) revert(reason);
    }
}
