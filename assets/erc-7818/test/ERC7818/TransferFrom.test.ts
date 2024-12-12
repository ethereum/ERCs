import { expect } from "chai";
import { deployERC7818, skipToBlock } from "../utils.test";
import {
  ERROR_ERC20_INSUFFICIENT_ALLOWANCE,
  ERROR_ERC20_INSUFFICIENT_BALANCE,
  ERROR_ERC7818_INVALID_EPOCH,
  ERROR_ERC7818_TRANSFER_EXPIRED,
  EVENT_APPROVAL,
  EVENT_TRANSFER,
} from "../constant.test";
import { ZeroAddress } from "ethers";
import { network } from "hardhat";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

export const run = async () => {
  describe("TransferFrom", async function () {
    beforeEach(async function () {
      await network.provider.send("hardhat_reset");
    });

    it("[SUCCESS] transfer from alice to bob", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});
      const amount = 100;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.connect(alice).approve(bob.address, amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);
      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        amount
      );      
      await expect(
        erc7818
          .connect(bob)
          .transferFrom(alice.address, bob.address, amount)
      ) .to.be.emit(erc7818, EVENT_TRANSFER)
      .withArgs(alice.address, bob.address, amount);
    });

    it("[SUCCESS] transfer from specific epoch from alice to bob", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});
      const amount = 100;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.connect(alice).approve(bob.address, amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);
      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        amount
      );
      await expect(
        erc7818
          .connect(bob)
          .transferFromAtEpoch(0, alice.address, bob.address, amount)
      ) .to.be.emit(erc7818, EVENT_TRANSFER)
      .withArgs(alice.address, bob.address, amount);
    });

    it("[FAILED] transfer from insufficient allowance", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});
      const amount = 100;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.connect(alice).approve(bob.address, amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);
      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        amount
      );
      await expect(
        erc7818
          .connect(bob)
          .transferFrom(alice.address, bob.address, amount * 2)
      )
        .to.be.revertedWithCustomError(
          erc7818,
          ERROR_ERC20_INSUFFICIENT_ALLOWANCE
        )
        .withArgs(bob.address, amount, amount * 2);
    });

    it("[FAILED] transfer from expired epoch from alice to bob", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});
      const amount = 100;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.connect(alice).approve(bob.address, amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);
      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        amount
      );
      await mine((await erc7818.epochLength()) * BigInt(10));
      await expect(
        erc7818
          .connect(bob)
          .transferFromAtEpoch(0, alice.address, bob.address, amount)
      ).to.be.revertedWithCustomError(erc7818, ERROR_ERC7818_TRANSFER_EXPIRED);
    });

    it("[FAILED] transfer from out of valid range epoch from alice to bob", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});
      const amount = 100;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.connect(alice).approve(bob.address, amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);
      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        amount
      );
      await expect(
        erc7818
          .connect(bob)
          .transferFromAtEpoch(100, alice.address, bob.address, amount)
      ).to.be.revertedWithCustomError(erc7818, ERROR_ERC7818_INVALID_EPOCH);
    });
  });
};
