// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {uRWA721} from "../contracts/uRWA721.sol";
import {IERC7943NonFungible} from "../contracts/interfaces/IERC7943.sol";
import {MockERC721Receiver} from "../contracts/mocks/MockERC721Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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

        // Whitelist initial users (both send and receive)
        _whitelistBoth(admin);
        _whitelistBoth(user1);
        _whitelistBoth(user2);
        _whitelistBoth(minter);
        _whitelistBoth(burner);
        _whitelistBoth(freezer);
        _whitelistBoth(forceTransferrer);
        _whitelistBoth(whitelister);
        vm.stopPrank();

        // Deploy mock receiver
        receiverContract = new MockERC721Receiver();
        vm.startPrank(admin);
        _whitelistBoth(address(receiverContract));
        vm.stopPrank();

        // Mint initial token for tests
        vm.prank(minter);
        token.safeMint(user1, TOKEN_ID_1);
    }

    function _whitelistBoth(address account) internal {
        token.changeSendWhitelist(account, true);
        token.changeReceiveWhitelist(account, true);
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

    function test_SendWhitelist_ChangeStatus() public {
        assertFalse(token.canSend(otherUser));
        vm.prank(whitelister);
        vm.expectEmit(true, false, false, true);
        emit uRWA721.SendWhitelisted(otherUser, true);
        token.changeSendWhitelist(otherUser, true);
        assertTrue(token.canSend(otherUser));

        vm.prank(whitelister);
        vm.expectEmit(true, false, false, true);
        emit uRWA721.SendWhitelisted(otherUser, false);
        token.changeSendWhitelist(otherUser, false);
        assertFalse(token.canSend(otherUser));
    }

    function test_ReceiveWhitelist_ChangeStatus() public {
        assertFalse(token.canReceive(otherUser));
        vm.prank(whitelister);
        vm.expectEmit(true, false, false, true);
        emit uRWA721.ReceiveWhitelisted(otherUser, true);
        token.changeReceiveWhitelist(otherUser, true);
        assertTrue(token.canReceive(otherUser));

        vm.prank(whitelister);
        vm.expectEmit(true, false, false, true);
        emit uRWA721.ReceiveWhitelisted(otherUser, false);
        token.changeReceiveWhitelist(otherUser, false);
        assertFalse(token.canReceive(otherUser));
    }

    function test_Revert_Whitelist_ChangeStatus_NotWhitelister() public {
        vm.prank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, otherUser, WHITELIST_ROLE));
        token.changeSendWhitelist(nonWhitelistedUser, true);
    }

    function test_Whitelist_IsUserAllowed() public view {
        assertTrue(token.canSend(user1));
        assertTrue(token.canReceive(user1));
        assertFalse(token.canSend(nonWhitelistedUser));
        assertFalse(token.canReceive(nonWhitelistedUser));
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

    function test_Revert_Mint_ToCannotReceive() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotReceive.selector, nonWhitelistedUser));
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
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, false);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, address(0), TOKEN_ID_1);
        token.burn(TOKEN_ID_1);

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

    function test_Revert_Burn_CannotSend() public {
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        vm.prank(whitelister);
        token.changeSendWhitelist(user1, false);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotSend.selector, user1));
        token.burn(TOKEN_ID_1);
    }

    function test_GetFrozenTokens_NonOwner() public {
        assertEq(token.ownerOf(TOKEN_ID_1), user1);

        vm.prank(freezer);
        token.setFrozenTokens(user2, TOKEN_ID_1, true);

        assertTrue(token.getFrozenTokens(user2, TOKEN_ID_1));

        vm.prank(user1);
        token.transferFrom(user1, user2, TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), user2);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943InsufficientUnfrozenBalance.selector, user2, TOKEN_ID_1));
        token.transferFrom(user2, user1, TOKEN_ID_1);
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
        vm.startPrank(admin);
        _whitelistBoth(otherUser);
        vm.stopPrank();

        vm.prank(otherUser);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        token.transferFrom(user1, user2, TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), user2);
    }

    function test_Revert_Transfer_FromCannotSend() public {
        vm.prank(whitelister);
        token.changeSendWhitelist(user1, false);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotSend.selector, user1));
        token.transferFrom(user1, user2, TOKEN_ID_1);
    }

    function test_Revert_Transfer_ToCannotReceive() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotReceive.selector, nonWhitelistedUser));
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

    function test_ForcedTransfer_Success_FromCannotSendToWhitelisted() public {
        vm.prank(whitelister);
        token.changeSendWhitelist(user1, false);

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.ForcedTransfer(user1, user2, TOKEN_ID_1);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);
        assertEq(token.ownerOf(TOKEN_ID_1), user2);
    }

    function test_ForcedTransfer_Success_UnfreezesFrozenToken() public {
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, false);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.ForcedTransfer(user1, user2, TOKEN_ID_1);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);

        assertEq(token.ownerOf(TOKEN_ID_1), user2);
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));
        assertFalse(token.getFrozenTokens(user2, TOKEN_ID_1));
    }

    function test_ForcedTransfer_Success_NoChangeWhenNotFrozen() public {
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC721.Transfer(user1, user2, TOKEN_ID_1);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.ForcedTransfer(user1, user2, TOKEN_ID_1);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);

        assertEq(token.ownerOf(TOKEN_ID_1), user2);
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));
        assertFalse(token.getFrozenTokens(user2, TOKEN_ID_1));
    }

    function test_Revert_ForcedTransfer_ToCannotReceive() public {
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC7943NonFungible.ERC7943CannotReceive.selector, nonWhitelistedUser));
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
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);

        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, false);
        token.setFrozenTokens(user1, TOKEN_ID_1, false);
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_1));
    }

    function test_SetFrozenTokens_Success_ChangeFromFrozenToFrozen() public {
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);

        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943NonFungible.Frozen(user1, TOKEN_ID_1, true);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);
        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));
    }

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

    function test_CanTransfer_Fail_FromCannotSend() public {
        vm.prank(whitelister);
        token.changeSendWhitelist(user1, false);
        assertFalse(token.canTransfer(user1, user2, TOKEN_ID_1));
    }

    function test_CanTransfer_Fail_ToCannotReceive() public view {
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
        vm.prank(minter);
        token.safeMint(user1, TOKEN_ID_2);

        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, true);

        assertTrue(token.getFrozenTokens(user1, TOKEN_ID_1));
        assertFalse(token.getFrozenTokens(user1, TOKEN_ID_2));

        vm.prank(user1);
        token.transferFrom(user1, user2, TOKEN_ID_2);
        assertEq(token.ownerOf(TOKEN_ID_2), user2);

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
        vm.prank(forceTransferrer);
        token.forcedTransfer(user1, user2, TOKEN_ID_1);

        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user2);

        vm.prank(user2);
        token.burn(TOKEN_ID_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, TOKEN_ID_1));
        token.ownerOf(TOKEN_ID_1);
    }

    // --- canSend / canReceive asymmetry tests ---

    function test_CanSend_True_CanReceive_False() public {
        vm.startPrank(whitelister);
        token.changeSendWhitelist(otherUser, true);
        token.changeReceiveWhitelist(otherUser, false);
        vm.stopPrank();

        assertTrue(token.canSend(otherUser));
        assertFalse(token.canReceive(otherUser));
    }

    function test_CanSend_False_CanReceive_True() public {
        vm.startPrank(whitelister);
        token.changeSendWhitelist(otherUser, false);
        token.changeReceiveWhitelist(otherUser, true);
        vm.stopPrank();

        assertFalse(token.canSend(otherUser));
        assertTrue(token.canReceive(otherUser));
    }
}
