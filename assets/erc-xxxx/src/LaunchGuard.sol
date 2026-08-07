// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ILaunchGuard} from "./ILaunchGuard.sol";
import {ILaunchAbuseRegistry} from "./ILaunchAbuseRegistry.sol";
import {ContainmentAction} from "./LaunchAbuseTypes.sol";
import {Containment} from "./Containment.sol";

/// @title Advisory pre-purchase guard.
/// @notice Never reverts, by construction. A guard consulted inside a purchase
///         path that can fail is a censorship primitive: anyone able to make it
///         revert could block every purchase that consults it. Failing open
///         confines a broken or hostile registry to withholding advice.
contract LaunchGuard is ILaunchGuard {
    ILaunchAbuseRegistry public immutable registry;

    constructor(ILaunchAbuseRegistry registry_) {
        registry = registry_;
    }

    function checkLaunch(bytes32 launchId)
        external
        view
        returns (ContainmentAction action, uint8 abuseScore, bytes32 reportId)
    {
        try registry.activeScore(launchId) returns (uint8 score, uint8 confidence, bytes32 rid) {
            return (Containment.ladder(score, confidence), score, rid);
        } catch {
            // An unreachable or misbehaving registry yields advice, not failure.
            return (ContainmentAction.None, 0, bytes32(0));
        }
    }
}
