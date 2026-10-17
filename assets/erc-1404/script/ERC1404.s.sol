// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1404} from "../src/ERC1404.sol";

/**
 * @notice Deploys an `ERC1404` token from `TOKEN_NAME`, `TOKEN_SYMBOL` and `TOKEN_INITIAL_SUPPLY` env vars.
 */
contract ERC1404Script is Script {
    /**
     * @notice Broadcasts the deployment of a new `ERC1404` token and logs its address.
     */
    function run() public {
        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");
        uint256 initialSupply = vm.envUint("TOKEN_INITIAL_SUPPLY");

        vm.startBroadcast();

        ERC1404 token = new ERC1404(name, symbol, initialSupply);

        console.log("ERC1404 deployed at:", address(token));
        console.log("Owner:              ", token.owner());
        console.log("Initial supply:     ", token.totalSupply());

        vm.stopBroadcast();
    }
}
