const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("ERC-6123 FX spot trade", () => {
  async function fixture(reverse = false, sign = 1) {
    const [a, b, outsider] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("ERC20TokenExample");
    const base = await Token.deploy("Base", "BASE", 18);
    const quote = await Token.deploy("Quote", "QUOTE", 6);
    const factory = await (await ethers.getContractFactory("FxSpotTradeFactory")).deploy();
    const router = await ethers.getContractAt("ERC20PvPSettlementRouter", await factory.settlementRouter());
    const receipt = await (await factory.createTrade(base.address, quote.address, a.address, b.address)).wait();
    const address = receipt.events.find((event) => event.event === "TradeCreated").args.trade;
    const spotTrade = await ethers.getContractAt("FxSpotTrade", address);
    const trade = await ethers.getContractAt("ISDCTrade", address);
    for (const token of [base, quote]) {
      for (const party of [a, b]) {
        await token.mint(party.address, 1000);
        await token.connect(party).approve(router.address, 1000);
      }
    }
    const [inceptor, counterparty] = reverse ? [b, a] : [a, b];
    const args = [inceptor.address, counterparty.address, "terms", sign * 100, -sign * 200, "market"];
    return { inceptor, counterparty, outsider, base, quote, router, spotTrade, trade, args };
  }

  it("settles through ISDCTrade with either inceptor and either payment direction", async () => {
    for (const reverse of [false, true]) {
      for (const sign of [1, -1]) {
        const { inceptor, counterparty, base, quote, router, spotTrade, trade, args } = await fixture(reverse, sign);
        expect(await router.activeTrade(spotTrade.address)).to.equal(true);
        expect(await trade.connect(inceptor).callStatic.inceptTrade(...args)).to.equal("1");
        await expect(trade.connect(inceptor).inceptTrade(...args)).to.emit(trade, "TradeIncepted")
          .withArgs(inceptor.address, counterparty.address, "1", ...args.slice(2));
        await expect(trade.connect(counterparty).confirmTrade("1", ...args)).to.emit(trade, "TradeConfirmed")
          .withArgs(counterparty.address, "1");
        expect(await base.balanceOf(inceptor.address)).to.equal(1000 + args[3]);
        expect(await base.balanceOf(counterparty.address)).to.equal(1000 - args[3]);
        expect(await quote.balanceOf(inceptor.address)).to.equal(1000 + args[4]);
        expect(await quote.balanceOf(counterparty.address)).to.equal(1000 - args[4]);
        expect(await spotTrade.phase()).to.equal(2);
        expect(await router.activeTrade(spotTrade.address)).to.equal(false);
        await expect(trade.connect(counterparty).confirmTrade("1", ...args)).to.be.reverted;
        await expect(trade.connect(inceptor).inceptTrade(...args)).to.be.reverted;
      }
    }
  });

  it("matches the identifier, ordered parties, unchanged amounts and text fields", async () => {
    const { inceptor, counterparty, outsider, trade, args } = await fixture();
    await trade.connect(inceptor).inceptTrade(...args);
    const mismatches = [
      ["", ...args], ["2", ...args],
      ["1", outsider.address, ...args.slice(1)],
      ["1", inceptor.address, outsider.address, ...args.slice(2)],
      ["1", counterparty.address, inceptor.address, ...args.slice(2)],
      ["1", ...args.slice(0, 2), "changed", ...args.slice(3)],
      ["1", ...args.slice(0, 3), -100, -200, "market"],
      ["1", ...args.slice(0, 4), 200, "market"],
      ["1", ...args.slice(0, 5), "changed"],
    ];
    for (const mismatch of mismatches) {
      await expect(trade.connect(counterparty).confirmTrade(...mismatch)).to.be.reverted;
      await expect(trade.connect(inceptor).cancelTrade(...mismatch)).to.be.reverted;
    }
    await trade.connect(counterparty).confirmTrade("1", ...args);
  });

  it("requires the named participant to submit each supported trade action", async () => {
    const { inceptor, counterparty, outsider, trade, args } = await fixture();
    for (const caller of [counterparty, outsider]) {
      await expect(trade.connect(caller).inceptTrade(...args)).to.be.reverted;
    }
    await expect(trade.connect(inceptor).inceptTrade(inceptor.address, outsider.address, ...args.slice(2)))
      .to.be.reverted;
    await trade.connect(inceptor).inceptTrade(...args);
    for (const caller of [inceptor, outsider]) {
      await expect(trade.connect(caller).confirmTrade("1", ...args)).to.be.reverted;
    }
    for (const caller of [counterparty, outsider]) {
      await expect(trade.connect(caller).cancelTrade("1", ...args)).to.be.reverted;
    }
    await trade.connect(inceptor).cancelTrade("1", ...args);
  });

  it("cancels the exact quote permanently without transferring either token", async () => {
    const { inceptor, counterparty, base, quote, router, spotTrade, trade, args } = await fixture();
    await trade.connect(inceptor).inceptTrade(...args);
    await expect(trade.connect(inceptor).cancelTrade("1", ...args)).to.emit(trade, "TradeCanceled")
      .withArgs(inceptor.address, "1");
    expect(await spotTrade.phase()).to.equal(3);
    for (const token of [base, quote]) {
      for (const party of [inceptor, counterparty]) {
        expect(await token.balanceOf(party.address)).to.equal(1000);
        expect(await token.allowance(party.address, router.address)).to.equal(1000);
      }
    }
    await expect(trade.connect(inceptor).inceptTrade(...args)).to.be.reverted;
    await expect(trade.connect(counterparty).confirmTrade("1", ...args)).to.be.reverted;
    await expect(trade.connect(inceptor).cancelTrade("1", ...args)).to.be.reverted;
  });

  it("exposes the termination signatures while rejecting unsupported termination", async () => {
    const { inceptor, trade } = await fixture();
    for (const method of ["requestTradeTermination", "confirmTradeTermination", "cancelTradeTermination"]) {
      await expect(trade.connect(inceptor)[method]("1", inceptor.address, 0, "termination")).to.be.reverted;
    }
  });
});
