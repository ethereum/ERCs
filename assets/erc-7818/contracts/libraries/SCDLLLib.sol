// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title An implementation of Sorted Circular Doubly Linked List with Sentinel node (SCDLLs) in Solidity.
// inspiration:
// https://github.com/o0ragman0o/LibCLL/
// https://github.com/vittominacori/solidity-linked-list/

library SCDLL {
    struct List {
        uint256 _size;
        mapping(uint256 node => mapping(bool direction => uint256 value)) _nodes;
        mapping(uint256 node => bytes data) _data;
    }

    uint8 private constant ONE_BIT = 1;
    uint8 private constant SENTINEL = 0;
    bool private constant PREV = false;
    bool private constant NEXT = true;
    bytes private constant EMPTY = ("");

    /// @notice Partitions the linked list in the specified direction.
    /// @dev This function creates an array `part` of size `listSize` containing indices of nodes
    /// in the linked list, traversing in the specified `direction` (NEXT or PREV).
    /// @param self The linked list state where the operation is performed.
    /// @param listSize The size of the list to partition.
    /// @param direction The direction of traversal: NEXT for forward, PREV for backward.
    /// @return part An array containing the indices of nodes in the partition.
    function _partition(
        List storage self,
        uint256 listSize,
        bool direction
    ) private view returns (uint256[] memory part) {
        unchecked {
            part = new uint256[](listSize);
            uint256 index;
            for (uint256 i = SENTINEL; i < listSize; i++) {
                part[i] = self._nodes[index][direction];
                index = part[i];
            }
        }
    }

    /// @notice Retrieves the path of node indices in the specified direction starting from the given index.
    /// @dev This function constructs an array `part` that holds indices of nodes in the linked list,
    /// starting from `index` and following the specified `direction` (NEXT or PREV) until reaching the end.
    /// @param self The linked list state where the operation is performed.
    /// @param index The starting index of the node.
    /// @param direction The direction of traversal: NEXT for forward, PREV for backward.
    /// @return part An array containing the indices of nodes from the starting index to the head (if traversing NEXT) or tail (if traversing PREV).
    function _path(List storage self, uint256 index, bool direction) private view returns (uint256[] memory part) {
        uint256 tmpSize = self._size;
        part = new uint[](tmpSize);
        uint256 counter;
        unchecked {
            while (index != SENTINEL && counter < tmpSize) {
                part[counter] = index;
                counter++;
                index = self._nodes[index][direction];
            }
        }
        // Resize the array to the actual count of elements using inline assembly.
        assembly {
            mstore(part, counter) // Set the array length to the actual count.
        }
    }

    /// @notice Traverses the linked list in the specified direction and returns a list of node indices.
    /// @dev This function constructs an array `list` that holds indices of nodes in the linked list,
    /// starting from either the head or the tail based on the `direction` parameter.
    /// @param self The linked list state where the operation is performed.
    /// @param direction The direction of traversal: true for forward (from head), false for backward (from tail).
    /// @return list An array containing the indices of nodes in the linked list, ordered according to the specified direction.
    function _traversal(List storage self, bool direction) private view returns (uint256[] memory list) {
        uint256 tmpSize = self._size;
        if (tmpSize > SENTINEL) {
            uint256 index;
            list = new uint256[](tmpSize);
            list[SENTINEL] = self._nodes[index][!direction];
            unchecked {
                for (uint256 i = tmpSize - 1; i > SENTINEL; i--) {
                    list[i] = self._nodes[index][direction];
                    index = list[i];
                }
            }
        }
    }

    /// @notice Check if a node exists in the linked list.
    /// @dev This function checks if a node exists in the linked list by the specified index.
    /// @param self The linked list.
    /// @param index The index of the node to check for existence.
    /// @return result if the node exists, false otherwise.
    function exist(List storage self, uint256 index) internal view returns (bool result) {
        result = (self._nodes[index][PREV] > SENTINEL || self._nodes[SENTINEL][NEXT] == index);
    }

    /// @notice Get the index of the next node in the list.
    /// @dev Accesses the `_nodes` mapping in the `List` structure to get the index of the next node.
    /// @param self The list.
    /// @param index The index of the current node.
    /// @return The index of the next node.
    function next(List storage self, uint256 index) internal view returns (uint256) {
        return self._nodes[index][NEXT];
    }

    /// @notice Get the index of the previous node in the list.
    /// @dev Accesses the `_nodes` mapping in the `List` structure to get the index of the previous node.
    /// @param self The list.
    /// @param index The index of the current node.
    /// @return The index of the previous node.
    function previous(List storage self, uint256 index) internal view returns (uint256) {
        return self._nodes[index][PREV];
    }

    /// @notice Insert data into the linked list at the specified index.
    /// @dev This function inserts data into the linked list at the specified index.
    /// @param self The linked list.
    /// @param index The index at which to insert the data.
    /// @param data The data to insert.
    function insert(List storage self, uint256 index, bytes memory data) internal {
        if (!exist(self, index)) {
            uint256 tmpTail = self._nodes[SENTINEL][PREV];
            uint256 tmpHead = self._nodes[SENTINEL][NEXT];
            uint256 tmpSize = self._size;
            self._data[index] = data;
            if (tmpSize == SENTINEL) {
                self._nodes[SENTINEL][NEXT] = index;
                self._nodes[SENTINEL][PREV] = index;
                self._nodes[index][PREV] = SENTINEL;
                self._nodes[index][NEXT] = SENTINEL;
            } else if (index < tmpHead) {
                self._nodes[SENTINEL][NEXT] = index;
                self._nodes[tmpHead][PREV] = index;
                self._nodes[index][PREV] = SENTINEL;
                self._nodes[index][NEXT] = tmpHead;
            } else if (index > tmpTail) {
                self._nodes[SENTINEL][PREV] = index;
                self._nodes[tmpTail][NEXT] = index;
                self._nodes[index][PREV] = tmpTail;
                self._nodes[index][NEXT] = SENTINEL;
            } else {
                uint256 tmpCurr;
                if (index - tmpHead <= tmpTail - index) {
                    tmpCurr = tmpHead;
                    while (index > tmpCurr) {
                        tmpCurr = self._nodes[tmpCurr][NEXT];
                    }
                } else {
                    tmpCurr = tmpTail;
                    while (index < tmpCurr) {
                        tmpCurr = self._nodes[tmpCurr][PREV];
                    }
                }
                uint256 tmpPrev = self._nodes[tmpCurr][PREV];
                self._nodes[tmpPrev][NEXT] = index;
                self._nodes[tmpCurr][PREV] = index;
                self._nodes[index][PREV] = tmpPrev;
                self._nodes[index][NEXT] = tmpCurr;
            }
            unchecked {
                self._size = tmpSize + 1;
            }
        }
    }

    /// @notice Remove a node from the linked list at the specified index.
    /// @dev This function removes a node from the linked list at the specified index.
    /// @param self The linked list.
    /// @param index The index of the node to remove.
    function remove(List storage self, uint256 index) internal {
        // Check if the node exists and the index is valid.
        if (exist(self, index)) {
            // remove the node from between existing nodes.
            uint256 tmpPrev = self._nodes[index][PREV];
            uint256 tmpNext = self._nodes[index][NEXT];
            self._nodes[index][NEXT] = SENTINEL;
            self._nodes[index][PREV] = SENTINEL;
            self._nodes[tmpPrev][NEXT] = tmpNext;
            self._nodes[tmpNext][PREV] = tmpPrev;
            self._data[index] = EMPTY;
            unchecked {
                self._size--;
            }
        }
    }

    /// @notice Shrinks the list by removing all nodes before the specified index.
    /// @dev This function updates the head of the list to the specified index, removing all previous nodes.
    /// @param self The list.
    /// @param index The index from which to shrink the list. All nodes before this index will be removed.
    function shrink(List storage self, uint256 index) internal {
        if (exist(self, index)) {
            uint256 tmpCurr = self._nodes[SENTINEL][NEXT];
            uint256 tmpSize = self._size;
            while (tmpCurr != index) {
                uint256 tmpNext = self._nodes[tmpCurr][NEXT];
                self._nodes[tmpCurr][NEXT] = SENTINEL;
                self._nodes[tmpCurr][PREV] = SENTINEL;
                self._data[tmpCurr] = EMPTY;
                tmpCurr = tmpNext;
                unchecked {
                    tmpSize--;
                }
            }
            self._size = tmpSize;
            self._nodes[SENTINEL][NEXT] = index;
            self._nodes[index][PREV] = SENTINEL;
        }
    }

    /// @notice Update the data of a node in the list.
    /// @dev This function updates the data of a node in the list at the specified index.
    /// @param self The list.
    /// @param index The target index of the node that wants to update.
    /// @param data The new data to assign to the node.
    function updateNodeData(List storage self, uint256 index, bytes memory data) internal {
        if (exist(self, index)) {
            self._data[index] = data;
        }
    }

    /// @notice Get the index of the head node in the linked list.
    /// @dev This function returns the index of the head node in the linked list.
    /// @param self The linked list.
    /// @return The index of the head node.
    function head(List storage self) internal view returns (uint256) {
        return self._nodes[SENTINEL][NEXT];
    }

    /// @notice Get the index of the middle node in the list.
    /// @dev This function returns the index of the middle node in the list.
    /// @param self The list.
    /// @return mid The index of the middle node.
    function middle(List storage self) internal view returns (uint256 mid) {
        if (self._size > SENTINEL) {
            uint256[] memory tmpList = firstPartition(self);
            mid = tmpList[tmpList.length - 1];
        }
    }

    /// @notice Get the index of the tail node in the linked list.
    /// @dev This function returns the index of the tail node in the linked list.
    /// @param self The linked list.
    /// @return The index of the tail node.
    function tail(List storage self) internal view returns (uint256) {
        return self._nodes[SENTINEL][PREV];
    }

    /// @notice Get the size of the linked list.
    /// @dev This function returns the size of the linked list.
    /// @param self The linked list.
    /// @return The size of the linked list.
    function size(List storage self) internal view returns (uint256) {
        return self._size;
    }

    /// @notice Get information about a node in the list.
    /// @dev This function returns information about a node in the list by the specified index.
    /// @param self The list.
    /// @param index The index of the node.
    /// @return prev The index of the previous node.
    /// @return data The data of the node.
    /// @return next The index of the next node.
    function node(List storage self, uint256 index) internal view returns (uint256, bytes memory, uint256) {
        return (self._nodes[index][PREV], self._data[index], self._nodes[index][NEXT]);
    }

    /// @notice Get the indices of nodes in ascending order.
    /// @dev This function returns an array containing the indices of nodes in ascending order.
    /// @param self The linked list.
    /// @return An array containing the indices of nodes in ascending order.
    function ascending(List storage self) internal view returns (uint256[] memory) {
        return _traversal(self, PREV);
    }

    /// @notice Get the indices of nodes in descending order.
    /// @dev This function returns an array containing the indices of nodes in descending order.
    /// @param self The linked list.
    /// @return An array containing the indices of nodes in descending order.
    function descending(List storage self) internal view returns (uint256[] memory) {
        return _traversal(self, NEXT);
    }

    /// @notice Get the indices of nodes in the first partition of the linked list.
    /// @dev This function returns an array containing the indices of nodes in the first partition of the linked list.
    /// @param self The linked list.
    /// @return part An array containing the indices of nodes in the first partition.
    function firstPartition(List storage self) internal view returns (uint256[] memory part) {
        uint256 tmpSize = self._size;
        if (tmpSize > SENTINEL) {
            unchecked {
                tmpSize = tmpSize == 1 ? tmpSize : tmpSize >> ONE_BIT;
            }
            part = _partition(self, tmpSize, NEXT);
        }
    }

    /// @notice Get the indices of nodes in the second partition of the linked list.
    /// @dev This function returns an array containing the indices of nodes in the second partition of the linked list.
    /// @param self The linked list.
    /// @return part An array containing the indices of nodes in the second partition.
    function secondPartition(List storage self) internal view returns (uint256[] memory part) {
        uint256 tmpSize = self._size;
        if (tmpSize > SENTINEL) {
            unchecked {
                if (tmpSize & ONE_BIT == SENTINEL) {
                    tmpSize = tmpSize >> ONE_BIT;
                } else {
                    tmpSize = (tmpSize + 1) >> ONE_BIT;
                }
                part = _partition(self, tmpSize, PREV);
            }
        }
    }

    /// @notice Get the path of indices from a specified node to the head of the linked list.
    /// @dev This function returns an array containing the indices of nodes from a specified node to the head of the linked list.
    /// @param self The linked list.
    /// @param index The starting index.
    /// @return part An array containing the indices of nodes from the starting node to the head.
    function pathToHead(List storage self, uint256 index) internal view returns (uint256[] memory part) {
        if (exist(self, index)) {
            part = _path(self, index, PREV);
        }
    }

    /// @notice Get the path of indices from a specified node to the tail of the linked list.
    /// @dev This function returns an array containing the indices of nodes from a specified node to the tail of the linked list.
    /// @param self The linked list.
    /// @param index The starting index.
    /// @return part An array containing the indices of nodes from the starting node to the tail.
    function pathToTail(List storage self, uint256 index) internal view returns (uint256[] memory part) {
        if (exist(self, index)) {
            part = _path(self, index, NEXT);
        }
    }

    /// @notice Get the indices starting from a specified node and wrapping around to the beginning if necessary.
    /// @dev This function returns an array containing the indices of nodes starting from a specified node and wrapping around to the beginning if necessary.
    /// @param self The linked list.
    /// @param start The starting index.
    /// @return part An array containing the indices of nodes.
    function partition(List storage self, uint256 start) internal view returns (uint256[] memory part) {
        if (exist(self, start)) {
            uint256 tmpSize = self._size;
            part = new uint[](tmpSize);
            uint256 counter;
            unchecked {
                while (counter < tmpSize) {
                    part[counter] = start; // Add the current index to the partition.
                    counter++;
                    start = self._nodes[start][NEXT]; // Move to the next node.
                    if (start == SENTINEL) {
                        start = self._nodes[start][NEXT]; // Move to the next node.
                    }
                }
            }
        }
    }
}
