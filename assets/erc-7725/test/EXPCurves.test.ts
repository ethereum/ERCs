import { expect } from "chai";
import { Contract } from "ethers";
import { ethers, network } from "hardhat";

describe("Valocracy using EXPCurves", async function () {
  let Valocracy: Contract;
  let owner: any;

  let day = 60 * 60 * 24;
  let month = 60 * 60 * 24 * 30;

  const initialVotingPower = ethers.utils.parseEther("300");
  const ncurvature = -5;

  before(async function () {
    [owner] = await ethers.getSigners();
    const Factory = await ethers.getContractFactory("Valocracy", owner);
    Valocracy = await Factory.deploy();
    await Valocracy.deployed();
  });

  it("Should configure the contract", async function () {
    await Valocracy.setCurvature(ncurvature);
    await Valocracy.setVacationPeriod(month);
    expect(await Valocracy.curvature()).to.equal(ncurvature);
    expect(await Valocracy.vacationPeriod()).to.equal(month);
  });

  it("Should contribute and earn more governance power", async function () {
    // Using voting power with 18 decimals
    await Valocracy.contribute(owner.address, initialVotingPower);
    const user = await Valocracy.votingPower(owner.address);
    const timestamp = (await ethers.provider.getBlock("latest")).timestamp;
    expect(user.votingPower).to.equal(initialVotingPower);
    expect(user.lastUpdate).to.equal(timestamp);
  });

  it("Should hold less power accross time", async function () {
    const initialVotingPower = await Valocracy.balanceOf(owner.address);
    expect(initialVotingPower).to.equal(initialVotingPower);
    console.log(
      "Current Voting Power: ",
      ethers.utils.formatEther(initialVotingPower).toString(),
    );

    for (let i = 0; i < 30; i++) {
      await network.provider.send("evm_increaseTime", [day]);
      await network.provider.send("evm_mine");
      const votingPower = await Valocracy.balanceOf(owner.address);
      console.log(
        "Current Voting Power: ",
        ethers.utils.formatEther(votingPower).toString(),
      );
    }
    const finalVotingPower = await Valocracy.balanceOf(owner.address);
    expect(finalVotingPower).to.equal(ethers.utils.parseEther("0"));
  });
});
