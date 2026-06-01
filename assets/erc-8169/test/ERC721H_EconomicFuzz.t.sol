// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "empty_src/ERC-721H.sol";

/**
 * @title Economic Fuzzing Test for ERC-721H
 * @notice Executable fuzz tests targeting the five core attack surfaces:
 *         1. Layer 1 immutability (creator corruption)
 *         2. Layer 2 integrity (unauthorized history infiltration)
 *         3. Sybil manipulation (same-block / same-TX transfer chains)
 *         4. Multi-token cross-token interactions
 *         5. Supply accounting invariants
 */
contract ERC721H_EconomicFuzz is Test {
    ERC721H public nft;
    address public constant OWNER = address(0xAAAA);
    address public constant VICTIM = address(0xDEAD);
    address public constant ATTACKER = address(0x1337);

    function setUp() public {
        vm.prank(OWNER);
        nft = new ERC721H("Historical NFT", "HNFT");
    }

    // ──────────────────────────────────────────────────
    // 1. LAYER 1 IMMUTABILITY — creator must never change
    // ──────────────────────────────────────────────────

    /// @notice Fuzz: regardless of who receives the token, originalCreator is always the minter.
    ///         EIP-1153 transient storage persists per-TX, so Foundry tests can only do
    ///         1 transfer per tokenId. Multi-hop is verified across separate test functions.
    function testFuzz_CreatorImmutableAfterTransfer(uint160 recipientSeed) public {
        // Avoid zero address, VICTIM (self-transfer reverts), and precompiles
        address recipient = address(uint160(bound(recipientSeed, 0x100, type(uint160).max)));
        vm.assume(recipient != VICTIM);

        vm.prank(OWNER);
        uint256 tokenId = nft.mint(VICTIM);
        uint256 mintBlockNum = block.number;

        vm.roll(block.number + 1);
        vm.prank(VICTIM);
        nft.transferFrom(VICTIM, recipient, tokenId);

        // Layer 1: still VICTIM regardless of recipient
        assertEq(nft.originalCreator(tokenId), VICTIM);
        assertTrue(nft.isOriginalOwner(tokenId, VICTIM));
        assertFalse(nft.isOriginalOwner(tokenId, recipient));
        assertEq(nft.mintBlock(tokenId), mintBlockNum);
    }

    /// @notice Creator survives burn — with or without an intermediate transfer
    function testFuzz_CreatorSurvivesBurn(bool transferFirst, uint160 holderSeed) public {
        address holder = address(uint160(bound(holderSeed, 0x100, type(uint160).max)));
        vm.assume(holder != VICTIM);

        vm.prank(OWNER);
        uint256 tokenId = nft.mint(VICTIM);
        uint256 mintBlockNum = block.number;

        address burner = VICTIM;
        if (transferFirst) {
            vm.roll(block.number + 1);
            vm.prank(VICTIM);
            nft.transferFrom(VICTIM, holder, tokenId);
            burner = holder;
        }

        vm.prank(burner);
        nft.burn(tokenId);

        // Layer 1 intact after burn
        assertEq(nft.originalCreator(tokenId), VICTIM);
        assertEq(nft.mintBlock(tokenId), mintBlockNum);
        assertTrue(nft.isOriginalOwner(tokenId, VICTIM));
    }

    // ──────────────────────────────────────────────────
    // 2. LAYER 2 INTEGRITY — unauthorized history infiltration
    // ──────────────────────────────────────────────────

    /// @notice Attacker cannot inject self into another token's history
    function testFuzz_AttackerCannotInfiltrateHistory(uint8 attempts) public {
        uint8 n = uint8(bound(attempts, 1, 20));

        vm.prank(OWNER);
        uint256 tokenId = nft.mint(VICTIM);

        // Attacker tries N unauthorized transfers
        for (uint8 i = 0; i < n; i++) {
            vm.prank(ATTACKER);
            try nft.transferFrom(VICTIM, ATTACKER, tokenId) {
                // Should never succeed
                fail();
            } catch {}
        }

        // Attacker must not appear in history
        assertFalse(nft.hasEverOwned(tokenId, ATTACKER));
        (address[] memory owners, ) = nft.getOwnershipHistory(tokenId);
        for (uint256 i = 0; i < owners.length; i++) {
            assertTrue(owners[i] != ATTACKER);
        }
    }

    /// @notice Fuzz N distinct tokens, transfer each once. History length must be exactly 2.
    ///         Tests accounting correctness across variable supply sizes.
    function testFuzz_HistoryLengthAcrossTokens(uint8 tokenCount) public {
        uint8 n = uint8(bound(tokenCount, 1, 15));

        uint256[] memory tokenIds = new uint256[](n);
        for (uint8 i = 0; i < n; i++) {
            address minter = address(uint160(0xD000 + i));
            vm.roll(block.number + 1);
            vm.prank(OWNER);
            tokenIds[i] = nft.mint(minter);
        }

        // Transfer each token to a unique recipient (new block per token)
        for (uint8 i = 0; i < n; i++) {
            address from = address(uint160(0xD000 + i));
            address to = address(uint160(0xDD00 + i));
            vm.roll(block.number + 1);
            vm.prank(from);
            nft.transferFrom(from, to, tokenIds[i]);
        }

        // Each token: 1 mint entry + 1 transfer entry = 2
        for (uint8 i = 0; i < n; i++) {
            assertEq(nft.getHistoryLength(tokenIds[i]), 2);
            assertEq(nft.getTransferCount(tokenIds[i]), 1);
        }
    }

    /// @notice Layer 2 history survives burn — fuzz the intermediate holder
    function testFuzz_HistorySurvivesBurn(uint160 holderSeed) public {
        address holder = address(uint160(bound(holderSeed, 0x100, type(uint160).max)));
        vm.assume(holder != VICTIM);

        vm.prank(OWNER);
        uint256 tokenId = nft.mint(VICTIM);

        vm.roll(block.number + 1);
        vm.prank(VICTIM);
        nft.transferFrom(VICTIM, holder, tokenId);

        uint256 histLenBefore = nft.getHistoryLength(tokenId);
        assertEq(histLenBefore, 2);

        vm.prank(holder);
        nft.burn(tokenId);

        // History length unchanged after burn
        assertEq(nft.getHistoryLength(tokenId), histLenBefore);
        assertTrue(nft.hasEverOwned(tokenId, VICTIM));
        assertTrue(nft.hasEverOwned(tokenId, holder));

        // Full history still retrievable
        (address[] memory owners, ) = nft.getOwnershipHistory(tokenId);
        assertEq(owners[0], VICTIM);
        assertEq(owners[1], holder);
    }

    // ──────────────────────────────────────────────────
    // 3. SYBIL GUARDS — same-block & same-TX chains
    // ──────────────────────────────────────────────────

    /// @notice Inter-TX Sybil: second transfer in same block always reverts
    function testFuzz_InterTxSybilBlocksSecondTransfer(uint8 seed) public {
        // Mint always occupies block.number slot
        vm.prank(OWNER);
        uint256 tokenId = nft.mint(VICTIM);

        // Same block: any transfer must revert with OwnerAlreadyRecordedForBlock
        address dest = address(uint160(0xF000 + uint160(seed)));
        vm.prank(VICTIM);
        vm.expectRevert(ERC721H.OwnerAlreadyRecordedForBlock.selector);
        nft.transferFrom(VICTIM, dest, tokenId);
    }

    /// @notice Intra-TX Sybil: A→B→C in one call always reverts
    function test_IntraTxSybilBlocksChain() public {
        vm.prank(OWNER);
        uint256 tokenId = nft.mint(VICTIM);

        SybilChainAttacker attacker = new SybilChainAttacker(nft);
        vm.prank(VICTIM);
        nft.approve(address(attacker), tokenId);

        address b = address(0x2222);
        address c = address(0x3333);

        vm.expectRevert();
        attacker.chainTransfer(VICTIM, b, c, tokenId);

        // History unchanged — only VICTIM
        assertEq(nft.getHistoryLength(tokenId), 1);
    }

    /// @notice Self-transfer always reverts (history pollution prevention)
    function testFuzz_SelfTransferAlwaysReverts(uint8 seed) public {
        address minter = address(uint160(0xA000 + uint160(bound(seed, 1, 200))));

        vm.prank(OWNER);
        uint256 tokenId = nft.mint(minter);

        vm.roll(block.number + 1);
        vm.prank(minter);
        vm.expectRevert(ERC721H.InvalidRecipient.selector);
        nft.transferFrom(minter, minter, tokenId);
    }

    // ──────────────────────────────────────────────────
    // 4. MULTI-TOKEN CROSS-TOKEN INTERACTIONS
    // ──────────────────────────────────────────────────

    /// @notice Fuzz: mint N tokens, each has independent history
    function testFuzz_MultiTokenIndependentHistory(uint8 count) public {
        uint8 n = uint8(bound(count, 2, 15));

        uint256[] memory tokenIds = new uint256[](n);
        for (uint8 i = 0; i < n; i++) {
            address minter = address(uint160(0x5000 + i));
            vm.prank(OWNER);
            tokenIds[i] = nft.mint(minter);
        }

        // Transfer only the first token
        address firstMinter = address(uint160(0x5000));
        address recipient = address(uint160(0x6000));
        vm.roll(block.number + 1);
        vm.prank(firstMinter);
        nft.transferFrom(firstMinter, recipient, tokenIds[0]);

        // First token: 2 history entries
        assertEq(nft.getHistoryLength(tokenIds[0]), 2);

        // All other tokens: still 1 history entry (unaffected)
        for (uint8 i = 1; i < n; i++) {
            assertEq(nft.getHistoryLength(tokenIds[i]), 1);
            assertFalse(nft.hasEverOwned(tokenIds[i], recipient));
        }
    }

    /// @notice Different tokens CAN transfer in the same block (no cross-token interference)
    function testFuzz_DifferentTokensSameBlockOK(uint8 count) public {
        uint8 n = uint8(bound(count, 2, 10));

        address minter = VICTIM;

        // Mint N tokens across separate blocks (mint occupies the block slot)
        uint256[] memory tokenIds = new uint256[](n);
        for (uint8 i = 0; i < n; i++) {
            vm.roll(block.number + 1);
            vm.prank(OWNER);
            tokenIds[i] = nft.mint(minter);
        }

        // Transfer all in the same block — each is a different tokenId, should all succeed
        vm.roll(block.number + 1);
        for (uint8 i = 0; i < n; i++) {
            address dest = address(uint160(0x7000 + i));
            vm.prank(minter);
            nft.transferFrom(minter, dest, tokenIds[i]);
        }

        // Verify all transferred
        for (uint8 i = 0; i < n; i++) {
            address dest = address(uint160(0x7000 + i));
            assertEq(nft.ownerOf(tokenIds[i]), dest);
            assertEq(nft.getHistoryLength(tokenIds[i]), 2);
        }
    }

    // ──────────────────────────────────────────────────
    // 5. SUPPLY ACCOUNTING INVARIANTS
    // ──────────────────────────────────────────────────

    /// @notice totalSupply + burned = totalMinted (always)
    function testFuzz_SupplyInvariant(uint8 mintCount, uint8 burnCount) public {
        uint8 mints = uint8(bound(mintCount, 1, 20));
        uint8 burns = uint8(bound(burnCount, 0, mints));

        uint256[] memory tokenIds = new uint256[](mints);
        for (uint8 i = 0; i < mints; i++) {
            address to = address(uint160(0x8000 + i));
            vm.prank(OWNER);
            tokenIds[i] = nft.mint(to);
        }

        assertEq(nft.totalSupply(), mints);
        assertEq(nft.totalMinted(), mints);

        // Burn `burns` tokens
        for (uint8 i = 0; i < burns; i++) {
            address tokenOwner = address(uint160(0x8000 + i));
            vm.prank(tokenOwner);
            nft.burn(tokenIds[i]);
        }

        assertEq(nft.totalSupply(), uint256(mints) - uint256(burns));
        assertEq(nft.totalMinted(), mints);
    }

    /// @notice Fuzz: pick a random token from a batch, verify paginated slices match full history.
    ///         Each token has exactly 2 history entries (mint + 1 transfer).
    function testFuzz_PaginationConsistency(uint8 tokenCount, uint8 targetIdx) public {
        uint8 n = uint8(bound(tokenCount, 1, 10));
        uint8 target = uint8(bound(targetIdx, 0, n - 1));

        uint256[] memory tokenIds = new uint256[](n);
        for (uint8 i = 0; i < n; i++) {
            address minter = address(uint160(0x9000 + i));
            vm.roll(block.number + 1);
            vm.prank(OWNER);
            tokenIds[i] = nft.mint(minter);
        }

        // Transfer each token
        for (uint8 i = 0; i < n; i++) {
            address from = address(uint160(0x9000 + i));
            address to = address(uint160(0x9900 + i));
            vm.roll(block.number + 1);
            vm.prank(from);
            nft.transferFrom(from, to, tokenIds[i]);
        }

        // Verify pagination on the fuzzed target token
        uint256 tokenId = tokenIds[target];
        uint256 len = nft.getHistoryLength(tokenId);
        (address[] memory fullOwners, uint256[] memory fullTs) = nft.getOwnershipHistory(tokenId);
        assertEq(len, fullOwners.length);

        // Page through in chunks of 1 (maximum granularity) and verify match
        for (uint256 idx = 0; idx < len; idx++) {
            (address[] memory page, uint256[] memory pageTs) = nft.getHistorySlice(tokenId, idx, 1);
            assertEq(page.length, 1);
            assertEq(page[0], fullOwners[idx]);
            assertEq(pageTs[0], fullTs[idx]);
        }

        // Out-of-bounds returns empty
        (address[] memory empty, ) = nft.getHistorySlice(tokenId, len, 1);
        assertEq(empty.length, 0);
    }
}

/// @notice Helper: attempts A→B→C in a single call (intra-TX Sybil attack)
contract SybilChainAttacker {
    ERC721H public nft;

    constructor(ERC721H _nft) {
        nft = _nft;
    }

    function chainTransfer(address a, address b, address c, uint256 tokenId) external {
        nft.transferFrom(a, b, tokenId);
        // Second transfer same tokenId same TX — should revert
        nft.transferFrom(b, c, tokenId);
    }
}
