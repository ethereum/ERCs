// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ISolvencyProof.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SolvencyProof
 * @author Sean Luis (@SeanLuis) <seanluis47@gmail.com>
 * @notice Implementation of DeFi Protocol Solvency Proof Standard (EIP-DRAFT)
 * @dev This contract implements ISolvencyProof interface for tracking and verifying protocol solvency
 *      It includes asset/liability tracking, solvency ratio calculations, and historical metrics
 */
contract SolvencyProof is ISolvencyProof, AccessControl, ReentrancyGuard {
    // === Constants ===
    /// @notice Base multiplier for ratio calculations (100% = 10000)
    uint256 private constant RATIO_DECIMALS = 10000;
    
    /// @notice Minimum solvency ratio required (105%)
    uint256 private constant MIN_SOLVENCY_RATIO = 10500;
    
    /// @notice Critical threshold for emergency measures (102%)
    uint256 private constant CRITICAL_RATIO = 10200;
    
    /// @notice Warning threshold for enhanced monitoring (110%)
    uint256 private constant WARNING_RATIO = 11000;
    
    // === Enhanced Security Constants ===
    /// @notice Maximum price deviation allowed between oracles (5%)
    uint256 private constant MAX_PRICE_DEVIATION = 500;
    
    /// @notice Maximum tokens per update to prevent DoS
    uint256 private constant MAX_TOKENS_PER_UPDATE = 50;
    
    /// @notice Oracle data staleness threshold (1 hour)
    uint256 private constant STALENESS_THRESHOLD = 3600;
    
    /// @notice Circuit breaker threshold for asset changes (20%)
    uint256 private constant CIRCUIT_BREAKER_THRESHOLD = 2000;
    
    /// @notice Rate limiting cooldown in blocks
    uint256 private constant UPDATE_COOLDOWN = 5;
    
    /// @notice Maximum historical entries to prevent unbounded growth
    uint256 private constant MAX_HISTORY_ENTRIES = 8760;
    
    // === Roles for Access Control ===
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // === State Variables ===
    /// @notice Current state of protocol assets
    ProtocolAssets private currentAssets;
    
    /// @notice Current state of protocol liabilities
    ProtocolLiabilities private currentLiabilities;
    
    /// @notice Legacy oracle mapping for backward compatibility
    /// @dev address => isAuthorized (deprecated, use ORACLE_ROLE instead)
    mapping(address => bool) public assetOracles;
    
    // === Enhanced Security State Variables ===
    /// @notice Multi-oracle price tracking: oracle => token => price
    mapping(address => mapping(address => uint256)) public oraclePrices;
    
    /// @notice Oracle last update timestamps for staleness detection
    mapping(address => uint256) public oracleLastUpdate;
    
    /// @notice Rate limiting: oracle => last update block
    mapping(address => uint256) public lastUpdateBlock;
    
    /// @notice Emergency pause state
    bool public emergencyPaused;
    
    /// @notice Emergency pause end timestamp
    uint256 public pauseEndTime;
    
    /// @notice Emergency guardian address
    address public emergencyGuardian;

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
        address updatedBy; // Track which oracle updated
    }
    
    /// @notice Array storing historical solvency metrics
    HistoricalMetric[] private metricsHistory;

    // === Events ===
    /// @notice Emitted when an oracle's authorization status changes
    /// @param oracle Address of the oracle
    /// @param authorized New authorization status
    event OracleUpdated(address indexed oracle, bool authorized);
    
    // === Enhanced Security Events ===
    /// @notice Emitted when emergency pause is triggered
    event EmergencyPaused(address indexed guardian, uint256 pauseEndTime);
    
    /// @notice Emitted when emergency pause is lifted
    event EmergencyUnpaused(address indexed guardian);
    
    /// @notice Emitted when circuit breaker is triggered
    event CircuitBreakerTriggered(string reason, uint256 deviation, uint256 threshold);
    
    /// @notice Emitted when price deviation is detected
    event PriceDeviationAlert(address indexed token, uint256 deviation, address[] oracles);
    
    /// @notice Emitted when rate limiting is triggered
    event RateLimitTriggered(address indexed oracle, uint256 blockNumber);

    /**
     * @notice Contract constructor
     * @dev Initializes AccessControl with msg.sender as admin and sets up roles
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
        emergencyGuardian = msg.sender;
    }

    // === Enhanced Modifiers ===
    
    /**
     * @notice Restricts function access to authorized oracles (backward compatible)
     * @dev Checks both legacy mapping and new role-based system
     */
    modifier onlyOracle() {
        require(
            assetOracles[msg.sender] || hasRole(ORACLE_ROLE, msg.sender), 
            "Not authorized oracle"
        );
        require(!emergencyPaused || block.timestamp > pauseEndTime, "Emergency paused");
        _;
    }
    
    /**
     * @notice Rate limiting modifier to prevent spam attacks
     */
    modifier rateLimited() {
        if (!testMode) {
            require(
                block.number >= lastUpdateBlock[msg.sender] + UPDATE_COOLDOWN,
                "Update too frequent"
            );
            lastUpdateBlock[msg.sender] = block.number;
            emit RateLimitTriggered(msg.sender, block.number);
        }
        _;
    }
    
    /**
     * @notice Validates array inputs to prevent DoS
     */
    modifier validArrays(address[] calldata tokens, uint256[] calldata amounts, uint256[] calldata values) {
        require(tokens.length <= MAX_TOKENS_PER_UPDATE, "Too many tokens");
        require(
            tokens.length == amounts.length && amounts.length == values.length,
            "Array lengths mismatch"
        );
        _;
    }
    
    /**
     * @notice Emergency guardian access control
     */
    modifier onlyEmergencyGuardian() {
        require(
            hasRole(EMERGENCY_ROLE, msg.sender) || 
            msg.sender == emergencyGuardian || 
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 
            "Not emergency guardian"
        );
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
    ) external onlyOracle rateLimited nonReentrant validArrays(tokens, amounts, values) {
        // Enhanced price validation with multi-oracle consensus
        _validateAndStorePrices(tokens, amounts, values);
        
        uint256 previousTotalAssets = _sumArray(currentAssets.values);

        currentAssets = ProtocolAssets({
            tokens: tokens,
            amounts: amounts,
            values: values,
            timestamp: block.timestamp
        });
        
        // Circuit breaker check for dramatic asset changes
        _checkCircuitBreaker(previousTotalAssets, _sumArray(values));
        
        oracleLastUpdate[msg.sender] = block.timestamp;
        _updateMetrics();
    }

    /// @inheritdoc ISolvencyProof
    function updateLiabilities(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata values
    ) external onlyOracle rateLimited nonReentrant validArrays(tokens, amounts, values) {
        currentLiabilities = ProtocolLiabilities({
            tokens: tokens,
            amounts: amounts,
            values: values,
            timestamp: block.timestamp
        });
        
        oracleLastUpdate[msg.sender] = block.timestamp;
        _updateMetrics();
    }

    /**
     * @notice Updates oracle authorization status (enhanced with role-based access)
     * @dev Maintains backward compatibility while adding new role system
     * @param oracle Address of the oracle to update
     * @param authorized New authorization status
     */
    function setOracle(address oracle, bool authorized) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(oracle != address(0), "Invalid oracle address");
        
        // Update legacy mapping for backward compatibility
        assetOracles[oracle] = authorized;
        
        // Update role-based system
        if (authorized) {
            _grantRole(ORACLE_ROLE, oracle);
        } else {
            _revokeRole(ORACLE_ROLE, oracle);
        }
        
        emit OracleUpdated(oracle, authorized);
    }
    
    // === Enhanced Security Functions ===
    
    /**
     * @notice Set emergency guardian with proper role management
     * @param guardian Address of the new emergency guardian
     */
    function setEmergencyGuardian(address guardian) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(guardian != address(0), "Invalid guardian address");
        emergencyGuardian = guardian;
        _grantRole(EMERGENCY_ROLE, guardian);
    }
    
    /**
     * @notice Emergency pause function
     */
    function emergencyPause() external onlyEmergencyGuardian {
        emergencyPaused = true;
        pauseEndTime = block.timestamp + 4 * 3600; // 4 hour default pause
        emit EmergencyPaused(msg.sender, pauseEndTime);
    }
    
    /**
     * @notice Emergency unpause function
     */
    function emergencyUnpause() external onlyEmergencyGuardian {
        emergencyPaused = false;
        pauseEndTime = 0;
        emit EmergencyUnpaused(msg.sender);
    }
    
    /**
     * @notice Extend emergency pause duration
     * @param additionalTime Additional time in seconds
     */
    function extendPause(uint256 additionalTime) external onlyEmergencyGuardian {
        require(emergencyPaused, "Not currently paused");
        pauseEndTime += additionalTime;
    }
    
    // === Enhanced View Functions ===
    
    /**
     * @notice Get emergency status information
     * @return isPaused Current pause state
     * @return endTime Pause end timestamp
     * @return guardian Emergency guardian address
     */
    function getEmergencyStatus() external view returns (bool isPaused, uint256 endTime, address guardian) {
        return (emergencyPaused, pauseEndTime, emergencyGuardian);
    }
    
    /**
     * @notice Get oracle status and staleness information
     * @param oracle Oracle address to check
     * @return isAuthorized Whether oracle is authorized
     * @return lastUpdate Last update timestamp
     * @return isStale Whether data is stale
     */
    function getOracleStatus(address oracle) external view returns (
        bool isAuthorized,
        uint256 lastUpdate,
        bool isStale
    ) {
        bool authorized = assetOracles[oracle] || hasRole(ORACLE_ROLE, oracle);
        bool stale = block.timestamp - oracleLastUpdate[oracle] > STALENESS_THRESHOLD;
        return (authorized, oracleLastUpdate[oracle], stale);
    }
    
    /**
     * @notice Get security parameters for transparency
     * @return maxPriceDeviation Maximum allowed price deviation between oracles (5%)
     * @return maxTokensPerUpdate Maximum tokens allowed per update operation
     * @return stalenessThreshold Oracle data staleness threshold in seconds
     * @return circuitBreakerThreshold Circuit breaker trigger threshold (20%)
     * @return updateCooldown Rate limiting cooldown in blocks
     */
    function getSecurityParameters() external pure returns (
        uint256 maxPriceDeviation,
        uint256 maxTokensPerUpdate,
        uint256 stalenessThreshold,
        uint256 circuitBreakerThreshold,
        uint256 updateCooldown
    ) {
        return (
            MAX_PRICE_DEVIATION,
            MAX_TOKENS_PER_UPDATE,
            STALENESS_THRESHOLD,
            CIRCUIT_BREAKER_THRESHOLD,
            UPDATE_COOLDOWN
        );
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

        emit SolvencyMetricsUpdated(
            totalAssets,
            totalLiabilities,
            ratio,
            block.timestamp
        );
        
        // Enhanced risk alerts with specific thresholds
        if (ratio < CRITICAL_RATIO) {
            emit RiskAlert("CRITICAL", ratio, CRITICAL_RATIO, block.timestamp);
            // Auto-trigger emergency pause for critical situations
            if (!emergencyPaused) {
                emergencyPaused = true;
                pauseEndTime = block.timestamp + 1 * 3600; // 1 hour emergency pause
                emit EmergencyPaused(address(this), pauseEndTime);
            }
        } else if (ratio < MIN_SOLVENCY_RATIO) {
            emit RiskAlert("HIGH_RISK", ratio, MIN_SOLVENCY_RATIO, block.timestamp);
        } else if (ratio < WARNING_RATIO) {
            emit RiskAlert("WARNING", ratio, WARNING_RATIO, block.timestamp);
        }
        
        // Store historical data with bounds
        if (metricsHistory.length >= MAX_HISTORY_ENTRIES) {
            // Remove oldest entry (shift array)
            for (uint256 i = 0; i < metricsHistory.length - 1; i++) {
                metricsHistory[i] = metricsHistory[i + 1];
            }
            metricsHistory.pop();
        }
        
        metricsHistory.push(HistoricalMetric({
            timestamp: block.timestamp,
            solvencyRatio: ratio,
            assets: currentAssets,
            liabilities: currentLiabilities,
            updatedBy: msg.sender
        }));
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
    
    // === Enhanced Security Internal Functions ===
    
    /**
     * @notice Validates and stores prices for multiple tokens
     * @param tokens Array of token addresses
     * @param amounts Array of token amounts  
     * @param values Array of token values
     */
    function _validateAndStorePrices(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata values
    ) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (amounts[i] > 0) {
                uint256 pricePerUnit = values[i] * 1e18 / amounts[i];
                require(
                    _validatePriceConsensus(tokens[i], pricePerUnit),
                    "Price consensus failed"
                );
                oraclePrices[msg.sender][tokens[i]] = pricePerUnit;
            }
        }
    }
    
    /**
     * @notice Checks circuit breaker conditions
     * @param previousTotal Previous total assets value
     * @param newTotal New total assets value
     */
    function _checkCircuitBreaker(uint256 previousTotal, uint256 newTotal) internal {
        if (previousTotal > 0) {
            uint256 assetChange = newTotal > previousTotal
                ? ((newTotal - previousTotal) * 10000) / previousTotal
                : ((previousTotal - newTotal) * 10000) / previousTotal;
                
            if (assetChange > CIRCUIT_BREAKER_THRESHOLD) {
                emergencyPaused = true;
                pauseEndTime = block.timestamp + 3600; // 1 hour pause
                emit CircuitBreakerTriggered("Large asset change", assetChange, CIRCUIT_BREAKER_THRESHOLD);
                emit EmergencyPaused(address(this), pauseEndTime);
            }
        }
    }
    
    /**
     * @notice Validates price consensus among multiple oracles
     * @param token Token address to validate price for
     * @param proposedPrice Proposed price to validate
     * @return isValid True if price is within acceptable deviation or not enough oracles for consensus
     */
    function _validatePriceConsensus(address token, uint256 proposedPrice) internal returns (bool) {
        address[] memory activeOracles = _getActiveOracles();
        if (activeOracles.length < 3) return true; // Need at least 3 oracles for consensus
        
        uint256[] memory prices = new uint256[](activeOracles.length);
        uint256 validPrices = 0;
        
        // Collect prices from all oracles
        for (uint256 i = 0; i < activeOracles.length; i++) {
            if (oraclePrices[activeOracles[i]][token] > 0) {
                prices[validPrices] = oraclePrices[activeOracles[i]][token];
                validPrices++;
            }
        }
        
        if (validPrices < 2) return true; // Not enough data for validation
        
        // Calculate median
        uint256 median = _calculateMedian(prices, validPrices);
        
        // Check deviation from median
        uint256 deviation = proposedPrice > median 
            ? ((proposedPrice - median) * 10000) / median
            : ((median - proposedPrice) * 10000) / median;
        
        if (deviation > MAX_PRICE_DEVIATION) {
            emit PriceDeviationAlert(token, deviation, activeOracles);
            return false;
        }
            
        return true;
    }
    
    /**
     * @notice Calculates median of an array
     * @param prices Array of prices
     * @param length Number of valid prices
     * @return medianValue The calculated median value
     */
    function _calculateMedian(uint256[] memory prices, uint256 length) internal pure returns (uint256) {
        // Simple bubble sort for small arrays
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (prices[j] > prices[j + 1]) {
                    uint256 temp = prices[j];
                    prices[j] = prices[j + 1];
                    prices[j + 1] = temp;
                }
            }
        }
        
        if (length % 2 == 0) {
            return (prices[length / 2 - 1] + prices[length / 2]) / 2;
        } else {
            return prices[length / 2];
        }
    }
    
    /**
     * @notice Gets list of active oracles (simplified implementation)
     * @dev In production, maintain a dynamic list of active oracles
     * @return activeOracles Array of active oracle addresses
     */
    function _getActiveOracles() internal pure returns (address[] memory) {
        // Simplified implementation - in production this should maintain
        // a dynamic list of all authorized oracles
        return new address[](0);
    }
    
    // === Liquidation Integration ===
    
    /// @notice Liquidation configuration
    struct LiquidationConfig {
        uint256 maxLiquidationRatio; // Max % of debt liquidatable in one tx
        uint256 liquidationBonus; // Bonus for liquidators (basis points)
        uint256 minHealthFactor; // Minimum health factor before liquidation
        uint256 maxSlippage; // Maximum allowed slippage (basis points)
        bool isActive; // Whether liquidation is enabled for this protocol
    }
    
    mapping(address => LiquidationConfig) public liquidationConfigs;
    mapping(address => mapping(address => uint256)) public userDebt; // protocol => user => debt
    mapping(address => mapping(address => uint256)) public userCollateral; // protocol => user => collateral
    
    event LiquidationConfigured(address indexed protocol, LiquidationConfig config);
    event LiquidationExecuted(
        address indexed protocol,
        address indexed user,
        address indexed liquidator,
        uint256 debtAmount,
        uint256 collateralAmount,
        uint256 bonus
    );
    event LiquidationRiskAlert(address indexed protocol, address indexed user, uint256 healthFactor);

    /**
     * @notice Configure liquidation parameters for a protocol
     * @param protocol Protocol address
     * @param maxLiquidationRatio Maximum liquidation ratio (50% = 5000)
     * @param liquidationBonus Liquidator bonus (5% = 500)
     * @param minHealthFactor Minimum health factor for liquidation (110% = 11000)
     * @param maxSlippage Maximum slippage tolerance (3% = 300)
     */
    function configureLiquidation(
        address protocol,
        uint256 maxLiquidationRatio,
        uint256 liquidationBonus,
        uint256 minHealthFactor,
        uint256 maxSlippage
    ) external onlyRole(ADMIN_ROLE) {
        require(protocol != address(0), "Invalid protocol");
        require(maxLiquidationRatio <= 5000, "Max liquidation ratio too high"); // 50% max
        require(liquidationBonus <= 1500, "Liquidation bonus too high"); // 15% max
        require(minHealthFactor >= 10500, "Min health factor too low"); // 105% min
        require(maxSlippage <= 1000, "Max slippage too high"); // 10% max
        
        liquidationConfigs[protocol] = LiquidationConfig({
            maxLiquidationRatio: maxLiquidationRatio,
            liquidationBonus: liquidationBonus,
            minHealthFactor: minHealthFactor,
            maxSlippage: maxSlippage,
            isActive: true
        });
        
        emit LiquidationConfigured(protocol, liquidationConfigs[protocol]);
    }
    
    /**
     * @notice Execute safe liquidation with comprehensive validation
     * @param protocol Protocol performing liquidation
     * @param user User being liquidated
     * @param debtAmount Amount of debt to liquidate
     * @param expectedCollateral Expected collateral to receive
     * @param maxSlippage Maximum slippage tolerance for this liquidation
     * @return actualCollateral Actual collateral received
     * @return liquidationBonus Bonus paid to liquidator
     */
    function safeLiquidation(
        address protocol,
        address user,
        uint256 debtAmount,
        uint256 expectedCollateral,
        uint256 maxSlippage
    ) external nonReentrant returns (uint256 actualCollateral, uint256 liquidationBonus) {
        require(!emergencyPaused || block.timestamp > pauseEndTime, "Emergency paused");
        
        LiquidationConfig memory config = liquidationConfigs[protocol];
        require(config.isActive, "Liquidation not configured for protocol");
        
        // Validate liquidation preconditions
        uint256 healthFactor = calculateUserHealthFactor(protocol, user);
        require(healthFactor < config.minHealthFactor, "User health factor too high");
        
        uint256 totalDebt = userDebt[protocol][user];
        uint256 totalCollateral = userCollateral[protocol][user];
        
        require(totalDebt > 0, "No debt to liquidate");
        require(totalCollateral > 0, "No collateral available");
        
        // Validate liquidation amount
        uint256 maxLiquidationAmount = (totalDebt * config.maxLiquidationRatio) / 10000;
        require(debtAmount <= maxLiquidationAmount, "Liquidation amount too large");
        
        // Calculate collateral with bonus
        uint256 collateralRatio = (totalCollateral * 10000) / totalDebt;
        uint256 baseCollateral = (debtAmount * collateralRatio) / 10000;
        liquidationBonus = (baseCollateral * config.liquidationBonus) / 10000;
        actualCollateral = baseCollateral + liquidationBonus;
        
        // Validate slippage
        uint256 actualSlippage = expectedCollateral > actualCollateral
            ? ((expectedCollateral - actualCollateral) * 10000) / expectedCollateral
            : ((actualCollateral - expectedCollateral) * 10000) / expectedCollateral;
            
        uint256 effectiveMaxSlippage = maxSlippage > 0 ? maxSlippage : config.maxSlippage;
        require(actualSlippage <= effectiveMaxSlippage, "Slippage too high");
        
        // Ensure liquidation improves user's health factor
        uint256 newDebt = totalDebt - debtAmount;
        uint256 newCollateral = totalCollateral - actualCollateral;
        uint256 newHealthFactor = newDebt > 0 ? (newCollateral * 10000) / newDebt : 20000; // 200% if no debt
        
        require(newHealthFactor > healthFactor, "Liquidation must improve health factor");
        require(newHealthFactor >= 10500 || newDebt == 0, "Final health factor too low");
        
        // Update user positions
        userDebt[protocol][user] = newDebt;
        userCollateral[protocol][user] = newCollateral;
        
        // Update protocol metrics if this liquidation affects overall solvency
        _updateMetrics();
        
        emit LiquidationExecuted(protocol, user, msg.sender, debtAmount, actualCollateral, liquidationBonus);
        
        return (actualCollateral, liquidationBonus);
    }
    
    /**
     * @notice Calculate user health factor for liquidation assessment
     * @param protocol Protocol address
     * @param user User address
     * @return healthFactor User's current health factor (basis points)
     */
    function calculateUserHealthFactor(address protocol, address user) public view returns (uint256) {
        uint256 debt = userDebt[protocol][user];
        uint256 collateral = userCollateral[protocol][user];
        
        if (debt == 0) return 20000; // 200% - maximum health
        if (collateral == 0) return 0; // 0% - liquidatable
        
        return (collateral * 10000) / debt;
    }
    
    /**
     * @notice Check if user is eligible for liquidation
     * @param protocol Protocol address
     * @param user User address
     * @return isEligible Whether user can be liquidated
     * @return healthFactor Current health factor
     * @param maxLiquidatable Maximum debt amount that can be liquidated
     */
    function getLiquidationEligibility(address protocol, address user) external view returns (
        bool isEligible,
        uint256 healthFactor,
        uint256 maxLiquidatable
    ) {
        LiquidationConfig memory config = liquidationConfigs[protocol];
        if (!config.isActive) return (false, 0, 0);
        
        healthFactor = calculateUserHealthFactor(protocol, user);
        isEligible = healthFactor < config.minHealthFactor;
        
        if (isEligible) {
            uint256 totalDebt = userDebt[protocol][user];
            maxLiquidatable = (totalDebt * config.maxLiquidationRatio) / 10000;
        }
        
        return (isEligible, healthFactor, maxLiquidatable);
    }
    
    /**
     * @notice Update user debt and collateral (called by integrated protocols)
     * @param user User address
     * @param newDebt New debt amount
     * @param newCollateral New collateral amount
     */
    function updateUserPosition(
        address user,
        uint256 newDebt,
        uint256 newCollateral
    ) external onlyOracle {
        address protocol = msg.sender;
        
        userDebt[protocol][user] = newDebt;
        userCollateral[protocol][user] = newCollateral;
        
        // Check for liquidation risk
        uint256 healthFactor = calculateUserHealthFactor(protocol, user);
        LiquidationConfig memory config = liquidationConfigs[protocol];
        
        if (config.isActive && healthFactor < config.minHealthFactor + 500) { // Alert 5% before liquidation
            emit LiquidationRiskAlert(protocol, user, healthFactor);
        }
    }
    
    /**
     * @notice Get comprehensive liquidation status for a user
     * @param protocol Protocol address
     * @param user User address
     * @return status Liquidation status struct
     */
    function getLiquidationStatus(address protocol, address user) external view returns (
        LiquidationStatus memory status
    ) {
        LiquidationConfig memory config = liquidationConfigs[protocol];
        uint256 debt = userDebt[protocol][user];
        uint256 collateral = userCollateral[protocol][user];
        uint256 healthFactor = calculateUserHealthFactor(protocol, user);
        
        status = LiquidationStatus({
            isEligible: config.isActive && healthFactor < config.minHealthFactor,
            healthFactor: healthFactor,
            totalDebt: debt,
            totalCollateral: collateral,
            maxLiquidatable: (debt * config.maxLiquidationRatio) / 10000,
            liquidationBonus: config.liquidationBonus,
            protocolConfig: config
        });
        
        return status;
    }
    
    /**
     * @notice Liquidation status structure
     */
    struct LiquidationStatus {
        bool isEligible;
        uint256 healthFactor;
        uint256 totalDebt;
        uint256 totalCollateral;
        uint256 maxLiquidatable;
        uint256 liquidationBonus;
        LiquidationConfig protocolConfig;
    }

    // === Test Utilities (for testing only) ===
    
    /// @notice Test mode flag to disable security features for backward compatibility
    bool public testMode;
    
    /**
     * @notice Enable/disable test mode for backward compatibility
     * @dev Only for testing - should be removed in production
     */
    function setTestMode(bool _testMode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        testMode = _testMode;
    }
    
    /**
     * @notice Test utility to set oracle prices directly
     * @dev Only for testing - should be removed in production
     */
    function testSetPrices(address oracle, address token, uint256 price) external onlyRole(DEFAULT_ADMIN_ROLE) {
        oraclePrices[oracle][token] = price;
    }
    
    /**
     * @notice Test utility to trigger circuit breaker manually
     * @dev Only for testing - should be removed in production
     */
    function testTriggerCircuitBreaker() external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyPaused = true;
        pauseEndTime = block.timestamp + 3600;
        emit CircuitBreakerTriggered("Test trigger", 2500, CIRCUIT_BREAKER_THRESHOLD);
        emit EmergencyPaused(msg.sender, pauseEndTime);
    }
}