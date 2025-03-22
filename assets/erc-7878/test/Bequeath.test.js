const { expect } = require("chai");
const { loadFixture, time  } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"



// start with a contract that has some tokens minted
async function deployTokenFixture() {

   const [investor, stranger, executor, inheritor] = await ethers.getSigners();

   const propToken = await ethers.deployContract("DeedRegistry");
   await propToken.waitForDeployment();

   await propToken.safeMint(investor.address,1);
   await propToken.safeMint(investor.address,2);

   return { propToken, investor, stranger, executor, inheritor };
}


describe("Token Ownership", async function() {
   let propToken, investor, stranger;

   before(async function() {
      return ({ propToken, investor, stranger } = await loadFixture(deployTokenFixture));
   });

   it("should have an initial supply greater than zero", async function(){
      expect(await propToken.totalSupply()).to.be.above(0, 'totalSupply is zero');
   });

   // and that the investor does have ownership of some tokens
   it("investor owns some tokens", async function(){
      expect(await propToken.balanceOf(investor.address)).to.be.above(0, 'investor does not own any tokens ');
   });

   // the stranger has no tokens
   it("stranger does not own tokens", async function(){
      expect(await propToken.balanceOf(stranger.address)).to.equal(0, 'stranger should not own any tokens');
   });

});


describe("Setting a will", async function() {
   let propToken, investor, stranger, executor;
   const moraTTL = 50;

   before(async function() {
      return ({ propToken, investor, stranger, executor } = await loadFixture(deployTokenFixture));
   });


   it("getting a will before setting it", async function(){
      const [executors2, _moraTTL2] = await propToken.connect(investor).getWill(investor.address);
      expect(executors2).to.be.an('array').that.is.empty;
      expect(_moraTTL2).to.equal(0, 'wrong obit TTL2');
   });

   it("investor is able to set a will", async function(){
      await expect(propToken
         .connect(investor)
         .setWill([executor.address], moraTTL)
      ).to.not.be.revertedWith("sender does not own any contracts");
   });

   it("stranger is unable to set a will", async function(){
      await expect(propToken
         .connect(stranger)
         .setWill([executor.address], moraTTL)
      ).to.be.revertedWith("sender does not own any contracts");
   });


   it("correct will details are returned", async function(){
      const [executors, _moraTTL] = await propToken.connect(investor).getWill(investor.address);
      expect(executors[0]).to.equal(executor.address, 'wrong executor address');
      expect(_moraTTL).to.equal(moraTTL, 'wrong obit TTL');
   });

   it("executor is not able to see the will", async function(){
      await expect(propToken
         .connect(executor)
         .getWill(investor.address)
      ).to.be.revertedWith("only owner");
   });

});

describe("Updating a will", async function() {
   let propToken, investor, stranger, executor;
   const moraTTL = 50;

   before(async function() {
      ({ propToken, investor, stranger, executor } = await loadFixture(deployTokenFixture));
      // set the initial will details
      await propToken.connect(investor).setWill([executor.address], moraTTL)

      return { propToken, investor, stranger, executor }
   });


   it("investor can change his will", async function(){
      obitTTL2 = 60;
      await expect(propToken
         .connect(investor)
         .setWill([stranger.address], obitTTL2)
      ).to.not.be.reverted;
   });

   it("correct will details are returned after the update", async function(){
      const [executors2, _moraTTL2] = await propToken.connect(investor).getWill(investor.address);
      expect(executors2[0]).to.equal(stranger.address, 'wrong executor address');
      expect(_moraTTL2).to.equal(obitTTL2, 'wrong obit TTL2');
   });


});


describe("Setting an Obituary", async function() {
   let propToken, investor, stranger, executor, inheritor;
   const moraTTL = 50;

   before(async function() {
      ({ propToken, investor, stranger, executor, inheritor } = await loadFixture(deployTokenFixture));
      // first set a will for this investor
      await propToken.connect(investor).setWill([executor.address], moraTTL);

      return { propToken, investor, stranger, executor, inheritor }
   });

   it("stranger is not able to set an obituary", async function() {
      await expect(propToken
         .connect(stranger)
         .announceObit(investor.address, stranger.address)
      ).to.be.revertedWith("only owner or executor");
   });

   it("zero address cannot inherit", async function(){
      await expect(propToken
         .connect(executor)
         .announceObit(investor.address, ZERO_ADDRESS)
      ).to.be.revertedWith("zero address cannot inherit");

   });

   it("executor is able to set an obituary", async function() {
      await expect(propToken
         .connect(executor)
         .announceObit(investor.address, inheritor.address)
      ).to.not.be.reverted;
   });

   // advance time to test the _moraTTL
   it("moratorium time has progressed", async function(){
      await time.increase(10);
      const [_inheritor, _moraTTL] = await propToken.connect(investor).getObit(investor.address);
      expect(_inheritor).to.equal(inheritor.address, 'wrong inheritor address');
      expect(_moraTTL).to.be.below(moraTTL, 'TTL is too large')
   });

   it("executor is not able to set the obituary again", async function(){
      await expect(propToken
         .connect(executor)
         .announceObit(investor.address, inheritor.address)
      ).to.be.revertedWith("obituary has already been set");
   });


});


describe("Cancelling an Obituary", async function() {
   let propToken, investor, stranger, executor, inheritor;
   const moraTTL = 50;

   before(async function() {
      ({ propToken, investor, stranger, executor, inheritor } = await loadFixture(deployTokenFixture));
      // first set a will for this investor
      await propToken.connect(investor).setWill([executor.address], moraTTL);
      // and set the obituary
      await propToken.connect(executor).announceObit(investor.address, inheritor.address);

      return { propToken, investor, stranger, executor, inheritor }
   });


   it("stranger is not able to cancel an obituary", async function(){
      await expect(propToken
         .connect(stranger)
         .cancelObit(investor.address)
      ).to.be.revertedWith("only owner or executor");
   });


   it("executor is able to cancel an obituary", async function(){
      await expect(propToken
         .connect(executor)
         .cancelObit(investor.address)
      ).to.not.be.reverted;
   });


   it("executor is able to set an obituary again", async function(){
      await expect(propToken
         .connect(executor)
         .announceObit(investor.address, inheritor.address)
      ).to.not.be.reverted;
   });

});


describe("Bequeathing the tokens", async function() {
   let  propToken, investor, stranger, executor, inheritor;
   const moraTTL = 50;

   before(async function() {
      ({ propToken, investor, stranger, executor, inheritor } = await loadFixture(deployTokenFixture));

      // set a will for this investor
      await propToken.connect(investor).setWill([executor.address], moraTTL);

      // and set the obituary
      await propToken.connect(executor).announceObit(investor.address, inheritor.address);

      // and fast forward by 20 seconds 
      await time.increase(20);

      return { propToken, investor, stranger, executor, inheritor }
   });

   // start by making sure investor has tokens and inheritor doesnt have any 
   // further down we will test that the transfer has happened and the opposite is true
   it("investor owns some tokens", async function(){
      expect(await propToken.balanceOf(investor.address)).to.be.above(0, 'investor should own some tokens');
   });

   it("inheritor does not owns any tokens", async function(){
      expect(await propToken.balanceOf(inheritor.address)).to.be.equal(0, 'inheritor should not own any tokens');
   });


   it("a stranger tries to bequeath", async function(){
      await expect(propToken
         .connect(stranger)
         .bequeath(investor.address)
      ).to.be.revertedWith("only an executor may bequeath a token");
   });


   it("executor unable bequeath before the moratorium is up", async function(){

      await expect(propToken
         .connect(executor)
         .bequeath(investor.address)
      ).to.be.revertedWith("Not enough time has passed yet to allow transfer of token");
   });


   it("stranger is still unable to bequeath after moratorium has expired", async function(){
      // fast forward by 50 seconds  - passed the moraTTL
      await time.increase(50);
      await expect(propToken
         .connect(stranger)
         .bequeath(investor.address)
      ).to.be.revertedWith("only an executor may bequeath a token");
   });

   it("inheritor is also unable to bequeath", async function(){
      await expect(propToken
         .connect(stranger)
         .bequeath(investor.address)
      ).to.be.revertedWith("only an executor may bequeath a token");
   });

   it("executor CAN bequeath", async function(){
      await expect(propToken
         .connect(executor)
         .bequeath(investor.address)
      ).to.not.be.reverted;
   });

   it("investor no longer owns any tokens", async function(){
      expect(await propToken.balanceOf(investor.address)).to.equal(0, 'investor should no longer own any tokens');
   });


   it("inheritor now owns some tokens", async function(){
      expect(await propToken.balanceOf(inheritor.address)).to.be.above(0, 'inheritor should not own some tokens');
   });

});

