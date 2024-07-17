import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer } = await getNamedAccounts();

  const salt = "0x220a70730c743a005cfd55180805d2c0d5b8c7695c5496100dcffa91c02befce";

  const result = await deploy("CodeIndex", {
    deterministicDeployment: salt,
    from: deployer,
    skipIfAlreadyDeployed: true,
  });

  console.log("CodeIndex deployed at", result.address);
  if (result.bytecode) {
    const codeHash = ethers.utils.keccak256(result.bytecode);
    console.log(`CodeHash: ${codeHash}`);
  }
};

export default func;
func.tags = ["code_index"];
