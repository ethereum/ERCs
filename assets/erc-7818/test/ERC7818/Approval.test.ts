import { expect } from "chai";
import { deployERC7818 } from "../utils.test";
import {
  ERROR_ERC20_INVALID_APPROVER,
  ERROR_ERC20_INVALID_SPENDER,
  EVENT_APPROVAL,
  EVENT_TRANSFER,
} from "../constant.test";
import { ZeroAddress } from "ethers";

export const run = async () => {
  describe("Approval", async function () {
    it("[SUCCESS] approve correctly", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      await expect(
        erc7818.connect(alice).approve(bob.address, amount)
      )
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, amount);

      expect(
        await erc7818.allowance(
          alice.address,
          bob.address
        )
      ).to.equal(amount);
    });

    it("[SUCCESS] maximum allowance", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});

      const amount = 100;

      const MAX_INT =
        "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      await expect(
        erc7818.connect(alice).approve(bob.address, MAX_INT)
      )
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(alice.address, bob.address, MAX_INT);

      expect(
        await erc7818.allowance(
          alice.address,
          bob.address
        )
      ).to.equal(MAX_INT);
    });

    it("[FAILED] invalid spender", async function () {
      const { erc7818, alice, bob } = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.mint(alice.address, amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZeroAddress, alice.address, amount);

      await expect(erc7818.connect(alice).approve(ZeroAddress, amount))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_SPENDER)
        .withArgs(ZeroAddress);
    });

    it("[FAILED] invalid approver", async function () {
      const { erc7818, alice } = await deployERC7818({});

      const amount = 100;

      await expect(
        erc7818.badApprove(ZeroAddress, alice.address, amount)
      )
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_APPROVER)
        .withArgs(ZeroAddress);
    });
  });
};
