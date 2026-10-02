// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

function reverseList(uint256[] memory list) pure returns (uint256[] memory reversedList) {
    if (list.length == 0) return reversedList;

    uint256 left = 0;
    uint256 right = list.length - 1;

    while (left < right) {
        uint256 temp = list[left];
        list[left] = list[right];
        list[right] = temp;

        left++;
        right--;
    }

    reversedList = list;
}

function toUint(bytes32 value) pure returns (uint256 result) {
    result = uint256(value);
}
