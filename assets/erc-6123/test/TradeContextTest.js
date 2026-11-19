const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("ERC-6123 trade context", () => {
  async function fixture() {
    const [, a, b, outsider] = await ethers.getSigners();
    const token = await (await ethers.getContractFactory("ERC20Settlement")).deploy();
    const sdc = await (await ethers.getContractFactory("SDCSingleTradePledgedBalance"))
      .deploy(a.address, b.address, token.address, 0, 0);
    await token.mint(a.address, 10000);
    await token.mint(b.address, 10000);
    const args = [a.address, b.address, "terms", 1, 0, "market"];
    return { a, b, outsider, token, sdc, args };
  }

  it("generates fresh IDs and rejects stale calls for identical replacement quotes", async () => {
    const { a, b, sdc, args } = await fixture();
    expect(await sdc.connect(a).callStatic.inceptTrade(...args)).to.equal("1");
    await expect(sdc.connect(a).inceptTrade(...args)).to.emit(sdc, "TradeIncepted")
      .withArgs(a.address, b.address, "1", "terms", 1, 0, "market");
    await sdc.connect(a).cancelTrade("1", ...args);
    expect(await sdc.connect(a).callStatic.inceptTrade(...args)).to.equal("2");
    await sdc.connect(a).inceptTrade(...args);
    expect(await sdc.getTradeID()).to.equal("2");
    for (const staleId of ["1", ""]) {
      await expect(sdc.connect(b).confirmTrade(staleId, ...args)).to.be.reverted;
      await expect(sdc.connect(a).cancelTrade(staleId, ...args)).to.be.reverted;
    }
    await expect(sdc.connect(b).confirmTrade("2", ...args)).to.emit(sdc, "TradeConfirmed")
      .withArgs(b.address, "2");
    await expect(sdc.connect(b).confirmTrade("2", ...args)).to.be.reverted;
  });

  it("matches the complete inception tuple without reversing parties or signs", async () => {
    const { a, b, outsider, sdc, args } = await fixture();
    args[4] = 100;
    await sdc.connect(a).inceptTrade(...args);
    const id = await sdc.getTradeID();
    const mismatches = [
      ["other", ...args],
      [id, outsider.address, ...args.slice(1)],
      [id, a.address, outsider.address, ...args.slice(2)],
      [id, b.address, a.address, ...args.slice(2)],
      [id, a.address, b.address, "changed", ...args.slice(3)],
      [id, ...args.slice(0, 3), -1, 100, "market"],
      [id, ...args.slice(0, 4), -100, "market"],
      [id, ...args.slice(0, 5), "changed"],
    ];
    for (const mismatch of mismatches) {
      await expect(sdc.connect(b).confirmTrade(...mismatch)).to.be.reverted;
      await expect(sdc.connect(a).cancelTrade(...mismatch)).to.be.reverted;
    }
    await sdc.connect(a).cancelTrade(id, ...args);
    expect(await sdc.getTradeState()).to.equal(0);
  });

  it("requires direct calls from the participant responsible for each action", async () => {
    const { a, b, outsider, sdc, args } = await fixture();
    const rejected = (call) => expect(call).to.be.revertedWith("Caller must be the trade party");
    for (const caller of [b, outsider]) await rejected(sdc.connect(caller).inceptTrade(...args));
    await sdc.connect(a).inceptTrade(...args);
    const id = await sdc.getTradeID();
    for (const caller of [a, outsider]) await rejected(sdc.connect(caller).confirmTrade(id, ...args));
    for (const caller of [b, outsider]) await rejected(sdc.connect(caller).cancelTrade(id, ...args));
    await sdc.connect(b).confirmTrade(id, ...args);
    const termination = [id, a.address, 100, "termination"];
    for (const caller of [b, outsider]) await rejected(sdc.connect(caller).requestTradeTermination(...termination));
    await sdc.connect(a).requestTradeTermination(...termination);
    for (const caller of [a, outsider]) await rejected(sdc.connect(caller).confirmTradeTermination(...termination));
    for (const caller of [b, outsider]) await rejected(sdc.connect(caller).cancelTradeTermination(...termination));
    await sdc.connect(a).cancelTradeTermination(...termination);
    await expect(sdc.connect(b).confirmTradeTermination(...termination)).to.be.reverted;
  });

  it("binds termination to its requester and retains that party's payment perspective", async () => {
    const { a, b, sdc, token, args } = await fixture();
    await sdc.connect(a).inceptTrade(...args);
    const id = await sdc.getTradeID();
    await sdc.connect(b).confirmTrade(id, ...args);
    const requestA = [id, a.address, 100, "termination"];
    const requestB = [id, b.address, 100, "termination"];
    await sdc.connect(a).requestTradeTermination(...requestA);
    for (const mismatch of [
      ["other", ...requestA.slice(1)], requestB,
      [id, a.address, -100, "termination"], [id, a.address, 100, "changed"],
    ]) {
      await expect(sdc.connect(b).confirmTradeTermination(...mismatch)).to.be.reverted;
      await expect(sdc.connect(a).cancelTradeTermination(...mismatch)).to.be.reverted;
    }
    await expect(sdc.connect(a).confirmTradeTermination(...requestB)).to.be.reverted;
    await sdc.connect(b).requestTradeTermination(...requestB);
    await sdc.connect(a).cancelTradeTermination(...requestA);
    await expect(sdc.connect(b).confirmTradeTermination(...requestA)).to.be.reverted;
    await expect(sdc.connect(a).confirmTradeTermination(...requestB))
      .to.emit(sdc, "TradeTerminationConfirmed").withArgs(a.address, id, 100, "termination");
    expect(await token.balanceOf(b.address)).to.equal(10100);
    expect(await token.balanceOf(a.address)).to.equal(9900);
  });
});
