const { ethers } = require("hardhat");

import { expect } from "chai";
import {
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";

const scriptURI1: string = "https://scripttoken.net/script1";

async function deployInitialFixture() {
  // Contracts are deployed using the first signer/account by default
  const [owner, otherAccount, otherAccount2] = await ethers.getSigners();

<<<<<<< HEAD
  const ExampleNFT = (await ethers.getContractFactory("ExampleNFT")).connect(
    owner
  );
  const exampleNFT = await ExampleNFT.deploy();
  await exampleNFT.waitForDeployment();
=======
  const StakingToken = (await ethers.getContractFactory("StakingToken")).connect(
    owner
  );
  const stakingToken = await StakingToken.deploy();
  await stakingToken.waitForDeployment();
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6

  //Deploy registry contract
  const Registry = (await ethers.getContractFactory("DecentralisedRegistryPermissioned")).connect(
    otherAccount
  );
  const registry = await Registry.deploy();
  await registry.waitForDeployment();

  return {
    owner,
    otherAccount,
    otherAccount2,
<<<<<<< HEAD
    exampleNFT,
=======
    stakingToken,
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
    registry,
  };
}

describe("Decentralised Permissioned Registry", function () {

  it("mint and set scriptURI with owner", async function () {
    const {
      owner,
      otherAccount,
      otherAccount2,
<<<<<<< HEAD
      exampleNFT,
      registry
    } = await loadFixture(deployInitialFixture);

    await expect(exampleNFT.connect(owner).safeMint())
      .to.emit(exampleNFT, "Transfer")
      .withArgs(ethers.ZeroAddress, owner.address, 1);

    //initially register with otherAccount
    await registry.connect(otherAccount).registerOwner(exampleNFT.target);

    //owner can override
    await registry.connect(owner).registerOwner(exampleNFT.target);

    await expect(registry.connect(otherAccount).registerOwner(exampleNFT.target))
=======
      stakingToken,
      registry
    } = await loadFixture(deployInitialFixture);

    await expect(stakingToken.connect(owner).safeMint())
      .to.emit(stakingToken, "Transfer")
      .withArgs(ethers.ZeroAddress, owner.address, 1);

    //initially register with otherAccount
    await registry.connect(otherAccount).registerOwner(stakingToken.target);

    //owner can override
    await registry.connect(owner).registerOwner(stakingToken.target);

    await expect(registry.connect(otherAccount).registerOwner(stakingToken.target))
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
      .to.revertedWith("Not authorized");

    const scriptURI = [scriptURI1];

    //set scriptURI
<<<<<<< HEAD
    await expect(registry.connect(otherAccount).setScriptURI(exampleNFT.target, scriptURI))
      .to.revertedWith("Not authorized");
    await expect(registry.connect(otherAccount2).setScriptURI(exampleNFT.target, scriptURI))
      .to.revertedWith("Not authorized");

    await registry.connect(owner).setScriptURI(exampleNFT.target, scriptURI);

    expect((await registry.scriptURI(exampleNFT.target)).toString()).to.be.equal(scriptURI.toString());

    //add delegate
    await expect(registry.connect(otherAccount).addDelegateSigner(exampleNFT.target, otherAccount2))
      .to.revertedWith("Contract Owner only");

    await registry.connect(owner).addDelegateSigner(exampleNFT.target, otherAccount2);

    //attempt to set Script URI with delegate account
    await registry.connect(otherAccount2).setScriptURI(exampleNFT.target, scriptURI);
=======
    await expect(registry.connect(otherAccount).setScriptURI(stakingToken.target, scriptURI))
      .to.revertedWith("Not authorized");
    await expect(registry.connect(otherAccount2).setScriptURI(stakingToken.target, scriptURI))
      .to.revertedWith("Not authorized");

    await registry.connect(owner).setScriptURI(stakingToken.target, scriptURI);

    expect((await registry.scriptURI(stakingToken.target)).toString()).to.be.equal(scriptURI.toString());

    //add delegate
    await expect(registry.connect(otherAccount).addDelegateSigner(stakingToken.target, otherAccount2))
      .to.revertedWith("Contract Owner only");

    await registry.connect(owner).addDelegateSigner(stakingToken.target, otherAccount2);

    //attempt to set Script URI with delegate account
    await registry.connect(otherAccount2).setScriptURI(stakingToken.target, scriptURI);
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6

    // Verify script signing operation.
    // Assume that a process has come back from evaluating the address of a TokenScript and needs to verify if the
    // key is allowed to validate the contract
    let ecRecoverSigningKey = otherAccount2.address;

<<<<<<< HEAD
    expect((await registry.isDelegateOrOwner(exampleNFT.target, otherAccount.address)))
      .to.be.equal(false);

    expect((await registry.isDelegateOrOwner(exampleNFT.target, ecRecoverSigningKey)))
      .to.be.equal(true);
    
    expect((await registry.isDelegateOrOwner(exampleNFT.target, owner.address)))
      .to.be.equal(true);  

    // revoke
    await expect(registry.connect(otherAccount2).revokeDelegateSigner(exampleNFT.target, otherAccount2))
      .to.revertedWith("Contract Owner only");

    await registry.connect(owner).revokeDelegateSigner(exampleNFT.target, otherAccount2);

    await expect(registry.connect(otherAccount2).setScriptURI(exampleNFT.target, scriptURI))
      .to.revertedWith("Not authorized");

    expect((await registry.isDelegateOrOwner(exampleNFT.target, ecRecoverSigningKey)))
      .to.be.equal(false);

    expect((await registry.isDelegateOrOwner(exampleNFT.target, owner.address)))
=======
    expect((await registry.isDelegateOrOwner(stakingToken.target, otherAccount.address)))
      .to.be.equal(false);

    expect((await registry.isDelegateOrOwner(stakingToken.target, ecRecoverSigningKey)))
      .to.be.equal(true);
    
    expect((await registry.isDelegateOrOwner(stakingToken.target, owner.address)))
      .to.be.equal(true);  

    // revoke
    await expect(registry.connect(otherAccount2).revokeDelegateSigner(stakingToken.target, otherAccount2))
      .to.revertedWith("Contract Owner only");

    await registry.connect(owner).revokeDelegateSigner(stakingToken.target, otherAccount2);

    await expect(registry.connect(otherAccount2).setScriptURI(stakingToken.target, scriptURI))
      .to.revertedWith("Not authorized");

    expect((await registry.isDelegateOrOwner(stakingToken.target, ecRecoverSigningKey)))
      .to.be.equal(false);

    expect((await registry.isDelegateOrOwner(stakingToken.target, owner.address)))
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
      .to.be.equal(true);  
  });

})