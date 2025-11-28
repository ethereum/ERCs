// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ISolvencyProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SolvencyProof
 * @author Sean Luis (@SeanLuis) <seanluis47@gmail.com>
 * @notice Implementation of DeFi Protocol Solvency Proof Standard (EIP-DRAFT)
 * @dev This contract implements ISolvencyProof interface for tracking and verifying protocol solvency
 *      It includes asset/liability tracking, solvency ratio calculations, and historical metrics
 */
contract SolvencyProof is ISolvencyProof, Ownable, ReentrancyGuard {
    // === Constants ===
    /// @notice Base multiplier for ratio calculations (100% = 10000)
    uint256 private constant RATIO_DECIMALS = 10000;
    
    /// @notice Minimum solvency ratio required (105%)
    uint256 private constant MIN_SOLVENCY_RATIO = 10500;
    
    /// @notice Critical threshold for emergency measures (102%)
    uint256 private constant CRITICAL_RATIO = 10200;

    // === State Variables ===
    /// @notice Current state of protocol assets
    ProtocolAssets private currentAssets;
    
    /// @notice Current state of protocol liabilities
    ProtocolLiabilities private currentLiabilities;
    
    /// @notice Mapping of authorized price oracles
    /// @dev address => isAuthorized
    mapping(address => bool) public assetOracles;

    /**
     * @notice Structure for storing historical solvency metrics
     * @dev Used to track protocol's financial health over time
     * @param timestamp Time when metrics were recorded
     * @param solvencyRatio Calculated solvency ratio at that time
     * @param assets Snapshot of protocol assets
     * @param liabilities Snapshot of protocol liabilities
     */
    struct HistoricalMetric {
        uint256 timestamp;
        uint256 solvencyRatio;
        ProtocolAssets assets;
        ProtocolLiabilities liabilities;
    }
    
    /// @notice Array storing historical solvency metrics
    HistoricalMetric[] private metricsHistory;

    // === Events ===
    /// @notice Emitted when an oracle's authorization status changes
    /// @param oracle Address of the oracle
    /// @param authorized New authorization status
    event OracleUpdated(address indexed oracle, bool authorized);

    /**
     * @notice Contract constructor
     * @dev Initializes Ownable with msg.sender as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Restricts function access to authorized oracles
     * @dev Throws if called by non-authorized address
     */
    modifier onlyOracle() {
        require(assetOracles[msg.sender], "Not authorized oracle");
        _;
    }

    // === External Functions ===
    /// @inheritdoc ISolvencyProof
    function getProtocolAssets() external view returns (ProtocolAssets memory) {
        return currentAssets;
    }

    /// @inheritdoc ISolvencyProof
    function getProtocolLiabilities() external view returns (ProtocolLiabilities memory) {
        return currentLiabilities;
    }

    /// @inheritdoc ISolvencyProof
    function getSolvencyRatio() external view returns (uint256) {
        return _calculateSolvencyRatio();
    }

    /// @inheritdoc ISolvencyProof
    function verifySolvency() external view returns (bool isSolvent, uint256 healthFactor) {
        uint256 ratio = _calculateSolvencyRatio();
        return (ratio >= MIN_SOLVENCY_RATIO, ratio);
    }

    /// @inheritdoc ISolvencyProof
    function getSolvencyHistory(uint256 startTime, uint256 endTime) 
        external 
        view 
        returns (
            uint256[] memory timestamps,
            uint256[] memory ratios,
            ProtocolAssets[] memory assets,
            ProtocolLiabilities[] memory liabilities
        )
    {
        uint256 count = 0;
        for (uint256 i = 0; i < metricsHistory.length; i++) {
            if (metricsHistory[i].timestamp >= startTime && 
                metricsHistory[i].timestamp <= endTime) {
                count++;
            }
        }

        timestamps = new uint256[](count);
        ratios = new uint256[](count);
        assets = new ProtocolAssets[](count);
        liabilities = new ProtocolLiabilities[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < metricsHistory.length && index < count; i++) {
            if (metricsHistory[i].timestamp >= startTime && 
                metricsHistory[i].timestamp <= endTime) {
                timestamps[index] = metricsHistory[i].timestamp;
                ratios[index] = metricsHistory[i].solvencyRatio;
                assets[index] = metricsHistory[i].assets;
                liabilities[index] = metricsHistory[i].liabilities;
                index++;
            }
        }

        return (timestamps, ratios, assets, liabilities);
    }

    /// @inheritdoc ISolvencyProof
    function updateAssets(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata values
    ) external onlyOracle nonReentrant {
        require(tokens.length == amounts.length && amounts.length == values.length, 
                "Array lengths mismatch");

        currentAssets = ProtocolAssets({
            tokens: tokens,
            amounts: amounts,
            values: values,
            timestamp: block.timestamp
        });

        _updateMetrics();
    }

    /// @inheritdoc ISolvencyProof
    function updateLiabilities(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata values
    ) external onlyOracle nonReentrant {
        require(tokens.length == amounts.length && amounts.length == values.length, 
                "Array lengths mismatch");

        currentLiabilities = ProtocolLiabilities({
            tokens: tokens,
            amounts: amounts,
            values: values,
            timestamp: block.timestamp
        });

        _updateMetrics();
    }

    /**
     * @notice Updates oracle authorization status
     * @dev Only callable by contract owner
     * @param oracle Address of the oracle to update
     * @param authorized New authorization status
     */
    function setOracle(address oracle, bool authorized) external onlyOwner {
        require(oracle != address(0), "Invalid oracle address");
        assetOracles[oracle] = authorized;
        emit OracleUpdated(oracle, authorized);
    }

    // === Internal Functions ===
    /**
     * @notice Calculates current solvency ratio
     * @dev Ratio = (Total Assets / Total Liabilities) × RATIO_DECIMALS
     * @return Current solvency ratio with RATIO_DECIMALS precision
     */
    function _calculateSolvencyRatio() internal view returns (uint256) {
        uint256 totalAssets = _sumArray(currentAssets.values);
        uint256 totalLiabilities = _sumArray(currentLiabilities.values);
        
        if (totalLiabilities == 0) {
            return totalAssets > 0 ? RATIO_DECIMALS * 2 : RATIO_DECIMALS;
        }
        
        return (totalAssets * RATIO_DECIMALS) / totalLiabilities;
    }

    /**
     * @notice Updates protocol metrics and emits relevant events
     * @dev Called after asset or liability updates
     */
    function _updateMetrics() internal {
        uint256 totalAssets = _sumArray(currentAssets.values);
        uint256 totalLiabilities = _sumArray(currentLiabilities.values);
        uint256 ratio = _calculateSolvencyRatio();

        // Debug log
        emit SolvencyMetricsUpdated(
            totalAssets,
            totalLiabilities,
            ratio,
            block.timestamp
        );
        
        metricsHistory.push(HistoricalMetric({
            timestamp: block.timestamp,
            solvencyRatio: ratio,
            assets: currentAssets,
            liabilities: currentLiabilities
        }));

        // Update alerts based on actual ratio
        if (ratio < CRITICAL_RATIO) {
            emit RiskAlert("CRITICAL", ratio, totalAssets, totalLiabilities);
        } else if (ratio < MIN_SOLVENCY_RATIO) {
            emit RiskAlert("HIGH_RISK", ratio, totalAssets, totalLiabilities);
        }
    }

    /**
     * @notice Sums all values in an array
     * @param array Array of uint256 values to sum
     * @return sum Total sum of array values
     */
    function _sumArray(uint256[] memory array) internal pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < array.length; i++) {
            sum += array[i];
        }
        return sum;
    }
}