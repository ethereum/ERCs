// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract RegistryENSName {
    function _formENSName(
        uint256 order,
        string memory name,
        address tokenContract
    ) internal pure returns (string memory) {
        string memory nameComponent = (bytes(name).length > 0)
            ? string(abi.encodePacked(name, "-"))
            : "";

        return
            string(
                abi.encodePacked(
                    Strings.toString(order),
                    "-",
                    nameComponent,
                    Strings.toHexString(uint160(tokenContract), 20)
                )
            );
    }
}
