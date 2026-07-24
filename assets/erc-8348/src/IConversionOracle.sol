// SPDX-License-Identifier: CC0-1.0
// src/IConversionOracle.sol
pragma solidity ^0.8.24;

/// @notice Resuelve unidades de cuenta → payment asset, escalado 1e18
interface IConversionOracle {
    function latestRate() external view returns (uint256 rate, uint64 asOf);
}
