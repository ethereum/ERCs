import hre, { network } from "hardhat";
import { expect } from "chai";
import { mine, time } from "@nomicfoundation/hardhat-network-helpers";

describe("ERC-7858 Epoch", function () {
  let tokenContract: any;
  let signers: any;

  beforeEach(async function () {
    tokenContract = await hre.ethers.deployContract(
      "MockERC7858Epoch",
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

  it("supportsInterface ERC-7858Epoch", async function () {
    expect(await tokenContract.supportsInterface("0xec7ffd66")).to.equal(true);
  });

  it("supportsInterface unknown", async function () {
    expect(await tokenContract.supportsInterface("0xFFFFFFFF")).to.equal(false);
  });

  it("expiryType", async function () {
    expect(await tokenContract.expiryType()).to.equal(0);
  });

  it("epochLength", async function () {
    expect(await tokenContract.epochLength()).to.equal(6574359);
  });

  it("validityDuration", async function () {
    expect(await tokenContract.validityDuration()).to.equal(4);
  });

  it("currentEpoch", async function () {
    expect(await tokenContract.currentEpoch()).to.equal(0);
    await mine(6574359);
    expect(await tokenContract.currentEpoch()).to.equal(1);
  });

  it("mint token", async function () {
    await tokenContract.mint(signers[0].address, 1);
    expect(await tokenContract.balanceOf(signers[0].address)).to.equal(1);
    expect(await tokenContract.unexpiredBalanceOf(signers[0].address)).to.equal(
      1
    );
    expect(
      await tokenContract.unexpiredBalanceOfAtEpoch(0, signers[0].address)
    ).to.equal(1);
  });

  it("burn token", async function () {
    await tokenContract.mint(signers[0].address, 1);
    expect(await tokenContract.balanceOf(signers[0].address)).to.equal(1);
    expect(await tokenContract.unexpiredBalanceOf(signers[0].address)).to.equal(
      1
    );
    expect(
      await tokenContract.unexpiredBalanceOfAtEpoch(0, signers[0].address)
    ).to.equal(1);
    await tokenContract.burn(1);
    expect(await tokenContract.balanceOf(signers[0].address)).to.equal(0);
    expect(await tokenContract.unexpiredBalanceOf(signers[0].address)).to.equal(
      0
    );
    expect(
      await tokenContract.unexpiredBalanceOfAtEpoch(0, signers[0].address)
    ).to.equal(0);
  });

  it("transfer token", async function () {
    const alice = signers[0].address;
    const bob = signers[1].address;
    await tokenContract.mint(alice, 1);
    expect(await tokenContract.balanceOf(alice)).to.equal(1);
    expect(await tokenContract.unexpiredBalanceOf(alice)).to.equal(1);
    expect(await tokenContract.unexpiredBalanceOfAtEpoch(0, alice)).to.equal(1);
    await tokenContract.connect(signers[0]).transferFrom(alice, bob, 1);
    expect(await tokenContract.balanceOf(alice)).to.equal(0);
    expect(await tokenContract.unexpiredBalanceOf(alice)).to.equal(0);
    expect(await tokenContract.unexpiredBalanceOfAtEpoch(0, alice)).to.equal(0);
    await tokenContract.mint(bob, 2);
    expect(await tokenContract.balanceOf(bob)).to.equal(2);
    expect(await tokenContract.unexpiredBalanceOf(bob)).to.equal(2);
    expect(await tokenContract.unexpiredBalanceOfAtEpoch(0, bob)).to.equal(2);
    await tokenContract.mint(bob, 3);
    await mine(6574359 * 4 - 1);
    expect(await tokenContract.balanceOf(bob)).to.equal(3);
    expect(await tokenContract.currentEpoch()).to.equal(4);
    expect(await tokenContract.unexpiredBalanceOfAtEpoch(0, bob)).to.equal(1);
    expect(await tokenContract.unexpiredBalanceOf(bob)).to.equal(1);
  });
});
