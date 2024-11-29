import { expect } from "chai";
import {
  calculateSlidingWindowState,
  deployERC7818,
  mineBlock,
  skipToBlock,
} from "../utils.test";
import { ERC20_NAME, ERC20_SYMBOL, EVENT_TRANSFER } from "../constant.test";
import { network } from "hardhat";
import { ZeroAddress } from "ethers";

export const run = async () => {
  describe("General", async function () {
    const blockPeriod = 400;
    const slotSize = 4;
    const frameSize = 2;

    it("[SUCCESS] query block per era", async function () {
      const { erc7818 } = await deployERC7818({ blockPeriod });
      const self = calculateSlidingWindowState({ blockPeriod });
      expect(await erc7818.getBlockPerEra()).to.equal(self._blockPerEra);
    });

    it("[SUCCESS] query block per slot", async function () {
      const { erc7818 } = await deployERC7818({ blockPeriod, slotSize });
      const self = calculateSlidingWindowState({ blockPeriod, slotSize });
      expect(await erc7818.getBlockPerSlot()).to.equal(self._blockPerSlot);
    });

    it("[SUCCESS] query slot per era", async function () {
      const { erc7818 } = await deployERC7818({ slotSize });
      const self = calculateSlidingWindowState({ slotSize });
      expect(await erc7818.getSlotPerEra()).to.equal(self._slotSize);
    });

    it("[SUCCESS] query frame size in block length", async function () {
      const { erc7818 } = await deployERC7818({
        blockPeriod,
        slotSize,
        frameSize,
      });
      const self = calculateSlidingWindowState({
        blockPeriod,
        slotSize,
        frameSize,
      });
      expect(await erc7818.validityPeriod()).to.equal(self._frameSizeInBlockLength);
    });

    it("[SUCCESS] query frame size in era length", async function () {
      const { erc7818 } = await deployERC7818({
        blockPeriod,
        slotSize,
        frameSize,
      });
      const self = calculateSlidingWindowState({
        blockPeriod,
        slotSize,
        frameSize,
      });
      expect(await erc7818.getFrameSizeInEraLength()).to.equal(
        self._frameSizeInEraAndSlotLength[0]
      );
    });

    it("[SUCCESS] query frame size in slot length", async function () {
      const { erc7818 } = await deployERC7818({
        blockPeriod,
        slotSize,
        frameSize,
      });
      const self = calculateSlidingWindowState({
        blockPeriod,
        slotSize,
        frameSize,
      });
      expect(await erc7818.getFrameSizeInSlotLength()).to.equal(
        self._frameSizeInEraAndSlotLength[1]
      );
    });

    it("[SUCCESS] query frame", async function () {
      const { erc7818 } = await deployERC7818({
        blockPeriod,
        slotSize,
        frameSize,
      });
      const self = calculateSlidingWindowState({
        blockPeriod,
        slotSize,
        frameSize,
      });
      await mineBlock(Number(self._blockPerSlot) * 5);
      const [fromEra, toEra, fromSlot, toSlot] = await erc7818.frame();
      expect(fromEra).to.equal(0);
      expect(toEra).to.equal(1);
      expect(fromSlot).to.equal(3);
      expect(toSlot).to.equal(1);
    });

    it("[SUCCESS] query safe frame", async function () {
      const { erc7818 } = await deployERC7818({
        blockPeriod,
        slotSize,
        frameSize,
      });
      const self = calculateSlidingWindowState({
        blockPeriod,
        slotSize,
        frameSize,
      });
      await mineBlock(Number(self._blockPerSlot) * 5);
      const [fromEra, toEra, fromSlot, toSlot] = await erc7818.safeFrame();
      expect(fromEra).to.equal(0);
      expect(toEra).to.equal(1);
      expect(fromSlot).to.equal(2);
      expect(toSlot).to.equal(1);
    });

    it("[SUCCESS] query name", async function () {
      const { erc7818 } = await deployERC7818({});
      expect(await erc7818.name()).to.equal(ERC20_NAME);
    });

    it("[SUCCESS] query symbol", async function () {
      const { erc7818 } = await deployERC7818({});
      expect(await erc7818.symbol()).to.equal(ERC20_SYMBOL);
    });

    it("[SUCCESS] query total supply", async function () {
      const { erc7818 } = await deployERC7818({});
      // Due to token can expiration there is no actual totalSupply.
      expect(await erc7818.totalSupply()).to.equal(0);
    });

    it("[SUCCESS] query decimals", async function () {
      const { erc7818 } = await deployERC7818({});
      expect(await erc7818.decimals()).to.equal(18);
    });

    it("[SUCCESS] query block balance ", async function () {
      const { erc7818, alice } = await deployERC7818({});

      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");
      expect(await erc7818.getBlockBalance(blockNumber)).to.equal(1);
      expect(await erc7818.getBlockBalance(blockNumber + 1n)).to.equal(0);
    });

    it("[SUCCESS] query balance of ", async function () {
      const { erc7818, alice } = await deployERC7818({});

      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");
      expect(
        await erc7818.balanceOfAtEpoch(alice.address, blockNumber)
      ).to.equal(1);
    });

    it("[FAILED] query balance of ", async function () {
      const { erc7818, alice } = await deployERC7818({});

      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");
      await skipToBlock(Number(blockNumber) + Number(await erc7818.validityPeriod()));
      expect(
        await erc7818.balanceOfAtEpoch(alice.address, blockNumber)
      ).to.equal(0);
    });

    it("[SUCCESS] query epoch ", async function () {
      const { erc7818 } = await deployERC7818({});
      expect(await erc7818.currentEpoch()).to.equal(0);
      await mineBlock(Number(await erc7818.getBlockPerEra()));
      expect(await erc7818.currentEpoch()).to.equal(1);
    });

    it("[SUCCESS] query isEpochExpired ", async function () {
      const { erc7818, alice } = await deployERC7818({});

      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");
      await skipToBlock(Number(blockNumber) + Number(await erc7818.validityPeriod()));
      expect(await erc7818.isEpochExpired(blockNumber)).to.equal(true);
    });

    it("[FAILED] query isEpochExpired ", async function () {
      const { erc7818, alice } = await deployERC7818({});

      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");
      expect(await erc7818.isEpochExpired(blockNumber)).to.equal(false);
    });
  });
};
