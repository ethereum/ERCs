// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract MockPriceOracle is Ownable {
    struct PricePoint {
        uint256 price;
        uint256 timestamp;
    }
    
    mapping(address => PricePoint[]) private priceHistory;
    mapping(address => uint256) private currentPrices;
    
    constructor() Ownable(msg.sender) {}
    
    function setPrice(address token, uint256 price) external onlyOwner {
        currentPrices[token] = price;
        priceHistory[token].push(PricePoint({
            price: price,
            timestamp: block.timestamp
        }));
    }
    
    function getPrice(address token) external view returns (uint256) {
        return currentPrices[token];
    }

    function getPriceHistory(address token, uint256 startTime, uint256 endTime) 
        external 
        view 
        returns (uint256[] memory prices, uint256[] memory timestamps) 
    {
        PricePoint[] storage history = priceHistory[token];
        uint256 count = 0;
        
        // Count valid entries
        for(uint256 i = 0; i < history.length; i++) {
            if(history[i].timestamp >= startTime && history[i].timestamp <= endTime) {
                count++;
            }
        }
        
        prices = new uint256[](count);
        timestamps = new uint256[](count);
        uint256 index = 0;
        
        // Fill arrays
        for(uint256 i = 0; i < history.length && index < count; i++) {
            if(history[i].timestamp >= startTime && history[i].timestamp <= endTime) {
                prices[index] = history[i].price;
                timestamps[index] = history[i].timestamp;
                index++;
            }
        }
        
        return (prices, timestamps);
    }
}
