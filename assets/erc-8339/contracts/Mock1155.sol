// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @notice Minimal mintable ERC-1155 for TwoPhaseEscrow tests.
contract Mock1155 is ERC1155 {
    constructor() ERC1155("") { }

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}
