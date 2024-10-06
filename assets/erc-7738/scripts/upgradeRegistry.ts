import dotenv from "dotenv";
const { ethers, upgrades } = require("hardhat");
const { getImplementationAddress } = require('@openzeppelin/upgrades-core');
const { getContractAddress } = require('@ethersproject/address')
dotenv.config();

// ENS registry contract address (same for all networks)
const ensAddress = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e";

const deployedENSHelper = "0x527E7E85cF60390b56bE953888e0cb036682761B"; // Replace with where your ENSAssigner Proxy is deployed
const deployedMetadata = "0x276d7760fA6774E3AE8F8a7446B88fb2479D38aC";

const deployedRegistryLogic = "0x30af1aea43490e2f03d4d7ef3116b745d7d58c30";
const deployedRegistry = "0x0077380bCDb2717C9640e892B9d5Ee02Bb5e0682";

// Helper script to re-assign ownership of ENS domain to the registry contract
async function main() {
    const privateKey: any = process.env.PRIVATE_KEY_DEPLOY;
    const secondaryKey: any = process.env.PRIVATE_KEY_2DEPLOY;
    if (!privateKey) {
        throw new Error("PRIVATE_KEY not found in .env file");
    }

    const primaryDeployKey = new ethers.Wallet(privateKey, ethers.provider);
    const secondaryDeployKey = new ethers.Wallet(secondaryKey, ethers.provider);
    console.log(`ADDR: ${primaryDeployKey.address}`);
    console.log(`2nd deploy addr: ${secondaryDeployKey.address}`);

    const Registry = await ethers.getContractFactory("DecentralisedRegistryNFT", primaryDeployKey);

    // Upgrade
    const registry = await upgrades.upgradeProxy(deployedRegistry, Registry);
    await registry.waitForDeployment();
    
    console.log(`Registry upgraded: ${registry.target}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });


 // to run: npx hardhat run .\scripts\updateRegistry.ts --network holesky