import { expect } from "chai";
import { deployERC7818 } from "../utils.test";
import {
  ERROR_ERC20_INVALID_SENDER,
  EVENT_TRANSFER,
} from "../constant.test";
import { ZeroAddress } from "ethers";
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { network } from "hardhat";

export const run = async () => {
  describe("Burn", async function () {
    beforeEach(async function () {
      await network.provider.send("hardhat_reset");
    });
    
    it("[SUCCESS] burn from non zero address", async function () {
      let amount = 1;
      const { erc7818, alice } = await deployERC7818({});
      await erc7818.mint(alice.address, amount);
      let epoch = await erc7818.currentEpoch();
      expect(await erc7818.balanceOf(alice.address)).equal(amount);
      expect(await erc7818.balanceOfAtEpoch(epoch, alice.address)).equal(
        amount
      );
      await erc7818.burn(alice.address, amount);
      expect(await erc7818.balanceOf(alice.address)).equal(0);
      expect(epoch).equal(0);
      amount = 100;
      await erc7818.mint(alice.address, amount);
      epoch = await erc7818.currentEpoch();
      expect(await erc7818.balanceOf(alice.address)).equal(amount);
      await erc7818.burn(alice.address, 1);
      expect(await erc7818.balanceOfAtEpoch(epoch, alice.address)).equal(
        99
      );
    });

    it("[SUCCESS] burn from non zero address overlap epoch", async function () {
      const windowSize = 2;
      const { erc7818, alice, bob } = await deployERC7818({ windowSize });
      const blocksPerEpoch = await erc7818.epochLength();
      const blocksPerWindow =
        (await erc7818.validityDuration()) * blocksPerEpoch;
      let epoch = await erc7818.currentEpoch();
      expect(epoch).equal(0);
      const amount = BigInt(1);
      const iterate = BigInt(200);
      const expectBalance = iterate * amount;
      await mine(blocksPerEpoch - BigInt(101));
      for (let index = 0; index < iterate; index++) {
        await erc7818.mint(alice.address, amount);
      }
      epoch = await erc7818.currentEpoch();
      expect(epoch).equal(1);
      expect(await erc7818.balanceOfAtEpoch(0, alice.address)).to.equal(100);
      expect(await erc7818.balanceOfAtEpoch(1, alice.address)).to.equal(100);
      expect(await erc7818.balanceOf(alice.address)).to.equal(expectBalance);
      await erc7818.burn(alice.address, expectBalance);
      expect(await erc7818.balanceOf(alice.address)).to.equal(0);
    });
  });
};
