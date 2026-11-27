// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {FinancialLease} from "../src/FinancialLease.sol";
import {IFinancialLease} from "../src/IFinancialLease.sol";
import {IFinancialLeaseAnchored} from "../src/IFinancialLeaseAnchored.sol";
import {IFinancialLeaseAssetBound} from "../src/IFinancialLeaseAssetBound.sol";

/// @dev Pins the spec's ERC-165 interfaceIds as constants: if a
///      signature changes (a function of the core or of an extension is added/removed/renamed),
///      the resulting interfaceId changes and this test fails
///      instead of silently letting a broken ERC-165 detection through.
contract InterfaceIdsTest is Test {
    bytes4 constant IFINANCIAL_LEASE_ID = 0xf6b0f493;
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

        assertEq(core, IFINANCIAL_LEASE_ID, "IFinancialLease.interfaceId changed value");
        assertEq(anchored, IFINANCIAL_LEASE_ANCHORED_ID, "IFinancialLeaseAnchored.interfaceId changed value");
        assertEq(assetBound, IFINANCIAL_LEASE_ASSET_BOUND_ID, "IFinancialLeaseAssetBound.interfaceId changed value");
    }

    function test_supportsInterface_core() public view {
        assertTrue(lease.supportsInterface(IFINANCIAL_LEASE_ID), "must declare support for IFinancialLease");
    }

    function test_supportsInterface_anchored() public view {
        assertTrue(
            lease.supportsInterface(IFINANCIAL_LEASE_ANCHORED_ID), "must declare support for IFinancialLeaseAnchored"
        );
    }

    function test_supportsInterface_erc165AndErc721() public view {
        assertTrue(lease.supportsInterface(0x01ffc9a7), "must declare support for ERC-165");
        assertTrue(lease.supportsInterface(0x80ac58cd), "must declare support for ERC-721");
    }

    /// @dev AssetBound is an optional extension that the reference does NOT
    ///      implement yet (out of scope): the contract must not
    ///      advertise support for functions it does not expose.
    function test_supportsInterface_assetBoundNotAdvertised() public view {
        assertFalse(
            lease.supportsInterface(IFINANCIAL_LEASE_ASSET_BOUND_ID),
            "must not declare support for an unimplemented extension"
        );
    }
}
