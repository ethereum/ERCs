// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {WhitelistRuleEngine} from "../src/engine/WhitelistRuleEngine.sol";
import {RestrictedToken} from "../src/engine/RestrictedToken.sol";

/// @notice Deploys a standalone `WhitelistRuleEngine` and a `RestrictedToken` bound to it.
contract WhitelistRuleEngineScript is Script {
    /**
     * @notice Broadcasts the deployment of the engine and a token bound to it, logging both addresses.
     */
    function run() public {
        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");
        uint256 initialSupply = vm.envUint("TOKEN_INITIAL_SUPPLY");

        vm.startBroadcast();

        WhitelistRuleEngine engine = new WhitelistRuleEngine();
        RestrictedToken token = new RestrictedToken(name, symbol, initialSupply, engine);

        console.log("WhitelistRuleEngine deployed at:", address(engine));
        console.log("RestrictedToken deployed at:    ", address(token));
        console.log("Engine owner:                   ", engine.owner());
        console.log("Token owner:                    ", token.owner());
        console.log("Initial supply:                 ", token.totalSupply());

        vm.stopBroadcast();
    }
}
