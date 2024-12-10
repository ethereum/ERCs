import { expect } from "chai";
import { calculateSlidingWindowState, deployERC7818 } from "../utils.test";
import { EVENT_TRANSFER } from "../constant.test";
import { ZeroAddress } from "ethers";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { network } from "hardhat";

export const run = async () => {
  describe("Interface", async function () {
    beforeEach(async function () {
      await network.provider.send("hardhat_reset");
    });
    
    it("[IERC20][IERC7818][Override] totalSupply", async function () {
      const { erc7818 } = await deployERC7818({});
      // Due to token can expiration there is no actual totalSupply.
      expect(await erc7818.totalSupply()).to.equal(0);
    });

    it("[IERC7818] currentEpoch ", async function () {
      const { erc7818 } = await deployERC7818({});
      expect(await erc7818.currentEpoch()).to.equal(0);
      await mine(await erc7818.epochLength());
      expect(await erc7818.currentEpoch()).to.equal(1);
    });

    it("[IERC7818] epochType ", async function () {
      const { erc7818 } = await deployERC7818({});
      expect(await erc7818.epochType()).to.equal(0);
    });

    it("[IERC7818] epochLength", async function () {
      const { erc7818 } = await deployERC7818({});
      const self = calculateSlidingWindowState({});
      expect(await erc7818.epochLength()).to.equal(self._blocksPerEpoch);
    });

    it("[IERC7818] validityDuration", async function () {
      const { erc7818 } = await deployERC7818({});
      const self = calculateSlidingWindowState({});
      expect(await erc7818.validityDuration()).to.equal(self._windowSize);
    });

    it("[IERC7818] isEpochExpired ", async function () {
      const { erc7818, alice } = await deployERC7818({});
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const epoch = await erc7818.currentEpoch();
      expect(await erc7818.isEpochExpired(epoch)).to.equal(false);
      await mine(
        (await erc7818.epochLength()) *
          ((await erc7818.validityDuration()) + BigInt(2))
      );
      expect(await erc7818.isEpochExpired(epoch)).to.equal(true);
    });
  });
};
