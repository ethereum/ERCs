// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, console} from "forge-std/Test.sol";
import {uRWA721} from "../contracts/uRWA721.sol";
import {IERC7943NonFungible} from "../contracts/interfaces/IERC7943.sol";
import {MockERC721Receiver} from "../contracts/mocks/MockERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

contract uRWA721Test is Test {
    uRWA721 public token;
    MockERC721Receiver public receiverContract;

    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant FREEZING_ROLE = keccak256("FREEZING_ROLE");
    bytes32 public constant FORCE_TRANSFER_ROLE = keccak256("FORCE_TRANSFER_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    bytes32 public constant ADMIN_ROLE = 0x00;

    // Users
    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public minter = address(4);
    address public burner = address(5);
    address public freezer = address(6);
    address public forceTransferrer = address(7);
    address public whitelister = address(8);
    address public nonWhitelistedUser = address(9);
    address public otherUser = address(10);

    // Token IDs
    uint256 public constant TOKEN_ID_1 = 1;
    uint256 public constant TOKEN_ID_2 = 2;
    uint256 public constant TOKEN_ID_3 = 3;
    uint256 public constant NON_EXISTENT_TOKEN_ID = 99;

    function setUp() public {
        vm.startPrank(admin);
        token = new uRWA721("uRWA NFT", "uNFT", admin);

        // Grant roles
        token.grantRole(MINTER_ROLE, minter);
        token.grantRole(BURNER_ROLE, burner);
        token.grantRole(FREEZING_ROLE, freezer);
        token.grantRole(FORCE_TRANSFER_ROLE, forceTransferrer);
        token.grantRole(WHITELIST_ROLE, whitelister);

        // Whitelist initial users
        token.changeWhitelist(admin, true);
        token.changeWhitelist(user1, true);
        token.changeWhitelist(user2, true);
        token.changeWhitelist(minter, true);
        token.changeWhitelist(burner, true);
        token.changeWhitelist(freezer, true);
        token.changeWhitelist(forceTransferrer, true);
        token.changeWhitelist(whitelister, true);
        vm.stopPrank();

        // Deploy mock receiver
        receiverContract = new MockERC721Receiver();
        vm.prank(admin);
        token.changeWhitelist(address(receiverContract), true);

        // Mint initial token for tests
        vm.prank(minter);
        token.safeMint(user1, TOKEN_ID_1);
    }

    // --- Constructor Tests ---

    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(token.name(), "uRWA NFT");
        assertEq(token.symbol(), "uNFT");
    }

    function test_Constructor_GrantsInitialRoles() public view {
        assertTrue(token.hasRole(ADMIN_ROLE, admin));
        assertTrue(token.hasRole(MINTER_ROLE, admin));
        assertTrue(token.hasRole(BURNER_ROLE, admin));
        assertTrue(token.hasRole(FREEZING_ROLE, admin));
        assertTrue(token.hasRole(FORCE_TRANSFER_ROLE, admin));
        assertTrue(token.hasRole(WHITELIST_ROLE, admin));
    }

    // --- Whitelist Tests ---

    function test_Whitelist_ChangeStatus() public {
        assertFalse(token.canTransact(otherUser));
        vm.prank(whitelister);
        vm.expectEmit(true, false, false, true);
        emit uRWA721.Whitelisted(otherUser, true);
        token.changeWhitelist(otherUser, true);
        assertTrue(token.canTransact(otherUser));

        vm.prank(whitelister);
        vm.expectEmit(true, false, false, true);
        emit uRWA721.Whitelisted(otherUser, false);
        token.changeWhitelist(otherUser, false);
        assertFalse(token.canTransact(otherUser));
    }

    function test_Revert_Whitelist_ChangeStatus_NotWhitelister() public {
        vm.prank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, otherUser, WHITELIST_ROLE));
        token.changeWhitelist(nonWhitelistedUser, true);
    }

    function test_Whitelist_IsUserAllowed() public view {
        assertTrue(token.canTransact(user1));
        assertFalse(token.canTransact(nonWhitelistedUser));
    }

    // --- Minting Tests ---

    function test_Mint_Success() public {
        vm.prank(minter);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(address(0), user2, TOKEN_ID_2);
        token.safeMint(user2, TOKEN_ID_2);
        assertEq(token.ownerOf(TOKEN_ID_2), user2);
        assertEq(token.balanceOf(user2), 1);
    }

    function test_Revert_Mint_NotMinter() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, MINTER_ROLE));
        token.safeMint(user2, TOKEN_ID_2);
    }

    function test_Revert_Mint_ToNonWhitelisted() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotTransact.selector, nonWhitelistedUser));
        token.safeMint(nonWhitelistedUser, TOKEN_ID_2);
    }

    function test_Revert_Mint_ExistingTokenId() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidSender.selector, address(0)));
        token.safeMint(user2, TOKEN_ID_1);
    }

    function test_Revert_Mint_ToZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        token.safeMint(address(0), TOKEN_ID_2);
    }

    function test_Mint_ToContractReceiver() public {
        vm.prank(minter);
        token.safeMint(address(receiverContract), TOKEN_ID_2);
        assertEq(token.ownerOf(TOKEN_ID_2), address(receiverContract));
    }

    function test_Revert_Mint_ToContractThatRejects() public {
        receiverContract.setShouldReject(true);
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(receiverContract)));
        token.safeMint(address(receiverContract), TOKEN_ID_2);
    }

    // --- Enhanced Burning Tests ---

    function test_Burn_Success_ByOwnerBurner() public {
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, address(0), TOKEN_ID_1);
        token.burn(TOKEN_ID_1);
        
        assertEq(token.balanceOf(user1), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, TOKEN_ID_1));
        token.ownerOf(TOKEN_ID_1);
    }

    function test_Burn_Success_ByApprovedBurner() public {
        vm.prank(user1);
        token.approve(burner, TOKEN_ID_1);

        vm.prank(burner);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, address(0), TOKEN_ID_1);
        token.burn(TOKEN_ID_1);
        
        assertEq(token.balanceOf(user1), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, TOKEN_ID_1));
        token.ownerOf(TOKEN_ID_1);
    }

    function test_Burn_Success_UnfreezesFrozenToken() public {
        // Grant burner role to user1
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        // Freeze the token first
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));

        // Burn should succeed and unfreeze the token
        vm.prank(user1);
        vm.expectEmit(true, true, true, true); // Frozen event from _excessFrozenUpdate
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, false);
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC721.Transfer(user1, address(0), TOKEN_ID_1);
        token.burn(TOKEN_ID_1);
        
        // Token should be burned
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, TOKEN_ID_1));
        token.ownerOf(TOKEN_ID_1);
    }

    function test_Revert_Burn_NotBurnerRole() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, BURNER_ROLE));
        token.burn(TOKEN_ID_1);
    }

    function test_Revert_Burn_BurnerNotOwnerOrApproved() public {
        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, burner, TOKEN_ID_1));
        token.burn(TOKEN_ID_1);
    }

    function test_Revert_Burn_NonExistentToken() public {
        vm.prank(burner);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, NON_EXISTENT_TOKEN_ID));
        token.burn(NON_EXISTENT_TOKEN_ID);
    }

    // --- Transfer Tests ---

    function test_Transfer_Success_WhitelistedToWhitelisted() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        token.transferFrom(user1, user2, TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), user2);
    }

    function test_Transfer_Success_ByApprovedWhitelisted() public {
        vm.prank(user1);
        token.approve(otherUser, TOKEN_ID_1);
        vm.prank(admin);
        token.changeWhitelist(otherUser, true);

        vm.prank(otherUser);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        token.transferFrom(user1, user2, TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), user2);
    }

    function test_Revert_Transfer_FromNotWhitelisted() public {
        vm.prank(whitelister);
        token.changeWhitelist(user1, false);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotTransact.selector, user1));
        token.transferFrom(user1, user2, TOKEN_ID_1);
    }

    function test_Revert_Transfer_ToNotWhitelisted() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotTransact.selector, nonWhitelistedUser));
        token.transferFrom(user1, nonWhitelistedUser, TOKEN_ID_1);
    }

    function test_Revert_Transfer_NotOwnerOrApproved() public {
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, user2, TOKEN_ID_1));
        token.transferFrom(user1, user2, TOKEN_ID_1);
    }

    function test_Revert_Transfer_WhenFrozen() public {
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943InsufficientUnfrozenBalance.selector, user1, TOKEN_ID_1));
        token.transferFrom(user1, user2, TOKEN_ID_1);
    }

    function test_Revert_Transfer_NonExistentToken() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, NON_EXISTENT_TOKEN_ID));
        token.transferFrom(user1, user2, NON_EXISTENT_TOKEN_ID);
    }

    // --- Enhanced ForceTransfer Tests ---

    function test_ForcedTransfer_Success_WhitelistedToWhitelisted() public {
        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.ForcedTransfer(user1, user2, TOKEN_ID_1);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), user2);
    }

    function test_ForcedTransfer_Success_FromNonWhitelistedToWhitelisted() public {
        vm.prank(whitelister);
        token.changeWhitelist(user1, false);

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.ForcedTransfer(user1, user2, TOKEN_ID_1);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), user2);
    }

    function test_ForcedTransfer_Success_UnfreezesFrozenToken() public {
        // Freeze the token first
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true); // Frozen event from _excessFrozenUpdate
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, false);
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        vm.expectEmit(true, true, true, true); // ForcedTransfer event
        emit IERC7943NonFungible.ForcedTransfer(user1, user2, TOKEN_ID_1);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);

        assertEq(token.ownerOf(TOKEN_ID_1), user2);
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1)); // Should be unfrozen for original owner
        assertFalse(token.getFrozenTokens(user2, TOKEN_ID_1)); // Should not be frozen for new owner
    }

    function test_ForcedTransfer_Success_NoChangeWhenNotFrozen() public {
        // Token is not frozen initially
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));

        vm.prank(forceTransferrer);
        // Should NOT emit Frozen event since token wasn't frozen
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        vm.expectEmit(true, true, true, true); // ForcedTransfer event
        emit IERC7943NonFungible.ForcedTransfer(user1, user2, TOKEN_ID_1);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);

        assertEq(token.ownerOf(TOKEN_ID_1), user2);
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));
        assertFalse(token.getFrozenTokens(user2, TOKEN_ID_1));
    }

    function test_Revert_ForcedTransfer_ToNonWhitelisted() public {
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotTransact.selector, nonWhitelistedUser));
        token.forcedTransfer(user1, nonWhitelistedUser, TOKEN_ID_1);
    }

    function test_Revert_ForcedTransfer_NotForceTransferrer() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, FORCE_TRANSFER_ROLE));
        token.forcedTransfer(user1, user2, TOKEN_ID_1);
    }

    function test_Revert_ForcedTransfer_NonExistentToken() public {
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, NON_EXISTENT_TOKEN_ID));
        token.forcedTransfer(user1, user2, NON_EXISTENT_TOKEN_ID);
    }

    function test_Revert_ForcedTransfer_FromIncorrectOwner() public {
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721IncorrectOwner.selector, user2, TOKEN_ID_1, user1));
        token.forcedTransfer(user2, admin, TOKEN_ID_1);
    }

    function test_Revert_ForcedTransfer_ToZeroAddress() public {
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InvalidReceiver.selector, address(0)));
        token.forcedTransfer(user1, address(0), TOKEN_ID_1);
    }

    // --- Enhanced Freeze/Unfreeze Tests ---

    function test_SetFrozenTokens_Success_FreezeToken() public {
        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, true);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));
    }

    function test_SetFrozenTokens_Success_UnfreezeToken() public {
        // First freeze the token
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);

        // Then unfreeze it
        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, false);
        token.setFrozenTokens(user1, TOKEN_ID_1, false);
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));
    }

    function test_SetFrozenTokens_Success_ChangeFromFrozenToFrozen() public {
        // First freeze the token
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);

        // Try to "freeze" again (should still emit event)
        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, true);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));
    }

    // Note: InvalidAmount tests removed as setFrozenTokens now uses boolean parameter

    function test_Revert_SetFrozenTokens_NotFreezer() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, FREEZING_ROLE));
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
    }

    function test_GetFrozenTokens_Correctness() public {
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));

        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));

        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, false);
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));
    }

    // --- canTransfer Tests ---

    function test_CanTransfer_Success() public view {
        assertTrue(token.canTransfer(user1, user2, TOKEN_ID_1));
    }

    function test_CanTransfer_Fail_FromNotOwner() public view {
        assertFalse(token.canTransfer(user2, user1, TOKEN_ID_1));
    }

    function test_CanTransfer_Fail_NonExistentToken() public view {
        assertFalse(token.canTransfer(user1, user2, NON_EXISTENT_TOKEN_ID));
    }

    function test_CanTransfer_Fail_FromNotWhitelisted() public {
        vm.prank(whitelister);
        token.changeWhitelist(user1, false);
        assertFalse(token.canTransfer(user1, user2, TOKEN_ID_1));
    }

    function test_CanTransfer_Fail_ToNotWhitelisted() public view {
        assertFalse(token.canTransfer(user1, nonWhitelistedUser, TOKEN_ID_1));
    }

    function test_CanTransfer_Fail_TokenFrozen() public {
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertFalse(token.canTransfer(user1, user2, TOKEN_ID_1));
    }

    // --- Interface Support Tests ---

    function test_Interface_SupportsIERC7943() public view {
        assertTrue(token.supportsInterface(type(IERC7943NonFungible).interfaceId));
    }

    function test_Interface_SupportsIERC721() public view {
        assertTrue(token.supportsInterface(type(IERC721).interfaceId));
    }

    function test_Interface_SupportsIERC165() public view {
        assertTrue(token.supportsInterface(type(IERC165).interfaceId));
    }

    function test_Interface_SupportsAccessControl() public view {
        assertTrue(token.supportsInterface(type(IAccessControlEnumerable).interfaceId));
    }

    function test_Interface_DoesNotSupportRandom() public view {
        assertFalse(token.supportsInterface(bytes4(0xdeadbeef)));
    }

    // --- Access Control Tests ---

    function test_AccessControl_GrantRevokeRole() public {
        assertFalse(token.hasRole(MINTER_ROLE, user1));
        vm.prank(admin);
        token.grantRole(MINTER_ROLE, user1);
        assertTrue(token.hasRole(MINTER_ROLE, user1));
        vm.prank(admin);
        token.revokeRole(MINTER_ROLE, user1);
        assertFalse(token.hasRole(MINTER_ROLE, user1));
    }

    function test_Revert_AccessControl_GrantRole_NotAdmin() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, ADMIN_ROLE));
        token.grantRole(MINTER_ROLE, user2);
    }

    // --- Edge Case Tests ---

    function test_EdgeCase_MultipleTokensFreezingIndependently() public {
        // Mint another token
        vm.prank(minter);
        token.safeMint(user1, TOKEN_ID_2);

        // Freeze only TOKEN_ID_1
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);

        // TOKEN_ID_1 should be frozen, TOKEN_ID_2 should not
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_2));

        // Transfer TOKEN_ID_2 should work
        vm.prank(user1);
        token.transferFrom(user1, user2, TOKEN_ID_2);
        assertEq(token.ownerOf(TOKEN_ID_2), user2);

        // Transfer TOKEN_ID_1 should fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943InsufficientUnfrozenBalance.selector, user1, TOKEN_ID_1));
        token.transferFrom(user1, user2, TOKEN_ID_1);
    }

    function test_EdgeCase_ForceTransferToContract() public {
        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, address(receiverContract), TOKEN_ID_1);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.ForcedTransfer(user1, address(receiverContract), TOKEN_ID_1);
        token.forcedTransfer(user1, address(receiverContract), TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), address(receiverContract));
    }

    function test_EdgeCase_BurnAfterForceTransfer() public {
        // Force transfer to user2
        vm.prank(forceTransferrer);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);

        // Give burner role to user2
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user2);

        // user2 should be able to burn the token
        vm.prank(user2);
        token.burn(TOKEN_ID_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, TOKEN_ID_1));
        token.ownerOf(TOKEN_ID_1);
    }

    // --- Helper Functions for Complex Scenarios ---

    function _setupTokenWithOwner(address owner, uint256 tokenId) internal {
        vm.prank(admin);
        token.changeWhitelist(owner, true);
        vm.prank(minter);
        token.safeMint(owner, tokenId);
    }

    function _verifyTokenState(address expectedOwner, uint256 tokenId, uint256 expectedFrozenAmount, string memory errorMsg) internal {
        if (expectedOwner == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
            token.ownerOf(tokenId);
        } else {
            assertEq(token.ownerOf(tokenId), expectedOwner, string.concat(errorMsg, " - Owner mismatch"));
        }
        if (expectedFrozenAmount == 1) {
            assertTrue(token.getFrozenTokens(expectedOwner, tokenId), string.concat(errorMsg, " - Should be frozen"));
        } else {
            assertFalse(token.getFrozenTokens(expectedOwner, tokenId), string.concat(errorMsg, " - Should not be frozen"));
        }
    }
}
