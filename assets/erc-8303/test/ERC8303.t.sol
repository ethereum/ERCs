// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC8303} from "../src/IERC8303.sol";
import {ERC8303} from "../src/ERC8303.sol";
import {ERC20VersionedExample} from "../src/examples/ERC20VersionedExample.sol";
import {ERC721VersionedExample} from "../src/examples/ERC721VersionedExample.sol";

contract ERC8303Concrete is ERC8303 {}

contract ERC8303Test is Test {
    bytes4 private constant INVALID_INTERFACE_ID = 0xffffffff;
    bytes4 private constant ERC8303_INTERFACE_ID = 0x54fd4d50;

    ERC8303Concrete private base;
    ERC20VersionedExample private erc20;
    ERC721VersionedExample private erc721;

    function setUp() public {
        base = new ERC8303Concrete();
        erc20 = new ERC20VersionedExample(1_000 ether);
        erc721 = new ERC721VersionedExample();
    }

    // --- Base contract ---

    function test_BaseVersionDoesNotRevertAndReturnsDeclaredVersion() public view {
        string memory declaredVersion = base.version();

        assertEq(declaredVersion, "1.0.0");
        assertEq(base.VERSION(), "1.0.0");
        assertGt(bytes(declaredVersion).length, 0);
    }

    function test_BaseSupportsERC8303Interface() public view {
        assertTrue(base.supportsInterface(ERC8303_INTERFACE_ID));
        assertTrue(base.supportsInterface(type(IERC165).interfaceId));
        assertFalse(base.supportsInterface(INVALID_INTERFACE_ID));
    }

    function test_IERC8303InterfaceIdMatchesSpecification() public pure {
        assertEq(type(IERC8303).interfaceId, ERC8303_INTERFACE_ID);
    }

    function test_ERC20VersionDoesNotRevertAndReturnsDeclaredVersion() public view {
        string memory declaredVersion = erc20.version();

        assertEq(declaredVersion, "1.0.0");
        assertEq(erc20.VERSION(), "1.0.0");
        assertGt(bytes(declaredVersion).length, 0);
    }

    function test_ERC20SupportsERC8303Interface() public view {
        assertTrue(erc20.supportsInterface(ERC8303_INTERFACE_ID));
        assertTrue(erc20.supportsInterface(type(IERC165).interfaceId));
        assertFalse(erc20.supportsInterface(INVALID_INTERFACE_ID));
    }

    function test_ERC20KeepsTokenBehavior() public view {
        assertEq(erc20.name(), "Versioned ERC20");
        assertEq(erc20.symbol(), "VER20");
        assertEq(erc20.balanceOf(address(this)), 1_000 ether);
        assertEq(erc20.totalSupply(), 1_000 ether);
    }

    function test_ERC721VersionDoesNotRevertAndReturnsDeclaredVersion() public view {
        string memory declaredVersion = erc721.version();

        assertEq(declaredVersion, "1.0.0");
        assertEq(erc721.VERSION(), "1.0.0");
        assertGt(bytes(declaredVersion).length, 0);
    }

    function test_ERC721SupportsERC8303AndERC721Interfaces() public view {
        assertTrue(erc721.supportsInterface(ERC8303_INTERFACE_ID));
        assertTrue(erc721.supportsInterface(type(IERC165).interfaceId));
        assertTrue(erc721.supportsInterface(type(IERC721).interfaceId));
        assertTrue(erc721.supportsInterface(type(IERC721Metadata).interfaceId));
        assertFalse(erc721.supportsInterface(INVALID_INTERFACE_ID));
    }

    function test_ERC721KeepsTokenBehavior() public {
        address owner = makeAddr("owner");

        uint256 tokenId = erc721.mint(owner, "https://eips.ethereum.org/erc");

        assertEq(tokenId, 0);
        assertEq(erc721.ownerOf(tokenId), owner);
        assertEq(erc721.tokenURI(tokenId), "https://eips.ethereum.org/erc");
    }
}
