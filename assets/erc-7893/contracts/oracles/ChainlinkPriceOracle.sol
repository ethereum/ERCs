// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ChainlinkPriceOracle
 * @dev REAL Chainlink integration for ERC-7893 solvency monitoring
 * @notice Production-ready oracle with real Chainlink price feeds
 */
contract ChainlinkPriceOracle is Ownable {
    struct PriceFeed {
        AggregatorV3Interface feed;
        uint256 heartbeat;
        uint8 decimals;
        bool isActive;
        string symbol;
    }
    
    mapping(address => PriceFeed) public priceFeeds;
    mapping(address => uint256) public emergencyPrices; // Fallback prices
    
    uint256 public constant STALENESS_MULTIPLIER = 2; // 2x heartbeat for staleness
    uint256 public constant MAX_PRICE_DEVIATION = 1000; // 10% max deviation for emergency fallback
    
    event PriceFeedAdded(address indexed token, address indexed feed, string symbol);
    event PriceFeedUpdated(address indexed token, address indexed feed);
    event EmergencyPriceSet(address indexed token, uint256 price, string reason);
    event StalePriceDetected(address indexed token, uint256 lastUpdate, uint256 heartbeat);
    
    // Real Mainnet Chainlink feeds
    constructor() Ownable(msg.sender) {
        // WETH/USD: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        _addPriceFeed(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, // WETH
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // ETH/USD feed
            3600, // 1 hour heartbeat
            8,    // 8 decimals
            "ETH/USD"
        );
        
        // WBTC/USD: 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c
        _addPriceFeed(
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
            0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // BTC/USD feed
            3600, // 1 hour heartbeat
            8,    // 8 decimals
            "BTC/USD"
        );
        
        // USDC/USD: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
        _addPriceFeed(
            0xA0B86A33E6417C1C83bF8b25C0b093FB2Ee4E91D, // USDC
            0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // USDC/USD feed  
            86400, // 24 hour heartbeat (stable)
            8,     // 8 decimals
            "USDC/USD"
        );
        
        // DAI/USD: 0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9
        _addPriceFeed(
            0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
            0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9, // DAI/USD feed
            3600, // 1 hour heartbeat
            8,    // 8 decimals
            "DAI/USD"
        );
    }
    
    /**
     * @notice Get real Chainlink price with comprehensive validation
     * @dev Implements all Chainlink security best practices from official documentation
     * @param token Token address
     * @return price Current price in USD (8 decimals)
     * @return isStale Whether the price is stale
     * @return confidence Price confidence score (0-100)
     */
    function getPrice(address token) external view returns (uint256 price, bool isStale, uint256 confidence) {
        PriceFeed memory feed = priceFeeds[token];
        require(feed.isActive, "Price feed not available");
        
        try feed.feed.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            // Security validations according to Chainlink docs
            require(answer > 0, "Chainlink: Invalid price");
            require(updatedAt > 0, "Chainlink: Invalid timestamp");
            require(startedAt > 0, "Chainlink: Invalid start time");
            
            // Critical: Check for stale round data (answeredInRound < roundId indicates stale data)
            require(answeredInRound >= roundId, "Chainlink: Stale round data");
            
            // Additional security: Check if the round is complete
            require(block.timestamp >= updatedAt, "Chainlink: Future timestamp");
            
            price = uint256(answer);
            
            // Staleness check with heartbeat validation
            uint256 timeSinceUpdate = block.timestamp - updatedAt;
            isStale = timeSinceUpdate > feed.heartbeat * STALENESS_MULTIPLIER;
            
            // Calculate confidence score based on data freshness
            if (isStale) {
                confidence = 0; // Zero confidence for stale data
            } else if (timeSinceUpdate <= feed.heartbeat) {
                confidence = 100; // Full confidence within heartbeat
            } else {
                // Linear decay of confidence after heartbeat
                uint256 staleness = timeSinceUpdate - feed.heartbeat;
                uint256 maxStaleness = feed.heartbeat * (STALENESS_MULTIPLIER - 1);
                confidence = staleness >= maxStaleness ? 1 : 
                    100 - ((staleness * 99) / maxStaleness);
            }
            
            return (price, isStale, confidence);
            
        } catch Error(string memory reason) {
            // Handle specific errors from Chainlink
            if (emergencyPrices[token] > 0) {
                return (emergencyPrices[token], true, 10); // Very low confidence emergency price
            }
            revert(string(abi.encodePacked("Chainlink error: ", reason)));
        } catch {
            // Handle unexpected errors
            if (emergencyPrices[token] > 0) {
                return (emergencyPrices[token], true, 5); // Minimum confidence emergency price
            }
            revert("Chainlink: Price feed unavailable");
        }
    }
    
    /**
     * @notice Validate price deviation against Chainlink feeds with enhanced security
     * @dev Implements multi-layer validation following Chainlink security guidelines
     * @param token Token to validate
     * @param proposedPrice Price to validate (8 decimals)
     * @return isValid Whether price is within acceptable deviation
     * @return deviation Actual deviation percentage (basis points)
     */
    function validatePrice(address token, uint256 proposedPrice) external view returns (bool isValid, uint256 deviation) {
        require(proposedPrice > 0, "Invalid proposed price");
        
        (uint256 chainlinkPrice, bool isStale, uint256 confidence) = this.getPrice(token);
        
        // Reject if Chainlink data is unreliable
        if (isStale) {
            return (false, 10000); // Maximum deviation indicates rejection
        }
        
        // Minimum confidence threshold for price validation
        if (confidence < 80) {
            return (false, 9999); // High deviation indicates low confidence
        }
        
        // Calculate absolute deviation in basis points
        if (chainlinkPrice == 0) {
            return (false, 10000); // Cannot validate against zero price
        }
        
        uint256 absDiff = chainlinkPrice > proposedPrice 
            ? chainlinkPrice - proposedPrice 
            : proposedPrice - chainlinkPrice;
            
        deviation = (absDiff * 10000) / chainlinkPrice;
        
        // Dynamic deviation tolerance based on confidence
        uint256 maxDeviation;
        if (confidence >= 95) {
            maxDeviation = 300; // 3% for high confidence
        } else if (confidence >= 90) {
            maxDeviation = 400; // 4% for good confidence  
        } else {
            maxDeviation = 500; // 5% for acceptable confidence
        }
        
        isValid = deviation <= maxDeviation;
        
        return (isValid, deviation);
    }
    
    /**
     * @notice Get comprehensive price analysis for risk management
     * @param token Token to analyze
     * @return currentPrice Current price
     * @return priceHistory Array of recent prices
     * @return volatility Price volatility (basis points)
     * @return trend Price trend (-1, 0, 1 for down, stable, up)
     */
    function getPriceAnalysis(address token) external view returns (
        uint256 currentPrice,
        uint256[] memory priceHistory,
        uint256 volatility,
        int8 trend
    ) {
        PriceFeed memory feed = priceFeeds[token];
        require(feed.isActive, "Price feed not available");
        
        // Get recent price history
        uint256 historyLength = 10;
        priceHistory = new uint256[](historyLength);
        uint256[] memory timestamps = new uint256[](historyLength);
        
        (uint80 latestRoundId, , , , ) = feed.feed.latestRoundData();
        
        uint256 validPrices = 0;
        for (uint256 i = 0; i < historyLength && validPrices < historyLength; i++) {
            if (latestRoundId < uint80(i)) break; // Prevent underflow
            
            try feed.feed.getRoundData(latestRoundId - uint80(i)) returns (
                uint80 roundId, 
                int256 price, 
                uint256 startedAt, 
                uint256 timestamp, 
                uint80 answeredInRound
            ) {
                // Apply same security validations as getPrice
                if (price > 0 && 
                    timestamp > 0 && 
                    startedAt > 0 && 
                    answeredInRound >= roundId &&
                    timestamp <= block.timestamp) {
                    
                    priceHistory[validPrices] = uint256(price);
                    timestamps[validPrices] = timestamp;
                    validPrices++;
                }
            } catch {
                // Continue to next round on error
                continue;
            }
        }
        
        if (validPrices > 0) {
            currentPrice = priceHistory[0];
            
            // Calculate volatility and trend
            if (validPrices >= 3) {
                (volatility, trend) = _calculateVolatilityAndTrend(priceHistory, validPrices);
            }
        }
        
        return (currentPrice, priceHistory, volatility, trend);
    }
    
    /**
     * @notice Get circuit breaker analysis based on historical data
     * @param token Token to analyze
     * @return shouldTrigger Whether circuit breaker should trigger
     * @return priceChange Recent price change percentage
     * @return reason Human readable reason
     */
    function getCircuitBreakerAnalysis(address token) external view returns (
        bool shouldTrigger,
        uint256 priceChange,
        string memory reason
    ) {
        (uint256 currentPrice, uint256[] memory history, uint256 volatility,) = this.getPriceAnalysis(token);
        
        if (history.length < 2) {
            return (false, 0, "Insufficient data");
        }
        
        // Check for large price movements
        uint256 previousPrice = history[1];
        if (previousPrice > 0) {
            priceChange = currentPrice > previousPrice
                ? ((currentPrice - previousPrice) * 10000) / previousPrice
                : ((previousPrice - currentPrice) * 10000) / previousPrice;
                
            // Trigger circuit breaker on >20% change or extreme volatility
            if (priceChange > 2000) { // 20%
                shouldTrigger = true;
                reason = "Large price movement detected";
            } else if (volatility > 1500) { // 15% volatility
                shouldTrigger = true;
                reason = "High volatility detected";
            } else {
                reason = "Normal market conditions";
            }
        }
        
        return (shouldTrigger, priceChange, reason);
    }
    
    // === Admin Functions ===
    
    /**
     * @notice Add a new price feed
     */
    function addPriceFeed(
        address token,
        address feedAddress,
        uint256 heartbeat,
        uint8 decimals,
        string calldata symbol
    ) external onlyOwner {
        _addPriceFeed(token, feedAddress, heartbeat, decimals, symbol);
    }
    
    /**
     * @notice Set emergency price for a token
     * @param token Token address
     * @param price Emergency price to set
     * @param reason Reason for setting emergency price
     */
    function setEmergencyPrice(address token, uint256 price, string calldata reason) external onlyOwner {
        require(price > 0, "Invalid emergency price");
        emergencyPrices[token] = price;
        emit EmergencyPriceSet(token, price, reason);
    }
    
    /**
     * @notice Disable a price feed
     */
    function disablePriceFeed(address token) external onlyOwner {
        priceFeeds[token].isActive = false;
    }
    
    // === Internal Functions ===
    
    function _addPriceFeed(
        address token,
        address feedAddress,
        uint256 heartbeat,
        uint8 decimals,
        string memory symbol
    ) internal {
        require(token != address(0), "Invalid token");
        require(feedAddress != address(0), "Invalid feed");
        
        priceFeeds[token] = PriceFeed({
            feed: AggregatorV3Interface(feedAddress),
            heartbeat: heartbeat,
            decimals: decimals,
            isActive: true,
            symbol: symbol
        });
        
        emit PriceFeedAdded(token, feedAddress, symbol);
    }
    
    function _calculateVolatilityAndTrend(
        uint256[] memory prices,
        uint256 length
    ) internal pure returns (uint256 volatility, int8 trend) {
        if (length < 3) return (0, 0);
        
        // Calculate simple volatility (standard deviation approximation)
        uint256 sum = 0;
        for (uint256 i = 0; i < length; i++) {
            sum += prices[i];
        }
        uint256 average = sum / length;
        
        uint256 squaredDiffsSum = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 diff = prices[i] > average ? prices[i] - average : average - prices[i];
            squaredDiffsSum += (diff * diff) / 1e16; // Scale down to prevent overflow
        }
        
        volatility = (squaredDiffsSum * 10000) / (length * average * average); // Convert to basis points
        
        // Calculate trend (compare first and last prices)
        if (prices[0] > prices[length - 1] * 105 / 100) { // >5% increase
            trend = 1; // Up trend
        } else if (prices[0] < prices[length - 1] * 95 / 100) { // >5% decrease
            trend = -1; // Down trend
        } else {
            trend = 0; // Stable
        }
        
        return (volatility, trend);
    }
}
