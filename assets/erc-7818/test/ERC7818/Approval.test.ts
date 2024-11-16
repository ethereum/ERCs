import {expect} from "chai";
import {deployERC7818} from "../utils.test";
import {
  ERROR_ERC20_INVALID_APPROVER,
  ERROR_ERC20_INVALID_SPENDER,
  EVENT_APPROVAL,
  EVENT_TRANSFER,
  ZERO_ADDRESS,
} from "../constant.test";

export const run = async () => {
  describe("Approval", async function () {
    it("[HAPPY] approve correctly", async function () {
      const {erc7818, alice, bob} = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.mint(await alice.getAddress(), amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, await alice.getAddress(), amount);

      await expect(erc7818.connect(alice).approve(await bob.getAddress(), amount))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(await alice.getAddress(), await bob.getAddress(), amount);

      expect(await erc7818.allowance(await alice.getAddress(), await bob.getAddress())).to.equal(amount);
    });

    it("[HAPPY] maximum allowance", async function () {
      const {erc7818, alice, bob} = await deployERC7818({});

      const amount = 100;

      const MAX_INT = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";

      await expect(erc7818.mint(await alice.getAddress(), amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, await alice.getAddress(), amount);

      await expect(erc7818.connect(alice).approve(await bob.getAddress(), MAX_INT))
        .to.be.emit(erc7818, EVENT_APPROVAL)
        .withArgs(await alice.getAddress(), await bob.getAddress(), MAX_INT);

      expect(await erc7818.allowance(await alice.getAddress(), await bob.getAddress())).to.equal(MAX_INT);
    });

    it("[UNHAPPY] invalid spender", async function () {
      const {erc7818, alice, bob} = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.mint(await alice.getAddress(), amount))
        .to.be.emit(erc7818, EVENT_TRANSFER)
        .withArgs(ZERO_ADDRESS, await alice.getAddress(), amount);

      await expect(erc7818.connect(alice).approve(ZERO_ADDRESS, amount))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_SPENDER)
        .withArgs(ZERO_ADDRESS);
    });

    it("[UNHAPPY] invalid approver", async function () {
      const {erc7818, alice} = await deployERC7818({});

      const amount = 100;

      await expect(erc7818.badApprove(ZERO_ADDRESS, await alice.getAddress(), amount))
        .to.be.revertedWithCustomError(erc7818, ERROR_ERC20_INVALID_APPROVER)
        .withArgs(ZERO_ADDRESS);
    });
  });
};
