// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.21;

import {IEvidenceDB} from "../interfaces/IEvidenceDB.sol";

/**
 * @notice Sparse Merkle Tree implementation.
 */
library SparseMerkleTree {
    /**
     * @dev A maximum depth hard cap for SMT
     * Due to the limitations of the uint256 data type, depths greater than 256 are not possible.
     */
    uint16 internal constant MAX_DEPTH_HARD_CAP = 256;

    uint64 internal constant ZERO_IDX = 0;

    bytes32 internal constant ZERO_HASH = bytes32(0);

    /**
     * @notice The type of the node in the Merkle tree.
     */
    enum NodeType {
        EMPTY,
        LEAF,
        MIDDLE
    }

    /**
     * @notice Defines the structure of the Sparse Merkle Tree.
     *
     * @param nodes A mapping of the tree's nodes, where the key is the node's index, starting from 1 upon node addition.
     * This approach differs from the original implementation, which utilized a hash as the key:
     * H(k || v || 1) for leaf nodes and H(left || right) for middle nodes.
     *
     * @param merkleRootId The index of the root node.
     * @param maxDepth The maximum depth of the Merkle tree.
     * @param nodesCount The total number of nodes within the Merkle tree.
     * @param customHasherSet Indicates whether custom hash functions have been configured (true) or not (false).
     * @param hash2 A hash function accepting two arguments.
     * @param hash3 A hash function accepting three arguments.
     */
    struct SMT {
        mapping(uint256 => Node) nodes;
        uint64 merkleRootId;
        uint64 nodesCount;
        uint64 deletedNodesCount;
        uint32 maxDepth;
        bool customHasherSet;
        function(bytes32, bytes32) view returns (bytes32) hash2;
        function(bytes32, bytes32, bytes32) view returns (bytes32) hash3;
    }

    /**
     * @notice Describes a node within the Merkle tree, including its type, children, hash, and key-value pair.
     *
     * @param nodeType The type of the node.
     * @param childLeft The index of the left child node.
     * @param childRight The index of the right child node.
     * @param nodeHash The hash of the node, calculated as follows:
     * - For leaf nodes, H(k || v || 1) where k is the key and v is the value;
     * - For middle nodes, H(left || right) where left and right are the hashes of the child nodes.
     *
     * @param key The key associated with the node.
     * @param value The value associated with the node.
     */
    struct Node {
        NodeType nodeType;
        uint64 childLeft;
        uint64 childRight;
        bytes32 nodeHash;
        bytes32 key;
        bytes32 value;
    }

    modifier onlyInitialized(SMT storage tree) {
        if (!_isInitialized(tree)) revert TreeNotInitialized();
        _;
    }

    error KeyAlreadyExists(bytes32 key);
    error LeafDoesNotMatch(bytes32 currentKey, bytes32 key);
    error MaxDepthExceedsHardCap(uint32 maxDepth);
    error MaxDepthIsZero();
    error MaxDepthReached();
    error NewMaxDepthMustBeLarger(uint32 currentDepth, uint32 newDepth);
    error NodeDoesNotExist(uint256 nodeId);
    error TreeAlreadyInitialized();
    error TreeNotInitialized();
    error TreeIsNotEmpty();

    /**
     * @notice The function to initialize the Merkle tree.
     * Under the hood it sets the maximum depth of the Merkle tree, therefore can be considered
     * alias function for the `setMaxDepth`.
     *
     * Requirements:
     * - The current tree depth must be 0.
     *
     * @param tree self.
     * @param maxDepth_ The max depth of the Merkle tree.
     */
    function initialize(SMT storage tree, uint32 maxDepth_) internal {
        if (_isInitialized(tree)) revert TreeAlreadyInitialized();

        _setMaxDepth(tree, maxDepth_);
    }

    /**
     * @notice The function to set the maximum depth of the Merkle tree. Complexity is O(1).
     *
     * Requirements:
     * - The max depth must be greater than zero.
     * - The max depth can only be increased.
     * - The max depth is less than or equal to MAX_DEPTH_HARD_CAP (256).
     *
     * @param tree self.
     * @param maxDepth_ The max depth of the Merkle tree.
     */
    function setMaxDepth(SMT storage tree, uint32 maxDepth_) internal {
        _setMaxDepth(tree, maxDepth_);
    }

    /**
     * @notice The function to set a custom hash functions, that will be used to build the Merkle Tree.
     *
     * Requirements:
     * - The tree must be empty.
     *
     * @param tree self.
     * @param hash2_ The hash function that accepts two argument.
     * @param hash3_ The hash function that accepts three arguments.
     */
    function setHashers(
        SMT storage tree,
        function(bytes32, bytes32) view returns (bytes32) hash2_,
        function(bytes32, bytes32, bytes32) view returns (bytes32) hash3_
    ) internal {
        if (_nodesCount(tree) != 0) revert TreeIsNotEmpty();

        tree.customHasherSet = true;

        tree.hash2 = hash2_;
        tree.hash3 = hash3_;
    }

    /**
     * @notice The function to add a new element to the bytes32 tree.
     * Complexity is O(log(n)), where n is the max depth of the tree.
     *
     * @param tree self.
     * @param key_ The key of the element.
     * @param value_ The value of the element.
     */
    function add(SMT storage tree, bytes32 key_, bytes32 value_) internal onlyInitialized(tree) {
        _add(tree, key_, value_);
    }

    /**
     * @notice The function to remove a (leaf) element from the bytes32 tree.
     * Complexity is O(log(n)), where n is the max depth of the tree.
     *
     * @param tree self.
     * @param key_ The key of the element.
     */
    function remove(SMT storage tree, bytes32 key_) internal onlyInitialized(tree) {
        tree.merkleRootId = uint64(_remove(tree, key_, tree.merkleRootId, 0));
    }

    /**
     * @notice The function to update a (leaf) element in the bytes32 tree.
     * Complexity is O(log(n)), where n is the max depth of the tree.
     *
     * @param tree self.
     * @param key_ The key of the element.
     * @param newValue_ The new value of the element.
     */
    function update(
        SMT storage tree,
        bytes32 key_,
        bytes32 newValue_
    ) internal onlyInitialized(tree) {
        _update(tree, key_, newValue_);
    }

    /**
     * @notice The function to get the proof if a node with specific key exists or not exists in the SMT.
     * Complexity is O(log(n)), where n is the max depth of the tree.
     *
     * @param tree self.
     * @param key_ The key of the element.
     * @return SMT proof struct.
     */
    function getProof(
        SMT storage tree,
        bytes32 key_
    ) internal view returns (IEvidenceDB.Proof memory) {
        uint256 maxDepth_ = _maxDepth(tree);

        IEvidenceDB.Proof memory proof_ = IEvidenceDB.Proof({
            root: _root(tree),
            siblings: new bytes32[](maxDepth_),
            existence: false,
            key: key_,
            value: ZERO_HASH,
            auxExistence: false,
            auxKey: ZERO_HASH,
            auxValue: ZERO_HASH
        });

        Node memory node_;
        uint256 nextNodeId_ = tree.merkleRootId;

        for (uint256 i = 0; i <= maxDepth_; i++) {
            node_ = _node(tree, nextNodeId_);

            if (node_.nodeType == NodeType.EMPTY) {
                break;
            } else if (node_.nodeType == NodeType.LEAF) {
                if (node_.key == proof_.key) {
                    proof_.existence = true;
                    proof_.value = node_.value;

                    break;
                } else {
                    proof_.auxExistence = true;
                    proof_.auxKey = node_.key;
                    proof_.auxValue = node_.value;
                    proof_.value = node_.value;

                    break;
                }
            } else {
                if ((uint256(proof_.key) >> i) & 1 == 1) {
                    nextNodeId_ = node_.childRight;

                    proof_.siblings[i] = tree.nodes[node_.childLeft].nodeHash;
                } else {
                    nextNodeId_ = node_.childLeft;

                    proof_.siblings[i] = tree.nodes[node_.childRight].nodeHash;
                }
            }
        }

        return proof_;
    }

    /**
     * @notice The function to get the root of the Merkle tree.
     * Complexity is O(1).
     *
     * @param tree self.
     * @return The root of the Merkle tree.
     */
    function getRoot(SMT storage tree) internal view returns (bytes32) {
        return _root(tree);
    }

    /**
     * @notice The function to get the node by its index.
     * Complexity is O(1).
     *
     * @param tree self.
     * @param nodeId_ The index of the node.
     * @return The node.
     */
    function getNode(SMT storage tree, uint256 nodeId_) internal view returns (Node memory) {
        return _node(tree, nodeId_);
    }

    /**
     * @notice The function to get the node by its key.
     * Complexity is O(log(n)), where n is the max depth of the tree.
     *
     * @param tree self.
     * @param key_ The key of the element.
     * @return The node.
     */
    function getNodeByKey(SMT storage tree, bytes32 key_) internal view returns (Node memory) {
        Node memory node_;
        uint256 nextNodeId_ = tree.merkleRootId;

        for (uint256 i = 0; i <= tree.maxDepth; i++) {
            node_ = tree.nodes[nextNodeId_];

            if (node_.nodeType == NodeType.EMPTY) {
                break;
            } else if (node_.nodeType == NodeType.LEAF) {
                if (node_.key == key_) {
                    break;
                }
            } else {
                if ((uint256(key_) >> i) & 1 == 1) {
                    nextNodeId_ = node_.childRight;
                } else {
                    nextNodeId_ = node_.childLeft;
                }
            }
        }

        return
            node_.key == key_
                ? node_
                : Node({
                    nodeType: NodeType.EMPTY,
                    childLeft: ZERO_IDX,
                    childRight: ZERO_IDX,
                    nodeHash: ZERO_HASH,
                    key: ZERO_HASH,
                    value: ZERO_HASH
                });
    }

    /**
     * @notice The function to get the max depth of the Merkle tree.
     *
     * @param tree self.
     * @return The max depth of the Merkle tree.
     */
    function getMaxDepth(SMT storage tree) internal view returns (uint64) {
        return uint64(_maxDepth(tree));
    }

    /**
     * @notice The function to get the number of nodes in the Merkle tree.
     *
     * @param tree self.
     * @return The number of nodes in the Merkle tree.
     */
    function getNodesCount(SMT storage tree) internal view returns (uint64) {
        return uint64(_nodesCount(tree));
    }

    /**
     * @notice The function to check if custom hash functions are set.
     *
     * @param tree self.
     * @return True if custom hash functions are set, otherwise false.
     */
    function isCustomHasherSet(SMT storage tree) internal view returns (bool) {
        return tree.customHasherSet;
    }

    function _setMaxDepth(SMT storage tree, uint32 maxDepth_) private {
        if (maxDepth_ == 0) revert MaxDepthIsZero();

        uint32 currentDepth_ = tree.maxDepth;

        if (maxDepth_ <= currentDepth_) revert NewMaxDepthMustBeLarger(currentDepth_, maxDepth_);
        if (maxDepth_ > MAX_DEPTH_HARD_CAP) revert MaxDepthExceedsHardCap(maxDepth_);

        tree.maxDepth = maxDepth_;
    }

    function _add(SMT storage tree, bytes32 key_, bytes32 value_) private {
        Node memory node_ = Node({
            nodeType: NodeType.LEAF,
            childLeft: ZERO_IDX,
            childRight: ZERO_IDX,
            nodeHash: ZERO_HASH,
            key: key_,
            value: value_
        });

        tree.merkleRootId = uint64(_add(tree, node_, tree.merkleRootId, 0));
    }

    function _update(SMT storage tree, bytes32 key_, bytes32 newValue_) private {
        Node memory node_ = Node({
            nodeType: NodeType.LEAF,
            childLeft: ZERO_IDX,
            childRight: ZERO_IDX,
            nodeHash: ZERO_HASH,
            key: key_,
            value: newValue_
        });

        _update(tree, node_, tree.merkleRootId, 0);
    }

    /**
     * @dev The check for whether the current depth exceeds the maximum depth is omitted for two reasons:
     * 1. The current depth may only surpass the maximum depth during the addition of a new leaf.
     * 2. As we navigate through middle nodes, the current depth is assured to remain below the maximum
     *    depth since the traversal must ultimately conclude at a leaf node.
     */
    function _add(
        SMT storage tree,
        Node memory newLeaf_,
        uint256 nodeId_,
        uint16 currentDepth_
    ) private returns (uint256) {
        Node memory currentNode_ = tree.nodes[nodeId_];

        if (currentNode_.nodeType == NodeType.EMPTY) {
            return _setNode(tree, newLeaf_);
        } else if (currentNode_.nodeType == NodeType.LEAF) {
            if (currentNode_.key == newLeaf_.key) revert KeyAlreadyExists(newLeaf_.key);

            return _pushLeaf(tree, newLeaf_, currentNode_, nodeId_, currentDepth_);
        } else {
            uint256 nextNodeId_;

            if ((uint256(newLeaf_.key) >> currentDepth_) & 1 == 1) {
                nextNodeId_ = _add(tree, newLeaf_, currentNode_.childRight, currentDepth_ + 1);

                tree.nodes[nodeId_].childRight = uint64(nextNodeId_);
            } else {
                nextNodeId_ = _add(tree, newLeaf_, currentNode_.childLeft, currentDepth_ + 1);

                tree.nodes[nodeId_].childLeft = uint64(nextNodeId_);
            }

            tree.nodes[nodeId_].nodeHash = _getNodeHash(tree, tree.nodes[nodeId_]);

            return nodeId_;
        }
    }

    function _remove(
        SMT storage tree,
        bytes32 key_,
        uint256 nodeId_,
        uint16 currentDepth_
    ) private returns (uint256) {
        Node memory currentNode_ = tree.nodes[nodeId_];

        if (currentNode_.nodeType == NodeType.EMPTY) {
            revert NodeDoesNotExist(nodeId_);
        } else if (currentNode_.nodeType == NodeType.LEAF) {
            if (currentNode_.key != key_) revert LeafDoesNotMatch(currentNode_.key, key_);

            _deleteNode(tree, nodeId_);

            return ZERO_IDX;
        } else {
            uint256 nextNodeId_;

            if ((uint256(key_) >> currentDepth_) & 1 == 1) {
                nextNodeId_ = _remove(tree, key_, currentNode_.childRight, currentDepth_ + 1);
            } else {
                nextNodeId_ = _remove(tree, key_, currentNode_.childLeft, currentDepth_ + 1);
            }

            NodeType rightType_ = tree.nodes[currentNode_.childRight].nodeType;
            NodeType leftType_ = tree.nodes[currentNode_.childLeft].nodeType;

            if (rightType_ == NodeType.EMPTY && leftType_ == NodeType.EMPTY) {
                _deleteNode(tree, nodeId_);

                return nextNodeId_;
            }

            NodeType nextType_ = tree.nodes[nextNodeId_].nodeType;

            if (
                (rightType_ == NodeType.EMPTY || leftType_ == NodeType.EMPTY) &&
                nextType_ != NodeType.MIDDLE
            ) {
                if (
                    nextType_ == NodeType.EMPTY &&
                    (leftType_ == NodeType.LEAF || rightType_ == NodeType.LEAF)
                ) {
                    _deleteNode(tree, nodeId_);

                    if (rightType_ == NodeType.LEAF) {
                        return currentNode_.childRight;
                    }

                    return currentNode_.childLeft;
                }

                if (rightType_ == NodeType.EMPTY) {
                    tree.nodes[nodeId_].childRight = uint64(nextNodeId_);
                } else {
                    tree.nodes[nodeId_].childLeft = uint64(nextNodeId_);
                }
            }

            tree.nodes[nodeId_].nodeHash = _getNodeHash(tree, tree.nodes[nodeId_]);

            return nodeId_;
        }
    }

    function _update(
        SMT storage tree,
        Node memory newLeaf_,
        uint256 nodeId_,
        uint16 currentDepth_
    ) private {
        Node memory currentNode_ = tree.nodes[nodeId_];

        if (currentNode_.nodeType == NodeType.EMPTY) {
            revert NodeDoesNotExist(nodeId_);
        } else if (currentNode_.nodeType == NodeType.LEAF) {
            if (currentNode_.key != newLeaf_.key)
                revert LeafDoesNotMatch(currentNode_.key, newLeaf_.key);

            tree.nodes[nodeId_] = newLeaf_;
            currentNode_ = newLeaf_;
        } else {
            if ((uint256(newLeaf_.key) >> currentDepth_) & 1 == 1) {
                _update(tree, newLeaf_, currentNode_.childRight, currentDepth_ + 1);
            } else {
                _update(tree, newLeaf_, currentNode_.childLeft, currentDepth_ + 1);
            }
        }

        tree.nodes[nodeId_].nodeHash = _getNodeHash(tree, currentNode_);
    }

    function _pushLeaf(
        SMT storage tree,
        Node memory newLeaf_,
        Node memory oldLeaf_,
        uint256 oldLeafId_,
        uint16 currentDepth_
    ) private returns (uint256) {
        if (currentDepth_ >= tree.maxDepth) revert MaxDepthReached();

        Node memory newNodeMiddle_;
        bool newLeafBitAtDepth_ = (uint256(newLeaf_.key) >> currentDepth_) & 1 == 1;
        bool oldLeafBitAtDepth_ = (uint256(oldLeaf_.key) >> currentDepth_) & 1 == 1;

        // Check if we need to go deeper if diverge at the depth's bit
        if (newLeafBitAtDepth_ == oldLeafBitAtDepth_) {
            uint256 nextNodeId_ = _pushLeaf(
                tree,
                newLeaf_,
                oldLeaf_,
                oldLeafId_,
                currentDepth_ + 1
            );

            if (newLeafBitAtDepth_) {
                // go right
                newNodeMiddle_ = Node({
                    nodeType: NodeType.MIDDLE,
                    childLeft: ZERO_IDX,
                    childRight: uint64(nextNodeId_),
                    nodeHash: ZERO_HASH,
                    key: ZERO_HASH,
                    value: ZERO_HASH
                });
            } else {
                // go left
                newNodeMiddle_ = Node({
                    nodeType: NodeType.MIDDLE,
                    childLeft: uint64(nextNodeId_),
                    childRight: ZERO_IDX,
                    nodeHash: ZERO_HASH,
                    key: ZERO_HASH,
                    value: ZERO_HASH
                });
            }

            return _setNode(tree, newNodeMiddle_);
        }

        uint256 newLeafId = _setNode(tree, newLeaf_);

        if (newLeafBitAtDepth_) {
            newNodeMiddle_ = Node({
                nodeType: NodeType.MIDDLE,
                childLeft: uint64(oldLeafId_),
                childRight: uint64(newLeafId),
                nodeHash: ZERO_HASH,
                key: ZERO_HASH,
                value: ZERO_HASH
            });
        } else {
            newNodeMiddle_ = Node({
                nodeType: NodeType.MIDDLE,
                childLeft: uint64(newLeafId),
                childRight: uint64(oldLeafId_),
                nodeHash: ZERO_HASH,
                key: ZERO_HASH,
                value: ZERO_HASH
            });
        }

        return _setNode(tree, newNodeMiddle_);
    }

    /**
     * @dev The function used to add new nodes.
     */
    function _setNode(SMT storage tree, Node memory node_) private returns (uint256) {
        node_.nodeHash = _getNodeHash(tree, node_);

        uint256 newCount_ = ++tree.nodesCount;
        tree.nodes[newCount_] = node_;

        return newCount_;
    }

    /**
     * @dev The function used to delete removed nodes.
     */
    function _deleteNode(SMT storage tree, uint256 nodeId_) private {
        delete tree.nodes[nodeId_];
        ++tree.deletedNodesCount;
    }

    /**
     * @dev The check for an empty node is omitted, as this function is called only with
     * non-empty nodes and is not intended for external use.
     */
    function _getNodeHash(SMT storage tree, Node memory node_) private view returns (bytes32) {
        function(bytes32, bytes32) view returns (bytes32) hash2_ = tree.customHasherSet
            ? tree.hash2
            : _hash2;
        function(bytes32, bytes32, bytes32) view returns (bytes32) hash3_ = tree.customHasherSet
            ? tree.hash3
            : _hash3;

        if (node_.nodeType == NodeType.LEAF) {
            return hash3_(node_.key, node_.value, bytes32(uint256(1)));
        }

        return hash2_(tree.nodes[node_.childLeft].nodeHash, tree.nodes[node_.childRight].nodeHash);
    }

    function _hash2(bytes32 a, bytes32 b) private pure returns (bytes32 result) {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            mstore(0, a)
            mstore(32, b)

            result := keccak256(0, 64)
        }
    }

    /**
     * @dev The decision not to update the free memory pointer is due to the temporary nature of the hash arguments.
     */
    function _hash3(bytes32 a, bytes32 b, bytes32 c) private pure returns (bytes32 result) {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            let free_ptr := mload(64)

            mstore(free_ptr, a)
            mstore(add(free_ptr, 32), b)
            mstore(add(free_ptr, 64), c)

            result := keccak256(free_ptr, 96)
        }
    }

    function _root(SMT storage tree) private view returns (bytes32) {
        return tree.nodes[tree.merkleRootId].nodeHash;
    }

    function _node(SMT storage tree, uint256 nodeId_) private view returns (Node memory) {
        return tree.nodes[nodeId_];
    }

    function _maxDepth(SMT storage tree) private view returns (uint256) {
        return tree.maxDepth;
    }

    function _nodesCount(SMT storage tree) private view returns (uint256) {
        return tree.nodesCount - tree.deletedNodesCount;
    }

    function _isInitialized(SMT storage tree) private view returns (bool) {
        return tree.maxDepth > 0;
    }
}
