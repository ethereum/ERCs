const { ethers } = require("hardhat");

import { expect } from "chai";
import {
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";

const scriptURI1: string = "https://scripttoken.net/script1";
const scriptURI2: string = "https://scripttoken.net/script2";
const scriptURI3: string = "https://scripttoken.net/script3";
const scriptURI4: string = "https://scripttoken.net/script4";
const origScriptURI: string = "https://scripttoken.net/script";

async function deployInitialFixture() {
  // Contracts are deployed using the first signer/account by default
  const [owner, otherAccount, otherAccount2, otherAccount3, otherAccount4] = await ethers.getSigners();

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
  const Registry = (await ethers.getContractFactory("DecentralisedRegistry")).connect(
    otherAccount
  );
  const registry = await Registry.deploy();
  await registry.waitForDeployment();

  return {
    owner,
    otherAccount,
    otherAccount2,
    otherAccount3,
    otherAccount4,
<<<<<<< HEAD
    exampleNFT,
=======
    stakingToken,
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
    registry,
  };
}

describe("DecentralisedRegistry", function () {

  it("mint and set scriptURI with owner", async function () {
    const {
      owner,
      otherAccount,
      otherAccount2,
      otherAccount3,
      otherAccount4,
<<<<<<< HEAD
      exampleNFT,
      registry
    } = await loadFixture(deployInitialFixture);

    await expect(exampleNFT.connect(owner).safeMint())
      .to.emit(exampleNFT, "Transfer")
=======
      stakingToken,
      registry
    } = await loadFixture(deployInitialFixture);

    await expect(stakingToken.connect(owner).safeMint())
      .to.emit(stakingToken, "Transfer")
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
      .withArgs(ethers.ZeroAddress, owner.address, 1);

    const scriptURI = [scriptURI1];
    const scriptURITest2 = [scriptURI2];
    const scriptURITest3 = [scriptURI3, scriptURI4];
    const origScript = [origScriptURI];

    //set scriptURI
<<<<<<< HEAD
    await registry.connect(otherAccount2).setScriptURI(exampleNFT.target, scriptURI);

    //console.log(`Current ScriptURI = ${await registry.scriptURI(exampleNFT.target)}`);

    expect((await registry.scriptURI(exampleNFT.target)).toString()).to.be.equal(scriptURI.toString());

    //attempt to set Script URI with delegate account
    await registry.connect(otherAccount).setScriptURI(exampleNFT.target, scriptURITest2);

    //now dump the current full scriptURI
    //console.log(`Current ScriptURI = ${await registry.scriptURI(exampleNFT.target)}`);

    await registry.connect(otherAccount3).setScriptURI(exampleNFT.target, scriptURITest3);

    //console.log(`Current ScriptURI = ${await registry.scriptURI(exampleNFT.target)}`);

    //now owner writes, should come first
    await registry.connect(owner).setScriptURI(exampleNFT.target, origScript);

    let finalScriptURI = await registry.scriptURI(exampleNFT.target);
=======
    await registry.connect(otherAccount2).setScriptURI(stakingToken.target, scriptURI);

    //console.log(`Current ScriptURI = ${await registry.scriptURI(stakingToken.target)}`);

    expect((await registry.scriptURI(stakingToken.target)).toString()).to.be.equal(scriptURI.toString());

    //attempt to set Script URI with delegate account
    await registry.connect(otherAccount).setScriptURI(stakingToken.target, scriptURITest2);

    //now dump the current full scriptURI
    //console.log(`Current ScriptURI = ${await registry.scriptURI(stakingToken.target)}`);

    await registry.connect(otherAccount3).setScriptURI(stakingToken.target, scriptURITest3);

    //console.log(`Current ScriptURI = ${await registry.scriptURI(stakingToken.target)}`);

    //now owner writes, should come first
    await registry.connect(owner).setScriptURI(stakingToken.target, origScript);

    let finalScriptURI = await registry.scriptURI(stakingToken.target);
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6

    //console.log(`Current ScriptURI = ${finalScriptURI}`);

    //test first element
    let firstScriptURI = finalScriptURI[0];

    //ensure owner script is first in list
    expect(firstScriptURI).to.equal(origScriptURI);

    //add another entry
<<<<<<< HEAD
    await registry.connect(otherAccount4).setScriptURI(exampleNFT.target, [scriptURI4, scriptURI1, scriptURI2]);

    //owner script should still be first
    finalScriptURI = await registry.scriptURI(exampleNFT.target);
=======
    await registry.connect(otherAccount4).setScriptURI(stakingToken.target, [scriptURI4, scriptURI1, scriptURI2]);

    //owner script should still be first
    finalScriptURI = await registry.scriptURI(stakingToken.target);
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
    firstScriptURI = finalScriptURI[0];
    expect(firstScriptURI).to.equal(origScriptURI);

    //attempt to write zero sized scriptURI
<<<<<<< HEAD
    await expect(registry.connect(otherAccount4).setScriptURI(exampleNFT.target, []))
      .to.revertedWith("> 0 entries required in scriptURIList");

    //remove an entry
    await registry.connect(otherAccount4).setScriptURI(exampleNFT.target, [""]);
    //console.log(`Current ScriptURI = ${await registry.scriptURI(exampleNFT.target)}`);

    //and another
    await registry.connect(otherAccount3).setScriptURI(exampleNFT.target, [""]);
    //console.log(`Current ScriptURI = ${await registry.scriptURI(exampleNFT.target)}`);

    //now add back
    await registry.connect(otherAccount3).setScriptURI(exampleNFT.target, [scriptURI4, scriptURI1, scriptURI2]);
    finalScriptURI = await registry.scriptURI(exampleNFT.target);
=======
    await expect(registry.connect(otherAccount4).setScriptURI(stakingToken.target, []))
      .to.revertedWith("> 0 entries required in scriptURIList");

    //remove an entry
    await registry.connect(otherAccount4).setScriptURI(stakingToken.target, [""]);
    //console.log(`Current ScriptURI = ${await registry.scriptURI(stakingToken.target)}`);

    //and another
    await registry.connect(otherAccount3).setScriptURI(stakingToken.target, [""]);
    //console.log(`Current ScriptURI = ${await registry.scriptURI(stakingToken.target)}`);

    //now add back
    await registry.connect(otherAccount3).setScriptURI(stakingToken.target, [scriptURI4, scriptURI1, scriptURI2]);
    finalScriptURI = await registry.scriptURI(stakingToken.target);
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
    //console.log(`Current ScriptURI = ${finalScriptURI}`);

    //check final return, should be:
    let correctFinal = [origScriptURI, scriptURI1, scriptURI2, scriptURI4, scriptURI1, scriptURI2, ""];
<<<<<<< HEAD
    expect((await registry.scriptURI(exampleNFT.target)).toString()).to.be.equal(correctFinal.toString());

    checkPageSize(2, correctFinal, registry, exampleNFT);
    checkPageSize(3, correctFinal, registry, exampleNFT);
    checkPageSize(1, correctFinal, registry, exampleNFT);
    checkPageSize(500, correctFinal, registry, exampleNFT);
  });


  async function checkPageSize(pageSize: number, correctFinal: string[], registry: any, exampleNFT: any) {
=======
    expect((await registry.scriptURI(stakingToken.target)).toString()).to.be.equal(correctFinal.toString());

    checkPageSize(2, correctFinal, registry, stakingToken);
    checkPageSize(3, correctFinal, registry, stakingToken);
    checkPageSize(1, correctFinal, registry, stakingToken);
    checkPageSize(500, correctFinal, registry, stakingToken);
  });


  async function checkPageSize(pageSize: number, correctFinal: string[], registry: any, stakingToken: any) {
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
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
  
<<<<<<< HEAD
          let contractReturn = await registry.scriptURI(exampleNFT.target, page, pageSize);
=======
          let contractReturn = await registry.scriptURI(stakingToken.target, page, pageSize);
>>>>>>> 4a582f5016fd4065b7a851531340835b2bad9bb6
          //console.log(`Actual return = ${contractReturn} Expected = ${expected}`);
          expect(contractReturn.toString()).to.be.equal(expected.toString());
      }
  }

})