import { expect } from "chai";
import { deployERC7818, skipToBlock } from "../utils.test";
import {
  ERROR_ERC20_INSUFFICIENT_ALLOWANCE,
  ERROR_ERC7818_TRANSFER_EXPIRED,
  EVENT_APPROVAL,
  EVENT_TRANSFER,
} from "../constant.test";
import { ZeroAddress } from "ethers";
import { network } from "hardhat";

export const run = async () => {
  describe("TransferFrom", async function () {
    it("[SUCCESS] transfer from alice to bob correctly", async function () {
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
          ["transferFrom(address,address,uint256)"](
            alice.address,
            bob.address,
            amount
          )
      )
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, amount);
    });

    it("[SUCCESS] transfer specific id from alice to bob correctly", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");

      await expect(erc7818.connect(alice).approve(bob.address, amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);

      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        amount
      );

      await expect(
        erc7818
          .connect(bob)
          .transferFromAtEpoch(
            alice.address,
            bob.address,
            blockNumber,
            amount
          )
      )
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, amount);

      expect(
        await erc7818.balanceOfAtEpoch(bob.address, blockNumber)
      ).to.equals(amount);
    });

    it("[SUCCESS] alice approve maximum and transfer to bob correctly", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});

      const amount = 100;
      const MAX_INT =
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");

      await expect(erc7818.connect(alice).approve(bob.address, MAX_INT))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, MAX_INT);

      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        MAX_INT
      );

      await expect(
        erc7818
          .connect(bob)
          ["transferFrom(address,address,uint256)"](
            alice.address,
            bob.address,
            amount
          )
      )
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(alice.address, bob.address, amount);
      expect(
        await erc7818.balanceOfAtEpoch(bob.address, blockNumber)
      ).to.equals(amount);
    });

    it("[FAILED] insufficient allowance", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      await expect(
        erc7818.connect(alice).approve(bob.address, amount)
      )
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);

      expect(
        await erc7818.allowance(
          alice.address,
          bob.address
        )
      ).to.equal(amount);

      await expect(
        erc7818
          .connect(bob)
          ["transferFrom(address,address,uint256)"](
            alice.address,
            bob.address,
            amount * 2
          )
      )
        .to.be.revertedWithCustomError(
          erc7818,
          ERROR_ERC20_INSUFFICIENT_ALLOWANCE
        )
        .withArgs(bob.address, amount, amount * 2);
    });

    it("[FAILED] transfer specific id from alice to bob", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");

      await expect(erc7818.connect(alice).approve(bob.address, amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);

      expect(await erc7818.allowance(alice.address, bob.address)).to.equal(
        amount
      );

      await skipToBlock(Number(blockNumber) + Number(await erc7818.validityPeriod()));
      await expect(
        erc7818
          .connect(bob)
          .transferFromAtEpoch(
            alice.address,
            bob.address,
            blockNumber,
            amount
          )
      ).to.be.revertedWithCustomError(erc7818, ERROR_ERC7818_TRANSFER_EXPIRED);

      expect(
        await erc7818.balanceOfAtEpoch(alice.address, blockNumber)
      ).to.equals(0);
    });
  });
};
