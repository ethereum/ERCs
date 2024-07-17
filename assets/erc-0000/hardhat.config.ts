import { task } from "hardhat/config";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-abi-exporter";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "solidity-docgen";
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

export default {
  docgen: {
    outputDir: "./docs/contracts",
    pages: "single",
    sourcesDir: "./src",
    pageExtension: ".md",
    exclude: ["mocks", "initializers", "vendor", "modifiers", "fixtures"],
  },
  namedAccounts: {
    deployer: {
      default: "0xF52E5dF676f51E410c456CC34360cA6F27959420", //TODO this must be set for networks
    },
    owner: {
      default: "0x520E00225C4a43B6c55474Db44a4a44199b4c3eE",
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
    // externalArtifacts: ["externalArtifacts/*.json"], // optional array of glob patterns with external artifacts to process (for example external libs from node_modules)
  },
  abiExporter: {
    path: "./abi",
    runOnCompile: true,
    clear: true,
    format: "json",
    // flat: true,
    // only: [":ERC20$"],
    spacing: 2,
    pretty: false,
  },
};
