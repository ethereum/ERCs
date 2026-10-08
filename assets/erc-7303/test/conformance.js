import { expect } from "chai";
import hre from "hardhat";
import { loadFixture } from "@nomicfoundation/hardhat-toolbox/network-helpers.js";

const { ethers } = hre;

// The durable expected values of the conformance fixture. Everything below
// is recomputable from the sources in ../contracts and holds on any chain.
const IERC7303_ID = "0x4ee69337";
const ERC165_ID = "0x01ffc9a7";
const INVALID_ID = "0xffffffff";
const MINTER_ROLE = ethers.id("MINTER_ROLE");
const BURNER_ROLE = ethers.id("BURNER_ROLE");
const REVERT_NO_TOKEN = "ERC7303: not has a required token";

async function deployFixture() {
  const [issuer, alice, bob, carol] = await ethers.getSigners();
  const ct721 = await ethers.deployContract("ERC721ControlToken");
  const ct1155 = await ethers.deployContract("ERC1155ControlToken");
  const target = await ethers.deployContract("FixtureTarget", [
    ct721.target,
    ct1155.target,
  ]);
  const legacy = await ethers.deployContract("LegacyTarget", [
    ct721.target,
    ct1155.target,
  ]);
  return { issuer, alice, bob, carol, ct721, ct1155, target, legacy };
}

describe("ERC-7303 conformance fixture", function () {
  describe("interface identifier", function () {
    it("recomputes to 0x4ee69337 from the three IERC7303 selectors", function () {
      const signatures = [
        "hasRole(bytes32,address)",
        "getERC721ControlTokens(bytes32)",
        "getERC1155ControlTokens(bytes32)",
      ];
      let acc = 0n;
      for (const sig of signatures) {
        acc ^= BigInt(ethers.dataSlice(ethers.id(sig), 0, 4));
      }
      expect("0x" + acc.toString(16).padStart(8, "0")).to.equal(IERC7303_ID);
    });

    it("is declared via ERC-165 by the compliant fixture", async function () {
      const { target } = await loadFixture(deployFixture);
      expect(await target.supportsInterface(ERC165_ID)).to.equal(true);
      expect(await target.supportsInterface(IERC7303_ID)).to.equal(true);
      expect(await target.supportsInterface(INVALID_ID)).to.equal(false);
    });
  });

  describe("introspection getters", function () {
    it("enumerates the canonical MINTER_ROLE structure", async function () {
      const { target, ct721, ct1155 } = await loadFixture(deployFixture);
      expect(await target.getERC721ControlTokens(MINTER_ROLE)).to.deep.equal([
        ct721.target,
      ]);
      const [contractIds, typeIds] =
        await target.getERC1155ControlTokens(MINTER_ROLE);
      expect(contractIds).to.deep.equal([ct1155.target]);
      expect(typeIds).to.deep.equal([1n]);
    });

    it("enumerates the canonical BURNER_ROLE structure, including the empty ERC-721 list", async function () {
      const { target, ct1155 } = await loadFixture(deployFixture);
      expect(await target.getERC721ControlTokens(BURNER_ROLE)).to.deep.equal([]);
      const [contractIds, typeIds] =
        await target.getERC1155ControlTokens(BURNER_ROLE);
      expect(contractIds).to.deep.equal([ct1155.target]);
      expect(typeIds).to.deep.equal([2n]);
    });

    it("answers empty lists for an unconfigured role", async function () {
      const { target } = await loadFixture(deployFixture);
      const unknown = ethers.id("UNKNOWN_ROLE");
      expect(await target.getERC721ControlTokens(unknown)).to.deep.equal([]);
      const [contractIds, typeIds] =
        await target.getERC1155ControlTokens(unknown);
      expect(contractIds).to.deep.equal([]);
      expect(typeIds).to.deep.equal([]);
    });
  });

  describe("association events", function () {
    it("emitted one ERC721ControlTokenAdded and two ERC1155ControlTokenAdded at deployment", async function () {
      const { target, ct721, ct1155 } = await loadFixture(deployFixture);

      const erc721Events = await target.queryFilter(
        target.filters.ERC721ControlTokenAdded()
      );
      expect(erc721Events).to.have.lengthOf(1);
      expect(erc721Events[0].args.role).to.equal(MINTER_ROLE);
      expect(erc721Events[0].args.contractId).to.equal(ct721.target);

      const erc1155Events = await target.queryFilter(
        target.filters.ERC1155ControlTokenAdded()
      );
      expect(erc1155Events).to.have.lengthOf(2);
      expect(erc1155Events[0].args.role).to.equal(MINTER_ROLE);
      expect(erc1155Events[0].args.contractId).to.equal(ct1155.target);
      expect(erc1155Events[0].args.typeId).to.equal(1n);
      expect(erc1155Events[1].args.role).to.equal(BURNER_ROLE);
      expect(erc1155Events[1].args.contractId).to.equal(ct1155.target);
      expect(erc1155Events[1].args.typeId).to.equal(2n);
    });
  });

  describe("role lifecycle (grant = mint, check = balanceOf, revoke = burn)", function () {
    it("tracks the ERC-721 control-token balance, including the issuer kill switch", async function () {
      const { target, ct721, alice } = await loadFixture(deployFixture);

      expect(await target.hasRole(MINTER_ROLE, alice.address)).to.equal(false);
      await expect(
        target.connect(alice).safeMint(alice.address, 1)
      ).to.be.revertedWith(REVERT_NO_TOKEN);

      await ct721.mint(alice.address); // tokenId 1
      expect(await target.hasRole(MINTER_ROLE, alice.address)).to.equal(true);
      await target.connect(alice).safeMint(alice.address, 1);
      expect(await target.ownerOf(1)).to.equal(alice.address);

      await ct721.burnByIssuer(1); // revocation needs no holder cooperation
      expect(await target.hasRole(MINTER_ROLE, alice.address)).to.equal(false);
      await expect(
        target.connect(alice).safeMint(alice.address, 2)
      ).to.be.revertedWith(REVERT_NO_TOKEN);
    });

    it("tracks the ERC-1155 control-token balance per typeId", async function () {
      const { target, ct1155, bob } = await loadFixture(deployFixture);

      await ct1155.mint(bob.address, 1, 1); // typeId 1 = MINTER_ROLE only
      expect(await target.hasRole(MINTER_ROLE, bob.address)).to.equal(true);
      expect(await target.hasRole(BURNER_ROLE, bob.address)).to.equal(false);

      await target.connect(bob).safeMint(bob.address, 10);
      await expect(target.connect(bob).burn(10)).to.be.revertedWith(
        REVERT_NO_TOKEN
      );

      await ct1155.mint(bob.address, 2, 1); // typeId 2 = BURNER_ROLE
      expect(await target.hasRole(BURNER_ROLE, bob.address)).to.equal(true);
      await target.connect(bob).burn(10);

      await ct1155.burnByIssuer(bob.address, 2);
      expect(await target.hasRole(BURNER_ROLE, bob.address)).to.equal(false);
    });

    it("requires every stacked role for a doubly-guarded function (AND semantics across modifiers)", async function () {
      const { target, ct721, ct1155, alice, bob, carol } =
        await loadFixture(deployFixture);

      await ct721.mint(alice.address); // MINTER_ROLE only
      await ct1155.mint(bob.address, 2, 1); // BURNER_ROLE only
      await ct1155.mint(carol.address, 1, 1); // MINTER_ROLE...
      await ct1155.mint(carol.address, 2, 1); // ...and BURNER_ROLE

      await target.connect(alice).safeMint(alice.address, 30);
      await expect(
        target.connect(alice).reissue(30, bob.address)
      ).to.be.revertedWith(REVERT_NO_TOKEN);
      await expect(
        target.connect(bob).reissue(30, bob.address)
      ).to.be.revertedWith(REVERT_NO_TOKEN);

      await target.connect(carol).reissue(30, bob.address);
      expect(await target.ownerOf(30)).to.equal(bob.address);

      // Cross-standard AND: alice already holds MINTER_ROLE via the ERC-721
      // control token; granting BURNER_ROLE via the ERC-1155 control token
      // must satisfy the conjunction just as the 1155+1155 pairing does.
      await ct1155.mint(alice.address, 2, 1);
      await target.connect(alice).reissue(30, carol.address);
      expect(await target.ownerOf(30)).to.equal(carol.address);
    });

    it("grants MINTER_ROLE through either control token (OR semantics across entries)", async function () {
      const { target, ct721, ct1155, alice, carol } =
        await loadFixture(deployFixture);

      await ct721.mint(alice.address); // ERC-721 path only
      await ct1155.mint(carol.address, 1, 1); // ERC-1155 path only

      expect(await target.hasRole(MINTER_ROLE, alice.address)).to.equal(true);
      expect(await target.hasRole(MINTER_ROLE, carol.address)).to.equal(true);
      await target.connect(alice).safeMint(alice.address, 21);
      await target.connect(carol).safeMint(carol.address, 22);
    });
  });

  describe("negative case: functionally identical legacy contract", function () {
    it("gates identically but does not declare IERC7303", async function () {
      const { legacy, ct721, alice } = await loadFixture(deployFixture);

      // Same gating behavior as the compliant fixture...
      await expect(
        legacy.connect(alice).safeMint(alice.address, 1)
      ).to.be.revertedWith(REVERT_NO_TOKEN);
      await ct721.mint(alice.address);
      await legacy.connect(alice).safeMint(alice.address, 1);

      // ...but discovery must classify it as NOT implementing this ERC:
      expect(await legacy.supportsInterface(ERC165_ID)).to.equal(true);
      expect(await legacy.supportsInterface(IERC7303_ID)).to.equal(false);
      expect(legacy.interface.getFunction("hasRole(bytes32,address)")).to.equal(
        null
      );
    });
  });
});
