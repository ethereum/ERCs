// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal mintable ERC-20 for TwoPhaseEscrow tests.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
