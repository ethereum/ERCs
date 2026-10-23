const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ERC-7621 Basket Token", function () {
  let basket;
  let tokenA, tokenB, tokenC;
  let owner, alice, bob;

  const SUPPLY = ethers.parseEther("1000000");
  const DEAD_SHARES = 1000n;

  async function deployBasket(tokens, weights, signer) {
    const s = signer || owner;
    const BasketToken = await ethers.getContractFactory("BasketToken", s);
    return BasketToken.deploy("Test Basket", "TBSK", s.address, tokens, weights);
  }

  async function deployAndSeed() {
    const tokens = [await tokenA.getAddress(), await tokenB.getAddress()];
    const weights = [6000n, 4000n];
    basket = await deployBasket(tokens, weights);

    const amounts = [ethers.parseEther("100"), ethers.parseEther("50")];
    await tokenA.approve(await basket.getAddress(), amounts[0]);
    await tokenB.approve(await basket.getAddress(), amounts[1]);
    const minShares = 0n;
    await basket.contribute(amounts, owner.address, minShares);
    return { tokens, weights, amounts };
  }

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    tokenA = await MockERC20.deploy("Token A", "TKA", SUPPLY);
    tokenB = await MockERC20.deploy("Token B", "TKB", SUPPLY);
    tokenC = await MockERC20.deploy("Token C", "TKC", SUPPLY);
  });

  // ---- Contribution ----

  describe("Contribution", function () {
    it("mints shares proportionally and emits Contributed with caller, receiver, amounts", async function () {
      await deployAndSeed();

      const amounts = [ethers.parseEther("10"), ethers.parseEther("5")];
      await tokenA.transfer(alice.address, amounts[0]);
      await tokenB.transfer(alice.address, amounts[1]);
      await tokenA.connect(alice).approve(await basket.getAddress(), amounts[0]);
      await tokenB.connect(alice).approve(await basket.getAddress(), amounts[1]);

      const tx = basket.connect(alice).contribute(amounts, alice.address, 0n);
      await expect(tx)
        .to.emit(basket, "Contributed")
        .withArgs(alice.address, alice.address, () => true, amounts);

      const bal = await basket.balanceOf(alice.address);
      expect(bal).to.be.gt(0n);
    });

    it("reverts with InsufficientShares when shares minted is below minShares", async function () {
      await deployAndSeed();

      const amounts = [ethers.parseEther("10"), ethers.parseEther("5")];
      await tokenA.transfer(alice.address, amounts[0]);
      await tokenB.transfer(alice.address, amounts[1]);
      await tokenA.connect(alice).approve(await basket.getAddress(), amounts[0]);
      await tokenB.connect(alice).approve(await basket.getAddress(), amounts[1]);

      const hugeMin = ethers.parseEther("999999");
      await expect(
        basket.connect(alice).contribute(amounts, alice.address, hugeMin)
      ).to.be.revertedWithCustomError(basket, "InsufficientShares");
    });

    it("reverts with LengthMismatch when amounts length mismatches constituents", async function () {
      await deployAndSeed();
      await expect(
        basket.contribute([ethers.parseEther("1")], owner.address, 0n)
      ).to.be.revertedWithCustomError(basket, "LengthMismatch");
    });

    it("reverts with ZeroAmount when all amounts are zero", async function () {
      await deployAndSeed();
      await expect(
        basket.contribute([0n, 0n], owner.address, 0n)
      ).to.be.revertedWithCustomError(basket, "ZeroAmount");
    });
  });

  // ---- Withdrawal ----

  describe("Withdrawal", function () {
    it("burns shares, returns proportional constituents, and emits Withdrawn", async function () {
      await deployAndSeed();

      const lpBal = await basket.balanceOf(owner.address);
      const half = lpBal / 2n;
      const minAmounts = [0n, 0n];

      const balABefore = await tokenA.balanceOf(owner.address);
      const balBBefore = await tokenB.balanceOf(owner.address);

      const tx = basket.withdraw(half, owner.address, minAmounts);
      await expect(tx).to.emit(basket, "Withdrawn");

      const balAAfter = await tokenA.balanceOf(owner.address);
      const balBAfter = await tokenB.balanceOf(owner.address);
      expect(balAAfter).to.be.gt(balABefore);
      expect(balBAfter).to.be.gt(balBBefore);
      expect(await basket.balanceOf(owner.address)).to.equal(lpBal - half);
    });

    it("reverts with InsufficientAmount when any returned amount is below minAmounts", async function () {
      await deployAndSeed();

      const lpBal = await basket.balanceOf(owner.address);
      const hugeMin = [ethers.parseEther("999999"), 0n];

      await expect(
        basket.withdraw(lpBal / 2n, owner.address, hugeMin)
      ).to.be.revertedWithCustomError(basket, "InsufficientAmount");
    });

    it("reverts with LengthMismatch when minAmounts length mismatches constituents", async function () {
      await deployAndSeed();
      await expect(
        basket.withdraw(1n, owner.address, [0n])
      ).to.be.revertedWithCustomError(basket, "LengthMismatch");
    });

    it("reverts with ZeroAmount when lpAmount is zero", async function () {
      await deployAndSeed();
      await expect(
        basket.withdraw(0n, owner.address, [0n, 0n])
      ).to.be.revertedWithCustomError(basket, "ZeroAmount");
    });

    it("rounds amounts down (favoring the basket)", async function () {
      await deployAndSeed();

      // Withdraw an amount that creates rounding: 3 shares out of total supply
      const supply = await basket.totalSupply();
      const withdrawShares = 3n;
      const resA = await basket.getReserve(await tokenA.getAddress());
      const resB = await basket.getReserve(await tokenB.getAddress());

      const previewAmounts = await basket.previewWithdraw(withdrawShares);

      // Verify integer division rounds down
      expect(previewAmounts[0]).to.equal((resA * withdrawShares) / supply);
      expect(previewAmounts[1]).to.equal((resB * withdrawShares) / supply);
      // And that rounding means amount * supply <= reserve * shares
      expect(previewAmounts[0] * supply).to.be.lte(resA * withdrawShares);
      expect(previewAmounts[1] * supply).to.be.lte(resB * withdrawShares);
    });
  });

  // ---- Rebalance ----

  describe("Rebalance", function () {
    it("owner can update constituents and emits Rebalanced", async function () {
      await deployAndSeed();

      const newTokens = [await tokenA.getAddress(), await tokenB.getAddress()];
      const newWeights = [7000n, 3000n];

      const tx = basket.rebalance(newTokens, newWeights);
      await expect(tx).to.emit(basket, "Rebalanced").withArgs(newTokens, newWeights);

      expect(await basket.getWeight(newTokens[0])).to.equal(7000n);
      expect(await basket.getWeight(newTokens[1])).to.equal(3000n);
    });

    it("reverts when called by non-owner", async function () {
      await deployAndSeed();

      const tokens = [await tokenA.getAddress(), await tokenB.getAddress()];
      await expect(
        basket.connect(alice).rebalance(tokens, [5000n, 5000n])
      ).to.be.revertedWithCustomError(basket, "Unauthorized");
    });

    it("reverts with InvalidWeights when weights do not sum to 10000", async function () {
      await deployAndSeed();

      const tokens = [await tokenA.getAddress(), await tokenB.getAddress()];
      await expect(
        basket.rebalance(tokens, [5000n, 4000n])
      ).to.be.revertedWithCustomError(basket, "InvalidWeights");
    });

    it("reverts with DuplicateConstituent when newTokens contains duplicates", async function () {
      await deployAndSeed();

      const addr = await tokenA.getAddress();
      await expect(
        basket.rebalance([addr, addr], [5000n, 5000n])
      ).to.be.revertedWithCustomError(basket, "DuplicateConstituent");
    });

    it("reverts with ZeroAddress when any entry is address(0)", async function () {
      await deployAndSeed();

      await expect(
        basket.rebalance([ethers.ZeroAddress, await tokenB.getAddress()], [5000n, 5000n])
      ).to.be.revertedWithCustomError(basket, "ZeroAddress");
    });
  });

  // ---- Preview Functions ----

  describe("Preview Functions", function () {
    it("previewContribute returns values consistent with contribute", async function () {
      await deployAndSeed();

      const amounts = [ethers.parseEther("10"), ethers.parseEther("5")];
      const preview = await basket.previewContribute(amounts);

      await tokenA.transfer(alice.address, amounts[0]);
      await tokenB.transfer(alice.address, amounts[1]);
      await tokenA.connect(alice).approve(await basket.getAddress(), amounts[0]);
      await tokenB.connect(alice).approve(await basket.getAddress(), amounts[1]);

      await basket.connect(alice).contribute(amounts, alice.address, 0n);
      const actual = await basket.balanceOf(alice.address);

      expect(actual).to.equal(preview);
    });

    it("previewWithdraw returns values consistent with withdraw", async function () {
      await deployAndSeed();

      const lpBal = await basket.balanceOf(owner.address);
      const half = lpBal / 2n;
      const preview = await basket.previewWithdraw(half);

      const balABefore = await tokenA.balanceOf(owner.address);
      const balBBefore = await tokenB.balanceOf(owner.address);

      await basket.withdraw(half, owner.address, [0n, 0n]);

      const gotA = (await tokenA.balanceOf(owner.address)) - balABefore;
      const gotB = (await tokenB.balanceOf(owner.address)) - balBBefore;

      expect(gotA).to.equal(preview[0]);
      expect(gotB).to.equal(preview[1]);
    });

    it("previewContribute with zero inputs returns zero", async function () {
      await deployAndSeed();
      expect(await basket.previewContribute([0n, 0n])).to.equal(0n);
    });

    it("previewWithdraw with zero returns zero amounts", async function () {
      await deployAndSeed();
      const amounts = await basket.previewWithdraw(0n);
      expect(amounts[0]).to.equal(0n);
      expect(amounts[1]).to.equal(0n);
    });
  });

  // ---- View Function Edge Cases ----

  describe("View Edge Cases", function () {
    it("getReserve returns zero for non-constituent tokens", async function () {
      await deployAndSeed();
      expect(await basket.getReserve(await tokenC.getAddress())).to.equal(0n);
    });

    it("getWeight reverts with NotConstituent for non-constituent tokens", async function () {
      await deployAndSeed();
      await expect(
        basket.getWeight(await tokenC.getAddress())
      ).to.be.revertedWithCustomError(basket, "NotConstituent");
    });

    it("getConstituents ordering is stable across calls", async function () {
      await deployAndSeed();

      const [tokens1] = await basket.getConstituents();
      const [tokens2] = await basket.getConstituents();

      expect(tokens1[0]).to.equal(tokens2[0]);
      expect(tokens1[1]).to.equal(tokens2[1]);
    });

    it("totalBasketValue is consistent with previewContribute", async function () {
      await deployAndSeed();

      const value = await basket.totalBasketValue();
      // totalBasketValue = sum of reserves
      const resA = await basket.getReserve(await tokenA.getAddress());
      const resB = await basket.getReserve(await tokenB.getAddress());
      expect(value).to.equal(resA + resB);
    });
  });

  // ---- Ownership (ERC-173) ----

  describe("Ownership (ERC-173)", function () {
    it("owner() and transferOwnership() conform to ERC-173", async function () {
      await deployAndSeed();

      expect(await basket.owner()).to.equal(owner.address);

      await basket.transferOwnership(alice.address);
      expect(await basket.owner()).to.equal(alice.address);

      // New owner can rebalance
      const tokens = [await tokenA.getAddress(), await tokenB.getAddress()];
      await expect(
        basket.connect(alice).rebalance(tokens, [5000n, 5000n])
      ).to.emit(basket, "Rebalanced");

      // Old owner cannot
      await expect(
        basket.rebalance(tokens, [5000n, 5000n])
      ).to.be.revertedWithCustomError(basket, "Unauthorized");
    });

    it("ownership renunciation makes rebalance permanently unavailable", async function () {
      await deployAndSeed();

      await basket.transferOwnership(ethers.ZeroAddress);
      expect(await basket.owner()).to.equal(ethers.ZeroAddress);

      const tokens = [await tokenA.getAddress(), await tokenB.getAddress()];
      await expect(
        basket.rebalance(tokens, [5000n, 5000n])
      ).to.be.revertedWithCustomError(basket, "Unauthorized");
    });

    it("emits OwnershipTransferred(address(0), initialOwner) at creation", async function () {
      const tokens = [await tokenA.getAddress()];
      const weights = [10000n];
      const BasketToken = await ethers.getContractFactory("BasketToken");
      const b = await BasketToken.deploy("Test", "T", owner.address, tokens, weights);
      const receipt = await b.deploymentTransaction().wait();

      // Check logs for OwnershipTransferred event
      const iface = b.interface;
      const event = receipt.logs
        .map(log => { try { return iface.parseLog(log); } catch { return null; } })
        .find(e => e && e.name === "OwnershipTransferred");

      expect(event).to.not.be.undefined;
      expect(event.args.previousOwner).to.equal(ethers.ZeroAddress);
      expect(event.args.newOwner).to.equal(owner.address);
    });
  });

  // ---- Initialization ----

  describe("Initialization", function () {
    it("first contribution to empty basket mints shares deterministically", async function () {
      const tokens = [await tokenA.getAddress(), await tokenB.getAddress()];
      const weights = [5000n, 5000n];
      basket = await deployBasket(tokens, weights);

      const amounts = [ethers.parseEther("100"), ethers.parseEther("100")];
      const preview = await basket.previewContribute(amounts);

      await tokenA.approve(await basket.getAddress(), amounts[0]);
      await tokenB.approve(await basket.getAddress(), amounts[1]);
      await basket.contribute(amounts, owner.address, 0n);

      const actual = await basket.balanceOf(owner.address);
      expect(actual).to.equal(preview);

      // Dead shares are minted
      const deadBal = await basket.balanceOf("0x000000000000000000000000000000000000dEaD");
      expect(deadBal).to.equal(DEAD_SHARES);
    });
  });

  // ---- ERC-165 ----

  describe("ERC-165", function () {
    it("reports support for IERC7621 (0xc9c80f73)", async function () {
      await deployAndSeed();
      expect(await basket.supportsInterface("0xc9c80f73")).to.be.true;
    });

    it("reports support for IERC173 (0x7f5828d0)", async function () {
      await deployAndSeed();
      expect(await basket.supportsInterface("0x7f5828d0")).to.be.true;
    });

    it("reports support for IERC165 (0x01ffc9a7)", async function () {
      await deployAndSeed();
      expect(await basket.supportsInterface("0x01ffc9a7")).to.be.true;
    });
  });
});
