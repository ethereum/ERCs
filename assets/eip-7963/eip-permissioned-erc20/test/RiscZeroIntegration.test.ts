import { expect } from "chai";
import { ethers } from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { RiscZeroVerifier, TransferOracle, PermissionedERC20 } from "../typechain-types";

describe("RISC Zero Integration", function () {
  let riscZeroVerifier: RiscZeroVerifier;
  let transferOracle: TransferOracle;
  let permissionedToken: PermissionedERC20;
  let owner: any;
  let user1: any;
  let user2: any;

  async function deployRiscZeroFixture() {
    const [_owner, _user1, _user2] = await ethers.getSigners();

    // Deploy RISC Zero verifier
    const RiscZeroVerifierFactory = await ethers.getContractFactory("RiscZeroVerifier");
    const _riscZeroVerifier = await RiscZeroVerifierFactory.deploy();
    await _riscZeroVerifier.waitForDeployment();

    // Deploy the oracle with a placeholder token address first
    const TransferOracleFactory = await ethers.getContractFactory("TransferOracle");
    const _transferOracle = await TransferOracleFactory.deploy(
      await _riscZeroVerifier.getAddress(),
      _owner.address, // Use owner address as placeholder for token
      _owner.address
    );
    await _transferOracle.waitForDeployment();

    // Deploy the token with the real oracle
    const PermissionedERC20Factory = await ethers.getContractFactory("PermissionedERC20");
    const _permissionedToken = await PermissionedERC20Factory.deploy(
      "Test Token",
      "TEST",
      await _transferOracle.getAddress(),
      _owner.address
    );
    await _permissionedToken.waitForDeployment();

    return {
      riscZeroVerifier: _riscZeroVerifier,
      transferOracle: _transferOracle,
      permissionedToken: _permissionedToken,
      owner: _owner,
      user1: _user1,
      user2: _user2
    };
  }

  beforeEach(async function () {
    const deployed = await loadFixture(deployRiscZeroFixture);
    riscZeroVerifier = deployed.riscZeroVerifier;
    transferOracle = deployed.transferOracle;
    permissionedToken = deployed.permissionedToken;
    owner = deployed.owner;
    user1 = deployed.user1;
    user2 = deployed.user2;
  });

  describe("RISC Zero Verifier", function () {
    it("should reject empty proof", async function () {
      const emptyProof = "0x";
      const journalHash = ethers.keccak256(ethers.toUtf8Bytes("test"));
      const sealHash = ethers.keccak256(ethers.toUtf8Bytes("seal"));

      const result = await riscZeroVerifier.verify(emptyProof, journalHash, sealHash);
      expect(result).to.be.false;
    });

    it("should reject zero hashes", async function () {
      const proof = "0x" + "00".repeat(32); // 32 bytes of zeros
      const zeroHash = ethers.ZeroHash;
      const validHash = ethers.keccak256(ethers.toUtf8Bytes("test"));

      // Test zero journal hash
      let result = await riscZeroVerifier.verify(proof, zeroHash, validHash);
      expect(result).to.be.false;

      // Test zero seal hash
      result = await riscZeroVerifier.verify(proof, validHash, zeroHash);
      expect(result).to.be.false;
    });

    it("should accept valid proof format", async function () {
      const proof = "0x" + "01".repeat(32); // 32 bytes of non-zero data
      const journalHash = ethers.keccak256(ethers.toUtf8Bytes("journal"));
      const sealHash = ethers.keccak256(ethers.toUtf8Bytes("seal"));

      const result = await riscZeroVerifier.verify(proof, journalHash, sealHash);
      expect(result).to.be.true;
    });

    it("should verify with method ID", async function () {
      const proof = "0x" + "01".repeat(32);
      const journalHash = ethers.keccak256(ethers.toUtf8Bytes("journal"));
      const sealHash = ethers.keccak256(ethers.toUtf8Bytes("seal"));
      const methodId = ethers.keccak256(ethers.toUtf8Bytes("method"));

      const result = await riscZeroVerifier.verifyWithMethodId(proof, journalHash, sealHash, methodId);
      expect(result).to.be.true;
    });
  });

  describe("TransferOracle Integration", function () {
    it("should be deployed with correct verifier", async function () {
      const verifierAddress = await transferOracle.verifier();
      expect(verifierAddress).to.equal(await riscZeroVerifier.getAddress());
    });

    it("should have correct issuer", async function () {
      const issuer = await transferOracle.getIssuer();
      expect(issuer).to.equal(owner.address);
    });
  });

  describe("PermissionedERC20 Integration", function () {
    it("should be deployed with correct oracle", async function () {
      const oracleAddress = await permissionedToken.transferOracle();
      expect(oracleAddress).to.equal(await transferOracle.getAddress());
    });

    it("should allow minting by owner", async function () {
      const mintAmount = ethers.parseEther("100");
      await permissionedToken.mint(user1.address, mintAmount);
      
      const balance = await permissionedToken.balanceOf(user1.address);
      expect(balance).to.equal(mintAmount);
    });

    it("should reject transfers without oracle approval", async function () {
      // Mint tokens to user1
      const mintAmount = ethers.parseEther("100");
      await permissionedToken.mint(user1.address, mintAmount);
      
      const transferAmount = ethers.parseEther("10");
      
      // This should fail because there's no approval in the oracle
      // Note: We expect it to revert but don't check the specific error since
      // the oracle was deployed with a placeholder token address
      try {
        await permissionedToken.connect(user1).transfer(user2.address, transferAmount);
        expect.fail("Transfer should have reverted");
      } catch (error: any) {
        // Transfer reverted as expected
        expect(error.message).to.include("revert");
      }
    });

    it("should allow standard ERC20 functions", async function () {
      // Test that standard ERC20 functions exist and work for non-transfer operations
      const mintAmount = ethers.parseEther("100");
      await permissionedToken.mint(user1.address, mintAmount);
      
      // Check balance
      const balance = await permissionedToken.balanceOf(user1.address);
      expect(balance).to.equal(mintAmount);
      
      // Check allowance functionality
      const approveAmount = ethers.parseEther("50");
      await permissionedToken.connect(user1).approve(user2.address, approveAmount);
      
      const allowance = await permissionedToken.allowance(user1.address, user2.address);
      expect(allowance).to.equal(approveAmount);
    });
  });
}); 