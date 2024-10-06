// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {IERC721Errors} from "openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC7496} from "src/dynamic-traits/interfaces/IERC7496.sol";
import {ERC721DynamicTraits} from "src/dynamic-traits/ERC721DynamicTraits.sol";
import {Solarray} from "solarray/Solarray.sol";

contract ERC721DynamicTraitsMintable is ERC721DynamicTraits {
    constructor() ERC721DynamicTraits() {}

    function mint(address to, uint256 tokenId) public onlyOwner {
        _mint(to, tokenId);
    }
}

contract ERC721DynamicTraitsTest is Test {
    ERC721DynamicTraitsMintable token;

    /* Events */
    event TraitUpdated(bytes32 indexed traitKey, uint256 tokenId, bytes32 trait);
    event TraitMetadataURIUpdated();

    function setUp() public {
        token = new ERC721DynamicTraitsMintable();
    }

    function testSupportsInterfaceId() public {
        assertTrue(token.supportsInterface(type(IERC7496).interfaceId));
    }

    function testReturnsValueSet() public {
        bytes32 key = bytes32("testKey");
        bytes32 value = bytes32("foo");
        uint256 tokenId = 12345;
        token.mint(address(this), tokenId);

        vm.expectEmit(true, true, true, true);
        emit TraitUpdated(key, tokenId, value);

        token.setTrait(tokenId, key, value);

        assertEq(token.getTraitValue(tokenId, key), value);
    }

    function testOnlyOwnerCanSetValues() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        token.setTrait(0, bytes32("test"), bytes32("test"));
    }

    function testSetTrait_Unchanged() public {
        bytes32 key = bytes32("testKey");
        bytes32 value = bytes32("foo");
        uint256 tokenId = 1;
        token.mint(address(this), tokenId);

        token.setTrait(tokenId, key, value);
        vm.expectRevert(IERC7496.TraitValueUnchanged.selector);
        token.setTrait(tokenId, key, value);
    }

    function testGetTraitValues() public {
        bytes32 key1 = bytes32("testKeyOne");
        bytes32 key2 = bytes32("testKeyTwo");
        bytes32 value1 = bytes32("foo");
        bytes32 value2 = bytes32("bar");
        uint256 tokenId = 1;
        token.mint(address(this), tokenId);

        token.setTrait(tokenId, key1, value1);
        token.setTrait(tokenId, key2, value2);

        bytes32[] memory values = token.getTraitValues(tokenId, Solarray.bytes32s(key1, key2));
        assertEq(values[0], value1);
        assertEq(values[1], value2);
    }

    function testGetAndSetTraitMetadataURI() public {
        string memory uri = "https://example.com/labels.json";

        vm.expectEmit(true, true, true, true);
        emit TraitMetadataURIUpdated();
        token.setTraitMetadataURI(uri);

        assertEq(token.getTraitMetadataURI(), uri);

        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1234)));
        token.setTraitMetadataURI(uri);
    }

    function testGetAndSetTraitValue_NonexistantToken() public {
        bytes32 key = bytes32("testKey");
        bytes32 value = bytes32(uint256(1));
        uint256 tokenId = 1;

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        token.setTrait(tokenId, key, value);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        token.getTraitValue(tokenId, key);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        token.getTraitValues(tokenId, Solarray.bytes32s(key));
    }

    function testGetTraitValue_DefaultZeroValue() public {
        bytes32 key = bytes32("testKey");
        uint256 tokenId = 1;
        token.mint(address(this), tokenId);

        bytes32 value = token.getTraitValue(tokenId, key);
        assertEq(value, bytes32(0), "should return bytes32(0)");

        bytes32[] memory values = token.getTraitValues(tokenId, Solarray.bytes32s(key));
        assertEq(values[0], bytes32(0), "should return bytes32(0)");
    }
}
