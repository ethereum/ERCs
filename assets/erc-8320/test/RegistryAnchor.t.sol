// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {RegistryAnchor} from "../contracts/RegistryAnchor.sol";
import {IRegistryAnchor} from "../contracts/interfaces/IRegistryAnchor.sol";

contract RegistryAnchorTest is Test {
    RegistryAnchor anchor;

    address owner = makeAddr("owner");
    address stranger = makeAddr("stranger");
    address registryA = makeAddr("registryA");
    address registryB = makeAddr("registryB");

    event RegistrySet(address indexed registry, address indexed asset, bool approved);

    function setUp() public {
        anchor = new RegistryAnchor(owner);
    }

    function test_Owner() public view {
        assertEq(anchor.owner(), owner);
    }

    function test_SetRegistryApproveListsAndEmits() public {
        vm.expectEmit(true, true, false, true, address(anchor));
        emit RegistrySet(registryA, address(anchor), true);
        vm.prank(owner);
        anchor.setRegistry(registryA, true);

        assertTrue(anchor.isRegistryApproved(registryA));
        address[] memory registries = anchor.getRegistries();
        assertEq(registries.length, 1);
        assertEq(registries[0], registryA);
    }

    function test_UnapproveRemovesFromList() public {
        vm.startPrank(owner);
        anchor.setRegistry(registryA, true);
        anchor.setRegistry(registryB, true);
        anchor.setRegistry(registryA, false);
        vm.stopPrank();

        assertFalse(anchor.isRegistryApproved(registryA));
        assertTrue(anchor.isRegistryApproved(registryB));
        address[] memory registries = anchor.getRegistries();
        assertEq(registries.length, 1);
        assertEq(registries[0], registryB);
    }

    function test_SetRegistryOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        anchor.setRegistry(registryA, true);
    }

    function test_SupportsInterface() public view {
        assertTrue(anchor.supportsInterface(type(IRegistryAnchor).interfaceId));
        assertTrue(anchor.supportsInterface(type(IERC165).interfaceId));
        assertFalse(anchor.supportsInterface(0xffffffff));
    }
}
