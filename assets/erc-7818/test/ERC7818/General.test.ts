import {expect} from "chai";
import {calculateSlidingWindowState, deployERC7818, mineBlock} from "../utils.test";
import {ERC20_NAME, ERC20_SYMBOL, EVENT_TRANSFER, ZERO_ADDRESS} from "../constant.test";
import {network} from "hardhat";

export const run = async () => {
  describe("General", async function () {
    it("[HAPPY] query block per era", async function () {
      const blockPeriod = 400;

      const {erc7818} = await deployERC7818({blockPeriod});

      const self = calculateSlidingWindowState({blockPeriod});
      expect(await erc7818.getBlockPerEra()).to.equal(self._blockPerEra);
    });

    it("[HAPPY] query block per slot", async function () {
      const blockPeriod = 400;
      const slotSize = 4;

      const {erc7818} = await deployERC7818({blockPeriod, slotSize});

      const self = calculateSlidingWindowState({blockPeriod, slotSize});
      expect(await erc7818.getBlockPerSlot()).to.equal(self._blockPerSlot);
    });

    it("[HAPPY] query slot per era", async function () {
      const slotSize = 4;

      const {erc7818} = await deployERC7818({slotSize});

      const self = calculateSlidingWindowState({slotSize});
      expect(await erc7818.getSlotPerEra()).to.equal(self._slotSize);
    });

    it("[HAPPY] query frame size in block length", async function () {
      const blockPeriod = 400;
      const slotSize = 4;
      const frameSize = 2;

      const {erc7818} = await deployERC7818({blockPeriod, slotSize, frameSize});

      const self = calculateSlidingWindowState({blockPeriod, slotSize, frameSize});
      expect(await erc7818.getFrameSizeInBlockLength()).to.equal(self._frameSizeInBlockLength);
    });

    it("[HAPPY] query frame size in era length", async function () {
      const blockPeriod = 400;
      const slotSize = 4;
      const frameSize = 2;

      const {erc7818} = await deployERC7818({blockPeriod, slotSize, frameSize});

      const self = calculateSlidingWindowState({blockPeriod, slotSize, frameSize});
      expect(await erc7818.getFrameSizeInEraLength()).to.equal(self._frameSizeInEraAndSlotLength[0]);
    });

    it("[HAPPY] query frame size in slot length", async function () {
      const blockPeriod = 400;
      const slotSize = 4;
      const frameSize = 2;

      const {erc7818} = await deployERC7818({blockPeriod, slotSize, frameSize});

      const self = calculateSlidingWindowState({blockPeriod, slotSize, frameSize});
      expect(await erc7818.getFrameSizeInSlotLength()).to.equal(self._frameSizeInEraAndSlotLength[1]);
    });

    it("[HAPPY] query frame", async function () {
      const blockPeriod = 400;
      const slotSize = 4;
      const frameSize = 2;

      const {erc7818} = await deployERC7818({blockPeriod, slotSize, frameSize});

      const self = calculateSlidingWindowState({blockPeriod, slotSize, frameSize});

      await mineBlock(Number(self._blockPerSlot) * 5);

      const [fromEra, toEra, fromSlot, toSlot] = await erc7818.frame();

      expect(fromEra).to.equal(0);
      expect(toEra).to.equal(1);

      expect(fromSlot).to.equal(3);
      expect(toSlot).to.equal(1);
    });

    it("[HAPPY] query safe frame", async function () {
      const blockPeriod = 400;
      const slotSize = 4;
      const frameSize = 2;

      const {erc7818} = await deployERC7818({blockPeriod, slotSize, frameSize});

      const self = calculateSlidingWindowState({blockPeriod, slotSize, frameSize});

      await mineBlock(Number(self._blockPerSlot) * 5);

      const [fromEra, toEra, fromSlot, toSlot] = await erc7818.safeFrame();

      expect(fromEra).to.equal(0);
      expect(toEra).to.equal(1);

      expect(fromSlot).to.equal(2);
      expect(toSlot).to.equal(1);
    });

    it("[HAPPY] query name", async function () {
      const {erc7818} = await deployERC7818({});

      expect(await erc7818.name()).to.equal(ERC20_NAME);
    });

    it("[HAPPY] query symbol", async function () {
      const {erc7818} = await deployERC7818({});

      expect(await erc7818.symbol()).to.equal(ERC20_SYMBOL);
    });

    it("[HAPPY] query total supply", async function () {
      const {erc7818} = await deployERC7818({});

      // Due to token can expiration there is no actual totalSupply.
      expect(await erc7818.totalSupply()).to.equal(0);
    });

    it("[HAPPY] query decimals", async function () {
      const {erc7818} = await deployERC7818({});

      expect(await erc7818.decimals()).to.equal(18);
    });

    it("[HAPPY] query block balance ", async function () {
      const {erc7818, alice} = await deployERC7818({});
      const aliceAddress = await alice.getAddress();
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);
      const blockNumber = await network.provider.send("eth_blockNumber");
      expect(await erc7818.getBlockBalance(blockNumber)).to.equal(1);
      expect(await erc7818.getBlockBalance(blockNumber + 1n)).to.equal(0);
    });
  });
};
