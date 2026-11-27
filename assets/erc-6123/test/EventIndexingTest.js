const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("ERC-6123 event filtering", () => {
  async function fixture() {
    const [a, b, outsider] = await ethers.getSigners();
    const token = await (await ethers.getContractFactory("ERC20Settlement")).deploy();
    const sdc = await (await ethers.getContractFactory("SDCSingleTradePledgedBalance"))
      .deploy(a.address, b.address, token.address, 0, 0);
    const args = [a.address, b.address, "readable trade terms", 1, 0, "market"];
    return { a, b, outsider, sdc, args };
  }

  it("filters by either economic participant while retaining the string trade ID", async () => {
    const { a, b, outsider, sdc, args } = await fixture();
    const receipt = await (await sdc.connect(a).inceptTrade(...args)).wait();
    const topic = (address) => ethers.utils.hexZeroPad(address, 32).toLowerCase();
    const event = receipt.events.find((item) => item.event === "TradeIncepted");
    expect(event.topics).to.deep.equal([
      sdc.interface.getEventTopic("TradeIncepted"), topic(a.address), topic(b.address),
    ]);
    expect(event.args.tradeId).to.equal("1");
    expect(event.args.tradeData).to.equal(args[2]);
    expect(await sdc.queryFilter(sdc.filters.TradeIncepted(a.address, null))).to.have.lengthOf(1);
    expect(await sdc.queryFilter(sdc.filters.TradeIncepted(null, b.address))).to.have.lengthOf(1);
    expect(await sdc.queryFilter(sdc.filters.TradeIncepted(outsider.address, null))).to.have.lengthOf(0);
    await sdc.connect(b).confirmTrade("1", ...args);
    const confirmed = await sdc.queryFilter(sdc.filters.TradeConfirmed(b.address));
    expect(confirmed).to.have.lengthOf(1);
    expect(confirmed[0].args.tradeId).to.equal("1");
  });

  it("filters settlement logs by initiator and exact numeric transaction ID", async () => {
    const { a, b, outsider, sdc, args } = await fixture();
    await sdc.connect(a).inceptTrade(...args);
    await sdc.connect(b).confirmTrade("1", ...args);
    await sdc.connect(b).initiateSettlement();
    expect(await sdc.queryFilter(sdc.filters.SettlementRequested(b.address))).to.have.lengthOf(1);
    expect(await sdc.queryFilter(sdc.filters.SettlementRequested(outsider.address))).to.have.lengthOf(0);
    const receipt = await (await sdc.connect(a).performSettlement(0, "valuation")).wait();
    expect(await sdc.queryFilter(sdc.filters.SettlementDetermined(a.address))).to.have.lengthOf(1);
    const event = receipt.events.find((item) => item.event === "SettlementTransferred");
    const id = event.args.transactionID;
    expect(event.topics).to.deep.equal([
      sdc.interface.getEventTopic("SettlementTransferred"), ethers.utils.hexZeroPad(id.toHexString(), 32),
    ]);
    expect(event.args.transactionData).to.equal(id.toString());
    expect(await sdc.queryFilter(sdc.filters.SettlementTransferred(id))).to.have.lengthOf(1);
    expect(await sdc.queryFilter(sdc.filters.SettlementTransferred(id.add(1)))).to.have.lengthOf(0);
  });
});
