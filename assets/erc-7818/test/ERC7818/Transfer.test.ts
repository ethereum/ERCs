import { expect } from "chai";
import { deployERC7818 } from "../utils.test";
import {
  ERROR_ERC20_INSUFFICIENT_BALANCE,
  ERROR_ERC20_INVALID_RECEIVER,
  EVENT_TRANSFER,
} from "../constant.test";
import { ZeroAddress } from "ethers";
import { network } from "hardhat";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

export const run = async () => {
  describe("Transfer", async function () {
    beforeEach(async function () {
      await network.provider.send("hardhat_reset");
    });

    it("[SUCCESS] transfer alice to bob", async function () {
      const windowSize = 2;
      const { erc7818, alice, bob } = await deployERC7818({ windowSize });
      const blocksPerEpoch = await erc7818.epochLength();
      const blocksPerWindow =
        (await erc7818.validityDuration()) * blocksPerEpoch;
      let epoch = await erc7818.currentEpoch();
      expect(epoch).equal(0);
      let amount = 100;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      expect(await erc7818.balanceOf(alice.address)).to.equal(amount);
      amount -= 10;
      await expect(erc7818.connect(alice).transfer(bob.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, amount);
      expect(await erc7818.balanceOf(bob.address)).to.equal(amount);
      await mine(blocksPerWindow + BigInt(2));
      epoch = await erc7818.currentEpoch();
      expect(epoch).equal(2);
      expect(await erc7818.balanceOf(bob.address)).to.equal(0);
    });

    it("[SUCCESS] transfer alice to bob FIFO", async function () {
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
      for (let index = 0; index < iterate; index++) {
        await erc7818.mint(alice.address, amount);
      }
      expect(await erc7818.balanceOf(alice.address)).to.equal(expectBalance);
      await expect(erc7818.connect(alice).transfer(bob.address, expectBalance))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, expectBalance);
      expect(await erc7818.balanceOf(bob.address)).to.equal(expectBalance);
      await mine(blocksPerWindow + iterate + BigInt(2));
      epoch = await erc7818.currentEpoch();
      expect(epoch).equal(2);
      expect(await erc7818.balanceOf(bob.address)).to.equal(0);
    });

    it("[SUCCESS] transfer alice to bob FIFO overlap epoch", async function () {
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
      await expect(erc7818.connect(alice).transfer(bob.address, expectBalance))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, expectBalance);
      expect(await erc7818.balanceOf(bob.address)).to.equal(expectBalance);
      await mine(blocksPerWindow);
      epoch = await erc7818.currentEpoch();
      expect(epoch).equal(3);
      expect(await erc7818.balanceOf(bob.address)).to.equal(0);
    });

    it("[SUCCESS] transfer alice to bob FIFO overlap epoch shrink expire balance", async function () {
      const windowSize = 2;
      const { erc7818, alice, bob } = await deployERC7818({ windowSize });
      const blocksPerEpoch = await erc7818.epochLength();
      const blocksPerWindow =
        (await erc7818.validityDuration()) * blocksPerEpoch;
      await erc7818.mint(alice.address, 10);
      await mine(blocksPerEpoch / BigInt(2));
      await erc7818.mint(alice.address, 10);
      await mine(blocksPerEpoch / BigInt(2));
      await mine(blocksPerEpoch * BigInt(1));
      await expect(erc7818.connect(alice).transfer(bob.address, 10))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, 10);
      expect(await erc7818.balanceOf(alice.address)).to.equal(0);
      expect(await erc7818.balanceOf(bob.address)).to.equal(10);
    });

    it("[SUCCESS] transfer specific epoch alice to bob ", async function () {
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
      const epochBalance = await erc7818.balanceOfAtEpoch(1, alice.address);
      expect(epochBalance).to.equal(100);
      expect(await erc7818.balanceOf(alice.address)).to.equal(expectBalance);
      // transfer balance over epoch balance will failed
      await expect(
        erc7818.connect(alice).transferAtEpoch(0, bob.address, expectBalance)
      )
        .to.be.revertedWithCustomError(
          erc7818,
          ERROR_ERC20_INSUFFICIENT_BALANCE
        )
        .withArgs(alice.address, epochBalance, expectBalance);
      await expect(
        erc7818.connect(alice).transferAtEpoch(0, bob.address, epochBalance)
      )
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, epochBalance);
      expect(await erc7818.balanceOf(bob.address)).to.equal(epochBalance);
    });

    it("[FAILED] insufficient balance", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});
      await expect(erc7818.connect(alice).transfer(bob.address, 1))
        .to.be.revertedWithCustomError(
          erc7818,
          ERROR_ERC20_INSUFFICIENT_BALANCE
        )
        .withArgs(alice.address, 0, 1);
    });
  });
};
