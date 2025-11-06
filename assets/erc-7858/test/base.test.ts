import hre, { network } from "hardhat";
import { expect } from "chai";
import { mine, time } from "@nomicfoundation/hardhat-network-helpers";

/** Excluding base ERC-721 tests as they inherit from OpenZeppelin. */

describe("ERC-7858 Base", function () {
  let tokenContract: any;
  let signers: any;

  beforeEach(async function () {
    tokenContract = await hre.ethers.deployContract(
      "MockERC7858",
      ["Test", "NFT"],
      {}
    );
    signers = await hre.ethers.getSigners();
  });

  afterEach(async function () {
    network.provider.send("hardhat_reset");
  });

  it("supportsInterface ERC-721", async function () {
    expect(await tokenContract.supportsInterface("0x80ac58cd")).to.equal(true);
  });

  it("supportsInterface ERC-7858", async function () {
    expect(await tokenContract.supportsInterface("0x3ebdfa31")).to.equal(true);
  });

  it("supportsInterface unknown", async function () {
    expect(await tokenContract.supportsInterface("0xFFFFFFFF")).to.equal(false);
  });

  it("expiryType", async function () {
    expect(await tokenContract.expiryType()).to.equal(0);
  });

  it("mint token and update timestamp", async function () {
    await tokenContract.mint(signers[0].address, 1);
    expect(await tokenContract.startTime(1)).to.equal(0);
    expect(await tokenContract.endTime(1)).to.equal(0);
    await tokenContract.updateTimeStamp(1, 1000, 2000);
    expect(await tokenContract.startTime(1)).to.equal(1000);
    expect(await tokenContract.endTime(1)).to.equal(2000);
  });

  it("burn and re-mint token", async function () {
    await tokenContract.mint(signers[0].address, 1);
    expect(await tokenContract.startTime(1)).to.equal(0);
    expect(await tokenContract.endTime(1)).to.equal(0);
    await tokenContract.updateTimeStamp(1, 1000, 2000);
    expect(await tokenContract.startTime(1)).to.equal(1000);
    expect(await tokenContract.endTime(1)).to.equal(2000);
    await tokenContract.burn(1);
    await tokenContract.mint(signers[0].address, 1);
    expect(await tokenContract.startTime(1)).to.equal(0);
    expect(await tokenContract.endTime(1)).to.equal(0);
  });

  it("token expire", async function () {
    await tokenContract.mint(signers[0].address, 1);
    expect(await tokenContract.startTime(1)).to.equal(0);
    expect(await tokenContract.endTime(1)).to.equal(0);
    await tokenContract.updateTimeStamp(1, 100, 200);
    expect(await tokenContract.isTokenExpired(1)).to.equal(false);
    await mine(200 - await time.latestBlock());
    expect(await tokenContract.isTokenExpired(1)).to.equal(true);
  });
});
