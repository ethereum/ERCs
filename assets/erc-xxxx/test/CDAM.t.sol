// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {StaticCallTransfer} from "src/StaticCallTransfer.sol";
import {AccessDapp} from "src/test/AccessDapp.sol";
import {Dapp} from "src/test/Dapp.sol";
import {IAccessDapp} from "src/test/IAccessDapp.sol";

contract CDAM is Test {
    StaticCallTransfer public staticCallTransfer;
    AccessDapp public accessDapp;
    Dapp public dapp;

    function setUp() public {
        staticCallTransfer = new StaticCallTransfer();
        accessDapp = new AccessDapp();
        dapp = new Dapp(address(staticCallTransfer));
    }

    function test_getCustomData() public view {
        bytes memory data = abi.encodeWithSelector(IAccessDapp.private_data.selector);
        bytes memory result = staticCallTransfer.getCustomData(address(dapp), address(accessDapp), data);
        (address private_data) = abi.decode(result, (address));
        assertEq(private_data, address(this));
    }
}