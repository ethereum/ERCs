import "dotenv/config"
import { HardhatUserConfig } from "hardhat/config"
import "@nomicfoundation/hardhat-toolbox"
import "hardhat-gas-reporter"

<<<<<<< HEAD
require('@openzeppelin/hardhat-upgrades');

let { PRIVATE_KEY, INFURA_KEY, ETHERSCAN_API_KEY, PRIVATE_KEY2, POLYGONSCAN_API_KEY, BASESCAN_API_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: { compilers: [{ version: "0.8.24" }, { version: "0.8.24" }], settings: { optimizer: { enabled: true, runs: 400} }},
=======
let { PRIVATE_KEY, INFURA_KEY, ETHERSCAN_API_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: { compilers: [{ version: "0.8.24" }, { version: "0.8.24" }] },
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
  networks: {
    mainnet: {
      url: `https://mainnet.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`],
    },
<<<<<<< HEAD
    holesky: {
      url: `https://ethereum-holesky-rpc.publicnode.com`,
      accounts: [`${PRIVATE_KEY}`],
    },
    basesepolia: {
      url: `https://base-sepolia.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    },
    klaytnbaobab : {
      url: `https://klaytn-baobab.blockpi.network/v1/rpc/public`,
      accounts: [`${PRIVATE_KEY}`]
    },
    klaytn : {
      url: `https://public-en.node.kaia.io`,
      accounts: [`${PRIVATE_KEY}`]
    },
    amoy: {
      url: `https://polygon-amoy.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    },
    base: {
      url: `https://base-mainnet.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    }, 
    polygon: {
      url: `https://polygon-mainnet.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    },
    mantlesepolia: {
      url: `https://rpc.sepolia.mantle.xyz`,
      accounts: [`${PRIVATE_KEY}`]
    },
    mantle: {
      url: `https://rpc.mantle.xyz`,
      accounts: [`${PRIVATE_KEY}`]
    },
    arbitrum: {
      url: `https://arbitrum-mainnet.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    },
    arbitrumsepolia: {
      url: `https://arbitrum-sepolia.infura.io/v3/${INFURA_KEY}`,
=======
    mumbai: {
      url: `https://polygon-mumbai.infura.io/v3/${INFURA_KEY}`,
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
      accounts: [`${PRIVATE_KEY}`]
    },
    hardhat: {
      gasPrice: 100000000000,
<<<<<<< HEAD
      allowUnlimitedContractSize: true,
    }
  },
  etherscan: {
    //apiKey: `${ETHERSCAN_API_KEY}` //for contract verify https://holesky.infura.io/v3/${INFURA_KEY}
    //apiKey: `${POLYGONSCAN_API_KEY}` //for verifying on Polygonscan powered chains
    apiKey: `${BASESCAN_API_KEY}`
=======
    }
  },
  etherscan: {
    apiKey: `${ETHERSCAN_API_KEY}` //for contract verify
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
  }
}

export default config
