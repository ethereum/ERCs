// LICENSE: CC0-1.0
pragma circom 2.1.9;

include "circomlib/circuits/poseidon.circom";
include "circomlib/circuits/switcher.circom";
include "circomlib/circuits/gates.circom";
include "circomlib/circuits/bitify.circom";

/**
 * Hash2 = Poseidon(H_L | H_R)
 */
template Hash2() {
    signal input a;
    signal input b;

    signal output out;

    component h = Poseidon(2);
    h.inputs[0] <== a;
    h.inputs[1] <== b;

    out <== h.out;
}

/**
 * Hash3 = Poseidon(key | value | 1)
 * 1 is added to the end of the leaf value to make the hash unique
 */
template Hash3() {
    signal input a;
    signal input b;
    signal input c;

    signal output out;

    c === 1;

    component h = Poseidon(3);
    h.inputs[0] <== a;
    h.inputs[1] <== b;
    h.inputs[2] <== c;

    out <== h.out;
}

/**
 * Returns an array of bits, where the index of `1` bit 
 * is the current depth of the tree
 */
template DepthDeterminer(depth) {
    assert(depth > 1);

    signal input siblings[depth];
    signal output desiredDepth[depth];

    signal done[depth - 1];
    
    component isZero[depth];

    for (var i = 0; i < depth; i++) {
        isZero[i] = IsZero();
        isZero[i].in <== siblings[i];
    }

    // The last sibling is always zero due to the way the proof is constructed
    isZero[depth - 1].out === 1;

    // If there is a branch on the previous depth, then the current depth is the desired one
    desiredDepth[depth - 1] <== 1 - isZero[depth - 2].out;
    done[depth - 2] <== desiredDepth[depth - 1];

    // desiredDepth will be `1` the first time we encounter non-zero branch on the previous depth
    for (var i = depth - 2; i > 0; i--) {
        desiredDepth[i] <== (1 - done[i]) * (1 - isZero[i - 1].out);
        done[i - 1] <== desiredDepth[i] + done[i];
    }

    desiredDepth[0] <== 1 - done[0];
}

/**
 * Determines the type of the node
 */
template NodeTypeDeterminer() {
    signal input auxIsEmpty;
    // 1 if the node is at the desired depth, 0 otherwise
    signal input isDesiredDepth;
    signal input isExclusion;

    signal input isPreviousMiddle;

    // 1 if the node is a middle node, 0 otherwise
    signal output middle;
    // 1 if the node is a leaf node for the exclusion proof, 0 otherwise
    signal output auxLeaf;
    // 1 if the node is a leaf node, 0 otherwise
    signal output leaf;

    // 1 if the node is a leaf node and we are checking for exclusion, 0 otherwise
    signal leafForExclusionCheck <== isDesiredDepth * isExclusion;

    // Determine the node as a middle, until getting to the desired depth
    middle <== isPreviousMiddle - isDesiredDepth;

    // Determine the node as a leaf, when we are at the desired depth and
    // we check for inclusion
    leaf <== isDesiredDepth - leafForExclusionCheck;

    // Determine the node as an auxLeaf, when we are at the desired depth and
    // we check for exclusion in a bamboo scenario
    auxLeaf <== leafForExclusionCheck * (1 - auxIsEmpty);
}

/**
 * Gets hash at the current depth, based on the type of the node
 * If the mode is a empty, then the hash is 0
 */
template DepthHasher() {
    signal input isMiddle;
    signal input isAuxLeaf;
    signal input isLeaf;

    signal input sibling;
    signal input auxLeaf;
    signal input leaf;
    signal input currentKeyBit;
    signal input child;

    signal output root;

    component switcher = Switcher();
    switcher.L <== child;
    switcher.R <== sibling;
    // Based on the current key bit, we understand which order to use
    switcher.sel <== currentKeyBit;

    component proofHash = Hash2();
    proofHash.a <== switcher.outL;
    proofHash.b <== switcher.outR;

    signal res[3];
    // hash of the middle node
    res[0] <== proofHash.out * isMiddle;
    // hash of the aux leaf node for the exclusion proof
    res[1] <== auxLeaf * isAuxLeaf;
    // hash of the leaf node for the inclusion proof
    res[2] <== leaf * isLeaf;

    // only one of the following will be non-zero
    root <== res[0] + res[1] + res[2];
}

/**
 * Checks the sparse merkle proof against the given root
 */
template SparseMerkleTree(depth) {
    // The root of the sparse merkle tree
    signal input root;
    // The siblings for each depth
    signal input siblings[depth];

    signal input key;
    signal input value;

    signal input auxKey;
    signal input auxValue;
    // 1 if the aux node is empty, 0 otherwise
    signal input auxIsEmpty;

    // 1 if we are checking for exclusion, 0 if we are checking for inclusion
    signal input isExclusion;

    // Check that the auxIsEmpty is 0 if we are checking for inclusion
    component exclusiveCase = AND();
    exclusiveCase.a <== 1 - isExclusion;
    exclusiveCase.b <== auxIsEmpty;
    exclusiveCase.out === 0;

    // Check that the key != auxKey if we are checking for exclusion and the auxIsEmpty is 0
    component areKeyEquals = IsEqual();
    areKeyEquals.in[0] <== auxKey;
    areKeyEquals.in[1] <== key;

    component keysOk = MultiAND(3);
    keysOk.in[0] <== isExclusion;
    keysOk.in[1] <== 1 - auxIsEmpty;
    keysOk.in[2] <== areKeyEquals.out;
    keysOk.out === 0;

    component auxHash = Hash3();
    auxHash.a <== auxKey;
    auxHash.b <== auxValue;
    auxHash.c <== 1;

    component hash = Hash3();
    hash.a <== key;
    hash.b <== value;
    hash.c <== 1;

    component keyBits = Num2Bits_strict();
    keyBits.in <== key;

    component depths = DepthDeterminer(depth);
    
    for (var i = 0; i < depth; i++) {
        depths.siblings[i] <== siblings[i];
    }

    component nodeType[depth];

    // Start with the middle node (closest to the root)
    for (var i = 0; i < depth; i++) {
        nodeType[i] = NodeTypeDeterminer();

        if (i == 0) {
            nodeType[i].isPreviousMiddle <== 1;
        } else {
            nodeType[i].isPreviousMiddle <== nodeType[i - 1].middle;
        }

        nodeType[i].auxIsEmpty <== auxIsEmpty;
        nodeType[i].isExclusion <== isExclusion;
        nodeType[i].isDesiredDepth <== depths.desiredDepth[i];
    }

    component depthHash[depth];

    // Hash up the elements in the reverse order
    for (var i = depth - 1; i >= 0; i--) {
        depthHash[i] = DepthHasher();

        depthHash[i].isMiddle <== nodeType[i].middle;
        depthHash[i].isLeaf <== nodeType[i].leaf;
        depthHash[i].isAuxLeaf <== nodeType[i].auxLeaf;

        depthHash[i].sibling <== siblings[i];
        depthHash[i].auxLeaf <== auxHash.out;
        depthHash[i].leaf <== hash.out;

        depthHash[i].currentKeyBit <== keyBits.out[i];

        if (i == depth - 1) {
            // The last depth has no child
            depthHash[i].child <== 0;
        } else {
            // The child of the current depth is the root of the next depth
            depthHash[i].child <== depthHash[i + 1].root;
        }
    }

    // The root of the merkle tree is the root of the first depth
    depthHash[0].root === root;
}
