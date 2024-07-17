import { task } from "hardhat/config";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "solidity-docgen";

export default {
  docgen: {
    outputDir: "./docs/contracts",
    pages: "single",
    sourcesDir: "./src",
    pageExtension: ".md",
  },
  namedAccounts: {
    deployer: {
      default: "0xF52E5dF676f51E410c456CC34360cA6F27959420", // this must be set for networks
    },
  },
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      accounts: {
        mnemonic: "casual vacant letter raw trend tool vacant opera buzz jaguar bridge myself",
      }, // ONLY LOCAL
    },
  },
  paths: {
    sources: "./src",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200000,
          },
        },
      },
    ],
  },
  typechain: {
    outDir: "types",
    target: "ethers-v5",
    alwaysGenerateOverloads: true, // should overloads with full signatures like deposit(uint256) be generated always, even if there are no overloads?
  },
  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    format: "json",
    spacing: 2,
    pretty: false,
  },
};
