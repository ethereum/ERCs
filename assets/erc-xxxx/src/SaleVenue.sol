// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {LaunchEscrow} from "./LaunchEscrow.sol";

/// @title Minimal fixed-price sale venue.
/// @notice Demonstrates the venue side of the standard: it takes buyer funds
///         into escrow rather than forwarding them to the deployer, and reports
///         both purchases and subsequent sales so net contribution stays exact.
///         A bonding curve differs only in how `tokens` is priced.
contract SaleVenue {
    LaunchEscrow public immutable escrow;
    bytes32 public launchId;
    uint256 public price; // wei per whole token

    constructor(LaunchEscrow escrow_) {
        escrow = escrow_;
    }

    function open(
        address token,
        address deployer,
        uint64  releaseStart,
        uint64  releaseEnd,
        uint256 price_
    ) external payable returns (bytes32) {
        require(launchId == bytes32(0), "already open");
        require(price_ > 0, "price must be non-zero");
        price = price_;
        launchId = escrow.registerLaunchNative{value: msg.value}(token, deployer, releaseStart, releaseEnd);
        return launchId;
    }

    function buy() external payable {
        require(msg.value > 0, "no value");
        uint256 tokens = msg.value / price;
        escrow.recordPurchase{value: msg.value}(launchId, msg.sender, msg.value, tokens);
    }

    /// @notice Report value a buyer realised by selling on a secondary market.
    function reportSale(address buyer, uint256 realised) external {
        escrow.recordSale(launchId, buyer, realised);
    }
}
