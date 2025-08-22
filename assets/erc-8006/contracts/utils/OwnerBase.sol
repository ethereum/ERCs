//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.30;

import { AUTH_ADMIN_ERR } from "../constants/ErrorCodes.sol";

contract OwnerBase {
    address private adminUser;

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    constructor(address _adminUser) {
        adminUser = _adminUser;
    }

    function setOwner(address newAdmin) public onlyOwner {
        adminUser = newAdmin;
    }

    function isAdmin(address maybeAdminUser) public view returns (bool isAdminAddress) {
        isAdminAddress = maybeAdminUser == adminUser;
    }

    function _checkOwner() internal view virtual {
        if (!isAdmin(msg.sender)) {
            revert(AUTH_ADMIN_ERR);
        }
    }
}
