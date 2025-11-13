/**
 * Placeholder for RFC 8785 JSON Canonicalization Scheme (JCS).
 * See: https://tools.ietf.org/html/rfc8785
 *
 * A proper implementation requires parsing the JSON and then serializing it according
 * to strict rules:
 * - UTF-8 encoding, no BOM.
 * - No insignificant whitespace.
 * - Keys sorted lexicographically (Unicode code points).
 * - Integer and floating-point number representations defined.
 * - String representations defined (e.g., escaping).
 *
 * Libraries like `canonicalize` on npm might provide this functionality.
 */

import jcsCanonicalize from 'canonical-json'; // Use default import
// import { canonicalize as jcsCanonicalize } from 'canonical-json'; // Old named import
// import poseidon from 'poseidon-lite';
// import { poseidon } from 'poseidon-lite'; // Try named import
import { poseidon1, poseidon2 } from 'poseidon-lite'; // Import specific arity functions
import keccak256 from 'keccak256';
import { MerkleTree } from 'merkletreejs';

// Type definitions for clarity
// Export JsonValue for use in other modules
export type JsonValue = string | number | boolean | null | JsonObject | JsonArray;
// Export JsonObject and JsonArray types as well
export interface JsonObject {
    [key: string]: JsonValue;
}
export interface JsonArray extends Array<JsonValue> {}

/**
 * Calculates Keccak256 hash of a UTF-8 string and returns it as a bigint (mod BN254 prime).
 * Note: BN254 prime is implicitly handled by Circom/snarkjs field operations.
 * Here, we just return the BigInt representation of the hex hash.
 * @param x The input string.
 * @returns The Keccak256 hash as a bigint.
 */
export function keccak256ToField(x: string): bigint {
    const hashBuffer = keccak256(Buffer.from(x, 'utf8'));
    // Use template literal for hex conversion
    return BigInt(`0x${hashBuffer.toString('hex')}`);
}

/**
 * Computes the Poseidon hash for a string value.
 * H(value) = Poseidon(Keccak256(value))
 * @param value The string value.
 * @returns The Poseidon hash as a bigint.
 */
export function poseidonHashString(value: string): bigint {
    return poseidon1([keccak256ToField(value)]); // Use poseidon1
}

/**
 * Computes the Poseidon hash for a canonicalized object.
 * H(obj) = Poseidon(Keccak256(JCS(obj)))
 * @param value The object value.
 * @returns The Poseidon hash as a bigint.
 */
export function poseidonHashObject(value: JsonObject | JsonArray): bigint {
    const canonicalString = jcsCanonicalize(value);
    return poseidon1([keccak256ToField(canonicalString)]); // Use poseidon1
}

/**
 * Scales a number string (representing a decimal) by 1000 and returns it as a bigint.
 * Rounds to the nearest integer after scaling.
 * @param value The number string (e.g., "123.456").
 * @returns The scaled value as a bigint.
 */
export function scaleNumberToField(value: string): bigint {
    // Use Number.parseFloat
    const scaled = Math.round(Number.parseFloat(value) * 1000);
    // Use Number.isNaN
    if (Number.isNaN(scaled)) {
        throw new Error(`Invalid number string for scaling: ${value}`);
    }
    return BigInt(scaled);
}

/**
 * Computes the final Merkle leaf based on the simplified circuit logic.
 * leaf = Poseidon(valueHash | scaledValue, 0)
 * @param value The original JSON value (string, number string, object, or bigint).
 * @returns The computed Merkle leaf as a bigint.
 */
export function computeMerkleLeaf(value: JsonValue | bigint): bigint {
    let valueRepresentation: bigint;

    if (typeof value === 'string') {
        // Is it a number string or a plain string?
        // Basic check: try parsing as float
        const parsedFloat = Number.parseFloat(value);
        // Use Number.isNaN and check if string representation matches original (trimmed)
        if (!Number.isNaN(parsedFloat) && parsedFloat.toString() === value.trim()) {
             // Treat as number string
            valueRepresentation = scaleNumberToField(value);
        } else {
            // Treat as plain string
            valueRepresentation = poseidonHashString(value);
        }
    } else if (typeof value === 'number') {
        // Convert number to string before scaling
        valueRepresentation = scaleNumberToField(value.toString());
    } else if (typeof value === 'bigint') { // Added check for bigint
        // For raw bigints (like timestamps), use directly without hashing/scaling
        valueRepresentation = value;
    } else if (typeof value === 'object' && value !== null) {
        valueRepresentation = poseidonHashObject(value as JsonObject | JsonArray);
    } else {
        // Handle null, boolean, etc. - assuming they are treated as strings for hashing?
        // EIP spec implies only S, N, OBJ types. Need clarification if others possible.
        // For now, let's hash their string representation.
        console.warn(`Unsupported type for leaf computation: ${typeof value}. Treating as string.`);
        valueRepresentation = poseidonHashString(String(value));
    }

    // Simplified leaf structure: Poseidon(valueRepresentation, 0)
    return poseidon2([valueRepresentation, BigInt(0)]); // Use poseidon2
}

/**
 * Custom hash function for MerkleTree that uses Poseidon.
 * Accepts two Buffers, converts them to BigInts, hashes using Poseidon(left, right),
 * and returns the result as a Buffer.
 * @param left Left node Buffer.
 * @param right Right node Buffer.
 * @returns Poseidon hash as a Buffer.
 */
function poseidonHashFn(left: Buffer | undefined | null, right: Buffer | undefined | null): Buffer {
    // Handle undefined/null inputs - use empty buffer as default
    const leftBuf = left || Buffer.alloc(32);
    const rightBuf = right || Buffer.alloc(32);
    
    // Check if inputs are actually buffers before calling toString
    if (!Buffer.isBuffer(leftBuf) || !Buffer.isBuffer(rightBuf)) {
        console.error("Error: poseidonHashFn received non-buffer input after null/undefined handling!");
        throw new Error("Invalid input to poseidonHashFn");
    }

    // Convert buffers (assumed hex) to BigInts
    const leftBigInt = BigInt(`0x${leftBuf.toString('hex')}`);
    const rightBigInt = BigInt(`0x${rightBuf.toString('hex')}`);
    
    // Compute Poseidon hash
    const hashBigInt = poseidon2([leftBigInt, rightBigInt]);

    // Convert result back to Buffer, ensuring it is 32 bytes
    // Pad with leading zeros to 64 hex characters (32 bytes)
    const paddedHex = hashBigInt.toString(16).padStart(64, '0'); 
    
    const resultBuffer = Buffer.from(paddedHex, 'hex');

    // Ensure buffer is exactly 32 bytes (sanity check, padStart should handle this)
    if (resultBuffer.length !== 32) {
        console.warn(`Padding warning: poseidonHashFn output buffer length is ${resultBuffer.length}, expected 32`);
        // If somehow length is wrong, create a zero-padded 32-byte buffer
        const finalBuffer = Buffer.alloc(32);
        resultBuffer.copy(finalBuffer, 32 - resultBuffer.length); 
        return finalBuffer;
    }

    return resultBuffer;
}

/**
 * Builds a Merkle tree from a list of JSON values corresponding to the critical fields.
 * Uses Poseidon hashing for consistency with the circuit verifier.
 * @param criticalFields An array of JSON values in the specified order.
 * @param treeSize The total size of the tree (power of 2, e.g., 16).
 * @returns The constructed MerkleTree object.
 */
export function buildMerkleTree(criticalFields: JsonValue[], treeSize: number): MerkleTree {
    if (criticalFields.length > treeSize) {
        throw new Error(`Number of fields (${criticalFields.length}) exceeds tree size (${treeSize})`);
    }

    // Compute leaves using Poseidon(valueRep, 0)
    const leaves = criticalFields.map(field => computeMerkleLeaf(field));

    // Pad with Poseidon(0) leaves if necessary
    const zeroLeaf = poseidon1([BigInt(0)]); // Use poseidon1 for zero leaf
    while (leaves.length < treeSize) {
        leaves.push(zeroLeaf);
    }

    // Convert leaves to Buffers for the tree library
    const leafBuffers = leaves.map(l => {
        // Pad hex to 32 bytes (64 chars) for consistency
        const leafHex = l.toString(16).padStart(64, '0'); 
        return Buffer.from(leafHex, 'hex');
    });

    // Use the custom Poseidon hash function for building the tree
    const tree = new MerkleTree(leafBuffers, poseidonHashFn);
    return tree;
}

// Example Usage (conceptual)
/*
const myJson = {
  b: 1,
  a: "hello",
  c: [3, 2, 1],
  d: { z: true, x: null }
};

try {
  const canonicalString = canonicalize(myJson);
  console.log(canonicalString);
  // Expected (roughly, depends on exact sorting/spacing): 
  // {"a":"hello","b":1,"c":[3,2,1],"d":{"x":null,"z":true}}
} catch (error) {
  console.error(error);
}
*/ 