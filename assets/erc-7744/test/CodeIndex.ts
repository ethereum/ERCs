import { ethers } from "hardhat";
import { Signer } from "ethers";
import { expect } from "chai";
import { CodeIndex, TestFacet } from "../types";
import hre, { deployments } from "hardhat";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
describe("CloneDistribution", function () {
  let codeIndex: CodeIndex;
  let testContract: TestFacet;

  beforeEach(async function () {
    await deployments.fixture("code_index"); // This is the key addition
    const codeIndexDeployment = await deployments.get("CodeIndex");
    codeIndex = (await ethers.getContractAt("CodeIndex", codeIndexDeployment.address)) as CodeIndex;
    const TestContract = await ethers.getContractFactory("TestFacet");
    testContract = (await TestContract.deploy()) as TestFacet;
  });

  it("should emit Distributed event", async function () {
    // const code = await testContract.provider.getCode(testContract.address);
    expect(await codeIndex.register(testContract.address)).to.emit(codeIndex, "Indexed");
  });

  it("should return address for registered code hash", async function () {
    await codeIndex.register(testContract.address);
    const code = await testContract.provider.getCode(testContract.address);
    const codeHash = ethers.utils.keccak256(code);
    expect(await codeIndex.get(codeHash)).to.equal(testContract.address);
  });

  it("Should revert on registering same code hash", async function () {
    await codeIndex.register(testContract.address);
    await expect(codeIndex.register(testContract.address)).to.be.revertedWithCustomError(codeIndex, "alreadyExists");
  });

  it("Should have deterministic address", async function () {
    expect(codeIndex.address).to.be.eq("0xc0D31d398c5ee86C5f8a23FA253ee8a586dA03Ce");
  });
});
