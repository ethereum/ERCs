require("@nomicfoundation/hardhat-toolbox")
require("@nomicfoundation/hardhat-ignition-ethers")

module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      evmVersion: "paris",
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  mocha: {
    bail: true,
    slow: 200,
    timeout: 30 * 1000,
  },
  networks: {
    hardhat: {
      tags: ["local"],
      allowBlocksWithSameTimestamp: true,
    },
    localhost: {
      tags: ["local"],
    },
  },
}
