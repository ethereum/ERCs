// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.20;

contract TestFacet {
    event Bar();

    function foo() public {
        emit Bar();
    }

    function ping() public pure returns (string memory) {
        return "pong";
    }
}
