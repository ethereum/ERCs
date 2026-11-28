// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IERCProtectedReceiveCore} from "./IERCProtectedReceiveCore.sol";
import {IERCProtectedReceiveOptIn} from "./IERCProtectedReceiveOptIn.sol";
import {IERCProtectedReceiveLevel} from "./IERCProtectedReceiveLevel.sol";
import {IERCProtectedReceiveSig} from "./IERCProtectedReceiveSig.sol";
import {IERCProtectedReceiveAllowlist} from "./IERCProtectedReceiveAllowlist.sol";
import {IERCProtectedReceiveDenylist} from "./IERCProtectedReceiveDenylist.sol";
import {IERCProtectedReceivePermit} from "./IERCProtectedReceivePermit.sol";
import {IERCProtectedReceivePolicy} from "./IERCProtectedReceivePolicy.sol";

/**
 * @title IERCProtectedReceive
 * @notice Consolidating interface combining all Protected ERC-20 extensions.
 * @dev Inherits `Core`, `OptIn`, `Level`, `Sig`, `Allowlist`, `Denylist`, `Permit`, and `Policy`.
 *      For ERC-165 discovery, query the individual sub-interface IDs.
 */
interface IERCProtectedReceive is
    IERCProtectedReceiveCore,
    IERCProtectedReceiveOptIn,
    IERCProtectedReceiveLevel,
    IERCProtectedReceiveSig,
    IERCProtectedReceiveAllowlist,
    IERCProtectedReceiveDenylist,
    IERCProtectedReceivePermit,
    IERCProtectedReceivePolicy
{}
