import { expect } from "chai";
import hre from "hardhat";
import {loadFixture} from "@nomicfoundation/hardhat-toolbox/network-helpers";

describe("DeFlashLoan", function () {
    // We define a fixture to reuse the same setup in every test.
    // We use loadFixture to run this setup once, snapshot that state,
    // and reset Hardhat Network to that snapshot in every test.
    async function deployDeFlashLoanFixture() {
    
        // Contracts are deployed using the first signer/account by default
        const [owner, otherAccount] = await hre.ethers.getSigners();

        const data = await hre.ethers.getContractFactory("Data",owner);
        const dataContract = await data.deploy();

        const be_attacked = await hre.ethers.getContractFactory("BeAttacked",owner);
        const be_attackedContract = await be_attacked.deploy(dataContract.target);
    
        const attack = await hre.ethers.getContractFactory("Attack",owner);
        const attackContract = await attack.deploy(dataContract.target,be_attackedContract.target);

        return { dataContract, be_attackedContract, attackContract, owner, otherAccount };

    }
    
    describe("Deployment", function () {
        it("Should set the right address", async function () {
        const { dataContract, be_attackedContract, attackContract, owner } = await loadFixture(deployDeFlashLoanFixture);
    
        expect(await be_attackedContract.data_contract()).to.equal(dataContract.target);

        expect(await attackContract.data_contract()).to.equal(dataContract.target);
        expect(await attackContract.be_attacked_contract()).to.equal(be_attackedContract.target);
        });
    });

    describe("Auto reset", function () {
        it("function_call_times should auto reset after any transaction", async function () {
            const { dataContract, otherAccount } = await loadFixture(deployDeFlashLoanFixture);
            await dataContract.connect(otherAccount).changeDataFunction(6);
            expect(await dataContract.getFunctionCallTimes(dataContract.interface.getFunction('changeDataFunction').selector)).to.equal(0);
        });

        it("contract_call_times should auto reset after any transaction", async function () {
            const { dataContract, otherAccount } = await loadFixture(deployDeFlashLoanFixture);
            await dataContract.connect(otherAccount).changeDataFunction(6);
            expect(await dataContract.getContractCallTimes()).to.equal(0);
        });
        
    });
    
    describe("Simulated attack", function () {
        it("Should revert with refuse reentry", async function () {
        const { attackContract, otherAccount } = await loadFixture(deployDeFlashLoanFixture);
    
        await expect(attackContract.connect(otherAccount).attack()).to.be.revertedWith("refuse reentry");
        });
    
    });

    });