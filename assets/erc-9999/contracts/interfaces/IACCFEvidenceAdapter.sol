// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes} from "./ACCFTypes.sol";

/// @title IACCFEvidenceAdapter
/// @notice Reads one record of another registry and reports whether it still supports the proposition the
///         adapter is defined for. An adapter supports that proposition only and never a whole axis.
interface IACCFEvidenceAdapter {
    /// @notice Identifier of the interpretation method and its version.
    function methodId() external view returns (bytes32);

    /// @notice Checks the record `recordId` of `source` for the unit `unitId` of the registry `units`.
    /// @param  commitment Adapter-defined expectation, for example a subject key, a scheme or a state root.
    /// @return status     Supported, NotSupported or Undetermined.
    /// @return validUntil Timepoint after which the record stops supporting the proposition; 0 if none is known.
    function probe(address units, bytes32 unitId, address source, bytes32 recordId, bytes32 commitment)
        external
        view
        returns (ACCFTypes.ProbeStatus status, uint48 validUntil);
}
