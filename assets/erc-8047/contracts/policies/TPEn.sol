// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0 <0.9.0;
/**
 * @title AbstractTokenPolicyEnforcement (TPEn) (dissertation prototype)
 * @dev Abstract contract for managing O(1) multi-dimensional token quarantines.
 * NOTE: This version is a functional prototype designed for academic demonstration.
 * further work implementation of `massDepth` batch operations. iterations
 * will push bit-shifting computations off-chain, allowing regulators to pass fully
 * computed 256-bit integer masks directly to a specific bucket slot, enabling the
 * simultaneous state-flipping of up to 256 topological depths in a single transaction.
 * @notice This contract allows regulators to freeze and unfreeze tokens using topological bounds, bitmasks, and discrete mapping.
 * @author Sirawit Techavanitch (sirawit_tec@live4.utcc.ac.th)
 */
abstract contract AbstractTokenPolicyEnforcement {
    enum FREEZE_TYPES {
        NONE,
        LOWER_BOUND,
        UPPER_BOUND,
        DEPTH,
        DISCRETE
    }

    struct Policy {
        uint128 beforeDepth;
        uint128 afterDepth;
        mapping(uint256 => bool) tokens;
        mapping(uint256 => uint256) bitmasks;
    }

    mapping(uint256 => Policy) private _policies;

    error TokenFrozen();
    error TokenNotFrozen();
    error DepthFrozen();
    error DepthNotFrozen();
    error ConflictingBounds();
    error InvalidUnfreezeTypes();
    error BoundNotSet();

    event FrozenToken(uint256 indexed tokenId);
    event FrozenBefore(uint256 indexed root, uint256 depth);
    event FrozenAfter(uint256 indexed root, uint256 depth);
    event FrozenDepth(uint256 indexed root, uint256 depth);

    event UnfrozenToken(uint256 indexed tokenId);
    event UnfrozenBefore(uint256 indexed root, uint256 depth);
    event UnfrozenAfter(uint256 indexed root, uint256 depth);
    event UnfrozenDepth(uint256 indexed root, uint256 depth);

    /**
     * @notice Calculates the 256-bit storage bucket and specific bit index for a given DAG depth.
     * @dev Uses pure bitwise operations in assembly for maximum EVM gas efficiency.
     * @param depth The chronological depth (Y-axis) of the token in the DAG.
     * @return bucket The exact 256-depth chunk where the state is stored.
     * @return bitIndex The specific bit position (0-255) within that bucket.
     */
    function calcTokenBucketAndBitIndex(uint256 depth) private pure returns (uint256 bucket, uint256 bitIndex) {
        assembly ("memory-safe") {
            // right shift by 8 bits (equivalent to depth / 256)
            bucket := shr(8, depth)
            // bitwise AND 255 (equivalent to depth % 256)
            bitIndex := and(depth, 0xFF)
        }
    }

    /**
     * @notice Internal function to update the discrete frozen status of a specific token.
     * @param root The identifier of the DAG transaction family.
     * @param tokenId The unique identifier of the discrete asset.
     * @param freeze The target status (true to freeze, false to unfreeze).
     */
    function updateFreezeToken(uint256 root, uint256 tokenId, bool freeze) private {
        _policies[root].tokens[tokenId] = freeze;
        if (freeze) {
            emit FrozenToken(tokenId);
        } else {
            emit UnfrozenToken(tokenId);
        }
    }

    /**
     * @notice Evaluates if a token is frozen.
     * @param root The DAG transaction family ID.
     * @param tokenId The specific discrete asset token ID.
     * @param depth The topological depth of the token.
     * @return isFrozen Boolean indicating if the token is locked.
     * @return freezeType The specific algorithmic rule that triggered the lock.
     */
    function isTokenFrozen(uint256 root, uint256 tokenId, uint256 depth) public view returns (bool, FREEZE_TYPES) {
        Policy storage policy = _policies[root];

        // boundary checks
        uint128 beforeDepth = policy.beforeDepth;
        uint128 afterDepth = policy.afterDepth;

        if (beforeDepth != 0 && depth <= beforeDepth) return (true, FREEZE_TYPES.LOWER_BOUND);
        if (afterDepth != 0 && depth >= afterDepth) return (true, FREEZE_TYPES.UPPER_BOUND);

        // bitmask check
        (uint256 bucket, uint256 bitIndex) = calcTokenBucketAndBitIndex(depth);
        if ((policy.bitmasks[bucket] & (1 << bitIndex)) != 0) {
            return (true, FREEZE_TYPES.DEPTH);
        }

        // specific token check
        if (policy.tokens[tokenId]) {
            return (true, FREEZE_TYPES.DISCRETE);
        }

        // fallback case
        return (false, FREEZE_TYPES.NONE);
    }

    /**
     * @notice Establishes a continuous lower bound. All tokens at or below this depth are frozen.
     * @dev Reverts if the requested depth overlaps with an existing upper bound.
     * @param root The DAG transaction family ID.
     * @param depth The DAG depth limit.
     */
    function freezeTokenBefore(uint256 root, uint256 depth) public virtual {
        Policy storage policy = _policies[root];
        if (policy.afterDepth != 0 && depth >= policy.afterDepth) revert ConflictingBounds();

        policy.beforeDepth = uint128(depth);
        emit FrozenBefore(root, depth);
    }

    /**
     * @notice Establishes a continuous upper bound. All tokens at or above this depth are frozen.
     * @dev Reverts if the requested depth overlaps with an existing lower bound.
     * @param root The DAG transaction family ID.
     * @param depth The DAG depth limit.
     */
    function freezeTokenAfter(uint256 root, uint256 depth) public virtual {
        Policy storage policy = _policies[root];
        if (policy.beforeDepth != 0 && depth <= policy.beforeDepth) revert ConflictingBounds();

        policy.afterDepth = uint128(depth);

        emit FrozenAfter(root, depth);
    }

    /**
     * @notice Completely lifts the continuous lower bound quarantine for a DAG family.
     * @param root The DAG transaction family ID.
     * @param depth The previous bound depth (logged for off-chain indexing).
     */
    function unfreezeTokenBefore(uint256 root, uint256 depth) public virtual {
        Policy storage policy = _policies[root];
        if (policy.beforeDepth == 0) revert BoundNotSet();

        policy.beforeDepth = 0;

        emit UnfrozenBefore(root, depth);
    }

    /**
     * @notice Completely lifts the continuous upper bound quarantine for a DAG family.
     * @param root The DAG transaction family ID.
     * @param depth The previous bound depth (logged for off-chain indexing).
     */
    function unfreezeTokenAfter(uint256 root, uint256 depth) public virtual {
        Policy storage policy = _policies[root];
        if (policy.afterDepth == 0) revert BoundNotSet();

        policy.afterDepth = 0;

        emit UnfrozenAfter(root, depth);
    }

    /**
     * @notice Applies an O(1) bitmask quarantine to a specific topological depth.
     * @dev Reverts if the targeted depth is already frozen to prevent redundant gas spend and duplicate events.
     * @param root The DAG transaction family ID.
     * @param depth The exact DAG depth to freeze.
     */
    function freezeDepth(uint256 root, uint256 depth) public virtual {
        (uint256 bucket, uint256 bitIndex) = calcTokenBucketAndBitIndex(depth);
        // load the current 256-bit bucket into memory (1 SLOAD)
        uint256 currentMask = _policies[root].bitmasks[bucket];
        uint256 targetBit = 1 << bitIndex;
        // check if the specific bit is already 1. If yes, revert.
        if ((currentMask & targetBit) != 0) revert DepthFrozen();
        // apply the bitwise OR and write back to storage (1 SSTORE)
        _policies[root].bitmasks[bucket] = currentMask | targetBit;

        emit FrozenDepth(root, depth);
    }

    /**
     * @notice Removes a specific topological depth from the bitmask quarantine.
     * @dev Reverts if the targeted depth is not currently frozen to prevent redundant gas spend.
     * @param root The DAG transaction family ID.
     * @param depth The exact DAG depth to unfreeze.
     */
    function unfreezeDepth(uint256 root, uint256 depth) public virtual {
        (uint256 bucket, uint256 bitIndex) = calcTokenBucketAndBitIndex(depth);
        // load the current 256-bit bucket into memory (1 SLOAD)
        uint256 currentMask = _policies[root].bitmasks[bucket];
        uint256 targetBit = 1 << bitIndex;
        // check if the specific bit is already 0. If yes, revert.
        if ((currentMask & targetBit) == 0) revert DepthNotFrozen();
        // apply the bitwise AND NOT and write back to storage (1 SSTORE)
        _policies[root].bitmasks[bucket] = currentMask & ~targetBit;

        emit UnfrozenDepth(root, depth);
    }

    /**
     * @notice Freezes a specific discrete token ID.
     * @param root The DAG transaction family ID.
     * @param tokenId The unique identifier of the token.
     * @param depth The topological depth of the token.
     */
    function freezeToken(uint256 root, uint256 tokenId, uint256 depth) public virtual {
        (bool isFrozen, ) = isTokenFrozen(root, tokenId, depth);
        if (isFrozen) revert TokenFrozen();

        updateFreezeToken(root, tokenId, true);
    }

    /**
     * @notice Unfreezes a specific discrete token ID.
     * @dev Reverts if the token is locked by a continuous bound or depth mask.
     * @param root The DAG transaction family ID.
     * @param tokenId The unique identifier of the token.
     * @param depth The topological depth of the token.
     */
    function unfreezeToken(uint256 root, uint256 tokenId, uint256 depth) public virtual {
        (bool isFrozen, FREEZE_TYPES types) = isTokenFrozen(root, tokenId, depth);

        if (!isFrozen) revert TokenNotFrozen();
        if (types != FREEZE_TYPES.DISCRETE) revert InvalidUnfreezeTypes();

        updateFreezeToken(root, tokenId, false);
    }
}