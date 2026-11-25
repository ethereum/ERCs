// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {BindingType, ConsumptionPath} from "./AITOTypes.sol";

/// @title Mapping from a carrier token to a series of AI inference entitlements
/// @notice Implemented by every contract whose tokens carry AITO units.
interface IAITOBinding {
    /// @notice The series a carrier token stands for.
    /// @param carrierId Token identifier within the carrier, or zero for single-token carriers.
    /// @return ledger The home ledger of the series.
    /// @return seriesId The series.
    /// @return bindingType Native when the carrier is the home ledger itself, Wrap for a locked 1:N representation.
    /// @return carrierPerUnit Carrier base units that stand for one denomination unit.
    /// @return path How units reached through this carrier are consumed.
    function aitoBinding(uint256 carrierId)
        external
        view
        returns (
            address ledger,
            uint256 seriesId,
            BindingType bindingType,
            uint256 carrierPerUnit,
            ConsumptionPath path
        );
}
