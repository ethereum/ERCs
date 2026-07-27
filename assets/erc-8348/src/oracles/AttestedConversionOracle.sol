// SPDX-License-Identifier: CC0-1.0
// src/oracles/AttestedConversionOracle.sol
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IConversionOracle} from "../IConversionOracle.sol";

/// @notice Adaptador para indices sin feed on-chain (ej. UVA, UF): un
///         atestador autorizado publica la tasa periodicamente.
/// @dev Trust model: la fuente de verdad es un atestador confiable
///      designado por el owner, NO un mecanismo descentralizado. Usar
///      solo cuando no exista un feed verificable on-chain para el indice
///      de referencia, y dejar este supuesto explicito en la due
///      diligence del lease que consuma este oraculo.
contract AttestedConversionOracle is IConversionOracle, Ownable {
    address public attester;
    uint256 public rate;
    uint64 public asOf;

    event RateAttested(uint256 rate, uint64 asOf);
    event AttesterUpdated(address indexed oldAttester, address indexed newAttester);

    error NotAttester();
    error NotYetAttested();

    constructor(address owner_, address attester_) Ownable(owner_) {
        attester = attester_;
    }

    function setAttester(address newAttester) external onlyOwner {
        emit AttesterUpdated(attester, newAttester);
        attester = newAttester;
    }

    function attest(uint256 newRate) external {
        if (msg.sender != attester) revert NotAttester();
        rate = newRate;
        asOf = uint64(block.timestamp);
        emit RateAttested(newRate, asOf);
    }

    function latestRate() external view returns (uint256, uint64) {
        if (asOf == 0) revert NotYetAttested();
        return (rate, asOf);
    }
}
