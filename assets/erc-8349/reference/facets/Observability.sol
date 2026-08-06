// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { LibCento as lc } from "../libraries/LibCento.sol";
import { bitmap256 } from "../libraries/LibBitmap.sol";
import { CentoStorage as CS } from "../structs/CentoStorage.sol";
import { Facet } from "../structs/Facet.sol";
import { IERC165 } from "../interfaces/IERC165.sol";
import { IObservability } from "../interfaces/IObservability.sol";

/// @title Observability
/// @notice Facet implementing protocol introspection interfaces.
contract Observability is IERC165, IObservability {

    /// @inheritdoc IObservability
    function getFacets() external override view returns (address[] memory result) {
        CS storage cs = lc._cs();
        uint8 index; uint256 i;
        bitmap256 bitmap = cs.indexBitmap;
        result = new address[](bitmap.countFilledSlots());
        while (bitmap256.unwrap(bitmap) != 0) {
            (bitmap, index) = bitmap.popFirstFilledSlot();
            result[i] = cs.facets[index];
            unchecked { ++i; }
        }
    }

    /// @inheritdoc IObservability
    function getFacetEntries() external override view returns (Facet[] memory result) {
        CS storage cs = lc._cs();
        uint8 index; uint256 i;
        bitmap256 bitmap = cs.indexBitmap;
        result = new Facet[](bitmap.countFilledSlots());
        while (bitmap256.unwrap(bitmap) != 0) {
            (bitmap, index) = bitmap.popFirstFilledSlot();
            result[i] = Facet({index: index, facet: cs.facets[index]});
            unchecked { ++i; }
        }
    }

    /// @inheritdoc IObservability
    function getFacetAt(uint8 index) external override view returns (address facet) {
        CS storage cs = lc._cs();
        facet = cs.facets[index];
    }

    /// @inheritdoc IObservability
    function getFacetCount() external override view returns (uint16 count) {
        CS storage cs = lc._cs();
        count = cs.indexBitmap.countFilledSlots();
    }

    /// @inheritdoc IObservability
    function getFirstFreeSlot() external override view returns (uint8 index) {
        CS storage cs = lc._cs();
        index = cs.indexBitmap.getFirstEmptySlot();
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 _interfaceId) external override view returns (bool) {
        CS storage cs = lc._cs();
        return cs.supportedInterfaces[_interfaceId];
    }
}
