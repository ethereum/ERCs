// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SignalVector} from "./LaunchAbuseTypes.sol";

/// @title The detector: assembly of a signal vector and its evidence.
/// @notice Four of the ten signals are readable from chain state and are derived
///         here, so a consumer need not trust the detector for them. Three
///         require historical graph traversal and are supplied by the off-chain
///         service. The remaining three come from the escrow and the directory.
///
///         Splitting it this way is the point: the more of the vector that is
///         independently recomputable, the more of a false report is provable,
///         and the more the detector's bond actually secures.
interface ILaunchDetector {
    /// @notice Hints a caller supplies for values that cannot be discovered from
    ///         a launch identifier alone.
    /// @param lpToken the liquidity token whose lock is being measured
    /// @param lockSinks addresses treated as locks or burns
    /// @param deployerWallets wallets attributed to the deployer
    /// @param deployerAllocation supply originally allocated to the deployer
    /// @param initialSupply total supply at window start, for dilution
    /// @param peakLiquidity the highest pool liquidity observed in the window
    /// @param currentLiquidity pool liquidity at window end
    struct ChainInputs {
        address   lpToken;
        address[] lockSinks;
        address[] deployerWallets;
        uint256   deployerAllocation;
        uint256   peakLiquidity;
        uint256   currentLiquidity;
        uint256   initialSupply;
        uint32    lpLockRemaining;
    }

    /// @notice Signals that cannot be derived on-chain, supplied by the service.
    /// @dev Each MUST be the unavailability sentinel where the service could not
    ///      establish it. Reporting zero would assert innocence it never checked.
    struct OffChainInputs {
        uint16 insiderAllocationShare;
        uint16 sniperConcentration;
        uint16 priorUpheldClaims;
        uint16 washTradeRatio;
    }

    /// @notice Assemble the full vector for a launch.
    function observe(
        bytes32 launchId,
        address token,
        ChainInputs calldata chainInputs,
        OffChainInputs calldata offChainInputs
    ) external view returns (SignalVector memory);

    /// @notice The canonical evidence leaf, so the commitment format is
    ///         executable rather than prose.
    /// @notice The `fieldId` an extension signal's evidence leaf commits to.
    /// @dev Derived from the schema and the field name so that a leaf for an
    ///      extension field cannot collide with one for a base signal.
    function extensionFieldId(bytes32 extensionSchema, string calldata fieldName)
        external
        view
        returns (bytes32);

    function evidenceLeaf(
        uint256 blockNumber,
        bytes32 txHash,
        uint256 logIndex,
        bytes32 fieldId,
        bytes32 value
    ) external view returns (bytes32);

    /// @notice Fold ordered leaves into the root a report commits to.
    function evidenceRoot(bytes32[] calldata leaves) external pure returns (bytes32);
}
