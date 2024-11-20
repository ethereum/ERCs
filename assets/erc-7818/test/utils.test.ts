import { Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import { mine, time } from "@nomicfoundation/hardhat-network-helpers";
import {
  ERC20_NAME,
  ERC20_SYMBOL,
  ERC20_EXPIRABLE_CONTRACT,
  SlidingWindowState,
  YEAR_IN_MILLISECONDS,
} from "./constant.test";

// tools
export const latestBlock = async function () {
  return await time.latestBlock();
};

export const mineBlock = async function (
  blocks: number = 1,
  options: { interval?: number } = {}
) {
  await mine(blocks, options);
};

export const skipToBlock = async function (target: number) {
  await mine(target - (await time.latestBlock()));
};

export const padIndexToData = function (index: Number) {
  // The padding is applied from the start of this string (output: 0x0001).
  return `0x${index.toString().padStart(4, "0")}`;
};

export const calculateSlidingWindowState = function ({
  startBlockNumber = 100,
  blockPeriod = 400,
  frameSize = 2,
  slotSize = 4,
}): SlidingWindowState {
  const self: SlidingWindowState = {
    _blockPerEra: 0,
    _blockPerSlot: 0,
    _frameSizeInBlockLength: 0,
    _frameSizeInEraAndSlotLength: [],
    _slotSize: 0,
    _startBlockNumber: 0,
  };

  self._startBlockNumber = startBlockNumber;

  // Why 'Math.floor', Since Solidity always rounds down.
  const blockPerSlotCache = Math.floor(
    Math.floor(YEAR_IN_MILLISECONDS / blockPeriod) / slotSize
  );
  const blockPerEraCache = blockPerSlotCache * slotSize;

  self._blockPerEra = blockPerEraCache;
  self._blockPerSlot = blockPerSlotCache;
  self._frameSizeInBlockLength = blockPerSlotCache * frameSize;
  self._slotSize = slotSize;
  if (frameSize <= slotSize) {
    self._frameSizeInEraAndSlotLength[0] = 0;
    self._frameSizeInEraAndSlotLength[1] = frameSize;
  } else {
    self._frameSizeInEraAndSlotLength[0] = frameSize / slotSize;
    self._frameSizeInEraAndSlotLength[1] = frameSize % slotSize;
  }

  return self;
};

export const getAddress = async function (account: Signer | Contract) {
  if (account instanceof Contract) {
    return account.address.toLowerCase();
  }
  return (await account.getAddress()).toLowerCase();
};

const deployERC7818Base = async function (
  blockPeriod: number,
  frameSize: number,
  slotSize: number
) {
  const [deployer, alice, bob, jame] = await ethers.getSigners();

  const ERC7818 = await ethers.getContractFactory(
    ERC20_EXPIRABLE_CONTRACT,
    deployer
  );
  const erc7818 = await ERC7818.deploy(
    ERC20_NAME,
    ERC20_SYMBOL,
    blockPeriod,
    frameSize,
    slotSize
  );
  await erc7818.waitForDeployment();

  return {
    erc7818,
    deployer,
    alice,
    bob,
    jame,
  };
};

export const deployERC7818 = async function ({
  blockPeriod = 400, // 400ms per block
  frameSize = 2, // frame size 2 slot
  slotSize = 4, // 4 slot per era
}) {
  return deployERC7818Base(blockPeriod, frameSize, slotSize);
};
