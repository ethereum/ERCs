// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MaliciousOracle
 * @dev Oracle designed to test attack scenarios and edge cases
 */
contract MaliciousOracle {
    mapping(address => uint256) public manipulatedPrices;
    mapping(address => bool) public shouldRevert;
    mapping(address => bool) public shouldReturnStale;
    mapping(address => uint256) public staleTimestamp;
    
    bool public globalRevert;
    bool public infiniteLoop;
    uint256 public gasConsumption;
    
    event MaliciousActivity(string activityType, address token, uint256 value);
    
    function setMaliciousPrice(address token, uint256 price) external {
        manipulatedPrices[token] = price;
        emit MaliciousActivity("PRICE_MANIPULATION", token, price);
    }
    
    function setShouldRevert(address token, bool _shouldRevert) external {
        shouldRevert[token] = _shouldRevert;
        emit MaliciousActivity("REVERT_ATTACK", token, _shouldRevert ? 1 : 0);
    }
    
    function setGlobalRevert(bool _shouldRevert) external {
        globalRevert = _shouldRevert;
        emit MaliciousActivity("GLOBAL_REVERT", address(0), _shouldRevert ? 1 : 0);
    }
    
    function setStalePrice(address token, bool _isStale) external {
        shouldReturnStale[token] = _isStale;
        if (_isStale) {
            staleTimestamp[token] = block.timestamp - 7200; // 2 hours old
        } else {
            staleTimestamp[token] = block.timestamp;
        }
        emit MaliciousActivity("STALE_PRICE", token, _isStale ? 1 : 0);
    }
    
    function enableInfiniteLoop(bool enable) external {
        infiniteLoop = enable;
        emit MaliciousActivity("INFINITE_LOOP", address(0), enable ? 1 : 0);
    }
    
    function setGasConsumption(uint256 _gasAmount) external {
        gasConsumption = _gasAmount;
        emit MaliciousActivity("GAS_CONSUMPTION", address(0), _gasAmount);
    }
    
    function getPrice(address token) external view returns (uint256) {
        // Global revert attack
        require(!globalRevert, "Oracle manipulation: global revert");
        
        // Token-specific revert attack
        require(!shouldRevert[token], "Oracle manipulation: token revert");
        
        // Infinite loop attack (will cause out-of-gas)
        if (infiniteLoop) {
            while (true) {
                // This will consume all gas
            }
        }
        
        // Gas consumption attack
        if (gasConsumption > 0) {
            uint256 startGas = gasleft();
            while (startGas - gasleft() < gasConsumption && gasleft() > gasConsumption) {
                // Waste gas
            }
        }
        
        // Return manipulated price if set
        if (manipulatedPrices[token] > 0) {
            return manipulatedPrices[token];
        }
        
        // Default reasonable price
        return 1 ether;
    }
    
    function getPriceWithTimestamp(address token) external view returns (uint256 price, uint256 timestamp) {
        price = this.getPrice(token);
        
        if (shouldReturnStale[token]) {
            timestamp = staleTimestamp[token];
        } else {
            timestamp = block.timestamp;
        }
        
        return (price, timestamp);
    }
    
    // Simulate flash loan attack scenario
    function flashLoanManipulation(address token, uint256 normalPrice, uint256 manipulatedPrice) external {
        // Set manipulated price
        manipulatedPrices[token] = manipulatedPrice;
        emit MaliciousActivity("FLASH_LOAN_START", token, manipulatedPrice);
        
        // In a real attack, malicious actions would happen here
        
        // Restore normal price
        manipulatedPrices[token] = normalPrice;
        emit MaliciousActivity("FLASH_LOAN_END", token, normalPrice);
    }
    
    // Simulate gradual price manipulation
    function gradualManipulation(address token, uint256 startPrice, uint256 endPrice, uint256 steps) external {
        uint256 priceStep = (endPrice > startPrice) 
            ? (endPrice - startPrice) / steps
            : (startPrice - endPrice) / steps;
            
        emit MaliciousActivity("GRADUAL_MANIPULATION_START", token, startPrice);
        
        if (endPrice > startPrice) {
            manipulatedPrices[token] = startPrice + (priceStep * steps);
        } else {
            manipulatedPrices[token] = startPrice - (priceStep * steps);
        }
        
        emit MaliciousActivity("GRADUAL_MANIPULATION_END", token, manipulatedPrices[token]);
    }
    
    // Reset all malicious behaviors
    function reset() external {
        globalRevert = false;
        infiniteLoop = false;
        gasConsumption = 0;
        emit MaliciousActivity("RESET", address(0), 0);
    }
    
    // Utility function to check if oracle is behaving maliciously
    function isMalicious(address token) external view returns (bool) {
        return globalRevert || 
               shouldRevert[token] || 
               shouldReturnStale[token] || 
               manipulatedPrices[token] > 0 ||
               infiniteLoop ||
               gasConsumption > 0;
    }
}
