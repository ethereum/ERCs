// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/**
 * @title ISolvencyProof
 * @author Sean Luis (@SeanLuis) <seanluis47@gmail.com>
 * @notice Standard Interface for DeFi Protocol Solvency (EIP-DRAFT)
 * @dev Interface for the DeFi Protocol Solvency Proof Standard
 * @custom:security-contact seanluis47@gmail.com
 * @custom:version 1.0.0
 */
interface ISolvencyProof {
    /**
     * @dev Protocol assets structure
     * @notice Represents the current state of protocol assets
     * @custom:validation All arrays must be equal length
     * @custom:validation Values must be in ETH with 18 decimals
     */
    struct ProtocolAssets {
        address[] tokens;    // Addresses of tracked tokens
        uint256[] amounts;   // Amount of each token
        uint256[] values;    // Value in ETH of each token amount
        uint256 timestamp;   // Last update timestamp
    }

    /**
     * @dev Protocol liabilities structure
     * @notice Represents the current state of protocol liabilities
     * @custom:validation All arrays must be equal length
     * @custom:validation Values must be in ETH with 18 decimals
     */
    struct ProtocolLiabilities {
        address[] tokens;    // Addresses of liability tokens
        uint256[] amounts;   // Amount of each liability
        uint256[] values;    // Value in ETH of each liability
        uint256 timestamp;   // Last update timestamp
    }

    /**
     * @dev Emitted on metrics update
     * @notice Real-time financial health update
     * @param totalAssets Sum of asset values in ETH
     * @param totalLiabilities Sum of liability values in ETH
     * @param healthFactor Calculated as (totalAssets/totalLiabilities) × 10000
     * @param timestamp Update timestamp
     */
    event SolvencyMetricsUpdated(
        uint256 totalAssets,
        uint256 totalLiabilities,
        uint256 healthFactor,
        uint256 timestamp
    );

    /**
     * @dev Emitted when risk thresholds are breached
     * @notice Alerts stakeholders of potential solvency risks
     * 
     * @param riskLevel Risk level indicating severity of the breach (CRITICAL, HIGH_RISK, WARNING)
     * @param currentValue Current value that triggered the alert
     * @param threshold Risk threshold that was breached
     * @param timestamp Alert timestamp
     */
    event RiskAlert(
        string riskLevel,
        uint256 currentValue,
        uint256 threshold,
        uint256 timestamp
    );

    /**
     * @notice Get protocol's current assets
     * @return Full asset state including tokens, amounts and values
     */
    function getProtocolAssets() external view returns (ProtocolAssets memory);

    /**
     * @notice Get protocol's current liabilities
     * @return Full liability state including tokens, amounts and values
     */
    function getProtocolLiabilities() external view returns (ProtocolLiabilities memory);

    /**
     * @notice Calculate current solvency ratio
     * @return SR = (Total Assets / Total Liabilities) × 10000
     */
    function getSolvencyRatio() external view returns (uint256);

    /**
     * @notice Check protocol solvency status
     * @return isSolvent True if ratio >= minimum required
     * @return healthFactor Current solvency ratio
     */
    function verifySolvency() external view returns (bool isSolvent, uint256 healthFactor);

    /**
     * @notice Get historical solvency metrics
     * @param startTime Start of time range
     * @param endTime End of time range
     * @return timestamps Array of historical update timestamps
     * @return ratios Array of historical solvency ratios
     * @return assets Array of historical asset states
     * @return liabilities Array of historical liability states
     */
    function getSolvencyHistory(uint256 startTime, uint256 endTime) 
        external 
        view 
        returns (
            uint256[] memory timestamps,
            uint256[] memory ratios,
            ProtocolAssets[] memory assets,
            ProtocolLiabilities[] memory liabilities
        );

    /**
     * @notice Update protocol assets
     * @dev Only callable by authorized oracle
     */
    function updateAssets(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata values
    ) external;

    /**
     * @notice Update protocol liabilities
     * @dev Only callable by authorized oracle
     */
    function updateLiabilities(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata values
    ) external;
}