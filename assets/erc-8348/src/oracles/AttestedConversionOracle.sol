// SPDX-License-Identifier: CC0-1.0
// src/oracles/AttestedConversionOracle.sol
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IConversionOracle} from "../IConversionOracle.sol";

/// @notice Adapter for indices with no on-chain feed (e.g. UVA, UF): an
///         authorized attester publishes the rate periodically.
/// @dev Trust model: the source of truth is a trusted attester
///      designated by the owner, NOT a decentralized mechanism. Use it
///      only when no verifiable on-chain feed exists for the reference
///      index, and state this assumption explicitly in the due
///      diligence of any lease that consumes this oracle.
contract AttestedConversionOracle is IConversionOracle, Ownable {
    address public attester;
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
        emit RateAttested(newRate, asOf);
    }

    function latestRate() external view returns (uint256, uint64) {
        if (asOf == 0) revert NotYetAttested();
        return (rate, asOf);
    }
}
