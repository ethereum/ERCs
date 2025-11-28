const { ethers, upgrades } = require("hardhat");
import { HardhatUserConfig } from "hardhat/config";
const { getImplementationAddress } = require('@openzeppelin/upgrades-core');
const { getContractAddress } = require('@ethersproject/address')
import dotenv from "dotenv";
dotenv.config();

import { expect } from "chai";
import {
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";

const config: HardhatUserConfig = {
  solidity: "0.7.0",
};

export default config;

const scriptURI1: string = "https://scripttoken.net/script1";
const scriptURI2: string = "https://scripttoken.net/script2";
const scriptURI3: string = "https://scripttoken.net/script3";
const scriptURI4: string = "https://scripttoken.net/script4";
const origScriptURI: string = "https://scripttoken.net/script";

const domainName = "erc7738";

async function deployInitialFixture() {
  // Contracts are deployed using the first signer/account by default
  const [owner, nftOwner, otherAccount2, otherAccount3, otherAccount4, regOwner] = await ethers.getSigners();

  let primaryDeploy;
  let secondaryDeploy;

  const privateKey: any = process.env.PRIVATE_KEY_DEPLOY;
  const secondaryKey: any = process.env.PRIVATE_KEY_2DEPLOY;
  if (!privateKey) {
    primaryDeploy = regOwner;
  } else {
    primaryDeploy = new ethers.Wallet(privateKey, ethers.provider);
  }

  if (!secondaryKey) {
    secondaryDeploy = owner;
  } else {
    secondaryDeploy = new ethers.Wallet(secondaryKey, ethers.provider);
  }

  // Define amounts to send (for example: 1 ether)
  const amountToSend = ethers.parseEther("1.0");

  // Send transaction to primary deploy key
  const tx1 = await owner.sendTransaction({
    to: primaryDeploy.address,
    value: amountToSend
  });
  await tx1.wait(); // Wait for the transaction to be mined

  // Send transaction to secondary deploy key
  const tx2 = await owner.sendTransaction({
    to: secondaryDeploy.address,
    value: amountToSend
  });
  await tx2.wait(); // Wait for the transaction to be mined

  const ExampleNFT = (await ethers.getContractFactory("ExampleNFT")).connect(
    nftOwner
  );
  const stakingToken = await ExampleNFT.deploy();
  await stakingToken.waitForDeployment();

  //deploy Fake ENS & resolver for testing
  const ENS = (await ethers.getContractFactory("ENSRegistry")).connect(
    nftOwner
  );
  const ens = await ENS.deploy();
  await ens.waitForDeployment();

  const Resolver = (await ethers.getContractFactory("PublicResolver")).connect(
    nftOwner
  );
  const resolver = await Resolver.deploy(ens.target);
  await resolver.waitForDeployment();

  console.log(`ENS: ${ens.target}`);
  console.log(`Resolver: ${resolver.target}`);

  const registryDeploymentAddress = getContractAddress({
    from: regOwner.address,
    nonce: 1
  })

  const ENSSubdomainAssigner = await ethers.getContractFactory("ENSSubdomainAssigner");
  const ensSubdomainAssigner = await upgrades.deployProxy(ENSSubdomainAssigner.connect(secondaryDeploy), [ens.target], { kind: 'uups' });
  await ensSubdomainAssigner.waitForDeployment();

  const RegistryMetadata = await ethers.getContractFactory("RegistryMetadata");
  const registryMetadata = await upgrades.deployProxy(RegistryMetadata.connect(secondaryDeploy), [], { kind: 'uups' });
  await registryMetadata.waitForDeployment();

  //use tools to generate nameHash
  let domainNameHash = await ensSubdomainAssigner.getName(domainName);
  await ens.connect(nftOwner).setRecord(domainNameHash, nftOwner.address, resolver.target, 0);

  //Deploy registry contract
  const Registry = await ethers.getContractFactory("DecentralisedRegistryNFT");
  const registry = await upgrades.deployProxy(Registry.connect(primaryDeploy), ["ERC-7738 Script Registry", "ERC7738", registryMetadata.target, ensSubdomainAssigner.target], { kind: 'uups' });
  await registry.waitForDeployment();

  await registryMetadata.connect(secondaryDeploy).setRegistry(registry.target);
  await ensSubdomainAssigner.connect(secondaryDeploy).setRegistry(registry.target);
  await registry.updateENSBase(domainName);

  // what is the deployment address?
  console.log(`Registry Address: ${registry.target}`);
  console.log(`RegistryMetadata Address: ${registryMetadata.target}`);
  console.log(`ENS Subdomain Assigner: ${ensSubdomainAssigner.target}`);

  //now call init on the logic contract
  const currentProxyLogicAddress = await getImplementationAddress(primaryDeploy.provider, registry.target);
  console.log("[LOGIC CONTRACTS] --> logic address for 7738 NFT: " + currentProxyLogicAddress);
  let logic7738NFT = Registry.attach(currentProxyLogicAddress);
  await logic7738NFT.connect(primaryDeploy).initialize("", "", registryMetadata.target, ensSubdomainAssigner.target);
  console.log("[LOGIC CONTRACTS] --> initialize logic for 7738");

  //change owner to the registry contract
  await ens.connect(nftOwner).setOwner(domainNameHash, ensSubdomainAssigner.target);

  console.log(`ENS Subdomain Manager: ${ensSubdomainAssigner.target}`);

  console.log(`Owner of domain: ${await ensSubdomainAssigner.getOwner(domainName)}`);

  console.log(`Resolver: ${(await registry.getENSInfo()).resolver}`);
  
  return {
    owner,
    regOwner,
    nftOwner,
    otherAccount2,
    otherAccount3,
    otherAccount4,
    stakingToken,
    registry,
    resolver,
    ens,
    ensSubdomainAssigner,
    primaryDeploy,
    secondaryDeploy
  };
}

describe("DecentralisedRegistryNFT", function () {

  it("mint and set scriptURI with owner", async function () {
    const {
      owner,
      regOwner,
      nftOwner,
      otherAccount2,
      otherAccount3,
      otherAccount4,
      stakingToken,
      registry,
      resolver,
      ens
    } = await loadFixture(deployInitialFixture);

    await expect(stakingToken.connect(nftOwner).safeMint())
      .to.emit(stakingToken, "Transfer")
      .withArgs(ethers.ZeroAddress, nftOwner.address, 1);

    const scriptURI = [scriptURI1];
    const scriptURITest2 = [scriptURI2];
    const scriptURITest3 = [scriptURI3, scriptURI4];
    const origScript = [origScriptURI];

    //set scriptURI
    await registry.connect(otherAccount2).setScriptURI(stakingToken.target, scriptURI);

    //check we got issued NFT #1
    expect((await registry.balanceOf(otherAccount2))).to.be.equal(1);
    let currentBalance = await registry.connect(otherAccount2).balanceOf(otherAccount2);
    expect(currentBalance).to.equal(1);
    //console.log(`Current Balance: ${currentBalance}`);

    checkScriptReturn(scriptURI, registry, stakingToken);

    await registry.connect(otherAccount4).setScriptURI(stakingToken.target, scriptURITest2);

    //now dump the current full scriptURI

    await registry.connect(otherAccount3).setScriptURI(stakingToken.target, scriptURITest3);

    //original owner sets scriptURI

    //now owner writes, should come first
    await registry.connect(nftOwner).setScriptURI(stakingToken.target, origScript);

    let finalScriptURI = await registry.scriptURI(stakingToken.target);

    //test first element
    let firstScriptURI = finalScriptURI[0];

    //ensure owner script is first in list
    expect(firstScriptURI).to.equal(origScriptURI);

    //add another entry
    await registry.connect(otherAccount4).setScriptURI(stakingToken.target, [scriptURI4, scriptURI1, scriptURI2]);

    //owner script should still be first
    finalScriptURI = await registry.scriptURI(stakingToken.target);
    firstScriptURI = finalScriptURI[0];
    expect(firstScriptURI).to.equal(origScriptURI);

    //attempt to write zero sized scriptURI
    await expect(registry.connect(otherAccount4).setScriptURI(stakingToken.target, []))
      .to.be.revertedWithCustomError(registry, "EmptyScriptURI");

    let correctFinal = [origScriptURI, scriptURI1, scriptURI2, scriptURI3, scriptURI4, scriptURI4, scriptURI1, scriptURI2];

    //check order
    checkScriptReturn(correctFinal, registry, stakingToken);

    //remove an entry using NFT
    await registry.connect(otherAccount2).updateScriptURI(1, "");

    checkScriptReturn([origScriptURI, scriptURI2, scriptURI3, scriptURI4, scriptURI4, scriptURI1, scriptURI2], registry, stakingToken);

    //now change an entry using NFT
    await registry.connect(otherAccount4).updateScriptURI(2, scriptURI4);

    checkScriptReturn([origScriptURI, scriptURI4, scriptURI3, scriptURI4, scriptURI4, scriptURI1, scriptURI2], registry, stakingToken);

    //insert and change back
    await registry.connect(otherAccount2).updateScriptURI(1, scriptURI1);
    await registry.connect(otherAccount4).updateScriptURI(2, scriptURI2);

    //attempt to update non-owned entry
    await expect(registry.connect(otherAccount4).updateScriptURI(1, ""))
      .to.be.revertedWithCustomError(registry, "ScriptOwnerOnly");

    //check order is back to original
    checkScriptReturn(correctFinal, registry, stakingToken);

    checkPageSize(2, correctFinal, registry, stakingToken);
    checkPageSize(3, correctFinal, registry, stakingToken);
    checkPageSize(1, correctFinal, registry, stakingToken);
    checkPageSize(500, correctFinal, registry, stakingToken);

    //now check metadata
    let metaData = await registry.tokenURI(5);
    //console.log(`MEta: ${metaData}`);

    //check order, contract and value
    let metaDataJSON = JSON.parse(metaData);
    let contractAddress = getAttributeValue(metaDataJSON.attributes, 'Contract');
    let order = getAttributeValue(metaDataJSON.attributes, 'Order');
    let attrScriptURI = getAttributeValue(metaDataJSON.attributes, 'scriptURI');

    expect(contractAddress.toLowerCase()).to.equal(stakingToken.target.toLowerCase());
    expect(order).to.equal("1");
    expect(attrScriptURI).to.equal(origScriptURI);

    //try another metadata
    metaData = await registry.tokenURI(4);
    metaDataJSON = JSON.parse(metaData);
    contractAddress = getAttributeValue(metaDataJSON.attributes, 'Contract');
    order = getAttributeValue(metaDataJSON.attributes, 'Order');
    attrScriptURI = getAttributeValue(metaDataJSON.attributes, 'scriptURI');

    //console.log(`${contractAddress}, ${order}, ${attrScriptURI}`);

    expect(contractAddress.toLowerCase()).to.equal(stakingToken.target.toLowerCase());
    expect(order).to.equal("5");
    expect(attrScriptURI).to.equal(scriptURI4);

    //console.log(`Bal: ${await stakingToken.balanceOf(owner)}`);

    expect(await stakingToken.balanceOf(nftOwner)).to.equal(2);
    // now move an NFT to the contract and attempt to move it back
    await stakingToken.connect(nftOwner).transferFrom(nftOwner.address, registry.target, 1);
    expect(await stakingToken.balanceOf(nftOwner)).to.equal(1);
    expect(await stakingToken.balanceOf(registry.target)).to.equal(1);

    // now transfer out of contract
    // await registry.connect(owner).transferOut(stakingToken.target, 1);
    expect(await stakingToken.balanceOf(registry.target)).to.equal(1);

    //set the name
    let tokenName = "jackstraws";
    let iconURI = "https://storage.com/icon"
    await registry.connect(nftOwner).setName(5, tokenName);
    await registry.connect(nftOwner).setIconURI(5, iconURI);

    // check name resolution
    // pull the ENS name
    metaData = await registry.tokenURI(5);
    
    metaDataJSON = JSON.parse(metaData);
    let thisNameENS = getAttributeValue(metaDataJSON.attributes, 'ENS');
    console.log(`${thisNameENS}`);

    let nameHash = ethers.namehash(thisNameENS);
    console.log(`Resolve addr/owner: ${await resolver.addr(nameHash)} ${await ens.owner(nameHash)}`);

    //check domain ownerships
    expect((await resolver.addr(nameHash))).to.be.equal(nftOwner.address);

    console.log(`Resolve addr/owner: ${await resolver.addr(nameHash)} ${await ens.owner(nameHash)}`);

    //attempt to change resolve address from nftOwner
    await expect(resolver.connect(nftOwner).setAddr(nameHash, nftOwner.address))
      .to.be.revertedWith("Must be owner");
      //.to.be.revertedWithCustomError(registry, "ScriptOwnerOnly");

    //console.log(`Owner NFT: ${await registry.ownerOf(5)}`);

    // Now test swapping ownership
    await registry.connect(nftOwner).transferFrom(nftOwner.address, otherAccount2.address, 5);

    //ensure that token resolves to new owner
    expect((await resolver.addr(nameHash))).to.be.equal(otherAccount2.address);

    //check authenticated
    expect((await registry.scriptDataElement(5)).isAuthenticated).to.equal(true);

    //expect(await registry.isAuthenticated(stakingToken.target, 1)).to.equal(true);

    //check list dump
    let tokenDetails = await registry.scriptData(stakingToken.target);

    //check some details
    expect(tokenDetails[0].name).to.equal(tokenName);
    expect(tokenDetails[0].iconURI).to.equal(iconURI);
    expect(tokenDetails[0].isAuthenticated).to.equal(true);
    expect(tokenDetails[1].name).to.equal("2");
    expect(tokenDetails[1].isAuthenticated).to.equal(false);
    expect(tokenDetails[0].scriptURI).to.equal(origScriptURI);
  });

  function getAttributeValue(attributes: any[], traitType: string): string {
    const attribute = attributes.find(attr => attr.trait_type === traitType);
    return attribute ? attribute.value : '';
  }

  async function checkScriptReturn(correctFinal: string[], registry: any, stakingToken: any) {
    let returnedScriptURI = (await registry.scriptURI(stakingToken.target)).toString();
    if (returnedScriptURI.endsWith(',')) {
      returnedScriptURI = returnedScriptURI.slice(0, -1);
    }
    expect(returnedScriptURI).to.be.equal(correctFinal.toString());
  }

  async function calculateContractAddress(walletAddress: string, nonce: number) {
    // Convert the deployer's address to a bytes format
    //const deployerAddressBytes = ethers.getAddress(deployerAddress);
  
    // RLP encode the deployer's address and the nonce (1 for the second contract)
    // nonce
    const rlpEncoded = ethers.RLP.encode([walletAddress, "0x01"]);
  
    // Hash the RLP encoded value using keccak256
    const contractAddressHash = ethers.keccak256(rlpEncoded);
  
    // Get the last 20 bytes of the hash to obtain the contract address
    const contractAddress = ethers.getAddress("0x" + contractAddressHash.slice(-40));
  
    console.log(`The second contract address will be: ${contractAddress}`);
  }

  async function checkPageSize(pageSize: number, correctFinal: string[], registry: any, stakingToken: any) {
      const totalPages = Math.ceil(correctFinal.length / pageSize);
  
      for (let page = 1; page <= totalPages; page++) {
          let start = (page - 1) * pageSize;
          let expected = [];
          
          for (let j = 0; j < pageSize; j++) {
              if (start + j < correctFinal.length) {
                  expected[j] = correctFinal[start + j];
              } else {
                  break;
              }
          }
  
          let contractReturn = await registry.scriptURI(stakingToken.target, page, pageSize);
          //console.log(`Actual return = ${contractReturn} Expected = ${expected}`);
          expect(contractReturn.toString()).to.be.equal(expected.toString());
      }
  }

})