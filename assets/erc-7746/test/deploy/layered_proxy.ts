import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { MockERC20, RateLimitLayer } from "../types";
import { ethers } from "hardhat";
import { LibAccessLayers } from "../types/src/MockERC20";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;

  const { deployer, owner } = await getNamedAccounts();

  const simpleLayer = await deployments.get("RateLimitLayer");
  const simpleLayerContract = (await ethers.getContractAt(simpleLayer.abi, simpleLayer.address)) as RateLimitLayer;

  let layer: LibAccessLayers.LayerStructStruct = {
    layerAddess: simpleLayer.address,
    beforeSig: simpleLayerContract.interface.getSighash(simpleLayerContract.interface.functions["beforeCallValidation(bytes,bytes4,address,uint256,bytes)"]),
    afterSig: simpleLayerContract.interface.getSighash(
      simpleLayerContract.interface.functions["afterCallValidation(bytes,bytes4,address,uint256,bytes,bytes)"]
    ),
    layerConfigData: ethers.utils.defaultAbiCoder.encode(["uint256"], [10]),
  };

  const result = await deploy("MockERC20", {
    from: deployer,
    args: [],
    skipIfAlreadyDeployed: true,
  });

  const lp = await deploy("MockERC20", {
    from: deployer,
    args: [owner, [layer], result.address],
    skipIfAlreadyDeployed: true,
  });
};

export default func;
func.dependencies = ["simple_layer"];
func.tags = ["poc", "layer_proxy"];
