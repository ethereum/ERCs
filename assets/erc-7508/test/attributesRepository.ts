import { ethers } from "hardhat";
import { expect } from "chai";
import { loadFixture, mine } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  OwnableMintableERC721Mock,
  AttributesRepository,
} from "../../typechain-types";

const IERC165 = "0x01ffc9a7";
const IERC7508 = "0x62ee8e7a";

// --------------- FIXTURES -----------------------

enum AccessType {
  Issuer,
  Collaborator,
  IssuerOrCollaborator,
  TokenOwner,
  SpecificAddress,
}

async function tokenAttributesFixture() {
  const factory = await ethers.getContractFactory("AttributesRepository");
  const tokenAttributes = await factory.deploy();
  await tokenAttributes.waitForDeployment();

  return tokenAttributes;
}

async function ownedCollectionFixture() {
  const factory = await ethers.getContractFactory("OwnableMintableERC721Mock");
  const [owner, ownerOf] = await ethers.getSigners();
  const ownedCollection = await factory.deploy(owner, ownerOf);
  await ownedCollection.waitForDeployment();

  return ownedCollection;
}

// --------------- TESTS -----------------------

describe("AttributesRepository", async function () {
  let tokenAttributes: AttributesRepository;
  let ownedCollection: OwnableMintableERC721Mock;
  let collectionOwner: SignerWithAddress;
  let tokenOwner: SignerWithAddress;
  let collaborator: SignerWithAddress;
  let collectionAddress: string;
  const tokenId = 1n;
  const tokenId2 = 2n;

  beforeEach(async function () {
    tokenAttributes = await loadFixture(tokenAttributesFixture);
    ownedCollection = await loadFixture(ownedCollectionFixture);
    collectionAddress = await ownedCollection.getAddress();
    [collectionOwner, tokenOwner, collaborator] = await ethers.getSigners();

    this.tokenAttributes = tokenAttributes;
    this.ownedCollection = ownedCollection;
  });

  shouldBehaveLikeAttributesRepositoryInterface();

  describe("Registering attributes and setting values", async function () {
    beforeEach(async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );
    });

    it("can set and get token attributes", async function () {
      expect(
        await tokenAttributes.setStringAttribute(
          collectionAddress,
          tokenId,
          "description",
          "test description"
        )
      )
        .to.emit(tokenAttributes, "StringAttributeSet")
        .withArgs(
          collectionAddress,
          tokenId,
          "description",
          "test description"
        );
      expect(
        await tokenAttributes.setStringAttribute(
          collectionAddress,
          tokenId,
          "description1",
          "test description"
        )
      )
        .to.emit(tokenAttributes, "StringAttributeSet")
        .withArgs(
          collectionAddress,
          tokenId,
          "description1",
          "test description"
        );
      expect(
        await tokenAttributes.setBoolAttribute(
          collectionAddress,
          tokenId,
          "rare",
          true
        )
      )
        .to.emit(tokenAttributes, "BoolAttributeSet")
        .withArgs(collectionAddress, tokenId, "rare", true);
      expect(
        await tokenAttributes.setAddressAttribute(
          collectionAddress,
          tokenId,
          "owner",
          tokenOwner.address
        )
      )
        .to.emit(tokenAttributes, "AddressAttributeSet")
        .withArgs(collectionAddress, tokenId, "owner", tokenOwner.address);
      expect(
        await tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "atk",
          100n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeSet")
        .withArgs(collectionAddress, tokenId, "atk", 100n);
      expect(
        await tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "health",
          100n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeSet")
        .withArgs(collectionAddress, tokenId, "health", 100n);
      expect(
        await tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "health",
          95n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeSet")
        .withArgs(collectionAddress, tokenId, "health", 95n);
      expect(
        await tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "health",
          80n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeSet")
        .withArgs(collectionAddress, tokenId, "health", 80n);
      expect(
        await tokenAttributes.setBytesAttribute(
          collectionAddress,
          tokenId,
          "data",
          "0x1234"
        )
      )
        .to.emit(tokenAttributes, "BytesAttributeSet")
        .withArgs(collectionAddress, tokenId, "data", "0x1234");

      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId,
          "description"
        )
      ).to.eql("test description");
      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId,
          "description1"
        )
      ).to.eql("test description");
      expect(
        await tokenAttributes.getBoolAttribute(
          collectionAddress,
          tokenId,
          "rare"
        )
      ).to.eql(true);
      expect(
        await tokenAttributes.getAddressAttribute(
          collectionAddress,
          tokenId,
          "owner"
        )
      ).to.eql(tokenOwner.address);
      expect(
        await tokenAttributes.getUintAttribute(
          collectionAddress,
          tokenId,
          "atk"
        )
      ).to.eql(100n);
      expect(
        await tokenAttributes.getUintAttribute(
          collectionAddress,
          tokenId,
          "health"
        )
      ).to.eql(80n);
      expect(
        await tokenAttributes.getBytesAttribute(
          collectionAddress,
          tokenId,
          "data"
        )
      ).to.eql("0x1234");

      await tokenAttributes.setStringAttribute(
        collectionAddress,
        tokenId,
        "description",
        "test description update"
      );
      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId,
          "description"
        )
      ).to.eql("test description update");
    });

    it("can set multiple attributes of multiple types at the same time", async function () {
      await expect(
        tokenAttributes.setAttributes(
          collectionAddress,
          tokenId,
          [
            { key: "string1", value: "value1" },
            { key: "string2", value: "value2" },
          ],
          [
            { key: "uint1", value: 1n },
            { key: "uint2", value: 2n },
          ],
          [
            { key: "bool1", value: true },
            { key: "bool2", value: false },
          ],
          [
            { key: "address1", value: tokenOwner.address },
            { key: "address2", value: await collectionOwner.getAddress() },
          ],
          [
            { key: "bytes1", value: "0x1234" },
            { key: "bytes2", value: "0x5678" },
          ]
        )
      )
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string1", "value1")
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string2", "value2")
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint1", 1n)
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint2", 2n)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool1", true)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool2", false)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(
          collectionAddress,
          tokenId,
          "address2",
          await collectionOwner.getAddress()
        )
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes2", "0x5678");
    });

    it("can update multiple attributes of multiple types at the same time", async function () {
      await tokenAttributes.setAttributes(
        collectionAddress,
        tokenId,
        [
          { key: "string1", value: "value0" },
          { key: "string2", value: "value1" },
        ],
        [
          { key: "uint1", value: 0n },
          { key: "uint2", value: 1n },
        ],
        [
          { key: "bool1", value: false },
          { key: "bool2", value: true },
        ],
        [
          { key: "address1", value: await collectionOwner.getAddress() },
          { key: "address2", value: tokenOwner.address },
        ],
        [
          { key: "bytes1", value: "0x5678" },
          { key: "bytes2", value: "0x1234" },
        ]
      );

      await expect(
        tokenAttributes.setAttributes(
          collectionAddress,
          tokenId,
          [
            { key: "string1", value: "value1" },
            { key: "string2", value: "value2" },
          ],
          [
            { key: "uint1", value: 1n },
            { key: "uint2", value: 2n },
          ],
          [
            { key: "bool1", value: true },
            { key: "bool2", value: false },
          ],
          [
            { key: "address1", value: tokenOwner.address },
            { key: "address2", value: await collectionOwner.getAddress() },
          ],
          [
            { key: "bytes1", value: "0x1234" },
            { key: "bytes2", value: "0x5678" },
          ]
        )
      )
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string1", "value1")
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string2", "value2")
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint1", 1n)
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint2", 2n)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool1", true)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool2", false)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(
          collectionAddress,
          tokenId,
          "address2",
          await collectionOwner.getAddress()
        )
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes2", "0x5678");
    });

    it("can set and update multiple attributes of multiple types at the same time even if not all types are updated at the same time", async function () {
      await tokenAttributes.setAttributes(
        collectionAddress,
        tokenId,
        [{ key: "string1", value: "value0" }],
        [
          { key: "uint1", value: 0n },
          { key: "uint2", value: 1n },
        ],
        [
          { key: "bool1", value: false },
          { key: "bool2", value: true },
        ],
        [
          { key: "address1", value: await collectionOwner.getAddress() },
          { key: "address2", value: tokenOwner.address },
        ],
        []
      );

      await expect(
        tokenAttributes.setAttributes(
          collectionAddress,
          tokenId,
          [],
          [
            { key: "uint1", value: 1n },
            { key: "uint2", value: 2n },
          ],
          [
            { key: "bool1", value: true },
            { key: "bool2", value: false },
          ],
          [
            { key: "address1", value: tokenOwner.address },
            { key: "address2", value: await collectionOwner.getAddress() },
          ],
          [
            { key: "bytes1", value: "0x1234" },
            { key: "bytes2", value: "0x5678" },
          ]
        )
      )
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint1", 1n)
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint2", 2n)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool1", true)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool2", false)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(
          collectionAddress,
          tokenId,
          "address2",
          await collectionOwner.getAddress()
        )
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes2", "0x5678");

      await expect(
        tokenAttributes.setAttributes(
          collectionAddress,
          tokenId,
          [],
          [],
          [
            { key: "bool1", value: false },
            { key: "bool2", value: true },
          ],
          [],
          []
        )
      )
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool1", false)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool2", true);
    });

    it("can set and update multiple attributes of multiple types at the same time", async function () {
      await expect(
        tokenAttributes.setAttributes(
          collectionAddress,
          tokenId,
          [
            { key: "string1", value: "value1" },
            { key: "string2", value: "value2" },
          ],
          [
            { key: "uint1", value: 1n },
            { key: "uint2", value: 2n },
          ],
          [
            { key: "bool1", value: true },
            { key: "bool2", value: false },
          ],
          [
            { key: "address1", value: tokenOwner.address },
            { key: "address2", value: await collectionOwner.getAddress() },
          ],
          [
            { key: "bytes1", value: "0x1234" },
            { key: "bytes2", value: "0x5678" },
          ]
        )
      )
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string1", "value1")
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string2", "value2")
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint1", 1n)
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint2", 2n)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool1", true)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool2", false)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(
          collectionAddress,
          tokenId,
          "address2",
          await collectionOwner.getAddress()
        )
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes2", "0x5678");
    });

    it("should allow to retrieve multiple attributes at once", async function () {
      await tokenAttributes.setAttributes(
        collectionAddress,
        tokenId,
        [
          { key: "string1", value: "value1" },
          { key: "string2", value: "value2" },
        ],
        [
          { key: "uint1", value: 1n },
          { key: "uint2", value: 2n },
        ],
        [
          { key: "bool1", value: true },
          { key: "bool2", value: false },
        ],
        [
          { key: "address1", value: tokenOwner.address },
          { key: "address2", value: await collectionOwner.getAddress() },
        ],
        [
          { key: "bytes1", value: "0x1234" },
          { key: "bytes2", value: "0x5678" },
        ]
      );

      expect(
        await tokenAttributes.getAttributes(
          collectionAddress,
          tokenId,
          ["string1", "string2"],
          ["uint1", "uint2"],
          ["bool1", "bool2"],
          ["address1", "address2"],
          ["bytes1", "bytes2"]
        )
      ).to.eql([
        ["value1", "value2"],
        [1n, 2n],
        [true, false],
        [tokenOwner.address, await collectionOwner.getAddress()],
        ["0x1234", "0x5678"],
      ]);
    });

    it("can set multiple string attributes at the same time", async function () {
      await expect(
        tokenAttributes.setStringAttributes(
          [collectionAddress],
          [tokenId],
          [
            { key: "string1", value: "value1" },
            { key: "string2", value: "value2" },
          ]
        )
      )
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string1", "value1")
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "string2", "value2");

      expect(
        await tokenAttributes.getAttributes(
          collectionAddress,
          tokenId,
          ["string1", "string2"],
          [],
          [],
          [],
          []
        )
      ).to.eql([["value1", "value2"], [], [], [], []]);
    });

    it("can set multiple uint attributes at the same time", async function () {
      await expect(
        tokenAttributes.setUintAttributes(
          [collectionAddress],
          [tokenId],
          [
            { key: "uint1", value: 1n },
            { key: "uint2", value: 2n },
          ]
        )
      )
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint1", 1n)
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "uint2", 2n);

      expect(
        await tokenAttributes.getAttributes(
          collectionAddress,
          tokenId,
          [],
          ["uint1", "uint2"],
          [],
          [],
          []
        )
      ).to.eql([[], [1n, 2n], [], [], []]);
    });

    it("can set multiple bool attributes at the same time", async function () {
      await expect(
        tokenAttributes.setBoolAttributes(
          [collectionAddress],
          [tokenId],
          [
            { key: "bool1", value: true },
            { key: "bool2", value: false },
          ]
        )
      )
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool1", true)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool2", false);

      expect(
        await tokenAttributes.getAttributes(
          collectionAddress,
          tokenId,
          [],
          [],
          ["bool1", "bool2"],
          [],
          []
        )
      ).to.eql([[], [], [true, false], [], []]);
    });

    it("can set multiple address attributes at the same time", async function () {
      await expect(
        tokenAttributes.setAddressAttributes(
          [collectionAddress],
          [tokenId],
          [
            { key: "address1", value: tokenOwner.address },
            { key: "address2", value: await collectionOwner.getAddress() },
          ]
        )
      )
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(
          collectionAddress,
          tokenId,
          "address2",
          await collectionOwner.getAddress()
        );

      expect(
        await tokenAttributes.getAttributes(
          collectionAddress,
          tokenId,
          [],
          [],
          [],
          ["address1", "address2"],
          []
        )
      ).to.eql([
        [],
        [],
        [],
        [tokenOwner.address, await collectionOwner.getAddress()],
        [],
      ]);
    });

    it("can set multiple bytes attributes at the same time", async function () {
      await expect(
        tokenAttributes.setBytesAttributes(
          [collectionAddress],
          [tokenId],
          [
            { key: "bytes1", value: "0x1234" },
            { key: "bytes2", value: "0x5678" },
          ]
        )
      )
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bytes2", "0x5678");

      expect(
        await tokenAttributes.getAttributes(
          collectionAddress,
          tokenId,
          [],
          [],
          [],
          [],
          ["bytes1", "bytes2"]
        )
      ).to.eql([[], [], [], [], ["0x1234", "0x5678"]]);
    });

    it("can reuse keys and values are fine", async function () {
      await tokenAttributes.setStringAttribute(
        collectionAddress,
        tokenId,
        "X",
        "X1"
      );
      await tokenAttributes.setStringAttribute(
        collectionAddress,
        tokenId2,
        "X",
        "X2"
      );

      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId,
          "X"
        )
      ).to.eql("X1");
      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId2,
          "X"
        )
      ).to.eql("X2");
    });

    it("can reuse keys among different attributes and values are fine", async function () {
      await tokenAttributes.setStringAttribute(
        collectionAddress,
        tokenId,
        "X",
        "test description"
      );
      await tokenAttributes.setBoolAttribute(
        collectionAddress,
        tokenId,
        "X",
        true
      );
      await tokenAttributes.setAddressAttribute(
        collectionAddress,
        tokenId,
        "X",
        tokenOwner.address
      );
      await tokenAttributes.setUintAttribute(
        collectionAddress,
        tokenId,
        "X",
        100n
      );
      await tokenAttributes.setBytesAttribute(
        collectionAddress,
        tokenId,
        "X",
        "0x1234"
      );

      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId,
          "X"
        )
      ).to.eql("test description");
      expect(
        await tokenAttributes.getBoolAttribute(collectionAddress, tokenId, "X")
      ).to.eql(true);
      expect(
        await tokenAttributes.getAddressAttribute(
          collectionAddress,
          tokenId,
          "X"
        )
      ).to.eql(tokenOwner.address);
      expect(
        await tokenAttributes.getUintAttribute(collectionAddress, tokenId, "X")
      ).to.eql(100n);
      expect(
        await tokenAttributes.getBytesAttribute(collectionAddress, tokenId, "X")
      ).to.eql("0x1234");
    });

    it("can reuse string values and values are fine", async function () {
      await tokenAttributes.setStringAttribute(
        collectionAddress,
        tokenId,
        "X",
        "common string"
      );
      await tokenAttributes.setStringAttribute(
        collectionAddress,
        tokenId2,
        "X",
        "common string"
      );

      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId,
          "X"
        )
      ).to.eql("common string");
      expect(
        await tokenAttributes.getStringAttribute(
          collectionAddress,
          tokenId2,
          "X"
        )
      ).to.eql("common string");
    });

    it("should not allow to set string values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setStringAttribute(
            collectionAddress,
            tokenId,
            "X",
            "test description"
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should not allow to set uint values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setUintAttribute(collectionAddress, tokenId, "X", 42n)
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should not allow to set boolean values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setBoolAttribute(collectionAddress, tokenId, "X", true)
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should not allow to set address values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should not allow to set bytes values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setBytesAttribute(collectionAddress, tokenId, "X", "0x1234")
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });
  });

  describe("Token attributes access control", async function () {
    it("should allow registering an already registered collection", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      await expect(
        tokenAttributes.registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        )
      ).to.emit(tokenAttributes, "AccessControlRegistration");
    });

    it("should not allow to register a collection if caller is not the owner of the collection", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .registerAccessControl(
            collectionAddress,
            await collectionOwner.getAddress(),
            true
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should not allow to register a collection without Ownable implemented", async function () {
      const erc20Factory = await ethers.getContractFactory("ERC20Mock");
      const erc20 = await erc20Factory.deploy();
      await expect(
        tokenAttributes.registerAccessControl(
          await erc20.getAddress(),
          await collectionOwner.getAddress(),
          false
        )
      ).to.be.revertedWithCustomError(tokenAttributes, "OwnableNotImplemented");
    });

    it("should allow to manage access control for registered collections", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      expect(
        await tokenAttributes
          .connect(collectionOwner)
          .manageAccessControl(
            collectionAddress,
            "X",
            AccessType.IssuerOrCollaborator,
            tokenOwner.address
          )
      )
        .to.emit(tokenAttributes, "AccessControlUpdate")
        .withArgs(collectionAddress, "X", 2, tokenOwner);
    });

    it("should allow issuer to manage collaborators", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      expect(
        await tokenAttributes
          .connect(collectionOwner)
          .manageCollaborators(collectionAddress, [tokenOwner.address], [true])
      )
        .to.emit(tokenAttributes, "CollaboratorUpdate")
        .withArgs(collectionAddress, [tokenOwner.address], [true]);
    });

    it("should not allow to manage collaborators of an unregistered collection", async function () {
      await expect(
        tokenAttributes
          .connect(collectionOwner)
          .manageCollaborators(collectionAddress, [tokenOwner.address], [true])
      ).to.be.revertedWithCustomError(
        tokenAttributes,
        "CollectionNotRegistered"
      );
    });

    it("should not allow to manage collaborators if the caller is not the issuer", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .manageCollaborators(collectionAddress, [tokenOwner.address], [true])
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should not allow to manage collaborators for registered collections if collaborator arrays are not of equal length", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      await expect(
        tokenAttributes
          .connect(collectionOwner)
          .manageCollaborators(
            collectionAddress,
            [tokenOwner.address, await collectionOwner.getAddress()],
            [true]
          )
      ).to.be.revertedWithCustomError(
        tokenAttributes,
        "CollaboratorArraysNotEqualLength"
      );
    });

    it("should not allow to manage access control for unregistered collections", async function () {
      await expect(
        tokenAttributes
          .connect(collectionOwner)
          .manageAccessControl(
            collectionAddress,
            "X",
            AccessType.IssuerOrCollaborator,
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(
        tokenAttributes,
        "CollectionNotRegistered"
      );
    });

    it("should not allow to manage access control if the caller is not issuer", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .manageAccessControl(
            collectionAddress,
            "X",
            AccessType.IssuerOrCollaborator,
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should not allow to manage access control if the caller is not returned as collection owner when using ownable", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        true
      );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .manageAccessControl(
            collectionAddress,
            "X",
            AccessType.IssuerOrCollaborator,
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should return the expected value when checking for collaborators", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      expect(
        await tokenAttributes.isCollaborator(
          tokenOwner.address,
          collectionAddress
        )
      ).to.be.false;

      await tokenAttributes
        .connect(collectionOwner)
        .manageCollaborators(collectionAddress, [tokenOwner.address], [true]);

      expect(
        await tokenAttributes.isCollaborator(
          tokenOwner.address,
          collectionAddress
        )
      ).to.be.true;
    });

    it("should return the expected value when checking for specific addresses", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        await collectionOwner.getAddress(),
        false
      );

      expect(
        await tokenAttributes.isSpecificAddress(
          tokenOwner.address,
          collectionAddress,
          "X"
        )
      ).to.be.false;

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.IssuerOrCollaborator,
          tokenOwner.address
        );

      expect(
        await tokenAttributes.isSpecificAddress(
          tokenOwner.address,
          collectionAddress,
          "X"
        )
      ).to.be.true;
    });

    it("should use the issuer returned from the collection when using only issuer when only issuer is allowed to manage parameter", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          true
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.Issuer,
          ethers.ZeroAddress
        );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });

    it("should only allow collaborator to modify the parameters if only collaborator is allowed to modify them", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.Collaborator,
          ethers.ZeroAddress
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageCollaborators(collectionAddress, [tokenOwner.address], [true]);

      await tokenAttributes
        .connect(tokenOwner)
        .setAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address
        );

      await expect(
        tokenAttributes
          .connect(collectionOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(
        tokenAttributes,
        "NotCollectionCollaborator"
      );
    });

    it("should only allow issuer and collaborator to modify the parameters if only issuer and collaborator is allowed to modify them", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.IssuerOrCollaborator,
          ethers.ZeroAddress
        );

      await tokenAttributes
        .connect(collectionOwner)
        .setAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address
        );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(
        tokenAttributes,
        "NotCollectionIssuerOrCollaborator"
      );

      await tokenAttributes
        .connect(collectionOwner)
        .manageCollaborators(collectionAddress, [tokenOwner.address], [true]);

      await tokenAttributes
        .connect(tokenOwner)
        .setAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address
        );
    });

    it("should only allow issuer and collaborator to modify the parameters if only issuer and collaborator is allowed to modify them even when using the ownable", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          true
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.IssuerOrCollaborator,
          ethers.ZeroAddress
        );

      await tokenAttributes
        .connect(collectionOwner)
        .setAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address
        );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(
        tokenAttributes,
        "NotCollectionIssuerOrCollaborator"
      );

      await tokenAttributes
        .connect(collectionOwner)
        .manageCollaborators(
          collectionAddress,
          [await collaborator.getAddress()],
          [true]
        );

      await tokenAttributes
        .connect(collaborator)
        .setAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address
        );
    });

    it("should only allow token owner to modify the parameters if only token owner is allowed to modify them", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.TokenOwner,
          ethers.ZeroAddress
        );

      await expect(
        tokenAttributes
          .connect(collaborator)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotTokenOwner");

      await expect(
        tokenAttributes
          .connect(collectionOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotTokenOwner");

      await tokenAttributes
        .connect(tokenOwner)
        .setAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address
        );
    });

    it("should only allow specific address to modify the parameters if only specific address is allowed to modify them", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.SpecificAddress,
          ethers.ZeroAddress
        );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotSpecificAddress");

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.SpecificAddress,
          tokenOwner.address
        );

      await tokenAttributes
        .connect(tokenOwner)
        .setAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address
        );
    });

    it("should allow to use presigned message to modify the parameters", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        );

      const uintMessage =
        await tokenAttributes.prepareMessageToPresignUintAttribute(
          collectionAddress,
          tokenId,
          "X",
          1,
          9999999999n
        );
      const stringMessage =
        await tokenAttributes.prepareMessageToPresignStringAttribute(
          collectionAddress,
          tokenId,
          "X",
          "test",
          9999999999n
        );
      const boolMessage =
        await tokenAttributes.prepareMessageToPresignBoolAttribute(
          collectionAddress,
          tokenId,
          "X",
          true,
          9999999999n
        );
      const bytesMessage =
        await tokenAttributes.prepareMessageToPresignBytesAttribute(
          collectionAddress,
          tokenId,
          "X",
          "0x1234",
          9999999999n
        );
      const addressMessage =
        await tokenAttributes.prepareMessageToPresignAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address,
          9999999999n
        );

      const uintSignature = await collectionOwner.signMessage(
        ethers.getBytes(uintMessage)
      );
      const stringSignature = await collectionOwner.signMessage(
        ethers.getBytes(stringMessage)
      );
      const boolSignature = await collectionOwner.signMessage(
        ethers.getBytes(boolMessage)
      );
      const bytesSignature = await collectionOwner.signMessage(
        ethers.getBytes(bytesMessage)
      );
      const addressSignature = await collectionOwner.signMessage(
        ethers.getBytes(addressMessage)
      );

      const uintR: string = uintSignature.substring(0, 66);
      const uintS: string = "0x" + uintSignature.substring(66, 130);
      const uintV: string = parseInt(
        uintSignature.substring(130, 132),
        16
      ).toString();

      const stringR: string = stringSignature.substring(0, 66);
      const stringS: string = "0x" + stringSignature.substring(66, 130);
      const stringV: string = parseInt(
        stringSignature.substring(130, 132),
        16
      ).toString();

      const boolR: string = boolSignature.substring(0, 66);
      const boolS: string = "0x" + boolSignature.substring(66, 130);
      const boolV: string = parseInt(
        boolSignature.substring(130, 132),
        16
      ).toString();

      const bytesR: string = bytesSignature.substring(0, 66);
      const bytesS: string = "0x" + bytesSignature.substring(66, 130);
      const bytesV: string = parseInt(
        bytesSignature.substring(130, 132),
        16
      ).toString();

      const addressR: string = addressSignature.substring(0, 66);
      const addressS: string = "0x" + addressSignature.substring(66, 130);
      const addressV: string = parseInt(
        addressSignature.substring(130, 132),
        16
      ).toString();

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetUintAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            1,
            9999999999n,
            uintV,
            uintR,
            uintS
          )
      )
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, 1, "X", 1);
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetStringAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "test",
            9999999999n,
            stringV,
            stringR,
            stringS
          )
      )
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(collectionAddress, 1, "X", "test");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBoolAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            true,
            9999999999n,
            boolV,
            boolR,
            boolS
          )
      )
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, 1, "X", true);
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBytesAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "0x1234",
            9999999999n,
            bytesV,
            bytesR,
            bytesS
          )
      )
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
        .withArgs(collectionAddress, 1, "X", "0x1234");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetAddressAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address,
            9999999999n,
            addressV,
            addressR,
            addressS
          )
      )
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(collectionAddress, 1, "X", tokenOwner.address);
    });

    it("should not allow to use presigned message to modify the parameters if the deadline has elapsed", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        );

      await mine(1000, { interval: 15 });

      const uintMessage =
        await tokenAttributes.prepareMessageToPresignUintAttribute(
          collectionAddress,
          tokenId,
          "X",
          1,
          10n
        );
      const stringMessage =
        await tokenAttributes.prepareMessageToPresignStringAttribute(
          collectionAddress,
          tokenId,
          "X",
          "test",
          10n
        );
      const boolMessage =
        await tokenAttributes.prepareMessageToPresignBoolAttribute(
          collectionAddress,
          tokenId,
          "X",
          true,
          10n
        );
      const bytesMessage =
        await tokenAttributes.prepareMessageToPresignBytesAttribute(
          collectionAddress,
          tokenId,
          "X",
          "0x1234",
          10n
        );
      const addressMessage =
        await tokenAttributes.prepareMessageToPresignAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address,
          10n
        );

      const uintSignature = await collectionOwner.signMessage(
        ethers.getBytes(uintMessage)
      );
      const stringSignature = await collectionOwner.signMessage(
        ethers.getBytes(stringMessage)
      );
      const boolSignature = await collectionOwner.signMessage(
        ethers.getBytes(boolMessage)
      );
      const bytesSignature = await collectionOwner.signMessage(
        ethers.getBytes(bytesMessage)
      );
      const addressSignature = await collectionOwner.signMessage(
        ethers.getBytes(addressMessage)
      );

      const uintR: string = uintSignature.substring(0, 66);
      const uintS: string = "0x" + uintSignature.substring(66, 130);
      const uintV: string = parseInt(
        uintSignature.substring(130, 132),
        16
      ).toString();

      const stringR: string = stringSignature.substring(0, 66);
      const stringS: string = "0x" + stringSignature.substring(66, 130);
      const stringV: string = parseInt(
        stringSignature.substring(130, 132),
        16
      ).toString();

      const boolR: string = boolSignature.substring(0, 66);
      const boolS: string = "0x" + boolSignature.substring(66, 130);
      const boolV: string = parseInt(
        boolSignature.substring(130, 132),
        16
      ).toString();

      const bytesR: string = bytesSignature.substring(0, 66);
      const bytesS: string = "0x" + bytesSignature.substring(66, 130);
      const bytesV: string = parseInt(
        bytesSignature.substring(130, 132),
        16
      ).toString();

      const addressR: string = addressSignature.substring(0, 66);
      const addressS: string = "0x" + addressSignature.substring(66, 130);
      const addressV: string = parseInt(
        addressSignature.substring(130, 132),
        16
      ).toString();

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetUintAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            1,
            10n,
            uintV,
            uintR,
            uintS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "ExpiredDeadline");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetStringAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "test",
            10n,
            stringV,
            stringR,
            stringS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "ExpiredDeadline");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBoolAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            true,
            10n,
            boolV,
            boolR,
            boolS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "ExpiredDeadline");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBytesAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "0x1234",
            10n,
            bytesV,
            bytesR,
            bytesS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "ExpiredDeadline");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetAddressAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address,
            10n,
            addressV,
            addressR,
            addressS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "ExpiredDeadline");
    });

    it("should not allow to use presigned message to modify the parameters if the setter does not match the actual signer", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          await collectionOwner.getAddress(),
          false
        );

      const uintMessage =
        await tokenAttributes.prepareMessageToPresignUintAttribute(
          collectionAddress,
          tokenId,
          "X",
          1,
          9999999999n
        );
      const stringMessage =
        await tokenAttributes.prepareMessageToPresignStringAttribute(
          collectionAddress,
          tokenId,
          "X",
          "test",
          9999999999n
        );
      const boolMessage =
        await tokenAttributes.prepareMessageToPresignBoolAttribute(
          collectionAddress,
          tokenId,
          "X",
          true,
          9999999999n
        );
      const bytesMessage =
        await tokenAttributes.prepareMessageToPresignBytesAttribute(
          collectionAddress,
          tokenId,
          "X",
          "0x1234",
          9999999999n
        );
      const addressMessage =
        await tokenAttributes.prepareMessageToPresignAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address,
          9999999999n
        );

      const uintSignature = await tokenOwner.signMessage(
        ethers.getBytes(uintMessage)
      );
      const stringSignature = await tokenOwner.signMessage(
        ethers.getBytes(stringMessage)
      );
      const boolSignature = await tokenOwner.signMessage(
        ethers.getBytes(boolMessage)
      );
      const bytesSignature = await tokenOwner.signMessage(
        ethers.getBytes(bytesMessage)
      );
      const addressSignature = await tokenOwner.signMessage(
        ethers.getBytes(addressMessage)
      );

      const uintR: string = uintSignature.substring(0, 66);
      const uintS: string = "0x" + uintSignature.substring(66, 130);
      const uintV: string = parseInt(
        uintSignature.substring(130, 132),
        16
      ).toString();

      const stringR: string = stringSignature.substring(0, 66);
      const stringS: string = "0x" + stringSignature.substring(66, 130);
      const stringV: string = parseInt(
        stringSignature.substring(130, 132),
        16
      ).toString();

      const boolR: string = boolSignature.substring(0, 66);
      const boolS: string = "0x" + boolSignature.substring(66, 130);
      const boolV: string = parseInt(
        boolSignature.substring(130, 132),
        16
      ).toString();

      const bytesR: string = bytesSignature.substring(0, 66);
      const bytesS: string = "0x" + bytesSignature.substring(66, 130);
      const bytesV: string = parseInt(
        bytesSignature.substring(130, 132),
        16
      ).toString();

      const addressR: string = addressSignature.substring(0, 66);
      const addressS: string = "0x" + addressSignature.substring(66, 130);
      const addressV: string = parseInt(
        addressSignature.substring(130, 132),
        16
      ).toString();

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetUintAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            1,
            9999999999n,
            uintV,
            uintR,
            uintS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "InvalidSignature");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetStringAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "test",
            9999999999n,
            stringV,
            stringR,
            stringS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "InvalidSignature");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBoolAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            true,
            9999999999n,
            boolV,
            boolR,
            boolS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "InvalidSignature");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBytesAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "0x1234",
            9999999999n,
            bytesV,
            bytesR,
            bytesS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "InvalidSignature");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetAddressAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address,
            9999999999n,
            addressV,
            addressR,
            addressS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "InvalidSignature");
    });

    it("should not allow to use presigned message to modify the parameters if the signer is not authorized to modify them", async function () {
      const uintMessage =
        await tokenAttributes.prepareMessageToPresignUintAttribute(
          collectionAddress,
          tokenId,
          "X",
          1,
          9999999999n
        );
      const stringMessage =
        await tokenAttributes.prepareMessageToPresignStringAttribute(
          collectionAddress,
          tokenId,
          "X",
          "test",
          9999999999n
        );
      const boolMessage =
        await tokenAttributes.prepareMessageToPresignBoolAttribute(
          collectionAddress,
          tokenId,
          "X",
          true,
          9999999999n
        );
      const bytesMessage =
        await tokenAttributes.prepareMessageToPresignBytesAttribute(
          collectionAddress,
          tokenId,
          "X",
          "0x1234",
          9999999999n
        );
      const addressMessage =
        await tokenAttributes.prepareMessageToPresignAddressAttribute(
          collectionAddress,
          tokenId,
          "X",
          tokenOwner.address,
          9999999999n
        );

      const uintSignature = await collectionOwner.signMessage(
        ethers.getBytes(uintMessage)
      );
      const stringSignature = await collectionOwner.signMessage(
        ethers.getBytes(stringMessage)
      );
      const boolSignature = await collectionOwner.signMessage(
        ethers.getBytes(boolMessage)
      );
      const bytesSignature = await collectionOwner.signMessage(
        ethers.getBytes(bytesMessage)
      );
      const addressSignature = await collectionOwner.signMessage(
        ethers.getBytes(addressMessage)
      );

      const uintR: string = uintSignature.substring(0, 66);
      const uintS: string = "0x" + uintSignature.substring(66, 130);
      const uintV: string = parseInt(
        uintSignature.substring(130, 132),
        16
      ).toString();

      const stringR: string = stringSignature.substring(0, 66);
      const stringS: string = "0x" + stringSignature.substring(66, 130);
      const stringV: string = parseInt(
        stringSignature.substring(130, 132),
        16
      ).toString();

      const boolR: string = boolSignature.substring(0, 66);
      const boolS: string = "0x" + boolSignature.substring(66, 130);
      const boolV: string = parseInt(
        boolSignature.substring(130, 132),
        16
      ).toString();

      const bytesR: string = bytesSignature.substring(0, 66);
      const bytesS: string = "0x" + bytesSignature.substring(66, 130);
      const bytesV: string = parseInt(
        bytesSignature.substring(130, 132),
        16
      ).toString();

      const addressR: string = addressSignature.substring(0, 66);
      const addressS: string = "0x" + addressSignature.substring(66, 130);
      const addressV: string = parseInt(
        addressSignature.substring(130, 132),
        16
      ).toString();

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetUintAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            1,
            9999999999n,
            uintV,
            uintR,
            uintS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetStringAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "test",
            9999999999n,
            stringV,
            stringR,
            stringS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBoolAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            true,
            9999999999n,
            boolV,
            boolR,
            boolS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBytesAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            "0x1234",
            9999999999n,
            bytesV,
            bytesR,
            bytesS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetAddressAttribute(
            await collectionOwner.getAddress(),
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address,
            9999999999n,
            addressV,
            addressR,
            addressS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionIssuer");
    });
  });
});

async function shouldBehaveLikeAttributesRepositoryInterface() {
  it("can support IERC165", async function () {
    expect(await this.tokenAttributes.supportsInterface(IERC165)).to.equal(
      true
    );
  });

  it("can support IERC7508", async function () {
    expect(await this.tokenAttributes.supportsInterface(IERC7508)).to.equal(
      true
    );
  });
}
