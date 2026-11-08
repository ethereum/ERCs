// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPPredicates
/// @notice ABI encoding of a predicate tree. A predicate is `abi.encode(Node[])`; node 0 is the root;
///         the children of a composite node `i` are `nodes[childStart .. childStart + childCount)` and
///         every child index is greater than `i` (the array is a pre-order forest, so it is acyclic).
///         `predicateHash = keccak256(abi.encode(nodes))` is what a paradigm commits to per role.
library AIFPPredicates {
    struct Node {
        uint8 kind; // leaf or composite kind, see constants below
        uint8 childStart; // composites only: index of the first child
        uint8 childCount; // composites only: number of children (>= 1)
        address verifier; // ALLOWLIST: the subject set; EXTERNAL and semantic leaves: the verifier
        bytes32 ref; // leaf-specific reference (scheme id, policy id, decision id, ...)
        bytes params; // leaf-specific parameters, opaque to the composite evaluator
    }

    // Leaf kinds evaluated natively by the reference composite verifier.
    uint8 internal constant OPEN = 0; // always SATISFIED
    uint8 internal constant ALLOWLIST = 1; // subject is contained in the set at `verifier`
    uint8 internal constant EXTERNAL = 2; // delegated to `verifier`
    // Composite kinds.
    uint8 internal constant ALL_OF = 3;
    uint8 internal constant ANY_OF = 4;
    // Semantic leaf kinds: delegated to `verifier` like EXTERNAL, the kind tells the verifier
    // which vocabulary the parameters follow (credential, stake, identity, member, decision).
    uint8 internal constant CREDENTIAL = 5;
    uint8 internal constant STAKE = 6;
    uint8 internal constant IDENTITY = 7;
    uint8 internal constant MEMBER = 8;
    uint8 internal constant DECISION = 9;

    uint8 internal constant MAX_KNOWN_KIND = 9;
    uint256 internal constant MAX_NODES = 64;
    uint256 internal constant MAX_DEPTH = 8;

    function decode(bytes memory predicate) internal pure returns (Node[] memory nodes) {
        nodes = abi.decode(predicate, (Node[]));
    }

    function hashOf(Node[] memory nodes) internal pure returns (bytes32) {
        return keccak256(abi.encode(nodes));
    }

    function isComposite(uint8 kind) internal pure returns (bool) {
        return kind == ALL_OF || kind == ANY_OF;
    }

    function isDelegated(uint8 kind) internal pure returns (bool) {
        return kind == EXTERNAL || (kind >= CREDENTIAL && kind <= DECISION);
    }

    /// @dev Structural validity: non-empty, bounded, composites have at least one child, children follow
    ///      their parent, leaves have no children. Does not check that the kinds are supported.
    function isWellFormed(Node[] memory nodes) internal pure returns (bool) {
        uint256 n = nodes.length;
        if (n == 0 || n > MAX_NODES) return false;
        for (uint256 i = 0; i < n; i++) {
            Node memory node = nodes[i];
            if (isComposite(node.kind)) {
                if (node.childCount == 0) return false;
                if (node.childStart <= i) return false;
                if (uint256(node.childStart) + node.childCount > n) return false;
            } else {
                if (node.childCount != 0 || node.childStart != 0) return false;
            }
        }
        return true;
    }
}
