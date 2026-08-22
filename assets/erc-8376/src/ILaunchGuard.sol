// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ContainmentAction} from "./LaunchAbuseTypes.sol";

/// @title Advisory guard consulted before a purchase.
/// @notice Callers MUST invoke this with STATICCALL (EIP-214) so the read-only
///         guarantee is enforced by the EVM rather than by implementer
///         discipline, and MUST treat any failure as `ContainmentAction.None`.
///         A guard that can revert inside a purchase path is a censorship
///         primitive: whoever can make it fail can block every purchase.
interface ILaunchGuard {
    function checkLaunch(bytes32 launchId)
        external
        view
        returns (ContainmentAction action, uint8 abuseScore, bytes32 reportId);
}
