import {expect} from "chai";
import {deployERC7818, mineBlock, skipToBlock} from "../utils.test";
import {
  ERROR_ERC20_INSUFFICIENT_BALANCE,
  ERROR_ERC20_INVALID_RECEIVER,
  ERROR_ERC20_INVALID_SENDER,
  EVENT_TRANSFER,
  ZERO_ADDRESS,
} from "../constant.test";

export const run = async () => {
  describe("Transfer", async function () {
    it("[HAPPY] transfer correctly if frame size is 2 and slot per era is 4", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 2, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice     Bob
      //  10, 10    10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  5, 10     5, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(15);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 10.
      // Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  0, 5      0, 5, 10, 10
      //  0, 0      0, 10, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[HAPPY] transfer correctly if frame size is 4 and slot per era is 4", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 4, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice     Bob
      //  10, 10    10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  5, 10     5, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(15);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 10.
      // Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  0, 5      0, 5, 10, 10
      //  0, 0      0, 10, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[HAPPY] transfer correctly if frame size is 6 and slot per era is 4", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 6, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice     Bob
      //  10, 10    10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  5, 10     5, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(15);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 10.
      // Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  0, 5      0, 5, 10, 10
      //  0, 0      0, 10, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[HAPPY] transfer correctly if frame size is 8 and slot per era is 4", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 8, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

      // Ensure we are in [era: 0, slot 0].
      let [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(0);

      // Mint into [era: 0, slot 0].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 0, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(1);

      // Mint into [era: 0, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice     Bob
      //  10, 10    10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  5, 10     5, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(15);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 10.
      // Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------|   <-- era 1.
      // {19723078}{19723078}{19723078}{19723078}   <-- 4 slot.
      //  *  [0]    *  [1]       [2]       [3]
      //  Alice --> Bob
      //  0, 5      0, 5, 10, 10
      //  0, 0      0, 10, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[HAPPY] transfer correctly if frame size is 2 and slot per era is 4 and mint at end era period", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 2, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

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
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 1, slot 0].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 1, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(0);

      // Mint into [era: 1, slot 0].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 1, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(0);

      // Mint into [era: 1, slot 0].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               10, 10    10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               5, 10 --> 5, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(15);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 10.
      // Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               0, 5  --> 0, 5, 10, 10
      //                               0, 0  --> 0, 10, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[HAPPY] transfer correctly if frame size is 4 and slot per era is 4 and mint at end era period", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 4, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

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
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 1, slot 0].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 1, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(0);

      // Mint into [era: 1, slot 0].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 1, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(0);

      // Mint into [era: 1, slot 0].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               10, 10    10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               5, 10 --> 5, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(15);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 10.
      // Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               0, 5  --> 0, 5, 10, 10
      //                               0, 0  --> 0, 10, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[HAPPY] transfer correctly if frame size is 6 and slot per era is 4 and mint at end era period", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 6, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

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
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 0, slot 3].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(0);
      expect(slot).equal(3);

      // Mint into [era: 0, slot 3].
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // Skip to [era: 1, slot 0].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 1, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(0);

      // Mint into [era: 1, slot 0].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 1, slot 0].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(0);

      // Mint into [era: 1, slot 0].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               10, 10    10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               5, 10 --> 5, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(15);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 10.
      // Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(10);
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   *   [3]   *  [0]       [1]       [2]       [3]
      //                               Alice     Bob
      //                               0, 5  --> 0, 5, 10, 10
      //                               0, 0  --> 0, 10, 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[HAPPY] transfer correctly if frame size is 8 and slot per era is 4 and mint at end era period", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({frameSize: 8, slotSize: 4});

      const blockPerSlot = Number(await erc7818.getBlockPerSlot());
      const blockPerFrame = Number(await erc7818.getFrameSizeInBlockLength());

      const aliceAddress = await alice.getAddress();
      const bobAddress = await bob.getAddress();

      const aliceExpectExp = [];
      const bobExpectExp = [];

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
      const amount = 10;
      await expect(erc7818.mint(aliceAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, aliceAddress, amount);

      let list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

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

      list = await erc7818.tokenList(aliceAddress, era, slot);
      aliceExpectExp.push(Number(list[0]) + blockPerFrame);
      expect(list.length).equal(1);

      // Skip to [era: 1, slot 1].
      await mineBlock(blockPerSlot);
      // Ensure we are in [era: 1, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(1);

      // Mint into [era: 1, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      // Skip 100 blocks
      await mineBlock(100);
      // Ensure we are in [era: 1, slot 1].
      [era, slot] = await erc7818.currentEraAndSlot();
      expect(era).equal(1);
      expect(slot).equal(1);

      // Mint into [era: 1, slot 1].
      await expect(erc7818.mint(bobAddress, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, bobAddress, amount);

      list = await erc7818.tokenList(bobAddress, era, slot);
      bobExpectExp.push(Number(list[0]) + blockPerFrame, Number(list[1]) + blockPerFrame);
      expect(list.length).equal(2);

      // blocks in year equal to 78892315 since blocktime equal to 400ms.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   |    [3]  |   [0]   |   [1]       [2]       [3]
      //                               |Alice    |         |
      //                               |10,      |10       |
      //                               |Bob      |         |
      //                               |         |         | 10, 10

      // Right now, the balance of Alice and Bob must be 20.
      expect(await erc7818.balanceOf(aliceAddress)).equal(amount * 2);
      expect(await erc7818.balanceOf(bobAddress)).equal(amount * 2);

      // Transfer 5 token from Alice to Bob.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   |    [3]  |   [0]   |   [1]       [2]       [3]
      //                               |Alice    |         |
      //                               |0,       |5        |
      //                               |Bob      |         |
      //                               |10       |5        | 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 15))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 15);
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(35);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[0]);

      // Right now, the balance of
      // Alice must be 5.
      // Bob must be 25.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(aliceAddress)).equal(5);
      expect(await erc7818.balanceOf(bobAddress)).equal(25);

      // // Transfer 5 tokens from Alice to Bob, repeating this process twice.
      // |-------------- 78892315 --------------||-------------- 78892315 --------------|  <-- era 2.
      // {19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}{19723078}  <-- 8 slot.
      //     [0]       [1]       [2]   |    [3]  |   [0]   |   [1]       [2]       [3]
      //                               |Alice    |         |
      //                               |0,       |0        |
      //                               |Bob      |         |
      //                               |0        |10       | 10, 10

      expect(await erc7818.connect(alice).transfer(bobAddress, 5))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(aliceAddress, bobAddress, 5);
      expect(await erc7818.balanceOf(aliceAddress)).equal(0);
      expect(await erc7818.balanceOf(bobAddress)).equal(30);

      // Skip to the expiry period of Alice.
      await skipToBlock(aliceExpectExp[1]);

      // Right now, the balance of Bob must be 20.
      // Because Alice's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(20);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[0]);

      // Right now, the balance of Bob must be 10.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(10);

      // Skip to the expiry period of Bob.
      await skipToBlock(bobExpectExp[1]);

      // Right now, the balance of Bob must be 0.
      // Because Bob's 10 tokens have expired.
      expect(await erc7818.balanceOf(bobAddress)).equal(0);
    });

    it("[UNHAPPY] transfer from zero address", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      expect(erc7818.badTransfer(ZERO_ADDRESS, await alice.getAddress(), 1))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_SENDER)
        .withArgs(ZERO_ADDRESS);
    });

    it("[UNHAPPY] transfer to zero address", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice} = await deployERC7818({});

      expect(erc7818.connect(alice).transfer(ZERO_ADDRESS, 1))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_RECEIVER)
        .withArgs(ZERO_ADDRESS);
    });

    it("[UNHAPPY] insufficient balance", async function () {
      // Start at block 100.
      const startBlockNumber = 100;

      await mineBlock(startBlockNumber);
      const {erc7818, alice, bob} = await deployERC7818({});

      expect(erc7818.connect(alice).transfer(await bob.getAddress(), 1))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INSUFFICIENT_BALANCE)
        .withArgs(await alice.getAddress(), 0, 1);
    });
  });
};
