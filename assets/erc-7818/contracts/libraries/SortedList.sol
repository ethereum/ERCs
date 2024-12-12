// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

// inspiration:
// https://github.com/o0ragman0o/LibCLL/
// https://github.com/vittominacori/solidity-linked-list/

library SortedList {
    struct List {
        uint256 _size;
        mapping(uint256 => mapping(bool => uint256)) _nodes;
    }

    uint8 private constant SENTINEL = 0;
    bool private constant PREV = false;
    bool private constant NEXT = true;

    /// @notice Traverses the linked list in the specified direction and returns a list of node indices.
    /// @dev This function constructs an array `list` that holds indices of nodes in the linked list,
    /// starting from either the front or the back based on the `direction` parameter.
    /// @param self The linked list state where the operation is performed.
    /// @return array containing the indices of nodes in the linked list, ordered according to the specified direction.
    function _toArray(
        List storage self
    ) private view returns (uint256[] memory array) {
        // return early pattern
        uint256 length = self._size;
        if (length == 0) return array;

        uint256 element;
        array = new uint256[](length);
        array[0] = self._nodes[element][NEXT];
        unchecked {
            for (uint256 i = length - 1; i > 0; i--) {
                array[i] = self._nodes[element][PREV];
                element = array[i];
            }
        }
    }

    /// @notice Check if a node exists in the linked list.
    /// @dev This function checks if a node exists in the linked list by the specified index.
    /// @param self The linked list.
    /// @param index The index of the node to check for existence.
    /// @return result if the node exists, false otherwise.
    function exist(
        List storage self,
        uint256 index
    ) internal view returns (bool result) {
        result = (self._nodes[index][PREV] > SENTINEL ||
            self._nodes[SENTINEL][NEXT] == index);
    }

    /// @notice Get the index of the next node in the list.
    /// @dev Accesses the `_nodes` mapping in the `List` structure to get the index of the next node.
    /// @param self The list.
    /// @param index The index of the current node.
    /// @return The index of the next node.
    function next(
        List storage self,
        uint256 index
    ) internal view returns (uint256) {
        return self._nodes[index][NEXT];
    }

    /// @notice Get the index of the previous node in the list.
    /// @dev Accesses the `_nodes` mapping in the `List` structure to get the index of the previous node.
    /// @param self The list.
    /// @param index The index of the current node.
    /// @return The index of the previous node.
    function previous(
        List storage self,
        uint256 index
    ) internal view returns (uint256) {
        return self._nodes[index][PREV];
    }

    /// @notice Insert data into the linked list at the specified index.
    /// @dev This function inserts data into the linked list at the specified index.
    /// @param self The linked list.
    /// @param index The index at which to insert the data.
    function insert(List storage self, uint256 index) internal {
        if (!exist(self, index)) {
            uint256 tmpTail = self._nodes[SENTINEL][PREV];
            uint256 tmpHead = self._nodes[SENTINEL][NEXT];
            uint256 tmpSize = self._size;
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
                uint256 tmpCurr = tmpHead;
                while (index > tmpCurr) {
                    tmpCurr = self._nodes[tmpCurr][NEXT];
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

    /// @notice Get the index of the head node in the linked list.
    /// @dev This function returns the index of the head node in the linked list.
    /// @param self The linked list.
    /// @return The index of the head node.
    function head(List storage self) internal view returns (uint256) {
        return self._nodes[SENTINEL][NEXT];
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
    /// @return next The index of the next node.
    function node(
        List storage self,
        uint256 index
    ) internal view returns (uint256, uint256) {
        return (self._nodes[index][PREV], self._nodes[index][NEXT]);
    }

    /// @notice Get the indices of nodes in ascending order.
    /// @dev This function returns an array containing the indices of nodes in ascending order.
    /// @param self The linked list.
    /// @return array containing the indices of nodes in ascending order.
    function toArray(
        List storage self
    ) internal view returns (uint256[] memory array) {
        return _toArray(self);
    }
}
