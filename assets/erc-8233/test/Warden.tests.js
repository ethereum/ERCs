const { expect } = require("chai")
const { ethers } = require("hardhat")
const { randomBytes, hexlify } = ethers
const {
  currentTime,
  advanceTimeTo,
  mine,
  setAutomine,
  setNextBlockTimestamp,
  snapshot,
  revert,
} = require("./evm")
const { FundStatus } = require("./warden")
const WardenModule = require("../ignition/modules/warden")

describe("Warden", function () {
  const fund = randomBytes(32)

  let token
  let warden
  let controller
  let holder, holder2, holder3

  beforeEach(async function () {
    await snapshot()

    const { warden: _warden, token: _token } = await ignition.deploy(
      WardenModule,
      {},
    )
    warden = _warden
    token = _token
    ;[controller, holder, holder2, holder3] = await ethers.getSigners()
    const tx = await token.mint(await controller.getAddress(), 1_000_000)
    await tx.wait()
  })

  afterEach(async function () {
    await revert()
  })

  describe("account ids", function () {
    let address
    let discriminator

    beforeEach(async function () {
      address = await holder.getAddress()
      discriminator = hexlify(randomBytes(12))
    })

    it("encodes the account holder and a discriminator in an account id", async function () {
      const account = await warden.encodeAccountId(address, discriminator)
      const decoded = await warden.decodeAccountId(account)
      expect(decoded[0]).to.equal(address)
      expect(decoded[1]).to.equal(discriminator)
    })
  })

  describe("when a fund has no lock set", function () {
    let account

    beforeEach(async function () {
      account = await warden.encodeAccountId(
        await holder.getAddress(),
        randomBytes(12),
      )
    })

    it("does not have any balances", async function () {
      const balance = await warden.getBalance(fund, account)
      const designated = await warden.getDesignatedBalance(fund, account)
      expect(balance).to.equal(0)
      expect(designated).to.equal(0)
    })

    it("allows a lock to be set", async function () {
      const expiry = (await currentTime()) + 80
      const maximum = (await currentTime()) + 100
      await warden.lock(fund, expiry, maximum)
      expect(await warden.getFundStatus(fund)).to.equal(FundStatus.Locked)
      expect(await warden.getLockExpiry(fund)).to.equal(expiry)
    })

    it("does not allow a lock with expiry past maximum", async function () {
      let maximum = (await currentTime()) + 100
      const locking = warden.lock(fund, maximum + 1, maximum)
      await expect(locking).to.be.revertedWithCustomError(
        warden,
        "WardenInvalidExpiry",
      )
    })

    describe("fund is not locked", function () {
      testFundThatIsNotLocked()
    })
  })

  describe("when a fund is locked", function () {
    let expiry
    let maximum
    let account

    beforeEach(async function () {
      const beginning = (await currentTime()) + 10
      expiry = beginning + 80
      maximum = beginning + 100
      account = await warden.encodeAccountId(
        await holder.getAddress(),
        randomBytes(12),
      )
      await setAutomine(false)
      await setNextBlockTimestamp(beginning)
      await warden.lock(fund, expiry, maximum)
    })

    describe("locking", function () {
      beforeEach(async function () {
        await setAutomine(true)
      })

      it("cannot set lock when already locked", async function () {
        await expect(
          warden.lock(fund, expiry, maximum),
        ).to.be.revertedWithCustomError(warden, "WardenFundAlreadyLocked")
      })

      it("can extend a lock expiry up to its maximum", async function () {
        await warden.extendLock(fund, expiry + 1)
        expect(await warden.getLockExpiry(fund)).to.equal(expiry + 1)
        await warden.extendLock(fund, maximum)
        expect(await warden.getLockExpiry(fund)).to.equal(maximum)
      })

      it("cannot extend a lock past its maximum", async function () {
        const extending = warden.extendLock(fund, maximum + 1)
        await expect(extending).to.be.revertedWithCustomError(
          warden,
          "WardenInvalidExpiry",
        )
      })

      it("cannot move expiry to an earlier time", async function () {
        const extending = warden.extendLock(fund, expiry - 1)
        await expect(extending).to.be.revertedWithCustomError(
          warden,
          "WardenInvalidExpiry",
        )
      })

      it("does not delete lock when no tokens remain", async function () {
        await token.connect(controller).approve(await warden.getAddress(), 30)
        await warden.deposit(fund, account, 30)
        await warden.burnAccount(fund, account)
        expect(await warden.getFundStatus(fund)).to.equal(FundStatus.Locked)
        expect(await warden.getLockExpiry(fund)).to.not.equal(0)
      })
    })

    describe("depositing", function () {
      const amount = 1000

      let account

      beforeEach(async function () {
        account = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        await setAutomine(true)
      })

      it("accepts deposits of tokens", async function () {
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account, amount)
        const balance = await warden.getBalance(fund, account)
        expect(balance).to.equal(amount)
      })

      it("keeps custody of tokens that are deposited", async function () {
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account, amount)
        expect(await token.balanceOf(await warden.getAddress())).to.equal(amount)
      })

      it("deposit fails when tokens cannot be transferred", async function () {
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount - 1)
        const depositing = warden.deposit(fund, account, amount)
        await expect(depositing).to.be.revertedWithCustomError(
          token,
          "ERC20InsufficientAllowance",
        )
      })

      it("adds multiple deposits to the balance", async function () {
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account, amount / 2)
        await warden.deposit(fund, account, amount / 2)
        const balance = await warden.getBalance(fund, account)
        expect(balance).to.equal(amount)
      })

      it("separates deposits from different accounts with the same holder", async function () {
        const address = await holder.getAddress()
        const account1 = await warden.encodeAccountId(address, randomBytes(12))
        const account2 = await warden.encodeAccountId(address, randomBytes(12))
        await token.connect(controller).approve(await warden.getAddress(), 3)
        await warden.deposit(fund, account1, 1)
        await warden.deposit(fund, account2, 2)
        expect(await warden.getBalance(fund, account1)).to.equal(1)
        expect(await warden.getBalance(fund, account2)).to.equal(2)
      })

      it("separates deposits from different funds", async function () {
        const fund1 = randomBytes(32)
        const fund2 = randomBytes(32)
        await warden.lock(fund1, expiry, maximum)
        await warden.lock(fund2, expiry, maximum)
        await token.connect(controller).approve(await warden.getAddress(), 3)
        await warden.deposit(fund1, account, 1)
        await warden.deposit(fund2, account, 2)
        expect(await warden.getBalance(fund1, account)).to.equal(1)
        expect(await warden.getBalance(fund2, account)).to.equal(2)
      })

      it("separates deposits from different controllers", async function () {
        const controller1 = holder2
        const controller2 = holder3
        const warden1 = warden.connect(controller1)
        const warden2 = warden.connect(controller2)
        await warden1.lock(fund, expiry, maximum)
        await warden2.lock(fund, expiry, maximum)
        await token.mint(await controller1.getAddress(), 1000)
        await token.mint(await controller2.getAddress(), 1000)
        await token.connect(controller1).approve(await warden.getAddress(), 1)
        await token.connect(controller2).approve(await warden.getAddress(), 2)
        await warden1.deposit(fund, account, 1)
        await warden2.deposit(fund, account, 2)
        expect(await warden1.getBalance(fund, account)).to.equal(1)
        expect(await warden2.getBalance(fund, account)).to.equal(2)
      })
    })

    describe("designating", function () {
      const amount = 1000

      let account, account2

      beforeEach(async function () {
        account = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        account2 = await warden.encodeAccountId(
          await holder2.getAddress(),
          randomBytes(12),
        )
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account, amount)
      })

      it("can designate tokens for the account holder", async function () {
        await setAutomine(true)
        await warden.designate(fund, account, amount)
        expect(await warden.getDesignatedBalance(fund, account)).to.equal(amount)
      })

      it("can designate part of the balance", async function () {
        await setAutomine(true)
        await warden.designate(fund, account, 10)
        expect(await warden.getDesignatedBalance(fund, account)).to.equal(10)
      })

      it("adds up designated tokens", async function () {
        await setAutomine(true)
        await warden.designate(fund, account, 10)
        await warden.designate(fund, account, 10)
        expect(await warden.getDesignatedBalance(fund, account)).to.equal(20)
      })

      it("does not change the balance", async function () {
        await setAutomine(true)
        await warden.designate(fund, account, 10)
        expect(await warden.getBalance(fund, account)).to.equal(amount)
      })

      it("cannot designate more than the undesignated balance", async function () {
        await setAutomine(true)
        await warden.designate(fund, account, amount)
        await expect(
          warden.designate(fund, account, 1),
        ).to.be.revertedWithCustomError(warden, "WardenInsufficientBalance")
      })

    })

    describe("transfering", function () {
      const amount = 1000

      let account1, account2, account3

      beforeEach(async function () {
        account1 = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        account2 = await warden.encodeAccountId(
          await holder2.getAddress(),
          randomBytes(12),
        )
        account3 = await warden.encodeAccountId(
          await holder3.getAddress(),
          randomBytes(12),
        )
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account1, amount)
      })

      it("can transfer tokens from one recipient to the other", async function () {
        await setAutomine(true)
        await warden.transfer(fund, account1, account2, amount)
        expect(await warden.getBalance(fund, account1)).to.equal(0)
        expect(await warden.getBalance(fund, account2)).to.equal(amount)
      })

      it("can transfer part of a balance", async function () {
        await setAutomine(true)
        await warden.transfer(fund, account1, account2, 10)
        expect(await warden.getBalance(fund, account1)).to.equal(amount - 10)
        expect(await warden.getBalance(fund, account2)).to.equal(10)
      })

      it("can transfer out funds that were transfered in", async function () {
        await setAutomine(true)
        await warden.transfer(fund, account1, account2, amount)
        await warden.transfer(fund, account2, account3, amount)
        expect(await warden.getBalance(fund, account2)).to.equal(0)
        expect(await warden.getBalance(fund, account3)).to.equal(amount)
      })

      it("can transfer to self", async function () {
        await setAutomine(true)
        await warden.transfer(fund, account1, account1, amount)
        expect(await warden.getBalance(fund, account1)).to.equal(amount)
      })

      it("does not transfer more than the balance", async function () {
        await setAutomine(true)
        await expect(
          warden.transfer(fund, account1, account2, amount + 1),
        ).to.be.revertedWithCustomError(warden, "WardenInsufficientBalance")
      })

      it("does not transfer designated tokens", async function () {
        await setAutomine(true)
        await warden.designate(fund, account1, 1)
        await expect(
          warden.transfer(fund, account1, account2, amount),
        ).to.be.revertedWithCustomError(warden, "WardenInsufficientBalance")
      })
    })

    describe("burning", function () {
      const dead = "0x000000000000000000000000000000000000dead"
      const amount = 1000

      let account1, account2, account3

      beforeEach(async function () {
        account1 = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        account2 = await warden.encodeAccountId(
          await holder2.getAddress(),
          randomBytes(12),
        )
        account3 = await warden.encodeAccountId(
          await holder3.getAddress(),
          randomBytes(12),
        )
        await setAutomine(true)
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account1, amount)
      })

      describe("burn designated", function () {
        const designated = 100

        beforeEach(async function () {
          await warden.designate(fund, account1, designated)
        })

        it("burns a number of designated tokens", async function () {
          await warden.burnDesignated(fund, account1, 10)
          expect(await warden.getDesignatedBalance(fund, account1)).to.equal(
            designated - 10,
          )
          expect(await warden.getBalance(fund, account1)).to.equal(amount - 10)
        })

        it("can burn all of the designated tokens", async function () {
          await warden.burnDesignated(fund, account1, designated)
          expect(await warden.getDesignatedBalance(fund, account1)).to.equal(0)
          expect(await warden.getBalance(fund, account1)).to.equal(
            amount - designated,
          )
        })

        it("moves burned tokens to address 0xdead", async function () {
          const before = await token.balanceOf(dead)
          await warden.burnDesignated(fund, account1, 10)
          const after = await token.balanceOf(dead)
          expect(after - before).to.equal(10)
        })

        it("cannot burn more than all designated tokens", async function () {
          await expect(
            warden.burnDesignated(fund, account1, designated + 1),
          ).to.be.revertedWithCustomError(warden, "WardenInsufficientBalance")
        })
      })

      describe("burn account", function () {
        it("can burn an account", async function () {
          await warden.burnAccount(fund, account1)
          expect(await warden.getBalance(fund, account1)).to.equal(0)
        })

        it("also burns the designated tokens", async function () {
          await warden.designate(fund, account1, 10)
          await warden.burnAccount(fund, account1)
          expect(await warden.getDesignatedBalance(fund, account1)).to.equal(0)
        })

        it("moves account tokens to address 0xdead", async function () {
          await warden.designate(fund, account1, 10)
          const before = await token.balanceOf(dead)
          await warden.burnAccount(fund, account1)
          const after = await token.balanceOf(dead)
          expect(after - before).to.equal(amount)
        })

        it("does not burn tokens from other accounts with the same holder", async function () {
          const account1a = await warden.encodeAccountId(
            await holder.getAddress(),
            randomBytes(12),
          )
          await warden.transfer(fund, account1, account1a, 10)
          await warden.burnAccount(fund, account1)
          expect(await warden.getBalance(fund, account1a)).to.equal(10)
        })

      })
    })

    describe("sealing", function () {
      const deposit = 1000

      let account1, account2, account3

      beforeEach(async function () {
        account1 = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        account2 = await warden.encodeAccountId(
          await holder2.getAddress(),
          randomBytes(12),
        )
        account3 = await warden.encodeAccountId(
          await holder3.getAddress(),
          randomBytes(12),
        )
        await token.approve(await warden.getAddress(), deposit)
        await warden.deposit(fund, account1, deposit)
      })

      it("can seal a fund", async function () {
        await setAutomine(true)
        await warden.sealFund(fund)
        expect(await warden.getFundStatus(fund)).to.equal(FundStatus.Sealed)
      })

    })

    describe("withdrawing", function () {
      const amount = 1000

      let account1, account2

      beforeEach(async function () {
        account1 = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        account2 = await warden.encodeAccountId(
          await holder2.getAddress(),
          randomBytes(12),
        )
        await setAutomine(true)
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account1, amount)
      })

      it("does not allow withdrawal before lock expires", async function () {
        await setNextBlockTimestamp(expiry - 1)
        const withdrawing = warden.withdraw(fund, account1)
        await expect(withdrawing).to.be.revertedWithCustomError(
          warden,
          "WardenFundNotUnlocked",
        )
      })

      it("disallows withdrawal for everyone in the fund", async function () {
        await warden.transfer(fund, account1, account2, amount / 2)
        let withdrawing1 = warden.withdraw(fund, account1)
        let withdrawing2 = warden.withdraw(fund, account2)
        await expect(withdrawing1).to.be.revertedWithCustomError(
          warden,
          "WardenFundNotUnlocked",
        )
        await expect(withdrawing2).to.be.revertedWithCustomError(
          warden,
          "WardenFundNotUnlocked",
        )
      })
    })
  })

  describe("when a fund lock is expiring", function () {
    let expiry
    let maximum
    let account1, account2, account3

    beforeEach(async function () {
      const beginning = (await currentTime()) + 10
      expiry = beginning + 80
      maximum = beginning + 100
      account1 = await warden.encodeAccountId(
        await holder.getAddress(),
        randomBytes(12),
      )
      account2 = await warden.encodeAccountId(
        await holder2.getAddress(),
        randomBytes(12),
      )
      account3 = await warden.encodeAccountId(
        await holder3.getAddress(),
        randomBytes(12),
      )
      await setAutomine(false)
      await setNextBlockTimestamp(beginning)
      await warden.lock(fund, expiry, maximum)
    })

    async function expire() {
      await setNextBlockTimestamp(expiry)
    }

    it("unlocks the funds", async function () {
      await mine()
      expect(await warden.getFundStatus(fund)).to.equal(FundStatus.Locked)
      await expire()
      await mine()
      expect(await warden.getFundStatus(fund)).to.equal(FundStatus.Withdrawing)
    })

    describe("locking", function () {
      beforeEach(async function () {
        await setAutomine(true)
      })

      it("cannot set lock when lock expired", async function () {
        await expire()
        const locking = warden.lock(fund, expiry, maximum)
        await expect(locking).to.be.revertedWithCustomError(
          warden,
          "WardenFundAlreadyLocked",
        )
      })

      it("cannot set lock when no tokens remain", async function () {
        await token.connect(controller).approve(await warden.getAddress(), 30)
        await warden.deposit(fund, account1, 30)
        await expire()
        await warden.withdraw(fund, account1)
        const locking = warden.lock(fund, expiry, maximum)
        await expect(locking).to.be.revertedWithCustomError(
          warden,
          "WardenFundAlreadyLocked",
        )
      })
    })

    describe("withdrawing", function () {
      const amount = 1000

      beforeEach(async function () {
        setAutomine(true)
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account1, amount)
        await token
          .connect(controller)
          .approve(await warden.getAddress(), amount)
        await warden.deposit(fund, account2, amount)
      })

      it("allows controller to withdraw for a recipient", async function () {
        await expire()
        const before = await token.balanceOf(await holder.getAddress())
        await warden.withdraw(fund, account1)
        const after = await token.balanceOf(await holder.getAddress())
        expect(after - before).to.equal(amount)
      })

      it("allows account holder to withdraw for itself", async function () {
        await expire()
        const before = await token.balanceOf(await holder.getAddress())
        await warden
          .connect(holder)
          .withdrawByRecipient(await controller.getAddress(), fund, account1)
        const after = await token.balanceOf(await holder.getAddress())
        expect(after - before).to.equal(amount)
      })

      it("does not allow anyone else to withdraw for the account holder", async function () {
        await expire()
        await expect(
          warden
            .connect(holder2)
            .withdrawByRecipient(await controller.getAddress(), fund, account1),
        ).to.be.revertedWithCustomError(warden, "WardenOnlyAccountHolder")
      })

      it("empties the balance when withdrawing", async function () {
        await expire()
        await warden.withdraw(fund, account1)
        expect(await warden.getBalance(fund, account1)).to.equal(0)
      })

      it("does not withdraw other accounts from the same holder", async function () {
        const account1a = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        await warden.transfer(fund, account1, account1a, 10)
        await expire()
        await warden.withdraw(fund, account1)
        expect(await warden.getBalance(fund, account1a)).to.equal(10)
      })

      it("allows designated tokens to be withdrawn", async function () {
        await warden.designate(fund, account1, 10)
        await expire()
        const before = await token.balanceOf(await holder.getAddress())
        await warden.withdraw(fund, account1)
        const after = await token.balanceOf(await holder.getAddress())
        expect(after - before).to.equal(amount)
      })

      it("does not withdraw designated tokens more than once", async function () {
        await warden.designate(fund, account1, 10)
        await expire()
        await warden.withdraw(fund, account1)
        const before = await token.balanceOf(await holder.getAddress())
        await warden.withdraw(fund, account1)
        const after = await token.balanceOf(await holder.getAddress())
        expect(after).to.equal(before)
      })

      it("can withdraw funds that were transfered in", async function () {
        await warden.transfer(fund, account1, account3, amount)
        await expire()
        const before = await token.balanceOf(await holder3.getAddress())
        await warden.withdraw(fund, account3)
        const after = await token.balanceOf(await holder3.getAddress())
        expect(after - before).to.equal(amount)
      })

      it("cannot withdraw funds that were transfered out", async function () {
        await warden.transfer(fund, account1, account3, amount)
        await expire()
        const before = await token.balanceOf(await holder.getAddress())
        await warden.withdraw(fund, account1)
        const after = await token.balanceOf(await holder.getAddress())
        expect(after).to.equal(before)
      })

      it("cannot withdraw more than once", async function () {
        await expire()
        await warden.withdraw(fund, account1)
        const before = await token.balanceOf(await holder.getAddress())
        await warden.withdraw(fund, account1)
        const after = await token.balanceOf(await holder.getAddress())
        expect(after).to.equal(before)
      })

      it("cannot withdraw burned tokens", async function () {
        await warden.burnAccount(fund, account1)
        await expire()
        const before = await token.balanceOf(await holder.getAddress())
        await warden.withdraw(fund, account1)
        const after = await token.balanceOf(await holder.getAddress())
        expect(after).to.equal(before)
      })
    })

    describe("fund is not locked", function () {
      beforeEach(async function () {
        setAutomine(true)
        await expire()
      })

      testFundThatIsNotLocked()
    })
  })

  describe("when a fund is sealed", function () {
    const amount = 1000

    let expiry
    let account

    beforeEach(async function () {
      expiry = (await currentTime()) + 100
      account = await warden.encodeAccountId(
        await holder.getAddress(),
        randomBytes(12),
      )
      await token.connect(controller).approve(await warden.getAddress(), amount)
      await warden.lock(fund, expiry, expiry)
      await warden.deposit(fund, account, amount)
      await warden.sealFund(fund)
    })

    it("does not allow setting a lock", async function () {
      const locking = warden.lock(fund, expiry, expiry)
      await expect(locking).to.be.revertedWithCustomError(
        warden,
        "WardenFundAlreadyLocked",
      )
    })

    it("does not allow withdrawal", async function () {
      const withdrawing = warden.withdraw(fund, account)
      await expect(withdrawing).to.be.revertedWithCustomError(
        warden,
        "WardenFundNotUnlocked",
      )
    })

    it("unlocks when the lock expires", async function () {
      await advanceTimeTo(expiry)
      expect(await warden.getFundStatus(fund)).to.equal(FundStatus.Withdrawing)
    })

    testFundThatIsNotLocked()
  })

  function testFundThatIsNotLocked() {
    let account, account2

    beforeEach(async function () {
      account = await warden.encodeAccountId(
        await holder.getAddress(),
        randomBytes(12),
      )
      account2 = await warden.encodeAccountId(
        await holder2.getAddress(),
        randomBytes(12),
      )
    })

    it("does not allow extending of lock", async function () {
      await expect(
        warden.extendLock(fund, (await currentTime()) + 1),
      ).to.be.revertedWithCustomError(warden, "WardenFundNotLocked")
    })

    it("does not allow depositing of tokens", async function () {
      const amount = 1000
      await token.connect(controller).approve(await warden.getAddress(), amount)
      await expect(
        warden.deposit(fund, account, amount),
      ).to.be.revertedWithCustomError(warden, "WardenFundNotLocked")
    })

    it("does not allow designating tokens", async function () {
      await expect(
        warden.designate(fund, account, 0),
      ).to.be.revertedWithCustomError(warden, "WardenFundNotLocked")
    })

    it("does not allow transfer of tokens", async function () {
      await expect(
        warden.transfer(fund, account, account2, 0),
      ).to.be.revertedWithCustomError(warden, "WardenFundNotLocked")
    })

    it("does not allow burning of designated tokens", async function () {
      await expect(
        warden.burnDesignated(fund, account, 1),
      ).to.be.revertedWithCustomError(warden, "WardenFundNotLocked")
    })

    it("does not allow burning of accounts", async function () {
      await expect(
        warden.burnAccount(fund, account),
      ).to.be.revertedWithCustomError(warden, "WardenFundNotLocked")
    })

    it("does not allow sealing of a fund", async function () {
      await expect(warden.sealFund(fund)).to.be.revertedWithCustomError(
        warden,
        "WardenFundNotLocked",
      )
    })
  }

  describe("pausing", function () {
    let owner
    let owner2
    let other

    beforeEach(async function () {
      ;[owner, owner2, other] = await ethers.getSigners()
    })

    it("allows the warden to be paused by the owner", async function () {
      await expect(warden.connect(owner).pause()).not.to.be.reverted
    })

    it("allows the warden to be unpaused by the owner", async function () {
      await warden.connect(owner).pause()
      await expect(warden.connect(owner).unpause()).not.to.be.reverted
    })

    it("does not allow pause to be called by others", async function () {
      await expect(warden.connect(other).pause()).to.be.revertedWithCustomError(
        warden,
        "OwnableUnauthorizedAccount",
      )
    })

    it("does not allow unpause to be called by others", async function () {
      await warden.connect(owner).pause()
      await expect(
        warden.connect(other).unpause(),
      ).to.be.revertedWithCustomError(warden, "OwnableUnauthorizedAccount")
    })

    it("allows the ownership to change", async function () {
      await warden.connect(owner).pause()
      await warden.connect(owner).transferOwnership(await owner2.getAddress())
      await expect(warden.connect(owner2).unpause()).not.to.be.reverted
    })

    it("allows the ownership to be renounced", async function () {
      await warden.connect(owner).renounceOwnership()
      await expect(warden.connect(owner).pause()).to.be.revertedWithCustomError(
        warden,
        "OwnableUnauthorizedAccount",
      )
    })

    describe("when the warden is paused", function () {
      let expiry
      let maximum
      let account1, account2

      beforeEach(async function () {
        expiry = (await currentTime()) + 80
        maximum = (await currentTime()) + 100
        account1 = await warden.encodeAccountId(
          await holder.getAddress(),
          randomBytes(12),
        )
        account2 = await warden.encodeAccountId(
          await holder2.getAddress(),
          randomBytes(12),
        )
        await warden.lock(fund, expiry, maximum)
        await token.approve(await warden.getAddress(), 1000)
        await warden.deposit(fund, account1, 1000)
        await warden.designate(fund, account1, 100)
        await warden.connect(owner).pause()
      })

      it("only allows a recipient to withdraw itself", async function () {
        await advanceTimeTo(expiry)
        await expect(
          warden
            .connect(holder)
            .withdrawByRecipient(await controller.getAddress(), fund, account1),
        ).not.to.be.reverted
      })

      it("does not allow funds to be locked", async function () {
        const fund = randomBytes(32)
        const expiry = (await currentTime()) + 100
        await expect(
          warden.lock(fund, expiry, expiry),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })

      it("does not allow extending of lock", async function () {
        await expect(
          warden.extendLock(fund, maximum),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })

      it("does not allow depositing of tokens", async function () {
        await token.approve(await warden.getAddress(), 100)
        await expect(
          warden.deposit(fund, account1, 100),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })

      it("does not allow designating tokens", async function () {
        await expect(
          warden.designate(fund, account1, 10),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })

      it("does not allow transfer of tokens", async function () {
        await expect(
          warden.transfer(fund, account1, account2, 10),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })

      it("does not allow burning of designated tokens", async function () {
        await expect(
          warden.burnDesignated(fund, account1, 10),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })

      it("does not allow burning of accounts", async function () {
        await expect(
          warden.burnAccount(fund, account1),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })

      it("does not allow sealing of funds", async function () {
        await expect(warden.sealFund(fund)).to.be.revertedWithCustomError(
          warden,
          "EnforcedPause",
        )
      })

      it("does not allow a controller to withdraw for a recipient", async function () {
        await advanceTimeTo(expiry)
        await expect(
          warden.withdraw(fund, account1),
        ).to.be.revertedWithCustomError(warden, "EnforcedPause")
      })
    })
  })

})
