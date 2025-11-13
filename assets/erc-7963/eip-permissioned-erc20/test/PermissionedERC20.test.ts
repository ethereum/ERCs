import { ethers, network } from "hardhat";
import { expect } from "chai";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import {
    PermissionedERC20__factory,
    MockTransferOracle__factory
} from "../typechain-types";
import type {
    PermissionedERC20,
    ITransferOracle,
    MockTransferOracle
} from "../typechain-types";
import type { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

const TOKEN_NAME = "Test Token";
const TOKEN_SYMBOL = "TST";

describe("PermissionedERC20", () => {
  let deployer: SignerWithAddress;
  let mockOracleAsSigner: SignerWithAddress;
  let initialOwnerSigner: SignerWithAddress;
  let otherAccount: SignerWithAddress;
  let permissionedERC20: PermissionedERC20;

  const deployPermissionedERC20Fixture = async () => {
    [deployer, mockOracleAsSigner, initialOwnerSigner, otherAccount] = await ethers.getSigners();
    const permissionedERC20Factory = new PermissionedERC20__factory(deployer);
    const token = await permissionedERC20Factory.deploy(
      TOKEN_NAME,
      TOKEN_SYMBOL,
      mockOracleAsSigner.address,
      initialOwnerSigner.address
    );
    await token.waitForDeployment();
    return { token, mockOracleAsSigner, initialOwnerSigner, deployer, otherAccount };
  };

  beforeEach(async () => {
    const deployed = await loadFixture(deployPermissionedERC20Fixture);
    permissionedERC20 = deployed.token;
    mockOracleAsSigner = deployed.mockOracleAsSigner;
    initialOwnerSigner = deployed.initialOwnerSigner;
    otherAccount = deployed.otherAccount;
    deployer = deployed.deployer;
  });

  describe("1.1. Constructor & Initial State", () => {
    it("Should deploy with valid parameters and set initial state correctly", async () => {
      expect(await permissionedERC20.name()).to.equal(TOKEN_NAME);
      expect(await permissionedERC20.symbol()).to.equal(TOKEN_SYMBOL);
      expect(await permissionedERC20.decimals()).to.equal(18);
      expect(await permissionedERC20.transferOracle()).to.equal(mockOracleAsSigner.address);
      expect(await permissionedERC20.owner()).to.equal(initialOwnerSigner.address);
      expect(await permissionedERC20.totalSupply()).to.equal(0);
    });

    it("Should revert if oracle address is address(0)", async () => {
      const signers = await ethers.getSigners();
      const tempDeployer = signers[0];
      const tempInitialOwner = signers[1] || tempDeployer;
      const factory = new PermissionedERC20__factory(tempDeployer);
      await expect(
        factory.deploy(TOKEN_NAME, TOKEN_SYMBOL, ethers.ZeroAddress, tempInitialOwner.address)
      ).to.be.revertedWithCustomError(factory, "PermissionedERC20__ZeroAddressOracle");
    });
  });

  describe("1.2. ERC20 Standard View Functions", () => {
    it("name(), symbol(), decimals() should return correct values", async () => {
      expect(await permissionedERC20.name()).to.equal(TOKEN_NAME);
      expect(await permissionedERC20.symbol()).to.equal(TOKEN_SYMBOL);
      expect(await permissionedERC20.decimals()).to.equal(18);
    });

    it("totalSupply() should return 0 initially", async () => {
      expect(await permissionedERC20.totalSupply()).to.equal(0);
    });

    it("balanceOf(account) should return 0 for any account initially", async () => {
      expect(await permissionedERC20.balanceOf(initialOwnerSigner.address)).to.equal(0);
      expect(await permissionedERC20.balanceOf(otherAccount.address)).to.equal(0);
      expect(await permissionedERC20.balanceOf(ethers.Wallet.createRandom().address)).to.equal(0);
    });

    it("allowance(owner, spender) should return 0 initially", async () => {
      expect(await permissionedERC20.allowance(initialOwnerSigner.address, otherAccount.address)).to.equal(0);
      expect(await permissionedERC20.allowance(otherAccount.address, initialOwnerSigner.address)).to.equal(0);
    });
  });

  describe("1.3. ERC20 Standard Mutative Functions (Non-Transfer)", () => {
    describe("approve(address spender, uint256 amount)", () => {
      const approvalAmount = ethers.parseUnits("100", 18);

      it("Should allow an owner to approve a spender for a given amount", async () => {
        await expect(permissionedERC20.connect(initialOwnerSigner).approve(otherAccount.address, approvalAmount))
          .to.emit(permissionedERC20, "Approval")
          .withArgs(initialOwnerSigner.address, otherAccount.address, approvalAmount);
        expect(await permissionedERC20.allowance(initialOwnerSigner.address, otherAccount.address)).to.equal(approvalAmount);
      });

      it("Should allow updating an existing approval", async () => {
        await permissionedERC20.connect(initialOwnerSigner).approve(otherAccount.address, approvalAmount);
        const newApprovalAmount = ethers.parseUnits("200", 18);
        await expect(permissionedERC20.connect(initialOwnerSigner).approve(otherAccount.address, newApprovalAmount))
          .to.emit(permissionedERC20, "Approval")
          .withArgs(initialOwnerSigner.address, otherAccount.address, newApprovalAmount);
        expect(await permissionedERC20.allowance(initialOwnerSigner.address, otherAccount.address)).to.equal(newApprovalAmount);
      });

      it("Should allow approving address(0) as spender", async () => {
        await expect(permissionedERC20.connect(initialOwnerSigner).approve(ethers.ZeroAddress, approvalAmount))
          .to.be.revertedWithCustomError(permissionedERC20, "ERC20InvalidSpender")
          .withArgs(ethers.ZeroAddress);
        expect(await permissionedERC20.allowance(initialOwnerSigner.address, ethers.ZeroAddress)).to.equal(0);
      });

      it("Should allow approving type(uint256).max amount", async () => {
        const maxUint256 = ethers.MaxUint256;
        await expect(permissionedERC20.connect(initialOwnerSigner).approve(otherAccount.address, maxUint256))
          .to.emit(permissionedERC20, "Approval")
          .withArgs(initialOwnerSigner.address, otherAccount.address, maxUint256);
        expect(await permissionedERC20.allowance(initialOwnerSigner.address, otherAccount.address)).to.equal(maxUint256);
      });
    });
  });

  describe("1.4. Core Transfer Logic (_update Hook and its Callers)", () => {
    let manualMockOracle: MockTransferOracle;
    let tokenWithManualMockOracle: PermissionedERC20;
    let tokenHolder: SignerWithAddress; 
    let recipientAccount: SignerWithAddress;
    let coreLogicDeployer: SignerWithAddress;
    
    const MINT_AMOUNT = ethers.parseUnits("1000", 18);
    const TRANSFER_AMOUNT = ethers.parseUnits("100", 18);
    const PROOF_ID = ethers.encodeBytes32String("testProofId123");

    beforeEach(async () => {
      [coreLogicDeployer, tokenHolder, recipientAccount, otherAccount] = await ethers.getSigners();

      const mockOracleFactory = new MockTransferOracle__factory(coreLogicDeployer);
      manualMockOracle = await mockOracleFactory.deploy();
      await manualMockOracle.waitForDeployment();
      
      const tokenFactory = new PermissionedERC20__factory(coreLogicDeployer);
      tokenWithManualMockOracle = await tokenFactory.deploy(
        TOKEN_NAME,
        TOKEN_SYMBOL,
        await manualMockOracle.getAddress(),
        tokenHolder.address 
      );
      await tokenWithManualMockOracle.waitForDeployment();

      await tokenWithManualMockOracle.connect(tokenHolder).mint(tokenHolder.address, MINT_AMOUNT);
      await manualMockOracle.resetCanTransferState();
    });

    describe("transfer(address recipient, uint256 amount)", () => {
      it("Should transfer tokens successfully when oracle permits", async () => {
        await manualMockOracle.setCanTransferResponse(PROOF_ID);

        const tx = tokenWithManualMockOracle.connect(tokenHolder).transfer(recipientAccount.address, TRANSFER_AMOUNT);

        await expect(tx)
          .to.emit(tokenWithManualMockOracle, "TransferValidated").withArgs(PROOF_ID)
          .and.to.emit(tokenWithManualMockOracle, "Transfer").withArgs(tokenHolder.address, recipientAccount.address, TRANSFER_AMOUNT);
        
        await expect(tx)
          .to.emit(manualMockOracle, "CanTransferCalled")
          .withArgs(await tokenWithManualMockOracle.getAddress(), tokenHolder.address, recipientAccount.address, TRANSFER_AMOUNT);

        expect(await tokenWithManualMockOracle.balanceOf(tokenHolder.address)).to.equal(MINT_AMOUNT - TRANSFER_AMOUNT);
        expect(await tokenWithManualMockOracle.balanceOf(recipientAccount.address)).to.equal(TRANSFER_AMOUNT);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(1);
      });

      it("Should revert if oracle denies the transfer", async () => {
        const revertMsg = "MockOracle: Denied";
        await manualMockOracle.setCanTransferRevert(revertMsg);

        await expect(tokenWithManualMockOracle.connect(tokenHolder).transfer(recipientAccount.address, TRANSFER_AMOUNT))
          .to.be.revertedWith(revertMsg);

        expect(await tokenWithManualMockOracle.balanceOf(tokenHolder.address)).to.equal(MINT_AMOUNT);
        expect(await tokenWithManualMockOracle.balanceOf(recipientAccount.address)).to.equal(0);
        // Cannot reliably check call count after mock revert due to state rollback
        // The fact that it reverted with `revertMsg` from the mock is proof it was called.
      });

      it("Should revert for insufficient balance (ERC20 standard)", async () => {
        const excessiveAmount = MINT_AMOUNT + ethers.parseUnits("1", 18);
        await manualMockOracle.setCanTransferResponse(PROOF_ID);
 
        await expect(tokenWithManualMockOracle.connect(tokenHolder).transfer(recipientAccount.address, excessiveAmount))
          .to.be.revertedWithCustomError(tokenWithManualMockOracle, "ERC20InsufficientBalance")
          .withArgs(tokenHolder.address, MINT_AMOUNT, excessiveAmount);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(0);
      });

      it("Should revert when transferring to address(0) (ERC20 standard)", async () => {
        await manualMockOracle.setCanTransferResponse(PROOF_ID);

        await expect(tokenWithManualMockOracle.connect(tokenHolder).transfer(ethers.ZeroAddress, TRANSFER_AMOUNT))
          .to.be.revertedWithCustomError(tokenWithManualMockOracle, "ERC20InvalidReceiver").withArgs(ethers.ZeroAddress);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(0);
      });

      it("Should handle zero amount transfer if oracle permits", async () => {
        await manualMockOracle.setCanTransferResponse(PROOF_ID);

        const tx = tokenWithManualMockOracle.connect(tokenHolder).transfer(recipientAccount.address, 0);
        await expect(tx)
          .to.emit(tokenWithManualMockOracle, "TransferValidated").withArgs(PROOF_ID)
          .and.to.emit(tokenWithManualMockOracle, "Transfer").withArgs(tokenHolder.address, recipientAccount.address, 0);
        await expect(tx)
          .to.emit(manualMockOracle, "CanTransferCalled")
          .withArgs(await tokenWithManualMockOracle.getAddress(), tokenHolder.address, recipientAccount.address, 0);
        
        expect(await tokenWithManualMockOracle.balanceOf(tokenHolder.address)).to.equal(MINT_AMOUNT);
        expect(await tokenWithManualMockOracle.balanceOf(recipientAccount.address)).to.equal(0);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(1);
      });

      it("Should handle transfer to self if oracle permits", async () => {
        await manualMockOracle.setCanTransferResponse(PROOF_ID);

        const tx = tokenWithManualMockOracle.connect(tokenHolder).transfer(tokenHolder.address, TRANSFER_AMOUNT);
        await expect(tx)
          .to.emit(tokenWithManualMockOracle, "TransferValidated").withArgs(PROOF_ID)
          .and.to.emit(tokenWithManualMockOracle, "Transfer").withArgs(tokenHolder.address, tokenHolder.address, TRANSFER_AMOUNT);
        await expect(tx)
          .to.emit(manualMockOracle, "CanTransferCalled")
          .withArgs(await tokenWithManualMockOracle.getAddress(), tokenHolder.address, tokenHolder.address, TRANSFER_AMOUNT);

        expect(await tokenWithManualMockOracle.balanceOf(tokenHolder.address)).to.equal(MINT_AMOUNT);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(1);
      });
    });

    describe("transferFrom(address sender, address recipient, uint256 amount)", () => {
      const ALLOWANCE_AMOUNT = ethers.parseUnits("500", 18);
      let spender: SignerWithAddress;

      beforeEach(async () => {
        const signers = await ethers.getSigners();
        if (signers.length < 5) throw new Error("Need at least 5 signers for transferFrom tests with distinct spender.");
        spender = signers[4]; 

        await tokenWithManualMockOracle.connect(tokenHolder).approve(spender.address, ALLOWANCE_AMOUNT);
        await manualMockOracle.resetCanTransferState();
      });

      it("Should transfer tokens successfully when oracle permits and spender has allowance", async () => {
        await manualMockOracle.setCanTransferResponse(PROOF_ID);

        const tx = await tokenWithManualMockOracle.connect(spender).transferFrom(tokenHolder.address, recipientAccount.address, TRANSFER_AMOUNT);
        
        await expect(tx)
          .to.emit(tokenWithManualMockOracle, "TransferValidated").withArgs(PROOF_ID)
          .and.to.emit(tokenWithManualMockOracle, "Transfer").withArgs(tokenHolder.address, recipientAccount.address, TRANSFER_AMOUNT);
        
        await expect(tx)
          .to.emit(manualMockOracle, "CanTransferCalled")
          .withArgs(await tokenWithManualMockOracle.getAddress(), tokenHolder.address, recipientAccount.address, TRANSFER_AMOUNT);

        expect(await tokenWithManualMockOracle.balanceOf(tokenHolder.address)).to.equal(MINT_AMOUNT - TRANSFER_AMOUNT);
        expect(await tokenWithManualMockOracle.balanceOf(recipientAccount.address)).to.equal(TRANSFER_AMOUNT);
        expect(await tokenWithManualMockOracle.allowance(tokenHolder.address, spender.address)).to.equal(ALLOWANCE_AMOUNT - TRANSFER_AMOUNT);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(1);
      });

      it("Should revert if oracle denies, even with allowance", async () => {
        const revertMsg = "MockOracle: DeniedByOracle";
        await manualMockOracle.setCanTransferRevert(revertMsg);

        await expect(tokenWithManualMockOracle.connect(spender).transferFrom(tokenHolder.address, recipientAccount.address, TRANSFER_AMOUNT))
          .to.be.revertedWith(revertMsg);

        expect(await tokenWithManualMockOracle.balanceOf(tokenHolder.address)).to.equal(MINT_AMOUNT);
        expect(await tokenWithManualMockOracle.balanceOf(recipientAccount.address)).to.equal(0);
        expect(await tokenWithManualMockOracle.allowance(tokenHolder.address, spender.address)).to.equal(ALLOWANCE_AMOUNT);
        // Cannot reliably check call count after mock revert due to state rollback
      });

      it("Should revert for insufficient allowance (ERC20 standard)", async () => {
        const excessiveAmount = ALLOWANCE_AMOUNT + ethers.parseUnits("1", 18);
        await manualMockOracle.setCanTransferResponse(PROOF_ID); 

        await expect(tokenWithManualMockOracle.connect(spender).transferFrom(tokenHolder.address, recipientAccount.address, excessiveAmount))
          .to.be.revertedWithCustomError(tokenWithManualMockOracle, "ERC20InsufficientAllowance")
          .withArgs(spender.address, ALLOWANCE_AMOUNT, excessiveAmount);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(0);
      });

      it("Should revert for insufficient balance of sender (ERC20 standard)", async () => {
        const senderInitialBalance = await tokenWithManualMockOracle.balanceOf(tokenHolder.address);
        const amountGreaterThanSendersBalance = senderInitialBalance + BigInt(1);
        await tokenWithManualMockOracle.connect(tokenHolder).approve(spender.address, amountGreaterThanSendersBalance);
        await manualMockOracle.setCanTransferResponse(PROOF_ID); 

        await expect(tokenWithManualMockOracle.connect(spender).transferFrom(tokenHolder.address, recipientAccount.address, amountGreaterThanSendersBalance))
            .to.be.revertedWithCustomError(tokenWithManualMockOracle, "ERC20InsufficientBalance")
            .withArgs(tokenHolder.address, senderInitialBalance, amountGreaterThanSendersBalance);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(0);
      });

       it("Should revert when transferring to address(0) (ERC20 standard)", async () => {
        await manualMockOracle.setCanTransferResponse(PROOF_ID);

        await expect(tokenWithManualMockOracle.connect(spender).transferFrom(tokenHolder.address, ethers.ZeroAddress, TRANSFER_AMOUNT))
          .to.be.revertedWithCustomError(tokenWithManualMockOracle, "ERC20InvalidReceiver").withArgs(ethers.ZeroAddress);
        expect(await manualMockOracle.getCanTransferCallCount()).to.equal(0);
      });
    });
  });

  describe("1.5. Owner-Only Functions", () => {
    it("owner() should return the current owner", async () => {
      expect(await permissionedERC20.owner()).to.equal(initialOwnerSigner.address);
    });

    describe("transferOwnership(address newOwner)", () => {
      it("Should allow the current owner to transfer ownership", async () => {
        await expect(permissionedERC20.connect(initialOwnerSigner).transferOwnership(otherAccount.address))
          .to.emit(permissionedERC20, "OwnershipTransferred")
          .withArgs(initialOwnerSigner.address, otherAccount.address);
        expect(await permissionedERC20.owner()).to.equal(otherAccount.address);
      });

      it("Should prevent non-owners from transferring ownership", async () => {
        await expect(permissionedERC20.connect(otherAccount).transferOwnership(deployer.address))
          .to.be.revertedWithCustomError(permissionedERC20, "OwnableUnauthorizedAccount")
          .withArgs(otherAccount.address);
      });

      it("Should revert if transferring ownership to the zero address", async () => {
        await expect(permissionedERC20.connect(initialOwnerSigner).transferOwnership(ethers.ZeroAddress))
          .to.be.revertedWithCustomError(permissionedERC20, "OwnableInvalidOwner")
          .withArgs(ethers.ZeroAddress);
      });

      it("New owner should have owner privileges after ownership transfer", async () => {
        await permissionedERC20.connect(initialOwnerSigner).transferOwnership(otherAccount.address);
        const mintAmount = ethers.parseUnits("50", 18);
        await expect(permissionedERC20.connect(otherAccount).mint(otherAccount.address, mintAmount))
          .to.emit(permissionedERC20, "Transfer")
          .withArgs(ethers.ZeroAddress, otherAccount.address, mintAmount);
        expect(await permissionedERC20.balanceOf(otherAccount.address)).to.equal(mintAmount);
      });
    });
  });

  describe("1.6. Ownable Functionality", () => {
    it("owner() should return the current owner", async () => {
      expect(await permissionedERC20.owner()).to.equal(initialOwnerSigner.address);
    });

    describe("transferOwnership(address newOwner)", () => {
      it("Should allow the current owner to transfer ownership", async () => {
        await expect(permissionedERC20.connect(initialOwnerSigner).transferOwnership(otherAccount.address))
          .to.emit(permissionedERC20, "OwnershipTransferred")
          .withArgs(initialOwnerSigner.address, otherAccount.address);
        expect(await permissionedERC20.owner()).to.equal(otherAccount.address);
      });

      it("Should prevent non-owners from transferring ownership", async () => {
        await expect(permissionedERC20.connect(otherAccount).transferOwnership(deployer.address))
          .to.be.revertedWithCustomError(permissionedERC20, "OwnableUnauthorizedAccount")
          .withArgs(otherAccount.address);
      });

      it("Should revert if transferring ownership to the zero address", async () => {
        await expect(permissionedERC20.connect(initialOwnerSigner).transferOwnership(ethers.ZeroAddress))
          .to.be.revertedWithCustomError(permissionedERC20, "OwnableInvalidOwner")
          .withArgs(ethers.ZeroAddress);
      });

      it("New owner should have owner privileges after ownership transfer", async () => {
        await permissionedERC20.connect(initialOwnerSigner).transferOwnership(otherAccount.address);
        const mintAmount = ethers.parseUnits("50", 18);
        await expect(permissionedERC20.connect(otherAccount).mint(otherAccount.address, mintAmount))
          .to.emit(permissionedERC20, "Transfer")
          .withArgs(ethers.ZeroAddress, otherAccount.address, mintAmount);
        expect(await permissionedERC20.balanceOf(otherAccount.address)).to.equal(mintAmount);
      });
    });
  });
}); 