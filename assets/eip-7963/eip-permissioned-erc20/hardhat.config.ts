import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache_hardhat",
    artifacts: "./artifacts",
  },
  networks: {
    hardhat: {
      // Configuration for the local Hardhat Network
    },
    // Add other network configurations here (e.g., Sepolia, mainnet)
  },
  mocha: {
    timeout: 40000, // Optional: Set a longer timeout for tests
  },
};

export default config; 