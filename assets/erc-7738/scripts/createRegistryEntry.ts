import dotenv from "dotenv";
const { ethers, upgrades } = require("hardhat");
const { getImplementationAddress } = require('@openzeppelin/upgrades-core');
const { getContractAddress } = require('@ethersproject/address')
dotenv.config();

const deployedRegistry = "0x0077380bCDb2717C9640e892B9d5Ee02Bb5e0682";

const myNFTContract = ""; // Your NFT contract address here
const myTokenScriptURI = ""; // Your TokenScript URI here, in IPFS format (ipfs://Qm....) or http (eg https://mystorage.com/mytoken1.tsml)

// Helper script to re-assign ownership of ENS domain to the registry contract
async function main() {
    const privateKey: any = process.env.PRIVATE_KEY;
    if (!privateKey) {
        throw new Error("PRIVATE_KEY not found in .env file");
    }

    const primaryDeployKey = new ethers.Wallet(privateKey, ethers.provider);
    console.log(`ADDR: ${primaryDeployKey.address}`);

    const Registry = await ethers.getContractFactory("DecentralisedRegistryNFT", primaryDeployKey);
    let registry = Registry.attach(deployedRegistry);

    // now write to contract
    await registry.connect(primaryDeployKey).setScriptURI(myNFTContract, [myTokenScriptURI]);

    // read script
    let scriptURIArray = await registry.scriptURI(myNFTContract);

    // assume we wrote the first script, our entry will be the first one. If there were previous scripts we need to adjust the array marker
    console.log(`Read scriptURI: ${scriptURIArray[0]}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });


 // to run: npx hardhat run .\scripts\createRegistryEntry.ts --network holesky