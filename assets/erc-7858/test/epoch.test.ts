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
        expect(await tokenContract.supportsInterface("0x8f55b98a")).to.equal(true);
      });
  
    it("supportsInterface unknown", async function () {
      expect(await tokenContract.supportsInterface("0xFFFFFFFF")).to.equal(false);
    });

});