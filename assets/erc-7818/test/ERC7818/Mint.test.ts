import { expect } from "chai";
import { deployERC7818, mineBlock, skipToBlock } from "../utils.test";
import { ERROR_ERC20_INVALID_RECEIVER, EVENT_TRANSFER } from "../constant.test";
import { ZeroAddress } from "ethers";

export const run = async () => {
  describe("Mint", async function () {
    it("[SUCCESS] mint correctly tokens into slot 0, 1 of era 0", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(amount);
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 1, 2 of era 0", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));

      // Ensure we are in [era: 0, slot 1].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(amount);
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 2].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 2].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 2, 3 of era 0", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));
      // Skip to [era: 0, slot 2].
      await mineBlock(Number(blockPerSlot));

      // Ensure we are in [era: 0, slot 2].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 3].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount + amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(4);

      // Skip to the expiry period of token 1,2.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 2.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 3,4.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 0, 1 of era 0 when frame size full era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({
        frameSize: 4,
        slotSize: 4,
      });

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(amount);
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 1, 2 of era 0 when frame size full era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({
        frameSize: 4,
        slotSize: 4,
      });

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));

      // Ensure we are in [era: 0, slot 1].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(amount);
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 2].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 2].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 2, 3 of era 0 when frame size full era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({
        frameSize: 4,
        slotSize: 4,
      });

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));
      // Skip to [era: 0, slot 2].
      await mineBlock(Number(blockPerSlot));

      // Ensure we are in [era: 0, slot 2].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 3].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount + amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(4);

      // Skip to the expiry period of token 1,2.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 2.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 3,4.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 0, 1 of era 0 when frame size over era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({
        frameSize: 6,
        slotSize: 4,
      });

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(amount);
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 1, 2 of era 0 when frame size over era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({
        frameSize: 6,
        slotSize: 4,
      });

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));

      // Ensure we are in [era: 0, slot 1].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(amount);
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 0, slot 2].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 2].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 1.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 1.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(1);

      // Skip to the expiry period of token 2.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[SUCCESS] mint correctly tokens into slot 2, 3 of era 0 when frame size over era", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818, alice } = await deployERC7818({
        frameSize: 6,
        slotSize: 4,
      });

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.duration());

      const expectExp = [];

      // Skip to [era: 0, slot 1].
      await mineBlock(Number(blockPerSlot));
      // Skip to [era: 0, slot 2].
      await mineBlock(Number(blockPerSlot));

      // Ensure we are in [era: 0, slot 2].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(2);

      // Mint into [era: 0, slot 2].
      const amount = 1;
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount
      );
      let list = await erc7818.tokenList(alice.address, era, slot);
      expectExp.push(Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 3].
      await mineBlock(Number(blockPerSlot));
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);
      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      expect(await erc7818["balanceOf(address)"](alice.address)).equal(
        amount + amount + amount + amount
      );
      list = await erc7818.tokenList(alice.address, era, slot);
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
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(4);

      // Skip to the expiry period of token 1,2.
      await skipToBlock(expectExp[0]);

      // Right now, the balance must be 2.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(2);

      // Skip to the expiry period of token 3,4.
      await skipToBlock(expectExp[1]);

      // Right now, the balance must be 0.
      expect(await erc7818["balanceOf(address)"](alice.address)).equal(0);
    });

    it("[FAILED] mint to zero address", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const { erc7818 } = await deployERC7818({});

      expect(erc7818.mint(ZeroAddress, 1))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_RECEIVER)
        .withArgs(ZeroAddress);
    });
  });
};
