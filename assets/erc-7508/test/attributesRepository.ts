import { ethers } from "hardhat";
import { expect } from "chai";
import { loadFixture, mine } from "@nomicfoundation/hardhat-network-helpers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import {
  OwnableMintableERC721Mock,
  AttributesRepository,
} from "../typechain-types";

const IERC165 = "0x01ffc9a7";
const IERC7508 = "0x212206a8";

// --------------- FIXTURES -----------------------

enum AccessType {
  Owner,
  Collaborator,
  OwnerOrCollaborator,
  TokenOwner,
  SpecificAddress,
}

async function fixture() {
  const tokenAttributesFactory = await ethers.getContractFactory(
    "AttributesRepository"
  );
  const tokenAttributes = await tokenAttributesFactory.deploy();
  await tokenAttributes.waitForDeployment();

  const collectionFactory = await ethers.getContractFactory(
    "OwnableMintableERC721Mock"
  );
  const [owner, ownerOf] = await ethers.getSigners();
  const ownedCollection1 = await collectionFactory.deploy(owner, ownerOf);
  await ownedCollection1.waitForDeployment();
  const ownedCollection2 = await collectionFactory.deploy(owner, ownerOf);
  await ownedCollection2.waitForDeployment();

  return {
    tokenAttributes,
    ownedCollection1,
    ownedCollection2,
  };
}

// --------------- TESTS -----------------------

describe("AttributesRepository", async function () {
  let tokenAttributes: AttributesRepository;
  let ownedCollection1: OwnableMintableERC721Mock;
  let ownedCollection2: OwnableMintableERC721Mock;
  let collectionOwner: SignerWithAddress;
  let tokenOwner: SignerWithAddress;
  let collaborator: SignerWithAddress;
  let collectionAddress: string;
  let collectionAddress2: string;
  const tokenId = 1n;
  const tokenId2 = 2n;

  beforeEach(async function () {
    ({ tokenAttributes, ownedCollection1, ownedCollection2 } =
      await loadFixture(fixture));
    collectionAddress = await ownedCollection1.getAddress();
    collectionAddress2 = await ownedCollection2.getAddress();
    [collectionOwner, tokenOwner, collaborator] = await ethers.getSigners();
  });

  it("can support IERC165", async function () {
    expect(await tokenAttributes.supportsInterface(IERC165)).to.equal(true);
  });

  it("can support IERC7508", async function () {
    expect(await tokenAttributes.supportsInterface(IERC7508)).to.equal(true);
  });

  describe("Attributes Metadata URI", async function () {
    beforeEach(async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        false
      );
    });

    it("should allow to set the attributes metadata URI if collection owner", async function () {
      await expect(
        tokenAttributes.setAttributesMetadataURIForCollection(
          collectionAddress,
          "ipfs://test"
        )
      ).to.emit(tokenAttributes, "MetadataURIUpdated");

      expect(
        await tokenAttributes.getAttributesMetadataURIForCollection(
          collectionAddress
        )
      ).to.eql("ipfs://test");
    });

    it("should not allow to set the attributes metadata URI if not collection owner", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAttributesMetadataURIForCollection(
            collectionAddress,
            "ipfs://test"
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });
  });

  describe("Registering attributes and setting values", async function () {
    beforeEach(async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        false
      );
      await tokenAttributes.registerAccessControl(
        collectionAddress2,
        collectionOwner.address,
        false
      );
    });

    it("can set and get token attributes", async function () {
      await expect(
        tokenAttributes.setStringAttribute(
          collectionAddress,
          tokenId,
          "description",
          "test description"
        )
      )
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(
          collectionAddress,
          tokenId,
          "description",
          "test description"
        );
      await expect(
        tokenAttributes.setStringAttribute(
          collectionAddress,
          tokenId,
          "description1",
          "test description"
        )
      )
        .to.emit(tokenAttributes, "StringAttributeUpdated")
        .withArgs(
          collectionAddress,
          tokenId,
          "description1",
          "test description"
        );
      await expect(
        tokenAttributes.setBoolAttribute(
          collectionAddress,
          tokenId,
          "rare",
          true
        )
      )
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "rare", true);
      await expect(
        tokenAttributes.setAddressAttribute(
          collectionAddress,
          tokenId,
          "owner",
          tokenOwner.address
        )
      )
        .to.emit(tokenAttributes, "AddressAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "owner", tokenOwner.address);
      await expect(
        tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "atk",
          100n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "atk", 100n);
      await expect(
        tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "health",
          100n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "health", 100n);
      await expect(
        tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "health",
          95n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "health", 95n);
      await expect(
        tokenAttributes.setUintAttribute(
          collectionAddress,
          tokenId,
          "health",
          80n
        )
      )
        .to.emit(tokenAttributes, "UintAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "health", 80n);
      await expect(
        tokenAttributes.setIntAttribute(collectionAddress, tokenId, "int", 1n)
      )
        .to.emit(tokenAttributes, "IntAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "int", 1n);
      await expect(
        tokenAttributes.setIntAttribute(
          collectionAddress,
          tokenId,
          "int2",
          -10n
        )
      )
        .to.emit(tokenAttributes, "IntAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "int2", -10n);
      await expect(
        tokenAttributes.setBytesAttribute(
          collectionAddress,
          tokenId,
          "data",
          "0x1234"
        )
      )
        .to.emit(tokenAttributes, "BytesAttributeUpdated")
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
        await tokenAttributes.getIntAttribute(collectionAddress, tokenId, "int")
      ).to.eql(1n);
      expect(
        await tokenAttributes.getIntAttribute(
          collectionAddress,
          tokenId,
          "int2"
        )
      ).to.eql(-10n);
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
            { key: "address1", value: tokenOwner.address },
            { key: "address2", value: collectionOwner.address },
          ],
          [
            { key: "bool1", value: true },
            { key: "bool2", value: false },
          ],
          [
            { key: "bytes1", value: "0x1234" },
            { key: "bytes2", value: "0x5678" },
          ],
          [
            { key: "int1", value: -10n },
            { key: "int2", value: 2n },
          ],
          [
            { key: "string1", value: "value1" },
            { key: "string2", value: "value2" },
          ],
          [
            { key: "uint1", value: 1n },
            { key: "uint2", value: 2n },
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
        .to.emit(tokenAttributes, "IntAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "int1", -10n)
        .to.emit(tokenAttributes, "IntAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "int2", 2n)
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
          collectionOwner.address
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
        [
          { key: "address1", value: collectionOwner.address },
          { key: "address2", value: tokenOwner.address },
        ],
        [
          { key: "bool1", value: false },
          { key: "bool2", value: true },
        ],
        [],
        [],
        [{ key: "string1", value: "value0" }],
        [
          { key: "uint1", value: 0n },
          { key: "uint2", value: 1n },
        ]
      );

      await expect(
        tokenAttributes.setAttributes(
          collectionAddress,
          tokenId,
          [
            { key: "address1", value: tokenOwner.address },
            { key: "address2", value: collectionOwner.address },
          ],
          [
            { key: "bool1", value: true },
            { key: "bool2", value: false },
          ],
          [
            { key: "bytes1", value: "0x1234" },
            { key: "bytes2", value: "0x5678" },
          ],
          [],
          [],
          [
            { key: "uint1", value: 1n },
            { key: "uint2", value: 2n },
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
          collectionOwner.address
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
          [
            { key: "bool1", value: false },
            { key: "bool2", value: true },
          ],
          [],
          [],
          [],
          []
        )
      )
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool1", false)
        .to.emit(tokenAttributes, "BoolAttributeUpdated")
        .withArgs(collectionAddress, tokenId, "bool2", true);
    });

    it("should allow to retrieve multiple attributes at once", async function () {
      await tokenAttributes.setAttributes(
        collectionAddress,
        tokenId,
        [
          { key: "address1", value: tokenOwner.address },
          { key: "address2", value: collectionOwner.address },
        ],
        [
          { key: "bool1", value: true },
          { key: "bool2", value: false },
        ],
        [
          { key: "bytes1", value: "0x1234" },
          { key: "bytes2", value: "0x5678" },
        ],
        [
          { key: "int1", value: -10n },
          { key: "int2", value: 2n },
        ],
        [
          { key: "string1", value: "value1" },
          { key: "string2", value: "value2" },
        ],
        [
          { key: "uint1", value: 1n },
          { key: "uint2", value: 2n },
        ]
      );

      expect(
        await tokenAttributes.getAttributes(
          collectionAddress,
          tokenId,
          ["address1", "address2"],
          ["bool1", "bool2"],
          ["bytes1", "bytes2"],
          ["int1", "int2"],
          ["string1", "string2"],
          ["uint1", "uint2"]
        )
      ).to.eql([
        [tokenOwner.address, collectionOwner.address],
        [true, false],
        ["0x1234", "0x5678"],
        [-10n, 2n],
        ["value1", "value2"],
        [1n, 2n],
      ]);
    });

    describe("Batch setters, multiple attributes, single collection and single token", async function () {
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
          await tokenAttributes.getStringAttributes(
            [collectionAddress],
            [tokenId],
            ["string1", "string2"]
          )
        ).to.eql(["value1", "value2"]);
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
          await tokenAttributes.getUintAttributes(
            [collectionAddress],
            [tokenId],
            ["uint1", "uint2"]
          )
        ).to.eql([1n, 2n]);
      });

      it("can set multiple int attributes at the same time", async function () {
        await expect(
          tokenAttributes.setIntAttributes(
            [collectionAddress],
            [tokenId],
            [
              { key: "int1", value: -10n },
              { key: "int2", value: 2n },
            ]
          )
        )
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "int1", -10n)
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "int2", 2n);

        expect(
          await tokenAttributes.getIntAttributes(
            [collectionAddress],
            [tokenId],
            ["int1", "int2"]
          )
        ).to.eql([-10n, 2n]);
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
          await tokenAttributes.getBoolAttributes(
            [collectionAddress],
            [tokenId],
            ["bool1", "bool2"]
          )
        ).to.eql([true, false]);
      });

      it("can set multiple address attributes at the same time", async function () {
        await expect(
          tokenAttributes.setAddressAttributes(
            [collectionAddress],
            [tokenId],
            [
              { key: "address1", value: tokenOwner.address },
              { key: "address2", value: collectionOwner.address },
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
            collectionOwner.address
          );

        expect(
          await tokenAttributes.getAddressAttributes(
            [collectionAddress],
            [tokenId],
            ["address1", "address2"]
          )
        ).to.eql([tokenOwner.address, collectionOwner.address]);
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
          await tokenAttributes.getBytesAttributes(
            [collectionAddress],
            [tokenId],
            ["bytes1", "bytes2"]
          )
        ).to.eql(["0x1234", "0x5678"]);
      });
    });

    describe("Batch setters, multiple attributes, single collection and multple tokens", async function () {
      it("can set multiple string attributes at the same time", async function () {
        await expect(
          tokenAttributes.setStringAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [
              { key: "string1", value: "value1" },
              { key: "string2", value: "value2" },
            ]
          )
        )
          .to.emit(tokenAttributes, "StringAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "string1", "value1")
          .to.emit(tokenAttributes, "StringAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "string2", "value2");

        expect(
          await tokenAttributes.getStringAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["string1", "string2"]
          )
        ).to.eql(["value1", "value2"]);
      });

      it("can set multiple uint attributes at the same time", async function () {
        await expect(
          tokenAttributes.setUintAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [
              { key: "uint1", value: 1n },
              { key: "uint2", value: 2n },
            ]
          )
        )
          .to.emit(tokenAttributes, "UintAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "uint1", 1n)
          .to.emit(tokenAttributes, "UintAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "uint2", 2n);

        expect(
          await tokenAttributes.getUintAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["uint1", "uint2"]
          )
        ).to.eql([1n, 2n]);
      });

      it("can set multiple int attributes at the same time", async function () {
        await expect(
          tokenAttributes.setIntAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [
              { key: "int1", value: -10n },
              { key: "int2", value: 2n },
            ]
          )
        )
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "int1", -10n)
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "int2", 2n);

        expect(
          await tokenAttributes.getIntAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["int1", "int2"]
          )
        ).to.eql([-10n, 2n]);
      });

      it("can set multiple bool attributes at the same time", async function () {
        await expect(
          tokenAttributes.setBoolAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [
              { key: "bool1", value: true },
              { key: "bool2", value: false },
            ]
          )
        )
          .to.emit(tokenAttributes, "BoolAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "bool1", true)
          .to.emit(tokenAttributes, "BoolAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "bool2", false);

        expect(
          await tokenAttributes.getBoolAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["bool1", "bool2"]
          )
        ).to.eql([true, false]);
      });

      it("can set multiple address attributes at the same time", async function () {
        await expect(
          tokenAttributes.setAddressAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [
              { key: "address1", value: tokenOwner.address },
              { key: "address2", value: collectionOwner.address },
            ]
          )
        )
          .to.emit(tokenAttributes, "AddressAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
          .to.emit(tokenAttributes, "AddressAttributeUpdated")
          .withArgs(
            collectionAddress,
            tokenId2,
            "address2",
            collectionOwner.address
          );

        expect(
          await tokenAttributes.getAddressAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["address1", "address2"]
          )
        ).to.eql([tokenOwner.address, collectionOwner.address]);
      });

      it("can set multiple bytes attributes at the same time", async function () {
        await expect(
          tokenAttributes.setBytesAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [
              { key: "bytes1", value: "0x1234" },
              { key: "bytes2", value: "0x5678" },
            ]
          )
        )
          .to.emit(tokenAttributes, "BytesAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
          .to.emit(tokenAttributes, "BytesAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "bytes2", "0x5678");

        expect(
          await tokenAttributes.getBytesAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["bytes1", "bytes2"]
          )
        ).to.eql(["0x1234", "0x5678"]);
      });
    });

    describe("Batch setters, single attribute, single collection and multple tokens", async function () {
      it("can set multiple string attributes at the same time", async function () {
        await expect(
          tokenAttributes.setStringAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [{ key: "string1", value: "value1" }]
          )
        )
          .to.emit(tokenAttributes, "StringAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "string1", "value1")
          .to.emit(tokenAttributes, "StringAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "string1", "value1");

        expect(
          await tokenAttributes.getStringAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["string1"]
          )
        ).to.eql(["value1", "value1"]);
      });

      it("can set multiple uint attributes at the same time", async function () {
        await expect(
          tokenAttributes.setUintAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [{ key: "uint1", value: 1n }]
          )
        )
          .to.emit(tokenAttributes, "UintAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "uint1", 1n)
          .to.emit(tokenAttributes, "UintAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "uint1", 1n);

        expect(
          await tokenAttributes.getUintAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["uint1"]
          )
        ).to.eql([1n, 1n]);
      });

      it("can set multiple int attributes at the same time", async function () {
        await expect(
          tokenAttributes.setIntAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [{ key: "int1", value: -10n }]
          )
        )
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "int1", -10n)
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "int1", -10n);

        expect(
          await tokenAttributes.getIntAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["int1"]
          )
        ).to.eql([-10n, -10n]);
      });

      it("can set multiple bool attributes at the same time", async function () {
        await expect(
          tokenAttributes.setBoolAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [{ key: "bool1", value: true }]
          )
        )
          .to.emit(tokenAttributes, "BoolAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "bool1", true)
          .to.emit(tokenAttributes, "BoolAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "bool1", true);

        expect(
          await tokenAttributes.getBoolAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["bool1"]
          )
        ).to.eql([true, true]);
      });

      it("can set multiple address attributes at the same time", async function () {
        await expect(
          tokenAttributes.setAddressAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [{ key: "address1", value: tokenOwner.address }]
          )
        )
          .to.emit(tokenAttributes, "AddressAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
          .to.emit(tokenAttributes, "AddressAttributeUpdated")
          .withArgs(
            collectionAddress,
            tokenId2,
            "address1",
            tokenOwner.address
          );

        expect(
          await tokenAttributes.getAddressAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["address1"]
          )
        ).to.eql([tokenOwner.address, tokenOwner.address]);
      });

      it("can set multiple bytes attributes at the same time", async function () {
        await expect(
          tokenAttributes.setBytesAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            [{ key: "bytes1", value: "0x1234" }]
          )
        )
          .to.emit(tokenAttributes, "BytesAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
          .to.emit(tokenAttributes, "BytesAttributeUpdated")
          .withArgs(collectionAddress, tokenId2, "bytes1", "0x1234");

        expect(
          await tokenAttributes.getBytesAttributes(
            [collectionAddress],
            [tokenId, tokenId2],
            ["bytes1"]
          )
        ).to.eql(["0x1234", "0x1234"]);
      });
    });

    describe("Batch setters, multiple attributes, multiple collections and multple tokens", async function () {
      it("can set multiple string attributes at the same time", async function () {
        await expect(
          tokenAttributes.setStringAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "string1", value: "value1" },
              { key: "string2", value: "value2" },
            ]
          )
        )
          .to.emit(tokenAttributes, "StringAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "string1", "value1")
          .to.emit(tokenAttributes, "StringAttributeUpdated")
          .withArgs(collectionAddress2, tokenId2, "string2", "value2");

        expect(
          await tokenAttributes.getStringAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            ["string1", "string2"]
          )
        ).to.eql(["value1", "value2"]);
      });

      it("can set multiple uint attributes at the same time", async function () {
        await expect(
          tokenAttributes.setUintAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "uint1", value: 1n },
              { key: "uint2", value: 2n },
            ]
          )
        )
          .to.emit(tokenAttributes, "UintAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "uint1", 1n)
          .to.emit(tokenAttributes, "UintAttributeUpdated")
          .withArgs(collectionAddress2, tokenId2, "uint2", 2n);

        expect(
          await tokenAttributes.getUintAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            ["uint1", "uint2"]
          )
        ).to.eql([1n, 2n]);
      });

      it("can set multiple int attributes at the same time", async function () {
        await expect(
          tokenAttributes.setIntAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "int1", value: -10n },
              { key: "int2", value: 2n },
            ]
          )
        )
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "int1", -10n)
          .to.emit(tokenAttributes, "IntAttributeUpdated")
          .withArgs(collectionAddress2, tokenId2, "int2", 2n);

        expect(
          await tokenAttributes.getIntAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            ["int1", "int2"]
          )
        ).to.eql([-10n, 2n]);
      });

      it("can set multiple bool attributes at the same time", async function () {
        await expect(
          tokenAttributes.setBoolAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "bool1", value: true },
              { key: "bool2", value: false },
            ]
          )
        )
          .to.emit(tokenAttributes, "BoolAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "bool1", true)
          .to.emit(tokenAttributes, "BoolAttributeUpdated")
          .withArgs(collectionAddress2, tokenId2, "bool2", false);

        expect(
          await tokenAttributes.getBoolAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            ["bool1", "bool2"]
          )
        ).to.eql([true, false]);
      });

      it("can set multiple address attributes at the same time", async function () {
        await expect(
          tokenAttributes.setAddressAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "address1", value: tokenOwner.address },
              { key: "address2", value: collectionOwner.address },
            ]
          )
        )
          .to.emit(tokenAttributes, "AddressAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "address1", tokenOwner.address)
          .to.emit(tokenAttributes, "AddressAttributeUpdated")
          .withArgs(
            collectionAddress2,
            tokenId2,
            "address2",
            collectionOwner.address
          );

        expect(
          await tokenAttributes.getAddressAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            ["address1", "address2"]
          )
        ).to.eql([tokenOwner.address, collectionOwner.address]);
      });

      it("can set multiple bytes attributes at the same time", async function () {
        await expect(
          tokenAttributes.setBytesAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "bytes1", value: "0x1234" },
              { key: "bytes2", value: "0x5678" },
            ]
          )
        )
          .to.emit(tokenAttributes, "BytesAttributeUpdated")
          .withArgs(collectionAddress, tokenId, "bytes1", "0x1234")
          .to.emit(tokenAttributes, "BytesAttributeUpdated")
          .withArgs(collectionAddress2, tokenId2, "bytes2", "0x5678");

        expect(
          await tokenAttributes.getBytesAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            ["bytes1", "bytes2"]
          )
        ).to.eql(["0x1234", "0x5678"]);
      });
    });

    describe("Batch setters, multiple attributes, multiple collections and multple tokens with different lengths", async function () {
      it("cannot set multiple string attributes at the same time if lenghts do not match", async function () {
        await expect(
          tokenAttributes.setStringAttributes(
            [collectionAddress, collectionAddress, collectionAddress2], // Additonal collection
            [tokenId, tokenId2],
            [
              { key: "string1", value: "value1" },
              { key: "string2", value: "value2" },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setStringAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId, tokenId2], // Additonal token
            [
              { key: "string1", value: "value1" },
              { key: "string2", value: "value2" },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setStringAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "string1", value: "value1" },
              { key: "string1", value: "value1" }, // Additional attribute
              { key: "string2", value: "value2" },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setStringAttributes(
            [
              collectionAddress,
              collectionAddress, // Additional collection
              collectionAddress2,
            ],
            [tokenId, tokenId2],
            [{ key: "string1", value: "value1" }]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
      });

      it("cannot set multiple uint attributes at the same time if lenghts do not match", async function () {
        await expect(
          tokenAttributes.setUintAttributes(
            [collectionAddress, collectionAddress, collectionAddress2], // Additonal collection
            [tokenId, tokenId2],
            [
              { key: "uint1", value: 1n },
              { key: "uint2", value: 2n },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setUintAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId, tokenId2], // Additonal token
            [
              { key: "uint1", value: 1n },
              { key: "uint2", value: 2n },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setUintAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "uint1", value: 1n },
              { key: "uint1", value: 1n }, // Additional attribute
              { key: "uint2", value: 2n },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
      });

      it("cannot set multiple int attributes at the same time if lenghts do not match", async function () {
        await expect(
          tokenAttributes.setIntAttributes(
            [collectionAddress, collectionAddress, collectionAddress2], // Additonal collection
            [tokenId, tokenId2],
            [
              { key: "int1", value: -10n },
              { key: "int2", value: 2n },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setIntAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId, tokenId2], // Additonal token
            [
              { key: "int1", value: -10n },
              { key: "int2", value: 2n },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setIntAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "int1", value: -10n },
              { key: "int1", value: -10n }, // Additional attribute
              { key: "int2", value: 2n },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
      });

      it("cannot set multiple bool attributes at the same time if lenghts do not match", async function () {
        await expect(
          tokenAttributes.setBoolAttributes(
            [collectionAddress, collectionAddress, collectionAddress2], // Additonal collection
            [tokenId, tokenId2],
            [
              { key: "bool1", value: true },
              { key: "bool2", value: false },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setBoolAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId, tokenId2], // Additonal token
            [
              { key: "bool1", value: true },
              { key: "bool2", value: false },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setBoolAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "bool1", value: true },
              { key: "bool1", value: true }, // Additional attribute
              { key: "bool2", value: false },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
      });

      it("cannot set multiple address attributes at the same time if lenghts do not match", async function () {
        await expect(
          tokenAttributes.setAddressAttributes(
            [collectionAddress, collectionAddress, collectionAddress2], // Additonal collection
            [tokenId, tokenId2],
            [
              { key: "address1", value: tokenOwner.address },
              { key: "address2", value: collectionOwner.address },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setAddressAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId, tokenId2], // Additonal token
            [
              { key: "address1", value: tokenOwner.address },
              { key: "address2", value: collectionOwner.address },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setAddressAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "address1", value: tokenOwner.address },
              { key: "address1", value: tokenOwner.address }, // Additional attribute
              { key: "address2", value: collectionOwner.address },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
      });

      it("cannot set multiple bytes attributes at the same time if lenghts do not match", async function () {
        await expect(
          tokenAttributes.setBytesAttributes(
            [collectionAddress, collectionAddress, collectionAddress2], // Additonal collection
            [tokenId, tokenId2],
            [
              { key: "bytes1", value: "0x1234" },
              { key: "bytes2", value: "0x5678" },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setBytesAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId, tokenId2], // Additonal token
            [
              { key: "bytes1", value: "0x1234" },
              { key: "bytes2", value: "0x5678" },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
        await expect(
          tokenAttributes.setBytesAttributes(
            [collectionAddress, collectionAddress2],
            [tokenId, tokenId2],
            [
              { key: "bytes1", value: "0x1234" },
              { key: "bytes1", value: "0x1234" }, // Additional attribute
              { key: "bytes2", value: "0x5678" },
            ]
          )
        ).to.be.revertedWithCustomError(tokenAttributes, "LengthsMismatch");
      });
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
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should not allow to set uint values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setUintAttribute(collectionAddress, tokenId, "X", 42n)
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should not allow to set boolean values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setBoolAttribute(collectionAddress, tokenId, "X", true)
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
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
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should not allow to set bytes values to unauthorized caller", async function () {
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setBytesAttribute(collectionAddress, tokenId, "X", "0x1234")
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });
  });

  describe("Token attributes access control", async function () {
    it("should allow registering an already registered collection", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        false
      );

      await expect(
        tokenAttributes.registerAccessControl(
          collectionAddress,
          collectionOwner.address,
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
            collectionOwner.address,
            true
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should not allow to register a collection without Ownable implemented", async function () {
      const erc20Factory = await ethers.getContractFactory("ERC20Mock");
      const erc20 = await erc20Factory.deploy();
      await expect(
        tokenAttributes.registerAccessControl(
          await erc20.getAddress(),
          collectionOwner.address,
          false
        )
      ).to.be.revertedWithCustomError(tokenAttributes, "OwnableNotImplemented");
    });

    it("should allow to manage access control for registered collections", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        false
      );

      expect(
        await tokenAttributes
          .connect(collectionOwner)
          .manageAccessControl(
            collectionAddress,
            "X",
            AccessType.OwnerOrCollaborator,
            tokenOwner.address
          )
      )
        .to.emit(tokenAttributes, "AccessControlUpdate")
        .withArgs(collectionAddress, "X", 2, tokenOwner);
    });

    it("should allow owner to manage collaborators", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
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

    it("should not allow to manage collaborators if the caller is not the owner", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        false
      );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .manageCollaborators(collectionAddress, [tokenOwner.address], [true])
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should not allow to manage collaborators for registered collections if collaborator arrays are not of equal length", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        false
      );

      await expect(
        tokenAttributes
          .connect(collectionOwner)
          .manageCollaborators(
            collectionAddress,
            [tokenOwner.address, collectionOwner.address],
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
            AccessType.OwnerOrCollaborator,
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(
        tokenAttributes,
        "CollectionNotRegistered"
      );
    });

    it("should not allow to manage access control if the caller is not owner", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        false
      );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .manageAccessControl(
            collectionAddress,
            "X",
            AccessType.OwnerOrCollaborator,
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should not allow to manage access control if the caller is not returned as collection owner when using ownable", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
        true
      );

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .manageAccessControl(
            collectionAddress,
            "X",
            AccessType.OwnerOrCollaborator,
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should return the expected value when checking for collaborators", async function () {
      await tokenAttributes.registerAccessControl(
        collectionAddress,
        collectionOwner.address,
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
        collectionOwner.address,
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
          AccessType.OwnerOrCollaborator,
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

    it("should use the owner returned from the collection when using only owner when only owner is allowed to manage parameter", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          collectionOwner.address,
          true
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.Owner,
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
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");

      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .setAddressAttribute(
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });

    it("should only allow collaborator to modify the parameters if only collaborator is allowed to modify them", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          collectionOwner.address,
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

    it("should only allow owner and collaborator to modify the parameters if only owner and collaborator is allowed to modify them", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          collectionOwner.address,
          false
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.OwnerOrCollaborator,
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
        "NotCollectionOwnerOrCollaborator"
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

    it("should only allow owner and collaborator to modify the parameters if only owner and collaborator is allowed to modify them even when using the ownable", async function () {
      await tokenAttributes
        .connect(collectionOwner)
        .registerAccessControl(
          collectionAddress,
          collectionOwner.address,
          true
        );

      await tokenAttributes
        .connect(collectionOwner)
        .manageAccessControl(
          collectionAddress,
          "X",
          AccessType.OwnerOrCollaborator,
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
        "NotCollectionOwnerOrCollaborator"
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
          collectionOwner.address,
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
          collectionOwner.address,
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
          collectionOwner.address,
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
      const intMessage =
        await tokenAttributes.prepareMessageToPresignIntAttribute(
          collectionAddress,
          tokenId,
          "X",
          -10n,
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
      const intSignature = await collectionOwner.signMessage(
        ethers.getBytes(intMessage)
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

      const intR: string = intSignature.substring(0, 66);
      const intS: string = "0x" + intSignature.substring(66, 130);
      const intV: string = parseInt(
        intSignature.substring(130, 132),
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
            collectionOwner.address,
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
          .presignedSetIntAttribute(
            collectionOwner.address,
            collectionAddress,
            tokenId,
            "X",
            -10n,
            9999999999n,
            intV,
            intR,
            intS
          )
      )
        .to.emit(tokenAttributes, "IntAttributeUpdated")
        .withArgs(collectionAddress, 1, "X", -10);
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetStringAttribute(
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
          collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
          collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
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
            collectionOwner.address,
            collectionAddress,
            tokenId,
            "X",
            1,
            9999999999n,
            uintV,
            uintR,
            uintS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetStringAttribute(
            collectionOwner.address,
            collectionAddress,
            tokenId,
            "X",
            "test",
            9999999999n,
            stringV,
            stringR,
            stringS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBoolAttribute(
            collectionOwner.address,
            collectionAddress,
            tokenId,
            "X",
            true,
            9999999999n,
            boolV,
            boolR,
            boolS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetBytesAttribute(
            collectionOwner.address,
            collectionAddress,
            tokenId,
            "X",
            "0x1234",
            9999999999n,
            bytesV,
            bytesR,
            bytesS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
      await expect(
        tokenAttributes
          .connect(tokenOwner)
          .presignedSetAddressAttribute(
            collectionOwner.address,
            collectionAddress,
            tokenId,
            "X",
            tokenOwner.address,
            9999999999n,
            addressV,
            addressR,
            addressS
          )
      ).to.be.revertedWithCustomError(tokenAttributes, "NotCollectionOwner");
    });
  });
});
