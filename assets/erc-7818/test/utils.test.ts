import { Contract, Signer } from "ethers";
import { ethers } from "hardhat";
import {
  ERC20_NAME,
  ERC20_SYMBOL,
  ERC20_EXPIRABLE_CONTRACT,
  YEAR_IN_MILLISECONDS,
} from "./constant.test";

export interface ISlidingWindowState {
  _blocksPerEpoch: Number;
  _windowSize: Number;
  _initialBlockNumber: Number;
}

export const calculateSlidingWindowState = function ({
  startBlockNumber = 100,
  blockTime = 400,
  windowSize = 2,
}): ISlidingWindowState {
  const self: ISlidingWindowState = {
    _blocksPerEpoch: 0,
    _windowSize: 0,
    _initialBlockNumber: 0,
  };
  self._initialBlockNumber = startBlockNumber;
  // since solidity always rounds down. then use 'Math.floor'
  const blocksPerEpochCache = Math.floor(Math.floor(YEAR_IN_MILLISECONDS / blockTime) / 4);
  self._blocksPerEpoch = blocksPerEpochCache;
  self._windowSize = windowSize;
  return self;
};

export const deployERC7818 = async function ({
  blockTime = 400, // assume 400ms block time
  windowSize = 2, // widow width size 2 epoch
} = {}) {
  const [deployer, alice, bob, jame] = await ethers.getSigners();

  const ERC7818 = await ethers.getContractFactory(
    ERC20_EXPIRABLE_CONTRACT,
    deployer
  );
  const erc7818 = await ERC7818.deploy(
    ERC20_NAME,
    ERC20_SYMBOL,
    blockTime,
    windowSize
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

