import { ethers } from "hardhat";
import { BigNumber } from "ethers";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ERC20Mock } from "../typechain-types";

const IERC165 = "0x01ffc9a7";
const IRMRKERC20Holder = "0x6f87c75c";
const IOtherInterface = "0xffffffff";

async function tokenHolderFixture() {
  const tokenHolderFactory = await ethers.getContractFactory("ERC7590Mock");
  const tokenHolder = await tokenHolderFactory.deploy(
    "Secure Token Transfer Protocol",
    "STTP"
  );
  await tokenHolder.deployed();

  const erc20Factory = await ethers.getContractFactory("ERC20Mock");
  const erc20A = await erc20Factory.deploy();
  await erc20A.deployed();

  const erc20B = await erc20Factory.deploy();
  await erc20B.deployed();

  return {
    tokenHolder,
    erc20A,
    erc20B,
  };
}

describe("ERC7590", async function () {
  let tokenHolder: RMRKERC20HolderMock;
  let erc20A: ERC20Mock;
  let erc20B: ERC20Mock;
  let holder: SignerWithAddress;
  let otherHolder: SignerWithAddress;
  let addrs: SignerWithAddress[];
  const tokenHolderId = BigNumber.from(1);
  const otherTokenHolderId = BigNumber.from(2);
  const tokenId = BigNumber.from(1);
  const mockValue = ethers.utils.parseEther("10");

  beforeEach(async function () {
    [holder, otherHolder, ...addrs] = await ethers.getSigners();
    ({ tokenHolder, erc20A, erc20B } = await loadFixture(tokenHolderFixture));
  });

  it("can support IERC165", async function () {
    expect(await tokenHolder.supportsInterface(IERC165)).to.equal(true);
  });

  it("can support TokenHolder", async function () {
    expect(await tokenHolder.supportsInterface(IRMRKERC20Holder)).to.equal(
      true
    );
  });

  it("does not support other interfaces", async function () {
    expect(await tokenHolder.supportsInterface(IOtherInterface)).to.equal(
      false
    );
  });

  describe("With minted tokens", async function () {
    beforeEach(async function () {
      await tokenHolder.mint(holder.address, tokenHolderId);
      await tokenHolder.mint(otherHolder.address, otherTokenHolderId);
      await erc20A.mint(holder.address, mockValue);
      await erc20A.mint(otherHolder.address, mockValue);
    });

    it("can receive ERC-20 tokens", async function () {
      await erc20A.approve(tokenHolder.address, mockValue);
      await expect(
        tokenHolder.transferERC20ToToken(
          erc20A.address,
          tokenHolderId,
          mockValue,
          "0x00"
        )
      )
        .to.emit(tokenHolder, "ReceivedERC20")
        .withArgs(erc20A.address, tokenHolderId, holder.address, mockValue);
      expect(await erc20A.balanceOf(tokenHolder.address)).to.equal(mockValue);
    });

    it("can transfer ERC-20 tokens", async function () {
      await erc20A.approve(tokenHolder.address, mockValue);
      await tokenHolder.transferERC20ToToken(
        erc20A.address,
        tokenHolderId,
        mockValue,
        "0x00"
      );
      await expect(
        tokenHolder.transferHeldERC20FromToken(
          erc20A.address,
          tokenHolderId,
          holder.address,
          mockValue.div(2),
          "0x00"
        )
      )
        .to.emit(tokenHolder, "TransferredERC20")
        .withArgs(
          erc20A.address,
          tokenHolderId,
          holder.address,
          mockValue.div(2)
        );
      expect(await erc20A.balanceOf(tokenHolder.address)).to.equal(
        mockValue.div(2)
      );
      expect(await tokenHolder.erc20TransferOutNonce(tokenHolderId)).to.equal(
        1
      );
    });

    it("cannot transfer 0 value", async function () {
      await expect(
        tokenHolder.transferERC20ToToken(erc20A.address, tokenId, 0, "0x00")
      ).to.be.revertedWithCustomError(tokenHolder, "InvalidValue");

      await expect(
        tokenHolder.transferHeldERC20FromToken(
          erc20A.address,
          tokenId,
          holder.address,
          0,
          "0x00"
        )
      ).to.be.revertedWithCustomError(tokenHolder, "InvalidValue");
    });

    it("cannot transfer to address 0", async function () {
      await expect(
        tokenHolder.transferHeldERC20FromToken(
          erc20A.address,
          tokenId,
          ethers.constants.AddressZero,
          1,
          "0x00"
        )
      ).to.be.revertedWithCustomError(tokenHolder, "InvalidAddress");
    });

    it("cannot transfer a token at address 0", async function () {
      await expect(
        tokenHolder.transferHeldERC20FromToken(
          ethers.constants.AddressZero,
          tokenId,
          holder.address,
          1,
          "0x00"
        )
      ).to.be.revertedWithCustomError(tokenHolder, "InvalidAddress");

      await expect(
        tokenHolder.transferERC20ToToken(
          ethers.constants.AddressZero,
          tokenId,
          1,
          "0x00"
        )
      ).to.be.revertedWithCustomError(tokenHolder, "InvalidAddress");
    });

    it("cannot transfer more balance than the token has", async function () {
      await erc20A.approve(tokenHolder.address, mockValue);

      await tokenHolder.transferERC20ToToken(
        erc20A.address,
        tokenId,
        mockValue.div(2),
        "0x00"
      );
      await tokenHolder.transferERC20ToToken(
        erc20A.address,
        otherTokenHolderId,
        mockValue.div(2),
        "0x00"
      );
      await expect(
        tokenHolder.transferHeldERC20FromToken(
          erc20A.address,
          tokenId,
          holder.address,
          mockValue, // The token only owns half of this value
          "0x00"
        )
      ).to.be.revertedWithCustomError(tokenHolder, "InsufficientBalance");
    });

    it("cannot transfer balance from not owned token", async function () {
      await erc20A.approve(tokenHolder.address, mockValue);
      await tokenHolder.transferERC20ToToken(
        erc20A.address,
        tokenHolderId,
        mockValue,
        "0x00"
      );
      // Other holder is not the owner of tokenId
      await expect(
        tokenHolder
          .connect(otherHolder)
          .transferHeldERC20FromToken(
            erc20A.address,
            tokenHolderId,
            otherHolder.address,
            mockValue,
            "0x00"
          )
      ).to.be.revertedWithCustomError(
        tokenHolder,
        "OnlyNFTOwnerCanTransferTokensFromIt"
      );
    });

    it("can manage multiple ERC20s", async function () {
      await erc20B.mint(holder.address, mockValue);
      await erc20A.approve(tokenHolder.address, mockValue);
      await erc20B.approve(tokenHolder.address, mockValue);

      await tokenHolder.transferERC20ToToken(
        erc20A.address,
        tokenHolderId,
        ethers.utils.parseEther("3"),
        "0x00"
      );
      await tokenHolder.transferERC20ToToken(
        erc20B.address,
        tokenHolderId,
        ethers.utils.parseEther("5"),
        "0x00"
      );

      expect(
        await tokenHolder.balanceOfERC20(erc20A.address, tokenHolderId)
      ).to.equal(ethers.utils.parseEther("3"));
      expect(
        await tokenHolder.balanceOfERC20(erc20B.address, tokenHolderId)
      ).to.equal(ethers.utils.parseEther("5"));
    });
  });
});
