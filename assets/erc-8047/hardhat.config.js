require("hardhat-gas-reporter");
require("hardhat-ignore-warnings");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  networks: {
    hardhat: {
      gasPrice: 0,
      initialBaseFeePerGas: 0,
      blockGasLimit: 100_000_000,
      mining: {
        mempool: {
          order: "fifo",
        },
      },
    },
  },
  gasReporter: {
    enabled: true,
  },
  warnings: {
    "contracts/abstracts/ForestToken.sol": {
      "unused-param": "off",
    },
    "contracts/abstracts/UTXOToken.sol": {
      "unused-param": "off",
    },
  },
};
