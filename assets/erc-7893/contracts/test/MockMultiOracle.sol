// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockMultiOracle
 * @dev Advanced mock oracle for testing multi-oracle consensus and security scenarios
 */
contract MockMultiOracle is Ownable {
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        bool isValid;
        address oracle;
    }
    
    // token => oracle => price data
    mapping(address => mapping(address => PriceData)) public oraclePrices;
    mapping(address => address[]) public tokenOracles;
    mapping(address => bool) public authorizedOracles;
    
    uint256 public constant STALENESS_THRESHOLD = 3600; // 1 hour
    uint256 public constant MAX_DEVIATION = 500; // 5%
    
    event PriceUpdated(address indexed token, address indexed oracle, uint256 price);
    event OracleAuthorized(address indexed oracle, bool authorized);
    event ConsensusReached(address indexed token, uint256 consensusPrice);
    event DeviationAlert(address indexed token, address indexed oracle, uint256 deviation);
    
    constructor() Ownable(msg.sender) {}
    
    function authorizeOracle(address oracle, bool authorized) external onlyOwner {
        authorizedOracles[oracle] = authorized;
        emit OracleAuthorized(oracle, authorized);
    }
    
    function updatePrice(address token, uint256 price, address oracle) external {
        require(authorizedOracles[oracle] || msg.sender == owner(), "Not authorized");
        require(price > 0, "Invalid price");
        
        // Add oracle to token's oracle list if not already present
        bool found = false;
        for (uint i = 0; i < tokenOracles[token].length; i++) {
            if (tokenOracles[token][i] == oracle) {
                found = true;
                break;
            }
        }
        if (!found) {
            tokenOracles[token].push(oracle);
        }
        
        oraclePrices[token][oracle] = PriceData({
            price: price,
            timestamp: block.timestamp,
            isValid: true,
            oracle: oracle
        });
        
        emit PriceUpdated(token, oracle, price);
        
        // Check for price consensus
        _checkConsensus(token);
    }
    
    function getConsensusPrice(address token) external view returns (uint256, bool) {
        address[] memory oracles = tokenOracles[token];
        if (oracles.length < 3) {
            return (0, false); // Need at least 3 oracles
        }
        
        uint256[] memory validPrices = new uint256[](oracles.length);
        uint256 validCount = 0;
        
        for (uint i = 0; i < oracles.length; i++) {
            PriceData memory data = oraclePrices[token][oracles[i]];
            if (data.isValid && block.timestamp - data.timestamp <= STALENESS_THRESHOLD) {
                validPrices[validCount] = data.price;
                validCount++;
            }
        }
        
        if (validCount < 2) {
            return (0, false); // Not enough valid prices
        }
        
        // Calculate median
        uint256 median = _calculateMedian(validPrices, validCount);
        
        // Validate deviation
        bool consensusReached = true;
        for (uint i = 0; i < validCount; i++) {
            uint256 deviation = validPrices[i] > median 
                ? ((validPrices[i] - median) * 10000) / median
                : ((median - validPrices[i]) * 10000) / median;
                
            if (deviation > MAX_DEVIATION) {
                consensusReached = false;
                break;
            }
        }
        
        return (median, consensusReached);
    }
    
    function _checkConsensus(address token) internal {
        (uint256 consensusPrice, bool reached) = this.getConsensusPrice(token);
        if (reached) {
            emit ConsensusReached(token, consensusPrice);
        }
    }
    
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
    
    // Test utilities
    function simulateStalePrice(address token, address oracle) external onlyOwner {
        PriceData storage data = oraclePrices[token][oracle];
        data.timestamp = block.timestamp - STALENESS_THRESHOLD - 1;
    }
    
    function simulateManipulation(address token, address oracle, uint256 manipulatedPrice) external onlyOwner {
        oraclePrices[token][oracle] = PriceData({
            price: manipulatedPrice,
            timestamp: block.timestamp,
            isValid: true,
            oracle: oracle
        });
        
        emit PriceUpdated(token, oracle, manipulatedPrice);
    }
    
    function getOracleData(address token, address oracle) external view returns (PriceData memory) {
        return oraclePrices[token][oracle];
    }
}
