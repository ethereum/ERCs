// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployDocumentTokensScript} from "script/DeployDocumentTokens.s.sol";
import {ERC20DocumentToken} from "src/ERC20DocumentToken.sol";
import {ERC721DocumentToken} from "src/ERC721DocumentToken.sol";

contract DeployDocumentTokensScriptTest is Test {
    function testDeploySetsOwnerAndMetadata() public {
        DeployDocumentTokensScript script = new DeployDocumentTokensScript();
        address initialOwner = address(0xA11CE);

        (ERC20DocumentToken erc20, ERC721DocumentToken erc721) = script.deploy(initialOwner);

        assertEq(erc20.owner(), initialOwner);
        assertEq(erc721.owner(), initialOwner);

        assertEq(erc20.name(), "ERC1643 Reference ERC20");
        assertEq(erc20.symbol(), "R1643");

        assertEq(erc721.name(), "ERC1643 Reference ERC721");
        assertEq(erc721.symbol(), "R1643NFT");

        assertEq(address(script.erc20Token()), address(erc20));
        assertEq(address(script.erc721Token()), address(erc721));
    }
}
