// SPDX-License-Identifier: CC0-1.0
pragma solidity =0.8.20;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./AccessLayers.sol";
import "./LibAccessLayers.sol";

contract Protected is TransparentUpgradeableProxy, AccessLayers {
    uint256 balance = 10000000 ether;

    constructor(
        address initialOwner,
        LibAccessLayers.LayerStruct[] memory layers,
        address initialImplementation
    ) TransparentUpgradeableProxy(initialImplementation, initialOwner, "") {
        LibAccessLayers.setLayers(layers);
    }

    event Transfer(address from, address to, uint256 amount);

    fallback() external payable override layers(msg.sig, msg.sender, msg.data, msg.value) {
        // _delegate(_implementation()); <- this method will not return to solidity :(
        (bool success, bytes memory result) = _implementation().delegatecall(msg.data);
        require(success, string(result));
    }

    receive() external payable {
        // custom function code
    }
}
