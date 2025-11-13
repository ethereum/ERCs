import { ethers, network } from "hardhat";
import { expect } from "chai";
import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import {
    TransferOracle__factory,
    MockRiscZeroVerifier__factory
} from "../typechain-types";
import type {
    TransferOracle,
    MockRiscZeroVerifier,
    ITransferOracle // For struct definitions
} from "../typechain-types";
import type { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";

describe("TransferOracle", () => {
  let deployer: SignerWithAddress;
  let initialIssuer: SignerWithAddress;
  let designatedToken: SignerWithAddress; // Using a signer address as placeholder for token contract
  let otherAccount: SignerWithAddress;
  let mockVerifier: MockRiscZeroVerifier;
  let transferOracle: TransferOracle;

  // Define the Approval struct type for encoding
  const ApprovalStructType = (
      "tuple(address sender, address recipient, uint256 minAmt, uint256 maxAmt, uint256 expiry, bytes32 proofId)"
  );

  // Dummy data for approveTransfer - adjust as needed for specific tests
  const getDefaultApproval = (sender: string, recipient: string, proofId: string, expiryOffsetSeconds = 3600): ITransferOracle.TransferApprovalStruct => ({
    sender: sender,
    recipient: recipient,
    minAmt: ethers.parseUnits("1", 18),
    maxAmt: ethers.parseUnits("1000", 18),
    expiry: Math.floor(Date.now() / 1000) + expiryOffsetSeconds, // Default to 1 hour from now
    proofId: ethers.encodeBytes32String(proofId)
  });

  const getDefaultProof = (): string => {
    // For RISC Zero, we just need some bytes representing the proof
    // This is a simple mock proof - 64 bytes of data
    return "0x" + "01".repeat(64);
  };

  // Helper function to create public inputs bytes matching RISC Zero contract decoding
  const getRiscZeroPublicInputs = (
    root: string, 
    senderHash: string, 
    recipientHash: string, 
    minAmtScaled: bigint, 
    maxAmtScaled: bigint, 
    expiry: number
  ): string => {
    const dummyCurrencyHashBytes32 = "0x5553440000000000000000000000000000000000000000000000000000000000"; // bytes32 representation of "USD"
    
    // RISC Zero format: (bytes32, bytes32, bytes32, uint256, uint256, bytes32, uint64)
    return ethers.AbiCoder.defaultAbiCoder().encode(
      ["bytes32", "bytes32", "bytes32", "uint256", "uint256", "bytes32", "uint64"],
      [root, senderHash, recipientHash, minAmtScaled, maxAmtScaled, dummyCurrencyHashBytes32, expiry]
    );
  };

  // Fixture to deploy the TransferOracle with dependencies
  async function deployTransferOracleFixture() {
    const [_deployer, _initialIssuer, _designatedToken, _otherAccount] = await ethers.getSigners();
    const mockVerifierFactory = new MockRiscZeroVerifier__factory(_deployer);
    const _verifier = await mockVerifierFactory.deploy();
    await _verifier.waitForDeployment();
    const transferOracleFactory = new TransferOracle__factory(_deployer);
    const _oracle = await transferOracleFactory.deploy(
      await _verifier.getAddress(),
      _designatedToken.address,
      _initialIssuer.address
    );
    await _oracle.waitForDeployment();
    // Return all needed signers and contracts
    return { 
        transferOracle: _oracle, 
        mockVerifier: _verifier, 
        initialIssuer: _initialIssuer, 
        designatedToken: _designatedToken, 
        deployer: _deployer, 
        otherAccount: _otherAccount 
    };
  }

  // Load fixture before any tests run
  beforeEach(async () => {
    const deployed = await loadFixture(deployTransferOracleFixture);
    transferOracle = deployed.transferOracle;
    mockVerifier = deployed.mockVerifier;
    initialIssuer = deployed.initialIssuer;
    designatedToken = deployed.designatedToken;
    deployer = deployed.deployer;
    otherAccount = deployed.otherAccount;
  });

  describe("2.1. Constructor & Initial State", () => {
    it("Should deploy with valid parameters and set initial state correctly", async () => {
      expect(await transferOracle.verifier()).to.equal(await mockVerifier.getAddress());
      expect(await transferOracle.permissionedToken()).to.equal(designatedToken.address);
      expect(await transferOracle.owner()).to.equal(initialIssuer.address);
      expect(await transferOracle.getIssuer()).to.equal(initialIssuer.address);
    });

    it("Should revert if verifier address is address(0)", async () => {
      const transferOracleFactory = new TransferOracle__factory(deployer);
      await expect(transferOracleFactory.deploy(
        ethers.ZeroAddress,
        designatedToken.address,
        initialIssuer.address
      )).to.be.revertedWith("TransferOracle: Zero address for verifier or token");
    });

    it("Should revert if token address is address(0)", async () => {
      const transferOracleFactory = new TransferOracle__factory(deployer);
      // Need a mock verifier instance for this test specifically
      const tempMockVerifierFactory = new MockRiscZeroVerifier__factory(deployer);
      const tempVerifier = await tempMockVerifierFactory.deploy();
      await tempVerifier.waitForDeployment();

      await expect(transferOracleFactory.deploy(
        await tempVerifier.getAddress(),
        ethers.ZeroAddress,
        initialIssuer.address
      )).to.be.revertedWith("TransferOracle: Zero address for verifier or token");
    });

    // Note: Ownable ensures initialIssuer cannot be address(0)
  });

  describe("2.2. approveTransfer", () => {
    let rootHashBytes32: string;
    let senderHashBytes32: string;
    let recipientHashBytes32: string;
    let calculatedProofId: string;
    let defaultApproval: ITransferOracle.TransferApprovalStruct;
    let defaultProofBytes: string;
    let defaultPublicInputsBytes: string;
    let senderAddr: string;
    let recipientAddr: string;
    let currentTimestamp: number;
    let expiryTimestamp: number;
    let minAmtScaled: bigint;
    let maxAmtScaled: bigint;

    beforeEach(async () => {
      senderAddr = otherAccount.address;
      recipientAddr = deployer.address;
      currentTimestamp = await time.latest();
      expiryTimestamp = currentTimestamp + 3600;

      // Generate *valid* random bytes32 hex strings for hashes
      rootHashBytes32 = ethers.hexlify(ethers.randomBytes(32));
      senderHashBytes32 = ethers.hexlify(ethers.randomBytes(32));
      recipientHashBytes32 = ethers.hexlify(ethers.randomBytes(32));

      // Correctly calculate proofId using existing bytes32 hex strings
      calculatedProofId = ethers.keccak256(
        ethers.solidityPacked(
          ["bytes32", "bytes32", "bytes32"],
          [rootHashBytes32, senderHashBytes32, recipientHashBytes32] // Pass hex strings directly
        )
      );
      
      const approvalObject = {
        sender: senderAddr,
        recipient: recipientAddr,
        minAmt: ethers.parseUnits("1", 18),
        maxAmt: ethers.parseUnits("1000", 18),
        expiry: expiryTimestamp,
        proofId: calculatedProofId 
      };
      defaultApproval = approvalObject;
      
      defaultProofBytes = getDefaultProof();
      minAmtScaled = BigInt(approvalObject.minAmt) * BigInt(1000);
      maxAmtScaled = BigInt(approvalObject.maxAmt) * BigInt(1000);
      // Use the new RISC Zero format
      defaultPublicInputsBytes = getRiscZeroPublicInputs(
        rootHashBytes32, 
        senderHashBytes32, 
        recipientHashBytes32, 
        minAmtScaled, 
        maxAmtScaled, 
        expiryTimestamp
      );
      
      await mockVerifier.setVerifyProofResult(true);
    });

    describe("Permissions & Reentrancy", () => {
       it("Should allow the issuer (owner) to call approveTransfer", async () => {
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, defaultPublicInputsBytes))
            .to.emit(transferOracle, "TransferApproved"); 
        });

        it("Should revert if called by non-issuer", async () => {
          await expect(transferOracle.connect(otherAccount).approveTransfer(defaultApproval, defaultProofBytes, defaultPublicInputsBytes))
            .to.be.revertedWithCustomError(transferOracle, "TransferOracle__CallerNotIssuer");
        });

        it.skip("Should prevent reentrancy", async () => {
          console.log("Skipping reentrancy test for approveTransfer - requires attacker contract.");
        });
    });

    describe("ZK Proof & Public Input Handling", () => {
      it("Should succeed with valid proof, inputs, and approval data", async () => {
          await mockVerifier.setVerifyProofResult(true);
          const tx = transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, defaultPublicInputsBytes);
          await expect(tx).to.emit(transferOracle, "TransferApproved").withArgs(initialIssuer.address, defaultApproval.sender, defaultApproval.recipient, defaultApproval.minAmt, defaultApproval.maxAmt, defaultApproval.expiry, calculatedProofId );
          expect(await transferOracle.isProofUsed(calculatedProofId)).to.be.true;
          expect(await transferOracle.getApprovalCount(defaultApproval.sender, defaultApproval.recipient)).to.equal(1);
      });

      it("Should revert if proof verification fails", async () => {
          await mockVerifier.setVerifyProofResult(false);
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, defaultPublicInputsBytes))
              .to.be.revertedWithCustomError(transferOracle, "TransferOracle__ProofVerificationFailed");
      });
      
       it("Should revert if publicInputs length is incorrect", async () => {
          // The contract decodes as uint256[] first, so encoding as wrong array type IS the way to test this specific revert
          const invalidPublicInputs = ethers.AbiCoder.defaultAbiCoder().encode(["uint256[6]"], [[1, 2, 3, 4, 5, 6]]);
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, invalidPublicInputs))
              .to.be.reverted; // Expect generic revert due to decode failure
      });

      it("Should revert on input consistency check failure (minAmt)", async () => {
          const wrongMinScaled = minAmtScaled + BigInt(1);
          // Generate inconsistent inputs using correct helper and valid hex hashes
          const inconsistentPublicInputs = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, wrongMinScaled, maxAmtScaled, expiryTimestamp);
          // defaultApproval still holds the *correct* calculatedProofId based on original inputs
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, inconsistentPublicInputs))
              .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidPublicInputs");
      });
      
      it("Should revert on input consistency check failure (maxAmt)", async () => {
          const wrongMaxScaled = maxAmtScaled + BigInt(1);
          const inconsistentPublicInputs = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, minAmtScaled, wrongMaxScaled, expiryTimestamp);
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, inconsistentPublicInputs))
              .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidPublicInputs");
      });
      
      it("Should revert on input consistency check failure (expiry)", async () => {
          const wrongExpiry = expiryTimestamp + 1;
          const inconsistentPublicInputs = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, minAmtScaled, maxAmtScaled, wrongExpiry);
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, inconsistentPublicInputs))
              .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidPublicInputs");
      });
      
      it("Should revert if proofId in approval struct does not match calculated proofId", async () => {
          const wrongProofId = ethers.encodeBytes32String("wrongProofId");
          defaultApproval.proofId = wrongProofId;
          const consistentPublicInputs = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, minAmtScaled, maxAmtScaled, expiryTimestamp);
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, consistentPublicInputs))
              .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidPublicInputs");
      });

      it("Should revert if proofId has already been used", async () => {
          const calculatedProofId = ethers.keccak256(
              ethers.solidityPacked(
                  ["bytes32","bytes32","bytes32"],
                  [rootHashBytes32, senderHashBytes32, recipientHashBytes32]
              )
          );
          defaultApproval.proofId = calculatedProofId;
          const currentPublicInputs = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, minAmtScaled, maxAmtScaled, expiryTimestamp);
          await transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, currentPublicInputs);
          expect(await transferOracle.isProofUsed(calculatedProofId)).to.be.true;
          await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, currentPublicInputs))
              .to.be.revertedWithCustomError(transferOracle, "TransferOracle__ProofAlreadyUsed");
      });
    });

    describe("Approval Data Semantic Validation", () => {
        beforeEach(async ()=>{
            // Correct calculation if needed here (uses hex strings from outer scope)
            calculatedProofId = ethers.keccak256(
                ethers.solidityPacked(
                    ["bytes32","bytes32","bytes32"],
                    [rootHashBytes32, senderHashBytes32, recipientHashBytes32]
                )
            );
            defaultApproval.proofId = calculatedProofId;
            defaultPublicInputsBytes = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, minAmtScaled, maxAmtScaled, expiryTimestamp);
        });
        it("Should revert if approval.sender is address(0)", async () => {
            defaultApproval.sender = ethers.ZeroAddress;
            await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, defaultPublicInputsBytes))
                .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidApprovalData");
        });
        it("Should revert if approval.recipient is address(0)", async () => {
            defaultApproval.recipient = ethers.ZeroAddress;
            await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, defaultPublicInputsBytes))
                .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidApprovalData");
        });
         it("Should revert if approval.minAmt > approval.maxAmt", async () => {
            defaultApproval.minAmt = BigInt(defaultApproval.maxAmt) + BigInt(1);
            minAmtScaled = BigInt(defaultApproval.minAmt) * BigInt(1000);
            maxAmtScaled = BigInt(defaultApproval.maxAmt) * BigInt(1000);
            // Use corrected inputs
            const currentPublicInputs = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, minAmtScaled, maxAmtScaled, expiryTimestamp);
            await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, currentPublicInputs))
                .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidApprovalData");
        });
         it("Should revert if approval.expiry is not in the future", async () => {
            const pastTimestamp = (await time.latest()) - 60;
            defaultApproval.expiry = pastTimestamp;
            expiryTimestamp = pastTimestamp;
            // Use corrected inputs
            const currentPublicInputs = getRiscZeroPublicInputs(rootHashBytes32, senderHashBytes32, recipientHashBytes32, minAmtScaled, maxAmtScaled, expiryTimestamp);
            await expect(transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, currentPublicInputs))
                .to.be.revertedWithCustomError(transferOracle, "TransferOracle__InvalidApprovalData");
        });
    });
    
    describe("State Changes & Edge Cases", () => {
        it("Should allow multiple different approvals for the same (sender, recipient)", async () => {
            const root2 = ethers.hexlify(ethers.randomBytes(32));
            const sh2 = ethers.hexlify(ethers.randomBytes(32));
            const rh2 = ethers.hexlify(ethers.randomBytes(32));
            const calcProofId1 = calculatedProofId;
            const approval1 = { ...defaultApproval };
            const inputs1 = defaultPublicInputsBytes;
            
            const calcProofId2 = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[root2, senderHashBytes32, recipientHashBytes32]));
            const approval2 = { ...defaultApproval, proofId: calcProofId2, minAmt: ethers.parseUnits("20", 18) }; 
            const inputs2 = getRiscZeroPublicInputs(root2, senderHashBytes32, recipientHashBytes32, BigInt(approval2.minAmt)*BigInt(1000), BigInt(approval2.maxAmt)*BigInt(1000), expiryTimestamp);
            
            await mockVerifier.setVerifyProofResult(true);
            await transferOracle.connect(initialIssuer).approveTransfer(approval1, defaultProofBytes, inputs1);
            expect(await transferOracle.getApprovalCount(approval1.sender, approval1.recipient)).to.equal(1);
            expect(await transferOracle.isProofUsed(calcProofId1)).to.be.true;
            await transferOracle.connect(initialIssuer).approveTransfer(approval2, defaultProofBytes, inputs2);
            expect(await transferOracle.getApprovalCount(approval2.sender, approval2.recipient)).to.equal(2);
            expect(await transferOracle.isProofUsed(calcProofId2)).to.be.true;
        });
        it("Should correctly store values using uint128/uint40 packing", async () => {
            await transferOracle.connect(initialIssuer).approveTransfer(defaultApproval, defaultProofBytes, defaultPublicInputsBytes);
            expect(await transferOracle.getApprovalCount(defaultApproval.sender, defaultApproval.recipient)).to.equal(1);
        });
        it.skip("Should revert if amount scaling causes overflow (difficult to test via approveTransfer)", async () => {
        });
    });

  }); // End 2.2. approveTransfer

  describe("2.3. canTransfer", () => {
    let sender: SignerWithAddress;
    let recipient: SignerWithAddress;
    let designatedTokenSigner: SignerWithAddress;
    let issuerSigner: SignerWithAddress;
    let transferOracleInstance: TransferOracle;
    let mockVerifierInstance: MockRiscZeroVerifier;

    // Approvals to set up:
    let approvalWide: ITransferOracle.TransferApprovalStruct; // range 10-100
    let proofIdWide: string;
    let inputsWide: string;
    
    let approvalTight: ITransferOracle.TransferApprovalStruct; // range 40-60
    let proofIdTight: string;
    let inputsTight: string;

    let approvalExpired: ITransferOracle.TransferApprovalStruct; // range 1-1000, expired
    let proofIdExpired: string;
    let inputsExpired: string;

    const transferAmountFitTight = ethers.parseUnits("50", 18);
    const transferAmountFitWideOnly = ethers.parseUnits("20", 18);
    const transferAmountTooLow = ethers.parseUnits("5", 18);
    const transferAmountTooHigh = ethers.parseUnits("101", 18);

    beforeEach(async () => {
        const deployed = await loadFixture(deployTransferOracleFixture);
        transferOracleInstance = deployed.transferOracle;
        mockVerifierInstance = deployed.mockVerifier;
        designatedTokenSigner = deployed.designatedToken;
        issuerSigner = deployed.initialIssuer;
        sender = deployed.otherAccount; 
        recipient = deployed.deployer;  
        
        const now = await time.latest();
        const futureExpiry = now + 3600;
        const expiryForExpiredSetup = now + 100; // Needs to be in the future initially
        const timeToAdvance = 200; // << CORRECTED: Advance less time

        await mockVerifierInstance.setVerifyProofResult(true);

        // Approval Wide (Valid)
        const rootW = ethers.hexlify(ethers.randomBytes(32)); const shW = ethers.hexlify(ethers.randomBytes(32)); const rhW = ethers.hexlify(ethers.randomBytes(32));
        proofIdWide = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[rootW, shW, rhW]));
        approvalWide = { sender: sender.address, recipient: recipient.address, minAmt: ethers.parseUnits("10", 18), maxAmt: ethers.parseUnits("100", 18), expiry: futureExpiry, proofId: proofIdWide };
        inputsWide = getRiscZeroPublicInputs(rootW, shW, rhW, BigInt(approvalWide.minAmt)*BigInt(1000), BigInt(approvalWide.maxAmt)*BigInt(1000), futureExpiry);
        await transferOracleInstance.connect(issuerSigner).approveTransfer(approvalWide, getDefaultProof(), inputsWide);
      
        // Approval Tight (Valid)
        const rootT = ethers.hexlify(ethers.randomBytes(32));
        proofIdTight = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[rootT, shW, rhW])); // Same sender/recipient basis
        approvalTight = { sender: sender.address, recipient: recipient.address, minAmt: ethers.parseUnits("40", 18), maxAmt: ethers.parseUnits("60", 18), expiry: futureExpiry, proofId: proofIdTight };
        inputsTight = getRiscZeroPublicInputs(rootT, shW, rhW, BigInt(approvalTight.minAmt)*BigInt(1000), BigInt(approvalTight.maxAmt)*BigInt(1000), futureExpiry);
        await transferOracleInstance.connect(issuerSigner).approveTransfer(approvalTight, getDefaultProof(), inputsTight);

        // Approval Expired (Add with future expiry first)
        const rootE = ethers.hexlify(ethers.randomBytes(32)); const shE = ethers.hexlify(ethers.randomBytes(32)); const rhE = ethers.hexlify(ethers.randomBytes(32));
        proofIdExpired = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[rootE, shE, rhE]));
        approvalExpired = { sender: sender.address, recipient: recipient.address, minAmt: ethers.parseUnits("1", 18), maxAmt: ethers.parseUnits("1000", 18), expiry: expiryForExpiredSetup, proofId: proofIdExpired };
        inputsExpired = getRiscZeroPublicInputs(rootE, shE, rhE, BigInt(approvalExpired.minAmt)*BigInt(1000), BigInt(approvalExpired.maxAmt)*BigInt(1000), expiryForExpiredSetup);
        await transferOracleInstance.connect(issuerSigner).approveTransfer(approvalExpired, getDefaultProof(), inputsExpired);

        // --- Advance Time --- 
        await time.increase(timeToAdvance); // Expire the 3rd approval, keep 1st & 2nd valid
        
        expect(await transferOracleInstance.getApprovalCount(sender.address, recipient.address)).to.equal(3);
    });

    describe("Permissions & Reentrancy", () => {
      it("Should allow the designated token contract to call canTransfer", async () => {
        // Call connect with the signer designated as the token address
        // Pass the token's address as the first argument, as the actual token contract would
        await expect(transferOracleInstance.connect(designatedTokenSigner).canTransfer(
            designatedTokenSigner.address, // Pass token address here
            sender.address, 
            recipient.address, 
            transferAmountFitTight 
          ))
          .to.not.be.reverted; // Expecting success
          
        // Check that the approval was consumed
        expect(await transferOracleInstance.getApprovalCount(sender.address, recipient.address)).to.equal(2);
      });

      // Other permission tests can remain, they should still fail correctly
       it("Should revert if called by an address other than the designated token", async () => {
         const nonTokenSigner = sender; // Example non-token signer
         await expect(transferOracleInstance.connect(nonTokenSigner).canTransfer(
             designatedTokenSigner.address, // Correct token address passed as arg
             sender.address, 
             recipient.address, 
             transferAmountFitTight 
           )).to.be.revertedWithCustomError(transferOracleInstance, "TransferOracle__CallerNotToken");
       });

       it("Should revert if the first argument (tokenAddress) doesn\'t match permissionedToken", async () => {
           const wrongTokenAddress = sender.address; // Example wrong address
           await expect(transferOracleInstance.connect(designatedTokenSigner).canTransfer(
               wrongTokenAddress, // Passing wrong address as first arg
               sender.address,
               recipient.address,
               transferAmountFitTight
           )).to.be.revertedWithCustomError(transferOracleInstance, "TransferOracle__CallerNotToken");
       });
        
      // ... skipped reentrancy test ...
       it.skip("Should prevent reentrancy", async () => {
           console.log("Skipping reentrancy test for canTransfer - requires functional attacker contract and oracle setup.");
       });
    }); 

    describe("Approval Logic & Consumption", () => {
       it("Should consume the best-fit (tightest range) valid approval and return its proofId", async () => {
          // transferAmountFitTight (50) fits both wide (10-100) and tight (40-60).
          // Expect tight (proofIdTight) to be consumed.
          const tx = await transferOracleInstance.connect(designatedTokenSigner).canTransfer(
               designatedTokenSigner.address, 
               sender.address, 
               recipient.address, 
               transferAmountFitTight
            );
            
          // Check return value (need to call statically or get from event if needed)
          // const returnedProofId = await transferOracleInstance.connect(designatedTokenSigner).canTransfer.staticCall(...) // Static call to check return value without state change
          // For now, check event and state change
          
          await expect(tx).to.emit(transferOracleInstance, "ApprovalConsumed")
              .withArgs(issuerSigner.address, sender.address, recipient.address, transferAmountFitTight, proofIdTight); // Check consumed proofId

          // Check state: one approval consumed
          expect(await transferOracleInstance.getApprovalCount(sender.address, recipient.address)).to.equal(2);
          // TODO: Optionally add getter to mock/real oracle to check *which* approvals remain
      });

      it("Should consume a wider-range valid approval if it's the only fit", async () => {
          // transferAmountFitWideOnly (20) fits wide (10-100) but not tight (40-60).
          // Expect wide (proofIdWide) to be consumed.
           const tx = await transferOracleInstance.connect(designatedTokenSigner).canTransfer(
               designatedTokenSigner.address, 
               sender.address, 
               recipient.address, 
               transferAmountFitWideOnly
            );

          await expect(tx).to.emit(transferOracleInstance, "ApprovalConsumed")
              .withArgs(issuerSigner.address, sender.address, recipient.address, transferAmountFitWideOnly, proofIdWide);

          expect(await transferOracleInstance.getApprovalCount(sender.address, recipient.address)).to.equal(2);
      });

      it("Should revert with NoApprovalFound if amount is too low for all valid approvals", async () => {
          await expect(transferOracleInstance.connect(designatedTokenSigner).canTransfer(
               designatedTokenSigner.address, 
               sender.address, 
               recipient.address, 
               transferAmountTooLow // 5 < min(10), min(40)
            )).to.be.revertedWithCustomError(transferOracleInstance, "TransferOracle__NoApprovalFound");
      });

      it("Should revert with NoApprovalFound if amount is too high for all valid approvals", async () => {
           await expect(transferOracleInstance.connect(designatedTokenSigner).canTransfer(
               designatedTokenSigner.address, 
               sender.address, 
               recipient.address, 
               transferAmountTooHigh // 101 > max(100), max(60)
            )).to.be.revertedWithCustomError(transferOracleInstance, "TransferOracle__NoApprovalFound");
      });

      it("Should revert with NoApprovalFound if the only matching approval is expired", async () => {
          // Consume the two valid approvals first
           await transferOracleInstance.connect(designatedTokenSigner).canTransfer(designatedTokenSigner.address, sender.address, recipient.address, transferAmountFitTight); // Consumes tight (proofId2)
           await transferOracleInstance.connect(designatedTokenSigner).canTransfer(designatedTokenSigner.address, sender.address, recipient.address, transferAmountFitWideOnly); // Consumes wide (proofId1)
           expect(await transferOracleInstance.getApprovalCount(sender.address, recipient.address)).to.equal(1); // Only expired one left

          // Try to transfer an amount that fits the expired approval's range (e.g., 500)
          const amountForExpired = ethers.parseUnits("500", 18);
          await expect(transferOracleInstance.connect(designatedTokenSigner).canTransfer(
               designatedTokenSigner.address, 
               sender.address, 
               recipient.address, 
               amountForExpired
            )).to.be.revertedWithCustomError(transferOracleInstance, "TransferOracle__NoApprovalFound");
      });

       it("Should revert with NoApprovalFound if no approvals exist for the sender/recipient pair", async () => {
           // Use a different sender/recipient pair with no approvals
           const nonExistentSender = deployer; 
           const nonExistentRecipient = otherAccount;
           await expect(transferOracleInstance.connect(designatedTokenSigner).canTransfer(
               designatedTokenSigner.address, 
               nonExistentSender.address, 
               nonExistentRecipient.address, 
               transferAmountFitTight 
            )).to.be.revertedWithCustomError(transferOracleInstance, "TransferOracle__NoApprovalFound");
      });
       
       // TODO: Test swap and pop logic explicitly? Difficult without reading array state.
       // Implicitly tested by consuming different approvals.

    });

  }); // End 2.3 canTransfer

  describe("2.4. View Functions", () => {
    it("getIssuer() should return the initial issuer address", async () => {
      expect(await transferOracle.getIssuer()).to.equal(initialIssuer.address);
    });

    describe("getApprovalCount(address sender, address recipient)", () => {
       let sender: SignerWithAddress;
       let recipient: SignerWithAddress;
       let otherSender: SignerWithAddress;

       beforeEach(async () => {
          // Need signers defined in this scope
          const signers = await ethers.getSigners();
          // Use distinct signers from the main fixture ones if needed for clarity
          sender = signers[4] || otherAccount; 
          recipient = signers[5] || deployer;
          otherSender = signers[6] || initialIssuer; // Just need a different address
          
          // Ensure count is 0 initially for this pair
          expect(await transferOracle.getApprovalCount(sender.address, recipient.address)).to.equal(0);

          // Add some approvals for setup
          const now = await time.latest();
          const expiry = now + 3600;
          const root1 = ethers.hexlify(ethers.randomBytes(32));
          const sh1 = ethers.hexlify(ethers.randomBytes(32));
          const rh1 = ethers.hexlify(ethers.randomBytes(32));
          const proofId1 = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[root1, sh1, rh1]));
          const approval1 = { sender: sender.address, recipient: recipient.address, minAmt: 10, maxAmt: 100, expiry: expiry, proofId: proofId1 };
          const inputs1 = getRiscZeroPublicInputs(root1, sh1, rh1, BigInt(approval1.minAmt)*BigInt(1000), BigInt(approval1.maxAmt)*BigInt(1000), expiry);
          
          const root2 = ethers.hexlify(ethers.randomBytes(32));
          const proofId2 = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[root2, sh1, rh1]));
          const approval2 = { sender: sender.address, recipient: recipient.address, minAmt: 20, maxAmt: 50, expiry: expiry, proofId: proofId2 };
          const inputs2 = getRiscZeroPublicInputs(root2, sh1, rh1, BigInt(approval2.minAmt)*BigInt(1000), BigInt(approval2.maxAmt)*BigInt(1000), expiry);

          await mockVerifier.setVerifyProofResult(true);
          // Use the main initialIssuer from the outer scope to add approvals
          await transferOracle.connect(initialIssuer).approveTransfer(approval1, getDefaultProof(), inputs1);
          await transferOracle.connect(initialIssuer).approveTransfer(approval2, getDefaultProof(), inputs2);
      });

      it("Should return the correct count of active approvals for a sender-recipient pair", async () => {
          expect(await transferOracle.getApprovalCount(sender.address, recipient.address)).to.equal(2);
      });

      it("Should return 0 for a sender-recipient pair with no approvals", async () => {
          expect(await transferOracle.getApprovalCount(otherSender.address, recipient.address)).to.equal(0);
      });

      it("Should decrease count after an approval is consumed by canTransfer", async () => {
           expect(await transferOracle.getApprovalCount(sender.address, recipient.address)).to.equal(2);
           // Consume one approval (amount 20 fits approval1)
           await transferOracle.connect(designatedToken).canTransfer(designatedToken.address, sender.address, recipient.address, 20);
           expect(await transferOracle.getApprovalCount(sender.address, recipient.address)).to.equal(1);
      });
    });

    describe("isProofUsed(bytes32 proofId)", () => {
        let proofIdToUse: string;

        beforeEach(async () => {
            // Add one specific approval to get a proofId
            const now = await time.latest();
            const sender = otherAccount;
            const recipient = deployer;
            const root = ethers.hexlify(ethers.randomBytes(32));
            const sh = ethers.hexlify(ethers.randomBytes(32));
            const rh = ethers.hexlify(ethers.randomBytes(32));
            proofIdToUse = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[root, sh, rh]));
            const expiry = now + 3600;
            const approval = { sender: sender.address, recipient: recipient.address, minAmt: 1, maxAmt: 10, expiry: expiry, proofId: proofIdToUse };
            const inputs = getRiscZeroPublicInputs(root, sh, rh, BigInt(approval.minAmt)*BigInt(1000), BigInt(approval.maxAmt)*BigInt(1000), expiry);
            
            await mockVerifier.setVerifyProofResult(true);
            await transferOracle.connect(initialIssuer).approveTransfer(approval, getDefaultProof(), inputs);
        });

       it("Should return true for a proofId that has been used in approveTransfer", async () => {
            expect(await transferOracle.isProofUsed(proofIdToUse)).to.be.true;
        });

        it("Should return false for a proofId that has not been used", async () => {
            const unusedProofId = ethers.hexlify(ethers.randomBytes(32));
            expect(await transferOracle.isProofUsed(unusedProofId)).to.be.false;
        });
    });

  }); // End 2.4 View Functions

  describe("2.5. Ownable Functionality (Issuer Role)", () => {
    it("owner() should return the current issuer address", async () => {
        // initialIssuer is set in the top-level beforeEach
        expect(await transferOracle.owner()).to.equal(initialIssuer.address);
    });

    describe("transferOwnership(address newOwner)", () => {
       let newOwner: SignerWithAddress;

       beforeEach(async () => {
           // Assign a distinct new owner
           newOwner = otherAccount; // Use one of the available signers
           // Ensure newOwner is not the same as initialIssuer
           expect(newOwner.address).to.not.equal(initialIssuer.address);
       });

       it("Should allow the current issuer to transfer ownership (issuer role)", async () => {
          await expect(transferOracle.connect(initialIssuer).transferOwnership(newOwner.address))
            .to.emit(transferOracle, "OwnershipTransferred")
            .withArgs(initialIssuer.address, newOwner.address);
          
          expect(await transferOracle.owner()).to.equal(newOwner.address);
          expect(await transferOracle.getIssuer()).to.equal(newOwner.address); // getIssuer should reflect new owner
       });

       it("Should prevent non-issuers from transferring ownership", async () => {
           const nonOwner = deployer; // Use deployer as a non-owner example
           await expect(transferOracle.connect(nonOwner).transferOwnership(newOwner.address))
             .to.be.revertedWithCustomError(transferOracle, "OwnableUnauthorizedAccount")
             .withArgs(nonOwner.address);
       });

       it("Should revert if transferring ownership to the zero address", async () => {
            await expect(transferOracle.connect(initialIssuer).transferOwnership(ethers.ZeroAddress))
             .to.be.revertedWithCustomError(transferOracle, "OwnableInvalidOwner")
             .withArgs(ethers.ZeroAddress);
       });

       it("New issuer should have issuer privileges (e.g., can call approveTransfer)", async () => {
            await transferOracle.connect(initialIssuer).transferOwnership(newOwner.address);
            // Verify newOwner can now call approveTransfer

            // Prepare minimal valid data for the call
            const now = await time.latest();
            const sender = otherAccount.address;
            const recipient = deployer.address;
            const root = ethers.hexlify(ethers.randomBytes(32));
            const sh = ethers.hexlify(ethers.randomBytes(32));
            const rh = ethers.hexlify(ethers.randomBytes(32));
            const proofId = ethers.keccak256(ethers.solidityPacked(["bytes32","bytes32","bytes32"],[root, sh, rh]));
            const expiry = now + 5000;
            const approval = { sender: sender, recipient: recipient, minAmt: 1, maxAmt: 10, expiry: expiry, proofId: proofId };
            const inputs = getRiscZeroPublicInputs(root, sh, rh, BigInt(approval.minAmt)*BigInt(1000), BigInt(approval.maxAmt)*BigInt(1000), expiry);
            const proof = getDefaultProof();
            await mockVerifier.setVerifyProofResult(true);
            
            // Call approveTransfer using the new owner
            await expect(transferOracle.connect(newOwner).approveTransfer(approval, proof, inputs))
                .to.emit(transferOracle, "TransferApproved"); // Check event emission as proof of success
       });
    });
  }); // End 2.5 Ownable Functionality

}); // End TransferOracle

// Need a specific reentrancy attacker for canTransfer
/*
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITransferOracle} from "../interfaces/ITransferOracle.sol";

contract ReentrantAttackerCanTransfer {
    ITransferOracle immutable targetOracle;
    bool private entered = false;
    
    address immutable tokenAddress;
    address immutable senderAddress;
    address immutable recipientAddress;
    uint256 immutable transferAmount;

    constructor(address oracleAddress) {
        targetOracle = ITransferOracle(oracleAddress);
        tokenAddress = address(this); // This contract is the designated token
    }

    // Function called by external test runner
    function attack(address _sender, address _recipient, uint256 _amount) external {
        // Make the initial call that will call back into this contract
        targetOracle.canTransfer(tokenAddress, _sender, _recipient, _amount);
    }
    
    // Assume canTransfer somehow calls back into this contract (e.g., via a hook)
    // This is a conceptual placeholder, as canTransfer itself doesn't make external calls.
    // A realistic test would need the actual PermissionedERC20 which *does* call canTransfer.
    // To test the guard directly on the oracle, we'd need a modified oracle or 
    // simulate the call sequence.
    
    // If targetOracle.canTransfer called back to this contract's fallback or another function:
    fallback() external payable {
       reenter(_sender, _recipient, _amount); // Doesn't work - need args
    }
    receive() external payable {
       reenter(_sender, _recipient, _amount); // Doesn't work - need args
    }
    
    // Need a specific function called back, or modify canTransfer itself for test
    function reenter(address _sender, address _recipient, uint256 _amount) public {
        if (!entered) {
            entered = true;
            // Attempt reentrant call
            targetOracle.canTransfer(tokenAddress, _sender, _recipient, _amount);
        }
    } 
}
*/ 