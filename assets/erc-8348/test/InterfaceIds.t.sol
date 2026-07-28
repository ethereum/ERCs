// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {IFinancialLease} from "../src/IFinancialLease.sol";
import {IFinancialLeaseAnchored} from "../src/IFinancialLeaseAnchored.sol";
import {IFinancialLeaseAssetBound} from "../src/IFinancialLeaseAssetBound.sol";

/// @dev Fija los interfaceId de ERC-165 de la spec como constantes: si una
///      firma cambia (se agrega/quita/renombra una función del core o de
///      una extensión), el interfaceId resultante cambia y este test falla
///      en vez de dejar pasar en silencio una detección ERC-165 rota.
contract InterfaceIdsTest is Test {
    bytes4 constant IFINANCIAL_LEASE_ID = 0xe3e0ac48;
    bytes4 constant IFINANCIAL_LEASE_ANCHORED_ID = 0x09fce36a;
    bytes4 constant IFINANCIAL_LEASE_ASSET_BOUND_ID = 0xf71550a8;

    FinancialLease lease;

    function setUp() public {
        lease = new FinancialLease();
    }

    function test_interfaceIds() public pure {
        bytes4 core = type(IFinancialLease).interfaceId;
        bytes4 anchored = type(IFinancialLeaseAnchored).interfaceId;
        bytes4 assetBound = type(IFinancialLeaseAssetBound).interfaceId;

        console2.logBytes4(core);
        console2.logBytes4(anchored);
        console2.logBytes4(assetBound);

        assertEq(core, IFINANCIAL_LEASE_ID, "IFinancialLease.interfaceId cambio de valor");
        assertEq(anchored, IFINANCIAL_LEASE_ANCHORED_ID, "IFinancialLeaseAnchored.interfaceId cambio de valor");
        assertEq(assetBound, IFINANCIAL_LEASE_ASSET_BOUND_ID, "IFinancialLeaseAssetBound.interfaceId cambio de valor");
    }

    function test_supportsInterface_core() public view {
        assertTrue(lease.supportsInterface(IFINANCIAL_LEASE_ID), "debe declarar soporte de IFinancialLease");
    }

    function test_supportsInterface_anchored() public view {
        assertTrue(
            lease.supportsInterface(IFINANCIAL_LEASE_ANCHORED_ID), "debe declarar soporte de IFinancialLeaseAnchored"
        );
    }

    function test_supportsInterface_erc165AndErc721() public view {
        assertTrue(lease.supportsInterface(0x01ffc9a7), "debe declarar soporte de ERC-165");
        assertTrue(lease.supportsInterface(0x80ac58cd), "debe declarar soporte de ERC-721");
    }

    /// @dev AssetBound es una extensión opcional que la referencia NO
    ///      implementa todavía (fuera de alcance): el contrato no debe
    ///      anunciar soporte para funciones que no expone.
    function test_supportsInterface_assetBoundNotAdvertised() public view {
        assertFalse(
            lease.supportsInterface(IFINANCIAL_LEASE_ASSET_BOUND_ID),
            "no debe declarar soporte de una extension no implementada"
        );
    }
}
