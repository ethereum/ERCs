import { expect } from "chai";
import { ethers } from "hardhat";
import { ExampleVerifier } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { MerkleTree } from "../src/merkle";

describe("SolidityTests", function () {
  let verifier: ExampleVerifier;
  let signer: SignerWithAddress;
  let otherAccount: SignerWithAddress;
  let signerWallet: ethers.Wallet;
  let otherWallet: ethers.Wallet;

  const orders = [
    {
      orderId: ethers.id("order1"),
      user: "0x1234567890123456789012345678901234567890",
    },
    {
      orderId: ethers.id("order2"),
      user: "0x2345678901234567890123456789012345678901",
    },
    {
      orderId: ethers.id("order3"),
      user: "0x3456789012345678901234567890123456789012",
    },
  ];

  async function getOrderHash(order: {
    orderId: string;
    user: string;
  }): Promise<Buffer> {
    const contractHash = await verifier.debugGenerateMessageHash(
      order.orderId,
      order.user
    );
    return Buffer.from(contractHash.slice(2), "hex");
  }

  beforeEach(async function () {
    const VerifierFactory = await ethers.getContractFactory("ExampleVerifier");
    verifier = await VerifierFactory.deploy();
    await verifier.waitForDeployment();

    [signer, otherAccount] = await ethers.getSigners();

    signerWallet = ethers.Wallet.createRandom().connect(ethers.provider);
    otherWallet = ethers.Wallet.createRandom().connect(ethers.provider);

    orders[0].user = signerWallet.address;
    orders[1].user = signerWallet.address;
    orders[2].user = signerWallet.address;
  });

  it("should successfully place an order with a composite signature", async function () {
    const orderHashes = await Promise.all(orders.map(getOrderHash));
    const tree = new MerkleTree(orderHashes);
    const merkleRoot = `0x${tree.getRoot().toString("hex")}`;
    const signature = signerWallet.signingKey.sign(tree.getRoot()).serialized;

    const proof = tree
      .getProof(orderHashes[0])
      .map((p) => `0x${p.toString("hex")}`);

    await expect(
      verifier.placeOrder(
        orders[0].orderId,
        signerWallet.address,
        signature,
        merkleRoot,
        proof
      )
    ).to.not.be.reverted;
  });

  it("should reject an order with invalid proof", async function () {
    const orderHashes = await Promise.all(orders.map(getOrderHash));
    const tree = new MerkleTree(orderHashes);
    const merkleRoot = `0x${tree.getRoot().toString("hex")}`;
    const signature = signerWallet.signingKey.sign(tree.getRoot()).serialized;

    // Use a valid proof but for a different order ID (intentionally wrong)
    const invalidOrderId = ethers.id("invalid-order");
    const proof = tree
      .getProof(orderHashes[0])
      .map((p) => `0x${p.toString("hex")}`);

    await expect(
      verifier.placeOrder(
        invalidOrderId,
        signerWallet.address,
        signature,
        merkleRoot,
        proof
      )
    ).to.be.revertedWithCustomError(verifier, "NotInTree");
  });

  it("should directly sign and verify a single-element merkle tree", async function () {
    const order = orders[0];
    const messageHash = await verifier.debugGenerateMessageHash(
      order.orderId,
      order.user
    );
    const leaf = Buffer.from(messageHash.slice(2), "hex");
    const tree = new MerkleTree([leaf]);
    const merkleRoot = `0x${tree.getRoot().toString("hex")}`;
    const signature = signerWallet.signingKey.sign(tree.getRoot()).serialized;

    await expect(
      verifier.placeOrder(
        order.orderId,
        signerWallet.address,
        signature,
        merkleRoot,
        // Proof for a single element tree is empty...
        [] as string[]
      )
    ).to.not.be.reverted;
  });

  it("should verify all orders with the same signature", async function () {
    const orderHashes = await Promise.all(orders.map(getOrderHash));
    const tree = new MerkleTree(orderHashes);
    const merkleRoot = `0x${tree.getRoot().toString("hex")}`;
    const signature = signerWallet.signingKey.sign(tree.getRoot()).serialized;

    // Verify each order works with the same signature
    for (let i = 0; i < orders.length; i++) {
      const proof = tree
        .getProof(orderHashes[i])
        .map((p) => `0x${p.toString("hex")}`);

      await expect(
        verifier.placeOrder(
          orders[i].orderId,
          signerWallet.address,
          signature,
          merkleRoot,
          proof
        )
      ).to.not.be.reverted;
    }
  });

  it("should reject a signature from a different signer", async function () {
    const orderHashes = await Promise.all(orders.map(getOrderHash));
    const tree = new MerkleTree(orderHashes);
    const merkleRoot = `0x${tree.getRoot().toString("hex")}`;

    // Sign with the other wallet (different than the one in the order.user field)
    const wrongSignature = otherWallet.signingKey.sign(
      tree.getRoot()
    ).serialized;

    const proof = tree
      .getProof(orderHashes[0])
      .map((p) => `0x${p.toString("hex")}`);

    await expect(
      verifier.placeOrder(
        orders[0].orderId,
        signerWallet.address, // The actual order owner
        wrongSignature,
        merkleRoot,
        proof
      )
    ).to.be.revertedWithCustomError(verifier, "Unauthorized");
  });
});
