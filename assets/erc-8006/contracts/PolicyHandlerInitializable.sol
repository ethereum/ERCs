//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { IPolicyHandlerInitializable } from "./Interfaces.sol";
import { PolicyHandler } from "./PolicyHandler.sol";

contract PolicyHandlerInitializable is IPolicyHandlerInitializable, PolicyHandler {
    constructor() PolicyHandler(address(0)) {
        // note: can not revert since no instance deploy happens then; which is required to deploy to make clone from
        // revert("Not supposed to be created through constructor");
    }

    // note: special init method used when this instance is created via clone factory pattern or proxy pattern
    function initialize(address adminUser) public override(IPolicyHandlerInitializable) {
        initializeOwnable(adminUser);
    }
}
