// SPDX-License-Identifier: CC0-1.0
// src/oracles/ComposedConversionOracle.sol
pragma solidity ^0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IConversionOracle} from "../IConversionOracle.sol";
import {AggregatorV3Interface} from "./ChainlinkConversionOracle.sol";

/// @notice Compone dos feeds Chainlink-compatible en un unico
///         IConversionOracle (ej: UVA/ARS x ARS/USD para liquidar un lease
///         indexado a UVA en USDC).
/// @dev asOf = min(asOf de ambos feeds): la frescura de una composicion es
///      la del input mas viejo, nunca mejor que su peor componente.
contract ComposedConversionOracle is IConversionOracle {
    using Math for uint256;

    // S1-02: misma cota defensiva que ChainlinkConversionOracle, aplicada
    // a ambos feeds compuestos.
    uint8 internal constant MAX_SANE_DECIMALS = 30;

    AggregatorV3Interface public immutable feedA;
    AggregatorV3Interface public immutable feedB;
    uint8 public immutable feedADecimals;
    uint8 public immutable feedBDecimals;
    bool public immutable invertB;
    uint8 public immutable paymentAssetDecimals;

    error InvalidAnswer();
    error IncompleteRound();
    error DecimalsOutOfRange();
    error DecimalsChanged();

    constructor(address feedA_, address feedB_, bool invertB_, uint8 paymentAssetDecimals_) {
        feedA = AggregatorV3Interface(feedA_);
        feedB = AggregatorV3Interface(feedB_);
        uint8 fdA = feedA.decimals();
        uint8 fdB = feedB.decimals();
        if (fdA > MAX_SANE_DECIMALS || fdB > MAX_SANE_DECIMALS) revert DecimalsOutOfRange(); // S1-02
        feedADecimals = fdA;
        feedBDecimals = fdB;
        invertB = invertB_;
        paymentAssetDecimals = paymentAssetDecimals_;
    }

    function latestRate() external view returns (uint256 rate, uint64 asOf) {
        (uint256 normA, uint256 updatedAtA) = _normalized(feedA, feedADecimals);
        (uint256 normB, uint256 updatedAtB) = _normalized(feedB, feedBDecimals);

        // S2-08: guard explicito antes de dividir, en vez de depender del
        // guard implicito (division por cero) que ya tiene Math.mulDiv
        // internamente — mismo criterio de error que el resto del
        // contrato (feed invalido = InvalidAnswer, sin importar en que
        // paso se detecto).
        if (invertB && normB == 0) revert InvalidAnswer();

        // Ambos normalizados a 1e18 antes de componer; invertB divide en
        // lugar de multiplicar cuando el segundo feed cotiza en sentido
        // inverso al necesario (ej: USD/ARS en vez de ARS/USD).
        uint256 composed1e18 = invertB ? normA.mulDiv(1e18, normB) : normA.mulDiv(normB, 1e18);

        rate = composed1e18.mulDiv(10 ** paymentAssetDecimals, 1e18);
        asOf = uint64(Math.min(updatedAtA, updatedAtB));
    }

    function _normalized(AggregatorV3Interface feed_, uint8 feedDecimals_)
        internal
        view
        returns (uint256 norm, uint256 updatedAt)
    {
        // S2-02: mismo criterio que ChainlinkConversionOracle — releer y
        // comparar decimals() en cada lectura, barato frente al riesgo
        // de mis-scaling silencioso si el feed envuelto cambia de
        // convencion post-deploy.
        if (feed_.decimals() != feedDecimals_) revert DecimalsChanged();

        (, int256 answer,, uint256 updatedAt_,) = feed_.latestRoundData();
        if (answer <= 0) revert InvalidAnswer();
        if (updatedAt_ == 0) revert IncompleteRound();
        norm = uint256(answer).mulDiv(1e18, 10 ** feedDecimals_);
        updatedAt = updatedAt_;
    }
}
