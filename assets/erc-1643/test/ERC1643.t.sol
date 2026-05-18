// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20DocumentToken} from "src/ERC20DocumentToken.sol";
import {ERC721DocumentToken} from "src/ERC721DocumentToken.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC1643} from "src/erc-1643/IERC1643.sol";
import {IERC165} from "openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

contract ERC1643ModuleTest is Test {
    event DocumentUpdated(bytes32 indexed name, string uri, bytes32 documentHash);
    event DocumentRemoved(bytes32 indexed name, string uri, bytes32 documentHash);

    ERC20DocumentToken internal erc20;
    ERC721DocumentToken internal erc721;

    address internal owner = address(0xA11CE);
    address internal alice = address(0xB0B);

    bytes32 internal constant DOC1 = bytes32("TERMS");
    bytes32 internal constant DOC2 = bytes32("DISCLOSURE");

    function setUp() public {
        erc20 = new ERC20DocumentToken("Doc20", "D20", owner);
        erc721 = new ERC721DocumentToken("Doc721", "D721", owner);
    }

    function testERC20_DocumentLifecycle() public {
        bytes32 hash1 = keccak256("doc-v1");
        bytes32 hash2 = keccak256("doc-v2");

        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit DocumentUpdated(DOC1, "ipfs://terms-v1", hash1);
        erc20.setDocument(DOC1, "ipfs://terms-v1", hash1);

        (string memory uri1, bytes32 docHash1, uint256 lastMod1) = erc20.getDocument(DOC1);
        assertEq(uri1, "ipfs://terms-v1");
        assertEq(docHash1, hash1);
        assertGt(lastMod1, 0);

        vm.warp(block.timestamp + 1);
        vm.expectEmit(true, true, true, true);
        emit DocumentUpdated(DOC1, "ipfs://terms-v2", hash2);
        erc20.setDocument(DOC1, "ipfs://terms-v2", hash2);

        (string memory uri2, bytes32 docHash2, uint256 lastMod2) = erc20.getDocument(DOC1);
        assertEq(uri2, "ipfs://terms-v2");
        assertEq(docHash2, hash2);
        assertGt(lastMod2, lastMod1);

        vm.expectEmit(true, true, true, true);
        emit DocumentRemoved(DOC1, "ipfs://terms-v2", hash2);
        erc20.removeDocument(DOC1);

        (string memory uri3, bytes32 docHash3, uint256 lastMod3) = erc20.getDocument(DOC1);
        assertEq(uri3, "");
        assertEq(docHash3, bytes32(0));
        assertEq(lastMod3, 0);

        bytes32[] memory docs = erc20.getAllDocuments();
        assertEq(docs.length, 0);

        vm.stopPrank();
    }

    function testERC20_EnumerationConsistency() public {
        vm.startPrank(owner);

        erc20.setDocument(DOC1, "ipfs://1", keccak256("1"));
        erc20.setDocument(DOC2, "ipfs://2", keccak256("2"));

        bytes32[] memory docs = erc20.getAllDocuments();
        assertEq(docs.length, 2);

        erc20.removeDocument(DOC1);
        docs = erc20.getAllDocuments();
        assertEq(docs.length, 1);
        assertEq(docs[0], DOC2);

        vm.stopPrank();
    }

    function testERC20_ReAddAfterRemoval_SwapAndPopPath() public {
        vm.startPrank(owner);

        // Setup two docs so removing DOC1 triggers swap-and-pop with DOC2.
        erc20.setDocument(DOC1, "ipfs://terms-v1", keccak256("terms-v1"));
        erc20.setDocument(DOC2, "ipfs://disc-v1", keccak256("disc-v1"));

        erc20.removeDocument(DOC1);

        bytes32[] memory docsAfterRemove = erc20.getAllDocuments();
        assertEq(docsAfterRemove.length, 1);
        assertEq(docsAfterRemove[0], DOC2);

        // Re-add DOC1 and ensure it behaves as a fresh active entry.
        erc20.setDocument(DOC1, "ipfs://terms-v2", keccak256("terms-v2"));

        bytes32[] memory docsAfterReAdd = erc20.getAllDocuments();
        assertEq(docsAfterReAdd.length, 2);
        assertEq(docsAfterReAdd[0], DOC2);
        assertEq(docsAfterReAdd[1], DOC1);

        (string memory uri1, bytes32 hash1, uint256 lastMod1) = erc20.getDocument(DOC1);
        assertEq(uri1, "ipfs://terms-v2");
        assertEq(hash1, keccak256("terms-v2"));
        assertGt(lastMod1, 0);

        // Ensure DOC1 can be removed again cleanly after re-add.
        erc20.removeDocument(DOC1);
        bytes32[] memory docsAfterSecondRemove = erc20.getAllDocuments();
        assertEq(docsAfterSecondRemove.length, 1);
        assertEq(docsAfterSecondRemove[0], DOC2);

        vm.stopPrank();
    }

    function testERC20_OnlyOwnerCanMutate() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        erc20.setDocument(DOC1, "ipfs://terms", keccak256("terms"));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        erc20.removeDocument(DOC1);
    }

    function testERC721_DocumentLifecycleAndOnlyOwner() public {
        bytes32 hash1 = keccak256("nft-doc");

        vm.prank(owner);
        erc721.setDocument(DOC1, "https://issuer.example/doc", hash1);

        (string memory uri1, bytes32 docHash1, uint256 lastMod1) = erc721.getDocument(DOC1);
        assertEq(uri1, "https://issuer.example/doc");
        assertEq(docHash1, hash1);
        assertGt(lastMod1, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        erc721.removeDocument(DOC1);

        vm.prank(owner);
        erc721.removeDocument(DOC1);

        (string memory uri2, bytes32 docHash2, uint256 lastMod2) = erc721.getDocument(DOC1);
        assertEq(uri2, "");
        assertEq(docHash2, bytes32(0));
        assertEq(lastMod2, 0);
    }

    function testRemoveMissingDocumentReverts() public {
        vm.prank(owner);
        vm.expectRevert(IERC1643.ERC1643MissingDocument.selector);
        erc20.removeDocument(bytes32("MISSING"));
    }

    function testERC20_ZeroNameReverts() public {
        vm.prank(owner);
        vm.expectRevert(IERC1643.ERC1643InvalidName.selector);
        erc20.setDocument(bytes32(0), "ipfs://zero-name", keccak256("zero-name-doc"));
    }

    function testERC20_EmptyUriAndHashAllowed() public {
        bytes32 name = bytes32("EMPTY_META");

        vm.prank(owner);
        erc20.setDocument(name, "", bytes32(0));

        (string memory uri, bytes32 storedHash, uint256 lastMod) = erc20.getDocument(name);
        assertEq(uri, "");
        assertEq(storedHash, bytes32(0));
        assertGt(lastMod, 0);
    }

    function testERC165Support_ERC20AndERC721() public view {
        bytes4 erc1643Id = type(IERC1643).interfaceId;
        bytes4 erc165Id = type(IERC165).interfaceId;
        bytes4 randomId = 0x12345678;

        assertTrue(erc20.supportsInterface(erc1643Id));
        assertTrue(erc20.supportsInterface(erc165Id));
        assertFalse(erc20.supportsInterface(randomId));

        assertTrue(erc721.supportsInterface(erc1643Id));
        assertTrue(erc721.supportsInterface(erc165Id));
        assertFalse(erc721.supportsInterface(randomId));
    }
}
