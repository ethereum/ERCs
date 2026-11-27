import {time} from "@nomicfoundation/hardhat-network-helpers";

export const hardhat_reset = async function () {
  await network.provider.send("hardhat_reset");
};

export const hardhat_latestBlock = async function () {
  return await time.latestBlock();
};
