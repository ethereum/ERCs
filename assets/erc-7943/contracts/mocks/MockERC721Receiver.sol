// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract MockERC721Receiver is IERC721Receiver {
    bool public shouldReject = false;
    bytes4 public constant ERC721_RECEIVER_MAGIC = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));

    function setShouldReject(bool _reject) external {
        shouldReject = _reject;
    }

    function onERC721Received(address, address, uint256, bytes memory) public view override returns (bytes4) {
        if (shouldReject) {
            return bytes4(0);
        } else {
            return ERC721_RECEIVER_MAGIC;
        }
    }
}