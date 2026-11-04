// SPDX-License-Identifier: CC0-1.0
// src/IConversionOracleHistory.sol
pragma solidity ^0.8.24;

/// @notice Optional companion to IConversionOracle: lets a consumer verify
///         on-chain whether the oracle was continuously fresh over a past
///         window, i.e. since when the index has been usable without a gap.
/// @dev The lease uses it to measure the recovery grace of the payment-path
///      liveness rule from on-chain data (round `updatedAt` for
///      Chainlink-style feeds, recording time for attested indices), never
///      from a timestamp the counterparty asserts.
interface IConversionOracleHistory {
    /// @notice True iff, at every instant t in [from, to], the observation
    ///         actually in force at t (the latest one recorded at or before t,
    ///         valid or not) was usable for conversion and no older than
    ///         `tolerance`. An unusable observation in force inside the window
    ///         makes the result false, even if an earlier usable observation
    ///         was still within tolerance.
    /// @dev Fail-closed: returns false when the history the oracle can walk
    ///      does not reach back to `from` (including when the walk hits its
    ///      round cap). MUST NOT revert for a well-formed window
    ///      (from <= to <= block.timestamp). The reference adapters catch
    ///      reverting feed calls; return data that fails to decode cannot be
    ///      caught in Solidity and would still revert.
    function continuouslyFresh(uint64 from, uint64 to, uint64 tolerance) external view returns (bool);
}
