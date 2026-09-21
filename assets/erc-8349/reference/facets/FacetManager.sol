// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { bitmap256 } from "../libraries/LibBitmap.sol";
import { CentoStorage as CS } from "../structs/CentoStorage.sol";
import { IFacetManager } from "../interfaces/IFacetManager.sol";
import { LibCento as lc } from "../libraries/LibCento.sol";
import { Facet } from "../structs/Facet.sol";


/// @title Facet Manager
/// @notice Facet responsible for protocol upgrades.
/// @dev Implements `IFacetManager` by atomically updating facets,
/// supported interfaces, and optional storage migrations.
contract FacetManager is IFacetManager { 

    /// @inheritdoc IFacetManager
    function atomicUpdate(
        Facet[]  calldata setF, 
        bytes4[] calldata addI, bytes4[] calldata remI,
        address       migrator, bytes    calldata _calldata
    ) external override {
        lc.enforceIsContractOwner();
        CS storage cs = lc._cs();
        uint256 i; bitmap256 bitmap = cs.indexBitmap;
        for (     ; i < setF.length;) {bitmap = lc.setFacet(setF[i].index, setF[i].facet, bitmap);  unchecked { ++i; }}
        for (i = 0; i < addI.length;) {cs.supportedInterfaces[addI[i]] = true;                      unchecked { ++i; }}
        for (i = 0; i < remI.length;) {cs.supportedInterfaces[remI[i]] = false;                     unchecked { ++i; }}
        cs.indexBitmap = bitmap;
        emit AtomicUpdate(setF, addI, remI, migrator, _calldata);
        lc.storageMigration(migrator, _calldata);
    }
}
