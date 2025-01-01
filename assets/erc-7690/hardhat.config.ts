import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.25",
    settings:{
      evmVersion: "cancun"
    }
  },
  
};

export default config;
