import {expect} from "chai";
import {deployERC7818, mineBlock, skipToBlock} from "../utils.test";
import {
  ERROR_ERC20_INSUFFICIENT_BALANCE,
  ERROR_ERC20_INVALID_SENDER,
  EVENT_TRANSFER,
  ZERO_ADDRESS,
} from "../constant.test";

export const run = async () => {
  describe("Burn", async function () {
    it("[HAPPY] burn correctly if mint tokens into slot 0, 1 of era 0", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  ^         ^
      //  |         |
      //  |         |
      //  |         |
      // mint      mint

      // Right now, the balance must be 2.
      expect(await erc7818.balanceOf(aliceAddress)).equal(2);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, amount);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 1, 2 of era 0", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 0, slot 1].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 2].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 2].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //     [0]    *  [1]    *  [2]       [3]
      //            ^         ^
      //            |         |
      //            |         |
      //            |         |
      //           mint      mint

      // Right now, the balance must be 2.
      expect(await erc7818.balanceOf(aliceAddress)).equal(2);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, amount);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 2, 3 of era 0", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Skip to [era: 0, slot 2].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 0, slot 2].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 3].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount + amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //     [0]       [1]    *  [2]    *  [3]
      //                      ^         ^
      //                      |         |
      //                      |         |
      //                      |         |
      //                     mint      mint

      // Right now, the balance must be 4.
      expect(await erc7818.balanceOf(aliceAddress)).equal(4);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, 3))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, 3);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1,2.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1. Because we have burned 3 tokens before.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 3,4.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 0, 1 of era 0 when frame size full era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({frameSize: 4, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  ^         ^
      //  |         |
      //  |         |
      //  |         |
      // mint      mint

      // Right now, the balance must be 2.
      expect(await erc7818.balanceOf(aliceAddress)).equal(2);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, amount);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 1, 2 of era 0 when frame size full era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({frameSize: 4, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 0, slot 1].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 2].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 2].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //     [0]    *  [1]    *  [2]       [3]
      //            ^         ^
      //            |         |
      //            |         |
      //            |         |
      //           mint      mint

      // Right now, the balance must be 2.
      expect(await erc7818.balanceOf(aliceAddress)).equal(2);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, amount);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 2, 3 of era 0 when frame size full era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({frameSize: 4, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Skip to [era: 0, slot 2].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 0, slot 2].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 3].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount + amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //     [0]       [1]    *  [2]    *  [3]
      //                      ^         ^
      //                      |         |
      //                      |         |
      //                      |         |
      //                     mint      mint

      // Right now, the balance must be 4.
      expect(await erc7818.balanceOf(aliceAddress)).equal(4);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, 3))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, 3);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1,2.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1. Because we have burned 3 tokens before.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 3,4.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 0, 1 of era 0 when frame size over era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({frameSize: 6, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  ^         ^
      //  |         |
      //  |         |
      //  |         |
      // mint      mint

      // Right now, the balance must be 2.
      expect(await erc7818.balanceOf(aliceAddress)).equal(2);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, amount);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 1, 2 of era 0 when frame size over era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({frameSize: 6, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 0, slot 1].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 2].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 2].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //     [0]    *  [1]    *  [2]       [3]
      //            ^         ^
      //            |         |
      //            |         |
      //            |         |
      //           mint      mint

      // Right now, the balance must be 2.
      expect(await erc7818.balanceOf(aliceAddress)).equal(2);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, amount);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint tokens into slot 2, 3 of era 0 when frame size over era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({frameSize: 6, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Skip to [era: 0, slot 2].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 0, slot 2].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 3].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount + amount + amount + amount);
      list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //     [0]       [1]    *  [2]    *  [3]
      //                      ^         ^
      //                      |         |
      //                      |         |
      //                      |         |
      //                     mint      mint

      // Right now, the balance must be 4.
      expect(await erc7818.balanceOf(aliceAddress)).equal(4);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, 3))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, 3);
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 1,2.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1. Because we have burned 3 tokens before.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to the expiry period of token 3,4.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if value less than block balance", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]       [1]       [2]       [3]
      //  ^
      //  |
      //  |
      //  |
      // mint

      // Right now, the balance must be 10.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);

      // Skip to the expiry period.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 0.
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[HAPPY] burn correctly if mint mint at end era period", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Skip to [era: 0, slot 2].
      await mineBlock(blockPerSlot);
      // Skip to [era: 0, slot 3].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 0, slot 3].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      const amount = 1;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      expect(await erc7818.balanceOf(aliceAddress)).equal(amount);
      let list = await erc7818.tokenList(aliceAddress, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //     [0]       [1]       [2]    *   [3]
      //                                ^
      //                                |
      //                                |
      //                                |
      //                                mint

      // Right now, the balance must be 1.
      expect(await erc7818.balanceOf(aliceAddress)).equal(1);

      // Skip to [era: 1, slot 0].
      await mineBlock(blockPerSlot);

      // Ensure we are in [era: 1, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(0);

      // Mint into [era: 1, slot 0].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Expectation is that the token will be burning from the head of the linked list.
      await expect(erc7818.burn(aliceAddress, amount + amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, ZERO_ADDRESS, amount + amount);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
    });

    it("[UNHAPPY] burn from zero address", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818} = await deployERC7818({});

      expect(erc7818.burn(ZERO_ADDRESS, 1))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_SENDER)
        .withArgs(ZERO_ADDRESS);
    });

    it("[UNHAPPY] insufficient balance", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      expect(erc7818.burn(await alice.getAddress(), 1))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INSUFFICIENT_BALANCE)
        .withArgs(await alice.getAddress(), 0, 1);
    });
  });
};
