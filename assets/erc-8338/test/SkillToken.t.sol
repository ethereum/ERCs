// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SkillToken} from "../contracts/SkillToken.sol";
import {ISkillToken} from "../contracts/interfaces/ISkillToken.sol";
import {IOnchainSkillDocument} from "../contracts/interfaces/IOnchainSkillDocument.sol";

/// Every test maps to a MUST clause of KERNEL v4.3 (frozen). Comments cite the rule.
contract SkillTokenTest is Test {
    SkillToken st;

    address creator     = address(0xC0FFEE);
    address buyer       = address(0xB0B);
    address marketplace = address(0xFEE1);

    // real fingerprints from the frozen public-v1 vector (finchip-daily-finance-brief)
    bytes32 constant MD  = 0x3ffb913330b04a8ec121fa218cc9dcc8916bc10aaf88a5b58aefb331c1c3015f;
    bytes32 constant PKG1 = keccak256("skillroot-v1"); // placeholder package digests
    bytes32 constant PKG2 = keccak256("skillroot-v2");
    bytes32 constant PKG3 = keccak256("skillroot-v3");

    function setUp() public {
        st = new SkillToken("Skill Token", "SKILL");
    }

    function _mint() internal returns (uint256 id) {
        vm.prank(creator);
        id = st.mintSkill(creator, creator, MD, PKG1, "ipfs://root-v1");
    }

    // ---------------- ERC-165: both interface ids discoverable
    function test_erc165() public view {
        assertTrue(st.supportsInterface(0x01ffc9a7)); // 165
        assertTrue(st.supportsInterface(0x80ac58cd)); // 721
        assertTrue(st.supportsInterface(type(ISkillToken).interfaceId));           // 0x734553a6
        assertTrue(st.supportsInterface(type(IOnchainSkillDocument).interfaceId)); // 0x7050dd2c
        assertEq(bytes32(type(ISkillToken).interfaceId), bytes32(bytes4(0x734553a6)));
        assertEq(bytes32(type(IOnchainSkillDocument).interfaceId), bytes32(bytes4(0x7050dd2c)));
    }

    // ---------------- mint: full binding, version 1, genesis events
    function test_mint_genesis() public {
        vm.expectEmit(true, false, false, true);
        emit ISkillToken.SkillUpdated(1, MD, PKG1, 1);
        vm.expectEmit(true, true, true, false);
        emit ISkillToken.SkillUpdateAuthorityChanged(1, address(0), creator);
        uint256 id = _mint();
        ISkillToken.SkillBinding memory b = st.skillOf(id);
        assertEq(b.version, 1);
        assertEq(b.mdHash, MD);
        assertEq(b.packageHash, PKG1);
    }

    function test_mint_rejects_placeholders() public {
        vm.startPrank(creator);
        vm.expectRevert(); st.mintSkill(creator, creator, bytes32(0), PKG1, "u");
        vm.expectRevert(); st.mintSkill(creator, creator, MD, bytes32(0), "u");
        vm.expectRevert(); st.mintSkill(creator, creator, MD, PKG1, "");
        vm.expectRevert(); st.mintSkill(creator, address(0), MD, PKG1, "u");
        vm.stopPrank();
    }

    // ---------------- nonexistent tokenId MUST revert on all views
    function test_nonexistent_reverts() public {
        vm.expectRevert(); st.skillOf(99);
        vm.expectRevert(); st.skillURI(99);
        vm.expectRevert(); st.updateAuthorityOf(99);
        vm.expectRevert(); st.isSkillFrozen(99);
        vm.expectRevert(); st.hasOnchainSkillDocument(99);
    }

    // ---------------- update rules: packageHash MUST differ; mdHash MAY stay
    function test_update_rules() public {
        uint256 id = _mint();
        vm.prank(creator);
        st.updateSkill(id, MD, PKG2);                    // companion-file-only update
        assertEq(st.skillOf(id).version, 2);
        assertEq(st.skillOf(id).mdHash, MD);             // mdHash unchanged: legal
        vm.prank(creator);
        vm.expectRevert();                               // same packageHash: illegal
        st.updateSkill(id, MD, PKG2);
        vm.prank(creator);
        vm.expectRevert();                               // zero hash: illegal
        st.updateSkill(id, bytes32(0), PKG3);
    }

    // ---------------- three-power separation: approvals never reach publication
    function test_approval_leakage_blocked() public {
        uint256 id = _mint();
        vm.prank(creator); st.approve(marketplace, id);
        vm.prank(creator); st.setApprovalForAll(marketplace, true);
        vm.startPrank(marketplace);
        vm.expectRevert(); st.updateSkill(id, MD, PKG2);
        vm.expectRevert(); st.setSkillURI(id, "ipfs://evil");
        vm.expectRevert(); st.setUpdateAuthority(id, marketplace);
        vm.expectRevert(); st.freezeSkill(id);
        st.transferFrom(creator, buyer, id);             // trading still works
        vm.stopPrank();
        assertEq(st.ownerOf(id), buyer);
        assertEq(st.updateAuthorityOf(id), creator);     // transfer never moves authority
        vm.prank(buyer);
        vm.expectRevert();                               // new owner has no publication power
        st.updateSkill(id, MD, PKG2);
    }

    // ---------------- authority transfer; zero forbidden
    function test_authority_transfer() public {
        uint256 id = _mint();
        vm.prank(creator);
        vm.expectRevert();                               // zero authority MUST revert
        st.setUpdateAuthority(id, address(0));
        vm.prank(creator); st.setUpdateAuthority(id, buyer);
        assertEq(st.updateAuthorityOf(id), buyer);
        vm.prank(creator);
        vm.expectRevert();                               // old authority is out
        st.updateSkill(id, MD, PKG2);
    }

    // ---------------- freeze: irreversible, binds content not transport
    function test_freeze() public {
        uint256 id = _mint();
        vm.prank(creator); st.freezeSkill(id);
        assertTrue(st.isSkillFrozen(id));
        vm.startPrank(creator);
        vm.expectRevert(); st.updateSkill(id, MD, PKG2);          // content frozen
        vm.expectRevert(); st.updateSkillWithDocument(id, "x", PKG2);
        st.setSkillURI(id, "ar://new-mirror");                    // transport lives on
        st.setUpdateAuthority(id, buyer);                         // stewardship transferable
        vm.expectRevert(); st.freezeSkill(id);                    // double-freeze revert
        vm.stopPrank();
    }

    // ---------------- setSkillURI never bumps version
    function test_uri_outside_identity() public {
        uint256 id = _mint();
        vm.prank(creator); st.setSkillURI(id, "https://mirror.example/pkg");
        assertEq(st.skillOf(id).version, 1);
        assertEq(st.skillURI(id), "https://mirror.example/pkg");
    }

    // ---------------- on-chain document lifecycle
    function test_onchain_document() public {
        uint256 id = _mint();
        bytes memory doc = "# finchip-daily-finance-brief\n";
        // publish MUST reject non-matching plaintext
        vm.prank(creator);
        vm.expectRevert();
        st.publishSkillDocument(id, doc);
        // atomic path: mdHash computed in-contract; version bumps; has -> true
        vm.prank(creator);
        st.updateSkillWithDocument(id, doc, PKG2);
        assertTrue(st.hasOnchainSkillDocument(id));
        assertEq(sha256(st.skillDocument(id)), st.skillOf(id).mdHash); // invariant 1
        assertEq(st.skillOf(id).version, 2);
        // with a live on-chain doc, plain updateSkill changing mdHash MUST revert
        vm.prank(creator);
        vm.expectRevert();
        st.updateSkill(id, keccak256("other-md"), PKG3);
        // ... but a companion-only update (same mdHash) is fine
        bytes32 cur = st.skillOf(id).mdHash;
        vm.prank(creator);
        st.updateSkill(id, cur, PKG3);
        assertEq(st.skillOf(id).version, 3);
        assertTrue(st.hasOnchainSkillDocument(id));       // monotone survives updates
    }

    // ---------------- publish without version change (disclosure only)
    function test_publish_no_version_change() public {
        uint256 id = _mint();
        bytes memory real = hex"23"; // must hash to MD to publish; use matching path:
        // mint a token whose mdHash matches a known document
        bytes memory doc = "hello skill";
        vm.prank(creator);
        uint256 id2 = st.mintSkill(creator, creator, sha256(doc), PKG1, "ipfs://x");
        vm.prank(creator);
        st.publishSkillDocument(id2, doc);
        assertTrue(st.hasOnchainSkillDocument(id2));
        assertEq(st.skillOf(id2).version, 1);             // MUST NOT change version
        assertEq(st.skillOf(id2).packageHash, PKG1);      // MUST NOT change packageHash
        real; id;                                         // silence warnings
    }

    // ---------------- document access before publication reverts
    function test_document_absent_reverts() public {
        uint256 id = _mint();
        assertFalse(st.hasOnchainSkillDocument(id));
        vm.expectRevert();
        st.skillDocument(id);
    }
}
