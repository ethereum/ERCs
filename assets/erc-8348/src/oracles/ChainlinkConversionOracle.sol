// SPDX-License-Identifier: CC0-1.0
// src/oracles/ChainlinkConversionOracle.sol
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "../IConversionOracle.sol";

/// @notice Subconjunto minimo de AggregatorV3Interface (declarado
///         localmente para no depender del paquete de Chainlink).
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice Adapta un feed Chainlink-compatible a IConversionOracle.
/// @dev rate = cuantas base units del payment asset equivalen a 1e18
///      unidades de cuenta: rate = answer * 10^payDecimals / 10^feedDecimals.
///      No enforza staleness: esa politica vive en el lease
///      (maxOracleStaleness), no en el adaptador.
contract ChainlinkConversionOracle is IConversionOracle {
    using Math for uint256;

    // S1-02: cota defensiva sobre feedDecimals — muy por encima de
    // cualquier feed real (todos usan <=18), deja margen de sobra para
    // que `10 ** feedDecimals` combinado con `10 ** paymentAssetDecimals`
    // en el mulDiv de latestRate() nunca se acerque a overflow de
    // uint256 (~1.16e77 en 10^77).
    uint8 internal constant MAX_SANE_DECIMALS = 30;

    AggregatorV3Interface public immutable feed;
    uint8 public immutable feedDecimals;
    uint8 public immutable paymentAssetDecimals;

    error InvalidAnswer();
    error IncompleteRound();
    error DecimalsOutOfRange();
    error DecimalsChanged();

    constructor(address feed_, uint8 paymentAssetDecimals_) {
        feed = AggregatorV3Interface(feed_);
        uint8 fd = feed.decimals();
        if (fd > MAX_SANE_DECIMALS) revert DecimalsOutOfRange(); // S1-02
        feedDecimals = fd;
        paymentAssetDecimals = paymentAssetDecimals_;
    }

    function latestRate() external view returns (uint256 rate, uint64 asOf) {
        // S2-02: el feed envuelto "deberia" ser Chainlink-compatible con
        // decimales inmutables (asi lo documenta el NatSpec del
        // contrato), pero no hay forma de exigirlo on-chain salvo
        // volver a leerlo y comparar. Costo: un staticcall extra por
        // lectura — barato (decimals() es una view trivial en cualquier
        // feed real) frente al riesgo que cierra: mis-scaling silencioso
        // sin revert ni evento si el feed envuelto cambia de convencion.
        if (feed.decimals() != feedDecimals) revert DecimalsChanged();

        (, int256 answer,, uint256 updatedAt,) = feed.latestRoundData();
        if (answer <= 0) revert InvalidAnswer();
        if (updatedAt == 0) revert IncompleteRound();

        rate = uint256(answer).mulDiv(10 ** paymentAssetDecimals, 10 ** feedDecimals);
        asOf = uint64(updatedAt);
    }
}
