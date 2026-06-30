// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ERC20DocumentToken} from "src/ERC20DocumentToken.sol";
import {ERC721DocumentToken} from "src/ERC721DocumentToken.sol";

contract DeployDocumentTokensScript is Script {
    ERC20DocumentToken public erc20Token;
    ERC721DocumentToken public erc721Token;

    function deploy(address initialOwner)
        public
        returns (ERC20DocumentToken deployedErc20, ERC721DocumentToken deployedErc721)
    {
        deployedErc20 = new ERC20DocumentToken("ERC1643 Reference ERC20", "R1643", initialOwner);
        deployedErc721 = new ERC721DocumentToken("ERC1643 Reference ERC721", "R1643NFT", initialOwner);

        erc20Token = deployedErc20;
        erc721Token = deployedErc721;
    }

    function run() public returns (ERC20DocumentToken deployedErc20, ERC721DocumentToken deployedErc721) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address initialOwner = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        (deployedErc20, deployedErc721) = deploy(initialOwner);
        vm.stopBroadcast();
    }
}
