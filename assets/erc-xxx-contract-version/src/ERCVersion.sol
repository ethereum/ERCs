// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERCVersion} from "./IERCVersion.sol";

abstract contract ERCVersion is IERCVersion, ERC165 {
    string public constant VERSION = "1.0.0";

    function version() external pure virtual returns (string memory) {
        return VERSION;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERCVersion).interfaceId || super.supportsInterface(interfaceId);
    }
}
