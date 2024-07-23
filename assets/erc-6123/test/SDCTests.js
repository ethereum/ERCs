const { ethers } = require("hardhat");
const { expect } = require("chai");
const AbiCoder = ethers.utils.AbiCoder;
const Keccak256 = ethers.utils.keccak256;

describe("Livecycle Unit-Tests for SDC Plege Balance", () => {

    // Define objects for TradeState enum, since solidity enums cannot provide their member names...
  const TradeState = {
      Inactive: 0,
      Incepted: 1,
      Confirmed: 2,
      Valuation: 3,
      InTransfer: 4,
      Settled: 5,
      InTermination: 6,
      Terminated: 7
  };

  const abiCoder = new AbiCoder();
  const trade_data = "<xml>here are the trade specification</xml";

 // let token;
  let tokenManager;
  let counterparty1;
  let counterparty2;
  let trade_id;
  let initialLiquidityBalance = 10000;
  let terminationFee = 100;
  let marginBufferAmount = 900;
  const settlementAmount1 = 200; // successful settlement in favour to CP1
  const settlementAmount2 = -1400; // failing settlement larger than buffer in favour to CP1
  const upfront = 10;
  const terminationPayment = 100;
  let SDCFactory;
  let ERC20Factory;

  before(async () => {
    const [_tokenManager, _counterparty1, _counterparty2] = await ethers.getSigners();
    tokenManager = _tokenManager;
    counterparty1 = _counterparty1;
    counterparty2 = _counterparty2;
    ERC20Factory = await ethers.getContractFactory("ERC20Settlement");
    SDCFactory = await ethers.getContractFactory("SDCPledgedBalance");
    //oken = await ERC20Factory.deploy();
   // await token.deployed();
  });



  it("Counterparties incept and confirm a trade successfully, upfront is transferred from CP1 to CP2", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);

     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);

//     console.log("SDC Address: %s", sdc.address);
     await token.connect(counterparty1).approve(sdc.address,terminationFee+marginBufferAmount);
     await token.connect(counterparty2).approve(sdc.address,terminationFee+marginBufferAmount+upfront);
     let trade_id ="";
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, -upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, upfront, "initialMarketData");
     await expect(confirm_call).to.emit(sdc, "TradeConfirmed");
     let trade_state =  await sdc.connect(counterparty1).getTradeState();
     await expect(trade_state).equal(TradeState.Settled);
     let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
     let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
     let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
     console.log("Balance for SDC-Address: %s", sdc_balance);
     await expect(sdc_balance).equal(2*(terminationFee+marginBufferAmount));
     await expect(cp1_balance).equal(initialLiquidityBalance-upfront-terminationFee-marginBufferAmount);
     await expect(cp2_balance).equal(initialLiquidityBalance+upfront-terminationFee-marginBufferAmount);
   });

  it("Counterparty incepts and cancels trade successfully", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     let trade_id ="";
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = await sdc.connect(counterparty1).cancelTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(confirm_call).to.emit(sdc, "TradeCanceled");
     let trade_state =  await sdc.connect(counterparty1).getTradeState();
     await expect(trade_state).equal(TradeState.Inactive);
   });

   it("Not enough balance to transfer upfront payment", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);

     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, 2*initialLiquidityBalance, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, -2*initialLiquidityBalance, "initialMarketData");
     await expect(confirm_call).to.emit(sdc, "TradeConfirmed");
     let trade_state =  await sdc.connect(counterparty1).getTradeState();
     await expect(trade_state).equal(TradeState.Terminated);
     let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
     let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
     let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
     await expect(sdc_balance).equal(0);
     await expect(cp1_balance).equal(initialLiquidityBalance);
     await expect(cp2_balance).equal(initialLiquidityBalance);
   });

   it("Trade Matching fails", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = sdc.connect(counterparty2).confirmTrade(counterparty1.address, "none", -1, -upfront, "initialMarketData23");
     await expect(confirm_call).to.be.revertedWith("Confirmation fails due to inconsistent trade data or wrong party address");
   });

   it("Trade cancellation fails due to wrong party calling cancel", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = sdc.connect(counterparty2).cancelTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(confirm_call).to.be.revertedWith("Cancellation fails due to inconsistent trade data or wrong party address");
   });

   it("Trade cancellation fails due to wrong arguments", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);

     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = sdc.connect(counterparty1).cancelTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData23");
     await expect(confirm_call).to.be.revertedWith("Cancellation fails due to inconsistent trade data or wrong party address");
   });

  it("Counterparties incept and confirm a trade successfully, Upfront is transferred from CP2 to CP1, Trade is terminated with Payment from CP1 to CP2", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     const receipt = await incept_call.wait();
     const event = receipt.events.find(event => event.event === 'TradeIncepted');
     const trade_id = event.args[1];
     const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, -upfront, "initialMarketData");
     await expect(confirm_call).to.emit(sdc, "TradeConfirmed");
     const terminate_call = await sdc.connect(counterparty1).requestTradeTermination(trade_id, terminationPayment, "terminationTerms");
     await expect(terminate_call).to.emit(sdc, "TradeTerminationRequest");
     const confirm_terminate_call = await sdc.connect(counterparty2).confirmTradeTermination(trade_id, -terminationPayment, "terminationTerms");
     await expect(confirm_terminate_call).to.emit(sdc, "TradeTerminationConfirmed");
     let trade_state =  await sdc.connect(counterparty1).getTradeState();
     await expect(trade_state).equal(TradeState.Terminated);
     let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
     let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
     let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
     await expect(sdc_balance).equal(0);
     await expect(cp1_balance).equal(initialLiquidityBalance+upfront-terminationPayment);
     await expect(cp2_balance).equal(initialLiquidityBalance-upfront+terminationPayment);
   });

  it("Successful Inception with Upfront transferred from CP2 to CP1 + successful settlement transferred from CP1 to CP2", async () => {
     let settlementAmount = -245;
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     let trade_id ="";
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, -upfront, "initialMarketData");
     await expect(confirm_call).to.emit(sdc, "TradeConfirmed");
     const initSettlementPhase = sdc.connect(counterparty2).initiateSettlement();
     await expect(initSettlementPhase).to.emit(sdc, "TradeSettlementRequest");

     const performSettlementCall = sdc.connect(counterparty1).performSettlement(settlementAmount,"settlementData");
     await expect(performSettlementCall).to.emit(sdc, "TradeSettlementPhase");
     let trade_state =  await sdc.connect(counterparty1).getTradeState();
     await expect(trade_state).equal(TradeState.Settled);
     let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
     let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
     let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
     await expect(sdc_balance).equal(2*(terminationFee+marginBufferAmount));
     await expect(cp1_balance).equal(initialLiquidityBalance-terminationFee-marginBufferAmount+upfront+settlementAmount);
     await expect(cp2_balance).equal(initialLiquidityBalance-terminationFee-marginBufferAmount-upfront-settlementAmount);

   });

    it("Failed settlement followed by Termination with Pledge Case", async () => {
        let settlementAmount = -500;
        let token = await ERC20Factory.deploy();
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
        let trade_id ="";
        let upfront_max = initialLiquidityBalance - marginBufferAmount - terminationFee;

        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, -upfront_max, "initialMarketData");
        await expect(incept_call).to.emit(sdc, "TradeIncepted");
        const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, +upfront_max, "initialMarketData");
        await expect(confirm_call).to.emit(sdc, "TradeConfirmed");

        const initSettlementPhase = sdc.connect(counterparty2).initiateSettlement();
        await expect(initSettlementPhase).to.emit(sdc, "TradeSettlementRequest");

        const performSettlementCall = sdc.connect(counterparty1).performSettlement(settlementAmount,"settlementData");
        await expect(performSettlementCall).to.emit(sdc, "TradeSettlementPhase");
        let trade_state =  await sdc.connect(counterparty1).getTradeState();
        let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);

        await expect(trade_state).equal(TradeState.Terminated);
        await expect(sdc_balance).equal(0);
        await expect(cp1_balance).equal(marginBufferAmount+settlementAmount);
        await expect(cp2_balance).equal(initialLiquidityBalance+upfront_max-settlementAmount+terminationFee);

    });

    it("Failed Mutual Termination: Payment from CP1 to CP2 results in pledge case with capped termination fee amount being transferred", async () => {
        let token = await ERC20Factory.deploy();
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, 0, "initialMarketData");
        const receipt = await incept_call.wait();
        const event = receipt.events.find(event => event.event === 'TradeIncepted');
        const trade_id = event.args[1];
        const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, 0, "initialMarketData");
        await expect(confirm_call).to.emit(sdc, "TradeConfirmed");
        const terminate_call = await sdc.connect(counterparty1).requestTradeTermination(trade_id, 10000000, "terminationTerms");
        await expect(terminate_call).to.emit(sdc, "TradeTerminationRequest");
        const confirm_terminate_call = await sdc.connect(counterparty2).confirmTradeTermination(trade_id, -10000000, "terminationTerms");
        await expect(confirm_terminate_call).to.emit(sdc, "TradeTerminationConfirmed");
        let trade_state =  await sdc.connect(counterparty1).getTradeState();
        await expect(trade_state).equal(TradeState.Terminated);
        let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
        await expect(sdc_balance).equal(0);
        await expect(cp1_balance).equal(initialLiquidityBalance+marginBufferAmount+terminationFee);
        await expect(cp2_balance).equal(initialLiquidityBalance-marginBufferAmount-terminationFee);
    });
});