// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  IADRFExecutor — informative entry point of an executor
/// @notice The kernel never calls executors. An executor named by a binding reads a Final ruling, checks its
///         own authority, amount, target and anti-duplication conditions, enacts within its own authority
///         and reports through `reportEnactment`. This interface only names the conventional entry point.
interface IADRFExecutor {
    function enact(bytes32 caseId, bytes32 effectId) external;
}
