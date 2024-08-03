// SPDX-License-Identifier: CC0-1.0
import "@openzeppelin/contracts-upgradable/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts-upgradalbe/access/OwnableUpgradeable.sol";

pragma solidity ^0.8.0;

contract MockERC20 is ERC20Burnable, Ownable {
    uint256 numTokens;

    constructor() ERC20("Mock", "MCK") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) public {
        require(to != address(0), "MockERC20->mint: Address not specified");
        require(amount != 0, "MockERC20->mint: amount not specified");
        _mint(to, amount);
    }
}
