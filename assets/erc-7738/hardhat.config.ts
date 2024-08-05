import "dotenv/config"
import { HardhatUserConfig } from "hardhat/config"
import "@nomicfoundation/hardhat-toolbox"
import "hardhat-gas-reporter"

let { PRIVATE_KEY, INFURA_KEY, ETHERSCAN_API_KEY } = process.env;

const config: HardhatUserConfig = {
  solidity: { compilers: [{ version: "0.8.24" }, { version: "0.8.24" }] },
  networks: {
    mainnet: {
      url: `https://mainnet.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`],
    },
    mumbai: {
      url: `https://polygon-mumbai.infura.io/v3/${INFURA_KEY}`,
      accounts: [`${PRIVATE_KEY}`]
    },
    hardhat: {
      gasPrice: 100000000000,
    }
  },
  etherscan: {
    apiKey: `${ETHERSCAN_API_KEY}` //for contract verify
  }
}

export default config
