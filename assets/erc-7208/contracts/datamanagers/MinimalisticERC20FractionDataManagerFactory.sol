// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Create2.sol";
import "./MinimalisticERC20FractionDataManager.sol";

contract MinimalisticERC20FractionDataManagerFactory {
    function deploy(uint256 id) external returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, id));
        return Create2.deploy(0, salt, type(MinimalisticERC20FractionDataManager).creationCode);
    }
}
