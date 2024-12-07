import { expect } from "chai";
import { deployERC7818 } from "../utils.test";
import { EVENT_TRANSFER } from "../constant.test";
import { ZeroAddress } from "ethers";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { network } from "hardhat";

export const run = async () => {
  describe("Mint", async function () {
    beforeEach(async function () {
      await network.provider.send("hardhat_reset");
    });

    it("[SUCCESS] mint to non zero address", async function () {
      const amount = 1;
      const {erc7818, alice} = await deployERC7818({});
      const blocksPerEpoch = await erc7818.epochLength();
      const blocksPerWindow = (await erc7818.validityDuration()) * blocksPerEpoch;
      let epoch = await erc7818.currentEpoch();

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      expect(await erc7818.balanceOf(alice.address)).equal(amount);
      expect(await erc7818.balanceOfAtEpoch(epoch, alice.address)).equal(amount);
      expect(epoch).equal(0);

      await mine(blocksPerWindow * BigInt(2));
      const currentEpoch = await erc7818.currentEpoch();
      expect(currentEpoch).equal(4);
      expect(await erc7818.balanceOf(alice.address)).equal(0);
      expect(await erc7818.balanceOfAtEpoch(epoch, alice.address)).equal(0);
      expect(await erc7818.balanceOfAtEpoch(currentEpoch + BigInt(1), alice.address)).equal(0);
    });
  });
};
