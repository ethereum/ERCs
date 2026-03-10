import { expect } from "chai";
import { MerkleTree, _keccak256 } from "../src/merkle";
import { randomBytes } from "crypto";

describe("MerkleTree", function () {
  function createRandomMessages(count: number, size: number = 32): Buffer[] {
    return Array.from({ length: count }, () => randomBytes(size));
  }

  describe("Proof Size Tests", function () {
    it("should have empty proof for single element tree", function () {
      const messages = createRandomMessages(1);
      const tree = new MerkleTree(messages);
      const proof = tree.getProof(messages[0]);

      expect(proof).to.be.an("array").that.is.empty;
    });

    it("should have ceil(log2(n)) proof elements for even message count", function () {
      const testCases = [2, 4, 6, 8, 10];

      for (const count of testCases) {
        const messages = createRandomMessages(count);
        const tree = new MerkleTree(messages);

        for (const message of messages) {
          const proof = tree.getProof(message);
          const expectedProofSize = Math.ceil(Math.log2(count));

          expect(proof).to.have.lengthOf(
            expectedProofSize,
            `Proof length for ${count} messages should be ${expectedProofSize}`
          );
        }
      }
    });

    it("should have ceil(log2(n)) proof elements for odd message count", function () {
      const testCases = [3, 5, 7, 9, 15];

      for (const count of testCases) {
        const messages = createRandomMessages(count);
        const tree = new MerkleTree(messages);

        for (const message of messages) {
          const proof = tree.getProof(message);
          const expectedProofSize = Math.ceil(Math.log2(count));

          expect(proof).to.have.lengthOf(
            expectedProofSize,
            `Proof length for ${count} messages should be ${expectedProofSize}`
          );
        }
      }
    });

    it("should have consistent proof size for all elements in the same tree", function () {
      for (const count of [3, 5, 8, 10]) {
        const messages = createRandomMessages(count);
        const tree = new MerkleTree(messages);

        const proofLengths = new Set();
        for (const message of messages) {
          const proof = tree.getProof(message);
          proofLengths.add(proof.length);
        }

        expect(proofLengths.size).to.equal(
          1,
          `All proofs for ${count} messages should have the same length`
        );
      }
    });
  });
});
