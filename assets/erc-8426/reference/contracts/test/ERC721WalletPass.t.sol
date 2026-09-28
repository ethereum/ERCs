// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ERC721WalletPass} from "../src/ERC721WalletPass.sol";
import {IERC721WalletPass} from "../src/IERC721WalletPass.sol";

contract ERC721WalletPassTest is Test {
    // Redeclared so the tests can assert on emission with expectEmit.
    event PassUpdate(uint256 indexed tokenId);
    event BatchPassUpdate(uint256 fromTokenId, uint256 toTokenId);

    // Well-known ERC-165 identifiers of the interfaces this contract composes.
    bytes4 internal constant IID_ERC165 = 0x01ffc9a7;
    bytes4 internal constant IID_ERC721 = 0x80ac58cd;
    bytes4 internal constant IID_ERC721_METADATA = 0x5b5e139f;
    bytes4 internal constant IID_WALLET_PASS = 0xef5f1e71;

    string internal constant META_BASE = "https://meta.example/eip155/8453/0xColl/";
    string internal constant PASS_BASE = "https://passes.example/eip155/8453/0xColl/";

    ERC721WalletPass internal pass;
    address internal deployer = makeAddr("deployer");
    address internal holder = makeAddr("holder");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        pass = new ERC721WalletPass("Wallet Pass Demo", "WPD", META_BASE, PASS_BASE, deployer);
    }

    function _mintTo(address to) internal returns (uint256 tokenId) {
        vm.prank(deployer);
        tokenId = pass.mint(to);
    }

    // Interface identifier

    /// The whole standard hangs on this constant being correct.
    function test_InterfaceIdEqualsSpecValue() public pure {
        assertEq(type(IERC721WalletPass).interfaceId, bytes4(0xef5f1e71));
    }

    function test_SupportsWalletPassInterface() public view {
        assertTrue(pass.supportsInterface(IID_WALLET_PASS));
        assertTrue(pass.supportsInterface(type(IERC721WalletPass).interfaceId));
    }

    function test_SupportsInheritedInterfaces() public view {
        assertTrue(pass.supportsInterface(IID_ERC165));
        assertTrue(pass.supportsInterface(IID_ERC721));
        assertTrue(pass.supportsInterface(IID_ERC721_METADATA));
    }

    function test_DoesNotSupportUnrelatedInterface() public view {
        assertFalse(pass.supportsInterface(0xffffffff));
        assertFalse(pass.supportsInterface(0xdeadbeef));
    }

    // passURI

    function test_PassURIComposesBasePlusTokenId() public {
        uint256 tokenId = _mintTo(holder);
        assertEq(pass.passURI(tokenId), string.concat(PASS_BASE, "1"));
    }

    function test_PassURIRevertsForNonexistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(999)));
        pass.passURI(999);
    }

    function test_TokenURIUsesMetadataBase() public {
        uint256 tokenId = _mintTo(holder);
        assertEq(pass.tokenURI(tokenId), string.concat(META_BASE, "1"));
    }

    // Mint

    function test_MintAssignsSequentialIdsAndOwnership() public {
        uint256 first = _mintTo(holder);
        uint256 second = _mintTo(stranger);
        assertEq(first, 1);
        assertEq(second, 2);
        assertEq(pass.ownerOf(first), holder);
        assertEq(pass.ownerOf(second), stranger);
    }

    // PassUpdate on state change

    function test_LevelUpEmitsPassUpdateAndIncrements() public {
        uint256 tokenId = _mintTo(holder);

        vm.expectEmit(true, false, false, true, address(pass));
        emit PassUpdate(tokenId);

        vm.prank(holder);
        pass.levelUp(tokenId);

        assertEq(pass.level(tokenId), 1);

        vm.prank(holder);
        pass.levelUp(tokenId);
        assertEq(pass.level(tokenId), 2);
    }

    function test_LevelUpAllowsApprovedOperator() public {
        uint256 tokenId = _mintTo(holder);

        vm.prank(holder);
        pass.approve(stranger, tokenId);

        vm.prank(stranger);
        pass.levelUp(tokenId);
        assertEq(pass.level(tokenId), 1);
    }

    function test_LevelUpRevertsForUnauthorizedCaller() public {
        uint256 tokenId = _mintTo(holder);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, stranger, tokenId));
        vm.prank(stranger);
        pass.levelUp(tokenId);
    }

    function test_LevelUpRevertsForNonexistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, uint256(1)));
        pass.levelUp(1);
    }

    // BatchPassUpdate

    function test_RefreshPassesEmitsBatchPassUpdate() public {
        vm.expectEmit(false, false, false, true, address(pass));
        emit BatchPassUpdate(1, 100);

        vm.prank(deployer);
        pass.refreshPasses(1, 100);
    }

    function test_RefreshPassesIsOwnerOnly() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        pass.refreshPasses(1, 2);
    }

    function test_RefreshPassesRevertsOnInvertedRange() public {
        vm.expectRevert(abi.encodeWithSelector(ERC721WalletPass.InvalidTokenRange.selector, uint256(5), uint256(4)));
        vm.prank(deployer);
        pass.refreshPasses(5, 4);
    }
}
