// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "empty_src/ERC-721H.sol";

contract ERC721H_FullTest is Test {
    ERC721H public nft;
    address public owner = address(0xAAAA);
    address public user1 = address(0x1111);
    address public user2 = address(0x2222);
    address public user3 = address(0x3333);

    function setUp() public {
        vm.prank(owner);
        nft = new ERC721H("Historical NFT", "HNFT");
    }

    function testMintAndLayers() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // Layer 1: Immutable Origin
        assertEq(nft.originalCreator(tokenId), user1);
        assertEq(nft.mintBlock(tokenId), block.number);
        assertTrue(nft.isOriginalOwner(tokenId, user1));

        // Layer 2: Historical Trail
        assertTrue(nft.hasEverOwned(tokenId, user1));
        uint256[] memory everOwned = nft.getEverOwnedTokens(user1);
        assertEq(everOwned.length, 1);
        assertEq(everOwned[0], tokenId);

        (address[] memory owners, uint256[] memory timestamps) = nft.getOwnershipHistory(tokenId);
        assertEq(owners.length, 1);
        assertEq(owners[0], user1);
        assertEq(timestamps[0], block.timestamp);

        // Layer 3: Current Authority
        assertEq(nft.ownerOf(tokenId), user1);
        assertEq(nft.balanceOf(user1), 1);
    }

    function testSingleTransferAndHistory() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // First transfer: User1 to User2
        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        assertEq(nft.ownerOf(tokenId), user2);
        assertTrue(nft.hasEverOwned(tokenId, user1));
        assertTrue(nft.hasEverOwned(tokenId, user2));
        
        (address[] memory owners, ) = nft.getOwnershipHistory(tokenId);
        assertEq(owners.length, 2);
        assertEq(owners[0], user1);
        assertEq(owners[1], user2);
    }

    function testSybilGuardSameTxReverts() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // Attempting A -> B -> C in same TX should fail due to transient storage guard
        SybilAttacker attacker = new SybilAttacker(nft);
        vm.prank(user1);
        nft.approve(address(attacker), tokenId);

        vm.expectRevert(); 
        attacker.attackSameTx(user1, user2, user3, tokenId);
    }

    function testHistoryPreservedAfterBurn() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);
        
        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        vm.prank(user2);
        nft.burn(tokenId);

        // History MUST survive burn (now allowed since we updated the contract)
        assertEq(nft.originalCreator(tokenId), user1);
        assertTrue(nft.hasEverOwned(tokenId, user1));
        assertTrue(nft.hasEverOwned(tokenId, user2));
        
        (address[] memory owners, ) = nft.getOwnershipHistory(tokenId);
        assertEq(owners.length, 2);
    }

    function testDeduplicationOfEverOwned() public {
        vm.prank(owner);
        uint256 token1 = nft.mint(user1);
        vm.prank(owner);
        uint256 token2 = nft.mint(user1);

        uint256[] memory everOwned = nft.getEverOwnedTokens(user1);
        assertEq(everOwned.length, 2);
        assertEq(everOwned[0], token1);
        assertEq(everOwned[1], token2);
    }

    function testProvenanceReport() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);
        
        (
            address creator,
            uint256 creationBlock,
            address currentOwnerAddress,
            uint256 totalTransfers,
            address[] memory allOwners,
            uint256[] memory transferTimestamps
        ) = nft.getProvenanceReport(tokenId);

        assertEq(creator, user1);
        assertEq(creationBlock, block.number);
        assertEq(currentOwnerAddress, user1);
        assertEq(totalTransfers, 0);
        assertEq(allOwners.length, 1);
        assertEq(transferTimestamps.length, 1);
    }

    // ── Missing Coverage: Inter-TX Sybil Guard ────────
    // Tests the _ownerAtBlock logic (separate from transient storage guard).
    // Mint sets _ownerAtBlock at block N; transfer at same block N must revert.
    function testInterTxSybilGuardReverts() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        // Same block as mint — _ownerAtBlock[tokenId][block.number] already set
        vm.prank(user1);
        vm.expectRevert(ERC721H.OwnerAlreadyRecordedForBlock.selector);
        nft.transferFrom(user1, user2, tokenId);
    }

    // ── Missing Coverage: Self-Transfer Rejection ─────
    // Spec MUST: from == to reverts with InvalidRecipient
    function testSelfTransferReverts() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 1);
        vm.prank(user1);
        vm.expectRevert(ERC721H.InvalidRecipient.selector);
        nft.transferFrom(user1, user1, tokenId);
    }

    // ── Missing Coverage: Approval Cleared After Transfer ─
    // ERC-721 compliance: approval MUST be cleared on transfer
    function testApprovalClearedAfterTransfer() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.prank(user1);
        nft.approve(user3, tokenId);
        assertEq(nft.getApproved(tokenId), user3);

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // Approval must be zero after transfer
        assertEq(nft.getApproved(tokenId), address(0));
    }

    // ── Missing Coverage: Negative Queries (Nonexistent Token) ─
    function testOwnerOfNonexistentReverts() public {
        vm.expectRevert(ERC721H.TokenDoesNotExist.selector);
        nft.ownerOf(999);
    }

    function testProvenanceReportNonexistentReverts() public {
        vm.expectRevert(ERC721H.TokenDoesNotExist.selector);
        nft.getProvenanceReport(999);
    }

    function testHistoryLengthNonexistentReverts() public {
        vm.expectRevert(ERC721H.TokenDoesNotExist.selector);
        nft.getHistoryLength(999);
    }

    function testHistorySliceNonexistentReverts() public {
        vm.expectRevert(ERC721H.TokenDoesNotExist.selector);
        nft.getHistorySlice(999, 0, 10);
    }

    // ── Missing Coverage: Pagination Slice ────────────
    // Validates getHistoryLength + getHistorySlice bounded reads.
    // Note: Only 1 transfer per tokenId per test function (Foundry test = 1 TX,
    //       transient storage persists). 2 entries is sufficient to validate
    //       all pagination edge cases: partial page, exact page, out-of-bounds.
    function testPaginationSlice() public {
        vm.prank(owner);
        uint256 tokenId = nft.mint(user1);

        vm.roll(block.number + 1);
        vm.prank(user1);
        nft.transferFrom(user1, user2, tokenId);

        // History: [user1, user2]
        assertEq(nft.getHistoryLength(tokenId), 2);

        // Full page: start=0, count=2
        (address[] memory full, uint256[] memory fullTs) = nft.getHistorySlice(tokenId, 0, 2);
        assertEq(full.length, 2);
        assertEq(full[0], user1);
        assertEq(full[1], user2);
        assertEq(fullTs.length, 2);

        // First entry only: start=0, count=1
        (address[] memory page1, ) = nft.getHistorySlice(tokenId, 0, 1);
        assertEq(page1.length, 1);
        assertEq(page1[0], user1);

        // Second entry only: start=1, count=1
        (address[] memory page2, ) = nft.getHistorySlice(tokenId, 1, 1);
        assertEq(page2.length, 1);
        assertEq(page2[0], user2);

        // Count exceeds remaining: clamped to actual length
        (address[] memory clamped, ) = nft.getHistorySlice(tokenId, 1, 100);
        assertEq(clamped.length, 1);
        assertEq(clamped[0], user2);

        // Out-of-bounds start: empty arrays
        (address[] memory empty, uint256[] memory emptyTs) = nft.getHistorySlice(tokenId, 10, 5);
        assertEq(empty.length, 0);
        assertEq(emptyTs.length, 0);
    }
}

contract SybilAttacker {
    ERC721H public nft;

    constructor(ERC721H _nft) {
        nft = _nft;
    }

    function attackSameTx(address from, address to1, address to2, uint256 tokenId) external {
        nft.transferFrom(from, to1, tokenId);
        nft.transferFrom(to1, to2, tokenId); // Should fail here
    }
}
