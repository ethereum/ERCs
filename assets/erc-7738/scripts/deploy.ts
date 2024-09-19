import dotenv from "dotenv";
const { ethers, upgrades, hre } = require("hardhat");
const { getContractAddress } = require('@ethersproject/address')
dotenv.config();

const placeholderDomainName = "7738"; //domain name to use if chain doesn't have ENS
// ENS registry contract address (same for all networks)
const ensAddress = "0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e";

// Helper script to re-assign ownership of ENS domain to the registry contract
async function main() {
    const privateKey: any = process.env.PRIVATE_KEY_DEPLOY;
    const secondaryKey: any = process.env.PRIVATE_KEY_2DEPLOY;
    const label: any = process.env.ENS_NAME;
    if (!privateKey) {
        throw new Error("PRIVATE_KEY not found in .env file");
    }

    if (!label) {
        throw new Error("ENS_NAME not set in .env");
    }

    const primaryDeployKey = new ethers.Wallet(privateKey, ethers.provider);
    const secondaryDeployKey = new ethers.Wallet(secondaryKey, ethers.provider);
    console.log(`ADDR: ${primaryDeployKey.address}`);
    console.log(`2nd deploy addr: ${secondaryDeployKey.address}`);

    // Interface of the ENS contract
    const ensAbi = [
        "function owner(bytes32 node) external view returns (address)",
        "function setOwner(bytes32 node, address owner) external",
        "function resolver(bytes32 node) external view returns (address)"
    ];

    const ens = new ethers.Contract(ensAddress, ensAbi, secondaryDeployKey);

    let domainName = label;
    let domainNameHash = getName(domainName);

    // Does this chain have ENS?
    let hasENS = false;
    try {
        let resolver = await ens.resolver(domainNameHash);
        console.log(`RESOLVER: ${resolver}`);
        hasENS = true;
    } catch (error) {
        hasENS = false;
        domainName = placeholderDomainName;
        domainNameHash = getName(domainName);
    }

    console.log(`HASENS: ${hasENS}`);

    if (hasENS) {
        console.log(`${domainName}.eth Owner: ${await ens.owner(domainNameHash)}`);
    }

    //calculate post address
    let firstAddr = getContractAddress({
        from: secondaryDeployKey.address,
        nonce: 1
    });

    console.log(`Deploy Addr: ${firstAddr}`);

    const { chainId } = await ethers.provider.getNetwork();

    if (hasENS) {
        console.log(`${domainName}.eth Owner: ${await ens.owner(domainNameHash)}`);
    }

    const ENSSubdomainAssigner = await ethers.getContractFactory("ENSSubdomainAssigner");

    //Deploy
    const ensSubdomainAssigner = await upgrades.deployProxy(ENSSubdomainAssigner.connect(secondaryDeployKey), [ensAddress], { kind: 'uups' });
    await ensSubdomainAssigner.waitForDeployment();
    console.log(`ENS Subdomain: ${ensSubdomainAssigner.target}`);

    await delay(6000);

    const RegistryMetadata = await ethers.getContractFactory("RegistryMetadata");

    //Deploy
    const registryMetadata = await upgrades.deployProxy(RegistryMetadata.connect(secondaryDeployKey), [], { kind: 'uups' });
    await registryMetadata.waitForDeployment();

    await delay(6000);
    
    console.log(`Deploy metadata: ${registryMetadata.target}`);

    const Registry = await ethers.getContractFactory("DecentralisedRegistryNFT", primaryDeployKey);
    // Deploy
    const registry = await upgrades.deployProxy(Registry.connect(primaryDeployKey), ["ERC-7738 Script Registry", "ERC7738", registryMetadata.target, ensSubdomainAssigner.target], { kind: 'uups' });
    await registry.waitForDeployment();

    await delay(6000);

    console.log(`Registry proxy deployed: ${registry.target}`);

    // Post Deploy
    let tx1 = await registryMetadata.connect(secondaryDeployKey).setRegistry(registry.target);
    tx1.wait();

    console.log("wait");
    await delay(6000);

    let tx2 = await ensSubdomainAssigner.connect(secondaryDeployKey).setRegistry(registry.target);
    tx2.wait();
    console.log(`Updated ENS Assigner`);
    
    await delay(6000);
    console.log("wait");

    if (chainId == 1) {
        //mainnet needs a bit longer usually
        console.log(`Mainnnet delay`);
        await delay(12000);
    }

    let txSetBase = await registry.connect(primaryDeployKey).updateENSBase(domainName);
    console.log("wait");
    txSetBase.wait();
    
    await delay(6000);

    if (chainId == 1) {
        //mainnet needs a bit longer usually
        console.log(`Mainnnet delay`);
        await delay(12000);
    }

    console.log(`Resolver: ${(await registry.getENSInfo())}`);

    if (hasENS) {
        console.log(`${domainName}.eth Owner: ${await ens.owner(domainNameHash)}`);
    }

    // what is the deployment address?
    console.log(`Registry         Address: ${registry.target}`);
    console.log(`RegistryMetadata Address: ${registryMetadata.target}`);
    console.log(`ENSSubdomain     Address: ${ensSubdomainAssigner.target}`);
}

function delay(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

function getName(label: string): string {
    const ETH_NODE = "0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae";
    const labelhash = ethers.keccak256(ethers.toUtf8Bytes(label));
    const node = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(
        ["bytes32", "bytes32"],
        [ETH_NODE, labelhash]
    ));
    return node;
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });


    // to run: npx hardhat run .\scripts\deploy.ts --network holesky
    // to verify logic: npx hardhat verify 0x30Af1aea43490e2F03d4d7eF3116b745D7D58c30 --network holesky 
    // to verify full: npx hardhat verify 0x0077380bCDb2717C9640e892B9d5Ee02Bb5e0682 --network holesky "ERC-7738 Script Registry", "ERC7738", 0x97b0341BEdbC521778B669550774691918202e65, 0x527E7E85cF60390b56bE953888e0cb036682761B

    // verify metadata logic: npx hardhat verify 0x276d7760fA6774E3AE8F8a7446B88fb2479D38aC --network mainnet

    // verify ensAssigner logic: npx hardhat verify 0x527E7E85cF60390b56bE953888e0cb036682761B --network mainnet