import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer, owner } = await getNamedAccounts();

  await deploy("Drainer", {
    from: deployer,
    args: [],
    skipIfAlreadyDeployed: true,
  });
};

export default func;
func.dependencies = ["layer_proxy"];
func.tags = ["poc", "drainer"];
