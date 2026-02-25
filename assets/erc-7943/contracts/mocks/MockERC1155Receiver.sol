// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MockERC1155Receiver is IERC1155Receiver {
    bool public shouldReject = false;
    bytes4 public constant ERC1155_RECEIVER_MAGIC = bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    bytes4 public constant ERC1155_BATCH_RECEIVER_MAGIC = bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"));

    function setShouldReject(bool _reject) external {
        shouldReject = _reject;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public view override returns (bytes4) {
        if (shouldReject) {
            return bytes4(0);
        } else {
            return ERC1155_RECEIVER_MAGIC;
        }
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public view override returns (bytes4) {
        if (shouldReject) {
            return bytes4(0);
        } else {
            return ERC1155_BATCH_RECEIVER_MAGIC;
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}