//SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import { AUTH_ADMIN_ERR } from "./Errors.sol";

contract OwnerBaseInitializable {
    bool private isOwnerInitialized;
    address private adminUser;

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    modifier onlyInitialized() {
        require(isOwnerInitialized, "Not initialized");
        _;
    }

    modifier onlyNonInitialized() {
        require(!isOwnerInitialized, "Already initialized");
        _;
    }

    constructor() {}

    function initializeOwnable(address _adminUser) public onlyNonInitialized {
        // todo: check not zero address
        adminUser = _adminUser;
        isOwnerInitialized = true;
    }

    function setOwner(address newAdmin) public onlyOwner onlyInitialized {
        // todo: check not zero address
        adminUser = newAdmin;
    }

    function isAdmin(
        address maybeAdminUser
    ) public view onlyInitialized returns (bool isAdminAddress) {
        isAdminAddress = maybeAdminUser == adminUser;
    }

    function _checkOwner() internal view virtual onlyInitialized {
        if (!isAdmin(msg.sender)) {
            revert(AUTH_ADMIN_ERR);
        }
    }
}
