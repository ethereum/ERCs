// SPDX-License-Identifier: CC0-1.0
// src/oracles/AttestedConversionOracle.sol
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IConversionOracle} from "../IConversionOracle.sol";
import {IConversionOracleHistory} from "../IConversionOracleHistory.sol";
import {FreshnessHistory} from "./FreshnessHistory.sol";

/// @notice Adapter for indices with no on-chain feed (e.g. UVA, UF): an
///         authorized attester publishes the rate periodically.
/// @dev Trust model: the source of truth is a trusted attester
///      designated by the owner, NOT a decentralized mechanism. Use it
///      only when no verifiable on-chain feed exists for the reference
///      index, and state this assumption explicitly in the due
///      diligence of any lease that consumes this oracle.
contract AttestedConversionOracle is IConversionOracle, IConversionOracleHistory, Ownable {
    address public attester;
    /// @dev Recording time of every attestation (append-only), so freshness
    ///      over a past window can be verified on-chain. asOf is the recording
    ///      time, not the off-chain observation time: a publication delay by the
    ///      attester is not visible on-chain, and the attester is trusted to
    ///      record each value promptly (see the spec's recording bound). Zero
    ///      rates are rejected, so every stored entry is usable.
    uint64[] public attestationTimes;
    uint256 public rate;
    uint64 public asOf;

    event RateAttested(uint256 rate, uint64 asOf);
    event AttesterUpdated(address indexed oldAttester, address indexed newAttester);

    error NotAttester();
    error NotYetAttested();
    error InvalidRate();

    constructor(address owner_, address attester_) Ownable(owner_) {
        attester = attester_;
    }

    function setAttester(address newAttester) external onlyOwner {
        emit AttesterUpdated(attester, newAttester);
        attester = newAttester;
    }

    function attest(uint256 newRate) external {
        if (msg.sender != attester) revert NotAttester();
        // S2-03: attesting 0 did not revert (asOf becomes != 0, satisfying
        // NotYetAttested) but left rate = 0 as an implicit denominator
        // -> division by zero on every future pay() -> full DoS until the
        // next valid attestation. The other two adapters already validate
        // answer > 0; this was the only one missing it.
        if (newRate == 0) revert InvalidRate();
        rate = newRate;
        asOf = uint64(block.timestamp);
        attestationTimes.push(asOf);
        emit RateAttested(newRate, asOf);
    }

    function latestRate() external view returns (uint256, uint64) {
        if (asOf == 0) revert NotYetAttested();
        return (rate, asOf);
    }

    function attestationCount() external view returns (uint256) {
        return attestationTimes.length;
    }

    /// @inheritdoc IConversionOracleHistory
    function continuouslyFresh(uint64 from, uint64 to, uint64 tolerance) external view returns (bool) {
        return FreshnessHistory.walkStored(attestationTimes, from, to, tolerance);
    }
}
