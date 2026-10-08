// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice Minimal ERC-1155 control token for the conformance fixture.
/// The issuer (owner) grants a role by minting and revokes it by burning
/// without the holder's cooperation — the issuer-side kill switch described
/// in the ERC's Security Considerations.
contract ERC1155ControlToken is ERC1155, Ownable {
    constructor() ERC1155("") Ownable(msg.sender) {}

    function mint(address to, uint256 id, uint256 amount) external onlyOwner {
        _mint(to, id, amount, "");
    }

    function burnByIssuer(address account, uint256 id) external onlyOwner {
        _burn(account, id, balanceOf(account, id));
    }
}
