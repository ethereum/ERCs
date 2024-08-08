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
    SDCFactory = await ethers.getContractFactory("SDCSingleTradePledgedBalance");
    //oken = await ERC20Factory.deploy();
   // await token.deployed();
  });


  it("1. Counterparties incept and confirm a trade successfully, Upfront is transferred from CP1 to CP2", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
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

    it("2a. CP1 is receiving party and pays initial Upfront (no buffers)", async () => {
        let token = await ERC20Factory.deploy();
        let upfront1 = 150;
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,0,0);
        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, -upfront1, "initialMarketData");
        const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, upfront1, "initialMarketData");
        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
        await expect(cp1_balance).equal(initialLiquidityBalance-upfront1);
        await expect(cp2_balance).equal(initialLiquidityBalance+upfront1);
    });

    it("2b. CP1 is paying party and receives initial Upfront (no buffers)", async () => {
        let token = await ERC20Factory.deploy();
        let upfront1 = 150;
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,0,0);
        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, -1, upfront1, "initialMarketData");
        const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, 1, -upfront1, "initialMarketData");
        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
        await expect(cp1_balance).equal(initialLiquidityBalance+upfront1);
        await expect(cp2_balance).equal(initialLiquidityBalance-upfront1);
    });

    it("2c. CP2 is paying party and pays initial Upfront (no buffers)", async () => {
        let token = await ERC20Factory.deploy();
        let upfront1 = 150;
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,0,0);
        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront1, "initialMarketData");
        const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, -upfront1, "initialMarketData");
        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
        await expect(cp1_balance).equal(initialLiquidityBalance+upfront1);
        await expect(cp2_balance).equal(initialLiquidityBalance-upfront1);
    });

  it("3. Counterparty incepts and cancels trade successfully", async () => {
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

   it("4. Not enough balance to transfer upfront payment", async () => {
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

   it("5. Trade Matching fails", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = sdc.connect(counterparty2).confirmTrade(counterparty1.address, "none", -1, -upfront, "initialMarketData23");
     await expect(confirm_call).to.be.revertedWith("Confirmation fails due to inconsistent trade data or wrong party address");
   });

   it("6. Trade cancellation fails due to wrong party calling cancel", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = sdc.connect(counterparty2).cancelTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(confirm_call).to.be.revertedWith("Cancellation fails due to inconsistent trade data or wrong party address");
   });

   it("7. Trade cancellation fails due to wrong arguments", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);

     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     await expect(incept_call).to.emit(sdc, "TradeIncepted");
     const confirm_call = sdc.connect(counterparty1).cancelTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData23");
     await expect(confirm_call).to.be.revertedWith("Cancellation fails due to inconsistent trade data or wrong party address");
   });

  it("8. Counterparties incept and confirm, upfront is transferred from CP2 to CP1, Trade is terminated with Payment from CP2 to CP1", async () => {
     let token = await ERC20Factory.deploy();
     await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
     await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
     let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
     const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, upfront, "initialMarketData");
     const receipt = await incept_call.wait();
     const event = receipt.events.find(event => event.event === 'TradeIncepted');
     const trade_id = event.args[2];
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
     await expect(cp1_balance).equal(initialLiquidityBalance+upfront+terminationPayment);
     await expect(cp2_balance).equal(initialLiquidityBalance-upfront-terminationPayment);
   });

    it("9a. CP1 is Receiving Party, Trade-Termination is incepted by CP2 which receives the termination payment from CP1", async () => {
        let token = await ERC20Factory.deploy();
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
        // Note: position = 1 => counterparty1 is the receivingParty
        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, 0, "initialMarketData");
        const receipt = await incept_call.wait();
        const event = receipt.events.find(event => event.event === 'TradeIncepted');
        const trade_id = event.args[2];
        const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, 0, "initialMarketData");

        // Note: terminationPayment is considered to be viewed from the requester here.
        const terminate_call = await sdc.connect(counterparty2).requestTradeTermination(trade_id, -terminationPayment, "terminationTerms");
        // Note: terminationPayment is considered to be viewed from the confirmer here.
        const confirm_terminate_call = await sdc.connect(counterparty1).confirmTradeTermination(trade_id, +terminationPayment, "terminationTerms");

        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
        await expect(cp1_balance).equal(initialLiquidityBalance+terminationPayment);
        await expect(cp2_balance).equal(initialLiquidityBalance-terminationPayment);
    });

    it("9b. CP1 is Receiving Party, Trade-Termination is incepted by CP1 which pays the termination payment to CP2", async () => {
        let token = await ERC20Factory.deploy();
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
        // Note: position = 1 => counterparty1 is the receivingParty
        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, 0, "initialMarketData");
        const receipt = await incept_call.wait();
        const event = receipt.events.find(event => event.event === 'TradeIncepted');
        const trade_id = event.args[2];
        const confirm_call = await sdc.connect(counterparty2).confirmTrade(counterparty1.address, trade_data, -1, 0, "initialMarketData");
        // Note: terminationPayment is considered to be viewed from the requester here.
        const terminate_call = await sdc.connect(counterparty1).requestTradeTermination(trade_id, terminationPayment, "terminationTerms");
        const confirm_terminate_call = await sdc.connect(counterparty2).confirmTradeTermination(trade_id, -terminationPayment, "terminationTerms");
        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
        await expect(cp1_balance).equal(initialLiquidityBalance+terminationPayment);
        await expect(cp2_balance).equal(initialLiquidityBalance-terminationPayment);
    });

  it("10. Successful Inception with Upfront transferred from CP2 to CP1 + successful settlement transferred from CP1 to CP2", async () => {
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
     await expect(initSettlementPhase).to.emit(sdc, "SettlementRequested");

     const performSettlementCall = sdc.connect(counterparty1).performSettlement(settlementAmount,"settlementData");
     await expect(performSettlementCall).to.emit(sdc, "SettlementEvaluated");
     let trade_state =  await sdc.connect(counterparty1).getTradeState();
     await expect(trade_state).equal(TradeState.Settled);
     let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
     let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
     let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);
     await expect(sdc_balance).equal(2*(terminationFee+marginBufferAmount));
     await expect(cp1_balance).equal(initialLiquidityBalance-terminationFee-marginBufferAmount+upfront+settlementAmount);
     await expect(cp2_balance).equal(initialLiquidityBalance-terminationFee-marginBufferAmount-upfront-settlementAmount);

   });

    it("11. Failed settlement followed by Termination with Pledge Case", async () => {
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
        await expect(initSettlementPhase).to.emit(sdc, "SettlementRequested");

        const performSettlementCall = sdc.connect(counterparty1).performSettlement(settlementAmount,"settlementData");
        await expect(performSettlementCall).to.emit(sdc, "SettlementEvaluated");
        let trade_state =  await sdc.connect(counterparty1).getTradeState();
        let sdc_balance = await token.connect(counterparty1).balanceOf(sdc.address);
        let cp1_balance = await token.connect(counterparty1).balanceOf(counterparty1.address);
        let cp2_balance = await token.connect(counterparty1).balanceOf(counterparty2.address);

        await expect(trade_state).equal(TradeState.Terminated);
        await expect(sdc_balance).equal(0);
        await expect(cp1_balance).equal(marginBufferAmount+settlementAmount);
        await expect(cp2_balance).equal(initialLiquidityBalance+upfront_max-settlementAmount+terminationFee);

    });

    it("12. Failed Mutual Termination: Payment from CP1 to CP2 results in pledge case with capped termination fee amount being transferred", async () => {
        let token = await ERC20Factory.deploy();
        await token.connect(counterparty1).mint(counterparty1.address,initialLiquidityBalance);
        await token.connect(counterparty2).mint(counterparty2.address,initialLiquidityBalance);
        let sdc = await SDCFactory.deploy(counterparty1.address, counterparty2.address,token.address,marginBufferAmount,terminationFee);
        const incept_call = await sdc.connect(counterparty1).inceptTrade(counterparty2.address, trade_data, 1, 0, "initialMarketData");
        const receipt = await incept_call.wait();
        const event = receipt.events.find(event => event.event === 'TradeIncepted');
        const trade_id = event.args[2];
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