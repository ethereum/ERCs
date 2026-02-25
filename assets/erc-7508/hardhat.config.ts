import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-chai-matchers";
import "@typechain/hardhat";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.21",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 100000,
      },
    },
  },
};

export default config;
