// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {uRWA1155} from "../contracts/uRWA1155.sol";
import {IERC7943MultiToken} from "../contracts/interfaces/IERC7943.sol";
import {MockERC1155Receiver} from "../contracts/mocks/MockERC1155Receiver.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

contract uRWA1155Test is Test {
    uRWA1155 public token;
    MockERC1155Receiver public receiverContract;
    string public constant TOKEN_URI = "ipfs://test.uri/{id}.json";

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

    // Token IDs and Amounts
    uint256 public constant TOKEN_ID_1 = 1;
    uint256 public constant TOKEN_ID_2 = 2;
    uint256 public constant NON_EXISTENT_TOKEN_ID = 99;
    uint256 public constant MINT_AMOUNT = 100;
    uint256 public constant TRANSFER_AMOUNT = 50;
    uint256 public constant BURN_AMOUNT = 20;
    uint256 public constant FORCE_TRANSFER_AMOUNT = 30;
    uint256 public constant FREEZE_AMOUNT = 40;

    function setUp() public {
        vm.startPrank(admin);
        token = new uRWA1155(TOKEN_URI, admin);

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
        receiverContract = new MockERC1155Receiver();
        vm.prank(admin);
        token.changeWhitelist(address(receiverContract), true);

        // Mint initial tokens for tests
        vm.prank(minter);
        token.mint(user1, TOKEN_ID_1, MINT_AMOUNT);
        vm.prank(minter);
        token.mint(user1, TOKEN_ID_2, MINT_AMOUNT);
    }

    // --- Constructor Tests ---

    function test_Constructor_SetsURI() public view {
        assertEq(token.uri(TOKEN_ID_1), TOKEN_URI);
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
        emit uRWA1155.Whitelisted(otherUser, true);
        token.changeWhitelist(otherUser, true);
        assertTrue(token.canTransact(otherUser));

        vm.prank(whitelister);
        vm.expectEmit(true, false, false, true);
        emit uRWA1155.Whitelisted(otherUser, false);
        token.changeWhitelist(otherUser, false);
        assertFalse(token.canTransact(otherUser));
    }

    function test_Revert_Whitelist_ChangeStatus_NotWhitelister() public {
        vm.prank(otherUser);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, otherUser, WHITELIST_ROLE));
        token.changeWhitelist(nonWhitelistedUser, true);
    }

    // --- Minting Tests ---

    function test_Mint_Success() public {
        vm.prank(minter);
        vm.expectEmit(true, true, true, true);
        emit IERC1155.TransferSingle(minter, address(0), user2, TOKEN_ID_2, MINT_AMOUNT);
        token.mint(user2, TOKEN_ID_2, MINT_AMOUNT);
        assertEq(token.balanceOf(user2, TOKEN_ID_2), MINT_AMOUNT);
    }

    function test_Revert_Mint_NotMinter() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, MINTER_ROLE));
        token.mint(user2, TOKEN_ID_2, MINT_AMOUNT);
    }

    function test_Revert_Mint_ToNonWhitelisted() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943CannotTransact.selector, nonWhitelistedUser));
        token.mint(nonWhitelistedUser, TOKEN_ID_2, MINT_AMOUNT);
    }

    function test_Revert_Mint_ToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(0)));
        vm.prank(minter);
        token.mint(address(0), TOKEN_ID_2, MINT_AMOUNT);
    }

    function test_Mint_ToContractReceiver() public {
        vm.prank(minter);
        token.mint(address(receiverContract), TOKEN_ID_2, MINT_AMOUNT);
        assertEq(token.balanceOf(address(receiverContract), TOKEN_ID_2), MINT_AMOUNT);
    }

    function test_Revert_Mint_ToContractThatRejects() public {
        receiverContract.setShouldReject(true);
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(receiverContract)));
        token.mint(address(receiverContract), TOKEN_ID_2, MINT_AMOUNT);
    }

    // --- Enhanced Burning Tests ---

    function test_Burn_Success() public {
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        uint256 initialBalance = token.balanceOf(user1, TOKEN_ID_1);
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit IERC1155.TransferSingle(user1, user1, address(0), TOKEN_ID_1, BURN_AMOUNT);
        token.burn(TOKEN_ID_1, BURN_AMOUNT);
        assertEq(token.balanceOf(user1, TOKEN_ID_1), initialBalance - BURN_AMOUNT);
    }

    function test_Burn_Success_ReducesFrozenWhenExceedsUnfrozen() public {
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        // Freeze some tokens
        uint256 frozenAmount = 60;
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, frozenAmount);

        uint256 unfrozenBalance = token.balanceOf(user1, TOKEN_ID_1) - frozenAmount;
        uint256 burnAmount = unfrozenBalance + 20; // More than unfrozen
        uint256 expectedNewFrozenAmount = frozenAmount - (burnAmount - unfrozenBalance);

        uint256 initialBalance = token.balanceOf(user1, TOKEN_ID_1);

        vm.prank(user1);
        vm.expectEmit(true, true, true, true); // Frozen event from _excessFrozenUpdate
        emit IERC7943MultiToken.Frozen(user1, TOKEN_ID_1, expectedNewFrozenAmount);
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC1155.TransferSingle(user1, user1, address(0), TOKEN_ID_1, burnAmount);
        token.burn(TOKEN_ID_1, burnAmount);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), initialBalance - burnAmount);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), expectedNewFrozenAmount);
    }

    function test_Burn_Success_DoesNotChangeFrozenWhenWithinUnfrozen() public {
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        // Freeze some tokens
        uint256 frozenAmount = 60;
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, frozenAmount);

        uint256 unfrozenBalance = token.balanceOf(user1, TOKEN_ID_1) - frozenAmount;
        uint256 burnAmount = unfrozenBalance - 10; // Less than unfrozen

        uint256 initialBalance = token.balanceOf(user1, TOKEN_ID_1);

        vm.prank(user1);
        // Should NOT emit Frozen event since we're not exceeding unfrozen balance
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC1155.TransferSingle(user1, user1, address(0), TOKEN_ID_1, burnAmount);
        token.burn(TOKEN_ID_1, burnAmount);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), initialBalance - burnAmount);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), frozenAmount); // Unchanged
    }

    function test_Revert_Burn_NotBurnerRole() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, BURNER_ROLE));
        token.burn(TOKEN_ID_1, BURN_AMOUNT);
    }

    function test_Revert_Burn_InsufficientBalance() public {
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        uint256 burnAmount = MINT_AMOUNT + 1;
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, user1, MINT_AMOUNT, burnAmount, TOKEN_ID_1));
        token.burn(TOKEN_ID_1, burnAmount);
    }

    // --- Transfer Tests ---

    function test_Transfer_Success_WhitelistedToWhitelisted() public {
        uint256 user1InitialBalance = token.balanceOf(user1, TOKEN_ID_1);
        uint256 user2InitialBalance = token.balanceOf(user2, TOKEN_ID_1);
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit IERC1155.TransferSingle(user1, user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT);
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT, "");
        assertEq(token.balanceOf(user1, TOKEN_ID_1), user1InitialBalance - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), user2InitialBalance + TRANSFER_AMOUNT);
    }

    function test_Transfer_Success_ByApprovedWhitelisted() public {
        vm.prank(user1);
        token.setApprovalForAll(otherUser, true);
        vm.prank(admin);
        token.changeWhitelist(otherUser, true);

        vm.prank(otherUser);
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT, "");
        assertEq(token.balanceOf(user1, TOKEN_ID_1), MINT_AMOUNT - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), TRANSFER_AMOUNT);
    }

    function test_Revert_Transfer_FromNotWhitelisted() public {
        vm.prank(whitelister);
        token.changeWhitelist(user1, false);

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943CannotTransact.selector, user1));
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT, "");
    }

    function test_Revert_Transfer_ToNotWhitelisted() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943CannotTransact.selector, nonWhitelistedUser));
        token.safeTransferFrom(user1, nonWhitelistedUser, TOKEN_ID_1, TRANSFER_AMOUNT, "");
    }

    function test_Revert_Transfer_NotApproved() public {
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155MissingApprovalForAll.selector, user2, user1));
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT, "");
    }

    function test_Revert_Transfer_InsufficientBalance() public {
        vm.prank(user1);
        uint256 transferAmount = MINT_AMOUNT + 1;
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, user1, MINT_AMOUNT, transferAmount, TOKEN_ID_1));
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, transferAmount, "");
    }

    function test_Revert_Transfer_InsufficientUnfrozenBalance() public {
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, FREEZE_AMOUNT);

        uint256 available = MINT_AMOUNT - FREEZE_AMOUNT;
        uint256 transferAmount = available + 1;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943InsufficientUnfrozenBalance.selector, user1, TOKEN_ID_1, transferAmount, available));
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, transferAmount, "");
    }

    function test_Revert_Transfer_ToZeroAddress() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(0)));
        token.safeTransferFrom(user1, address(0), TOKEN_ID_1, TRANSFER_AMOUNT, "");
    }

    function test_Revert_Transfer_WhenFrozen() public {
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, FREEZE_AMOUNT);

        uint256 availableToTransfer = MINT_AMOUNT - FREEZE_AMOUNT;
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943InsufficientUnfrozenBalance.selector, user1, TOKEN_ID_1, availableToTransfer + 1, availableToTransfer));
        vm.prank(user1);
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, availableToTransfer + 1, "");
    }

    function test_Revert_Transfer_ToContractThatRejects() public {
        receiverContract.setShouldReject(true);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(receiverContract)));
        vm.prank(user1);
        token.safeTransferFrom(user1, address(receiverContract), TOKEN_ID_1, TRANSFER_AMOUNT, "");
    }

    // --- Enhanced ForceTransfer Tests ---

    function test_ForcedTransfer_Success_WhitelistedToWhitelisted() public {
        uint256 user1InitialBalance = token.balanceOf(user1, TOKEN_ID_1);
        uint256 user2InitialBalance = token.balanceOf(user2, TOKEN_ID_1);

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC1155.TransferSingle(forceTransferrer, user1, user2, TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IERC7943MultiToken.ForcedTransfer(user1, user2, TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
        token.forcedTransfer(user1, user2, TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), user1InitialBalance - FORCE_TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), user2InitialBalance + FORCE_TRANSFER_AMOUNT);
    }

    function test_ForcedTransfer_Success_ReducesFrozenWhenExceedsUnfrozen() public {
        // Freeze some tokens
        uint256 frozenAmount = 60;
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, frozenAmount);

        uint256 unfrozenBalance = token.balanceOf(user1, TOKEN_ID_1) - frozenAmount;
        uint256 forceTransferAmount = unfrozenBalance + 20; // More than unfrozen
        uint256 expectedNewFrozenAmount = frozenAmount - (forceTransferAmount - unfrozenBalance);

        uint256 user1InitialBalance = token.balanceOf(user1, TOKEN_ID_1);
        uint256 user2InitialBalance = token.balanceOf(user2, TOKEN_ID_1);

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true); // Frozen event from _excessFrozenUpdate
        emit IERC7943MultiToken.Frozen(user1, TOKEN_ID_1, expectedNewFrozenAmount);
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC1155.TransferSingle(forceTransferrer, user1, user2, TOKEN_ID_1, forceTransferAmount);
        vm.expectEmit(true, true, true, true); // ForcedTransfer event
        emit IERC7943MultiToken.ForcedTransfer(user1, user2, TOKEN_ID_1, forceTransferAmount);
        token.forcedTransfer(user1, user2, TOKEN_ID_1, forceTransferAmount);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), user1InitialBalance - forceTransferAmount);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), user2InitialBalance + forceTransferAmount);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), expectedNewFrozenAmount);
    }

    function test_ForcedTransfer_Success_DoesNotChangeFrozenWhenWithinUnfrozen() public {
        // Freeze some tokens
        uint256 frozenAmount = 60;
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, frozenAmount);

        uint256 unfrozenBalance = token.balanceOf(user1, TOKEN_ID_1) - frozenAmount;
        uint256 forceTransferAmount = unfrozenBalance - 10; // Less than unfrozen

        uint256 user1InitialBalance = token.balanceOf(user1, TOKEN_ID_1);
        uint256 user2InitialBalance = token.balanceOf(user2, TOKEN_ID_1);

        vm.prank(forceTransferrer);
        // Should NOT emit Frozen event since we're not exceeding unfrozen balance
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC1155.TransferSingle(forceTransferrer, user1, user2, TOKEN_ID_1, forceTransferAmount);
        vm.expectEmit(true, true, true, true); // ForcedTransfer event
        emit IERC7943MultiToken.ForcedTransfer(user1, user2, TOKEN_ID_1, forceTransferAmount);
        token.forcedTransfer(user1, user2, TOKEN_ID_1, forceTransferAmount);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), user1InitialBalance - forceTransferAmount);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), user2InitialBalance + forceTransferAmount);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), frozenAmount); // Unchanged
    }

    function test_ForcedTransfer_Success_FromNonWhitelistedToWhitelisted() public {
        vm.prank(whitelister);
        token.changeWhitelist(user1, false);

        vm.prank(forceTransferrer);
        token.forcedTransfer(user1, user2, TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user1, TOKEN_ID_1), MINT_AMOUNT - FORCE_TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), FORCE_TRANSFER_AMOUNT);
    }

    function test_ForcedTransfer_Success_AllTokensFrozenThenForceTransferAll() public {
        // Freeze ALL tokens
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, MINT_AMOUNT);

        uint256 user2InitialBalance = token.balanceOf(user2, TOKEN_ID_1);

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true); // Frozen event - all frozen tokens should be unfrozen
        emit IERC7943MultiToken.Frozen(user1, TOKEN_ID_1, 0);
        vm.expectEmit(true, true, true, true); // Transfer event
        emit IERC1155.TransferSingle(forceTransferrer, user1, user2, TOKEN_ID_1, MINT_AMOUNT);
        vm.expectEmit(true, true, true, true); // ForcedTransfer event
        emit IERC7943MultiToken.ForcedTransfer(user1, user2, TOKEN_ID_1, MINT_AMOUNT);
        token.forcedTransfer(user1, user2, TOKEN_ID_1, MINT_AMOUNT);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), 0);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), user2InitialBalance + MINT_AMOUNT);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), 0);
    }

    function test_Revert_ForcedTransfer_ToNonWhitelisted() public {
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943CannotTransact.selector, nonWhitelistedUser));
        token.forcedTransfer(user1, nonWhitelistedUser, TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
    }

    function test_Revert_ForcedTransfer_NotForceTransferrer() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, FORCE_TRANSFER_ROLE));
        token.forcedTransfer(user1, user2, TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
    }

    function test_Revert_ForcedTransfer_InsufficientBalance() public {
        uint256 forceAmount = MINT_AMOUNT + 1;
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, user1, MINT_AMOUNT, forceAmount, TOKEN_ID_1));
        token.forcedTransfer(user1, user2, TOKEN_ID_1, forceAmount);
    }

    function test_Revert_ForcedTransfer_ToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(0)));
        vm.prank(forceTransferrer);
        token.forcedTransfer(user1, address(0), TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
    }

    function test_Revert_ForcedTransfer_FromZeroAddress() public {
        vm.prank(forceTransferrer);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidSender.selector, address(0)));
        token.forcedTransfer(address(0), user2, TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
    }

    function test_ForcedTransfer_ToContractReceiver() public {
        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC1155.TransferSingle(forceTransferrer, user1, address(receiverContract), TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IERC7943MultiToken.ForcedTransfer(user1, address(receiverContract), TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
        token.forcedTransfer(user1, address(receiverContract), TOKEN_ID_1, FORCE_TRANSFER_AMOUNT);
        assertEq(token.balanceOf(address(receiverContract), TOKEN_ID_1), FORCE_TRANSFER_AMOUNT);
    }

    // --- Batch Transfer Tests ---

    function test_SafeBatchTransfer_Success_WhitelistedToWhitelisted() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = TOKEN_ID_1;
        ids[1] = TOKEN_ID_2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = TRANSFER_AMOUNT;
        amounts[1] = TRANSFER_AMOUNT;

        uint256 user1InitialBalance1 = token.balanceOf(user1, TOKEN_ID_1);
        uint256 user1InitialBalance2 = token.balanceOf(user1, TOKEN_ID_2);
        uint256 user2InitialBalance1 = token.balanceOf(user2, TOKEN_ID_1);
        uint256 user2InitialBalance2 = token.balanceOf(user2, TOKEN_ID_2);

        vm.expectEmit(true, true, true, true);
        emit IERC1155.TransferBatch(user1, user1, user2, ids, amounts);

        vm.prank(user1);
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");

        assertEq(token.balanceOf(user1, TOKEN_ID_1), user1InitialBalance1 - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user1, TOKEN_ID_2), user1InitialBalance2 - TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2, TOKEN_ID_1), user2InitialBalance1 + TRANSFER_AMOUNT);
        assertEq(token.balanceOf(user2, TOKEN_ID_2), user2InitialBalance2 + TRANSFER_AMOUNT);
    }

    function test_Revert_SafeBatchTransfer_ArraysLengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = TOKEN_ID_1;
        ids[1] = TOKEN_ID_2;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = TRANSFER_AMOUNT;

        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidArrayLength.selector, 2, 1));
        vm.prank(user1);
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");
    }

    function test_Revert_SafeBatchTransfer_InsufficientBalance() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = TOKEN_ID_1;
        ids[1] = TOKEN_ID_2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = MINT_AMOUNT;
        amounts[1] = MINT_AMOUNT + 1; // Insufficient for TOKEN_ID_2

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, user1, MINT_AMOUNT, MINT_AMOUNT + 1, TOKEN_ID_2));
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");
    }

    function test_Revert_SafeBatchTransfer_InsufficientUnfrozenBalance() public {
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, FREEZE_AMOUNT);

        uint256[] memory ids = new uint256[](1);
        ids[0] = TOKEN_ID_1;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = (MINT_AMOUNT - FREEZE_AMOUNT) + 1;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943InsufficientUnfrozenBalance.selector, user1, TOKEN_ID_1, amounts[0], MINT_AMOUNT - FREEZE_AMOUNT));
        token.safeBatchTransferFrom(user1, user2, ids, amounts, "");
    }

    // --- Enhanced Freeze/Unfreeze Tests ---

    function test_SetFrozenTokens_Success_EmitsCorrectEvents() public {
        uint256 newFrozenAmount = FREEZE_AMOUNT;

        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943MultiToken.Frozen(user1, TOKEN_ID_1, newFrozenAmount);
        token.setFrozenTokens(user1, TOKEN_ID_1, newFrozenAmount);

        // Change frozen amount
        uint256 updatedFrozenAmount = FREEZE_AMOUNT * 2;
        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943MultiToken.Frozen(user1, TOKEN_ID_1, updatedFrozenAmount);
        token.setFrozenTokens(user1, TOKEN_ID_1, updatedFrozenAmount);

        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), updatedFrozenAmount);
    }

    function test_SetFrozenTokens_Success_UnfreezeEmitsCorrectEvent() public {
        // First freeze some tokens
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, FREEZE_AMOUNT);

        // Then unfreeze them
        vm.prank(freezer);
        vm.expectEmit(true, true, true, true);
        emit IERC7943MultiToken.Frozen(user1, TOKEN_ID_1, 0);
        token.setFrozenTokens(user1, TOKEN_ID_1, 0);

        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), 0);
    }

    function test_Revert_SetFrozenTokens_NotFreezer() public {
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user2, FREEZING_ROLE));
        token.setFrozenTokens(user1, TOKEN_ID_1, FREEZE_AMOUNT);
    }

    // Note: Contract doesn't validate balance in setFrozenTokens - allows freezing more than balance
    // function test_Revert_SetFrozenTokens_InsufficientBalance() public {
    //     uint256 excessiveAmount = MINT_AMOUNT + 1;
    //     vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, user1, token.balanceOf(user1, TOKEN_ID_1), excessiveAmount, TOKEN_ID_1));
    //     vm.prank(freezer);
    //     token.setFrozenTokens(user1, TOKEN_ID_1, excessiveAmount);
    // }

    // --- canTransfer Tests ---

    function test_CanTransfer_Success() public view {
        assertTrue(token.canTransfer(user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT));
    }

    function test_CanTransfer_Fail_InsufficientBalance() public view {
        assertFalse(token.canTransfer(user1, user2, TOKEN_ID_1, MINT_AMOUNT + 1));
    }

    function test_CanTransfer_Fail_FromNotWhitelisted() public {
        vm.prank(whitelister);
        token.changeWhitelist(user1, false);
        assertFalse(token.canTransfer(user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT));
    }

    function test_CanTransfer_Fail_ToNotWhitelisted() public view {
        assertFalse(token.canTransfer(user1, nonWhitelistedUser, TOKEN_ID_1, TRANSFER_AMOUNT));
    }

    function test_CanTransfer_Fail_InsufficientUnfrozenBalance() public {
        vm.prank(freezer);
        uint256 amountToFreeze = MINT_AMOUNT - TRANSFER_AMOUNT + 1;
        if (amountToFreeze > MINT_AMOUNT) amountToFreeze = MINT_AMOUNT;
        token.setFrozenTokens(user1, TOKEN_ID_1, amountToFreeze);
        assertFalse(token.canTransfer(user1, user2, TOKEN_ID_1, TRANSFER_AMOUNT));
    }

    // --- canTransact Tests ---

    function test_IsUserAllowed_Success() public view {
        assertTrue(token.canTransact(user1));
    }

    function test_IsUserAllowed_Fail_NotWhitelisted() public view {
        assertFalse(token.canTransact(nonWhitelistedUser));
    }

    // --- Interface Support Tests ---

    function test_Interface_SupportsIERC7943() public view {
        assertTrue(token.supportsInterface(type(IERC7943MultiToken).interfaceId));
    }

    function test_Interface_SupportsIERC1155() public view {
        assertTrue(token.supportsInterface(type(IERC1155).interfaceId));
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

    function test_EdgeCase_ForceTransferExactBalance() public {
        uint256 userBalance = token.balanceOf(user1, TOKEN_ID_1);

        vm.prank(forceTransferrer);
        vm.expectEmit(true, true, true, true);
        emit IERC1155.TransferSingle(forceTransferrer, user1, user2, TOKEN_ID_1, userBalance);
        vm.expectEmit(true, true, true, true);
        emit IERC7943MultiToken.ForcedTransfer(user1, user2, TOKEN_ID_1, userBalance);
        token.forcedTransfer(user1, user2, TOKEN_ID_1, userBalance);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), 0);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), 0);
    }

    function test_EdgeCase_BurnAfterPartialForceTransfer() public {
        vm.prank(admin);
        token.grantRole(BURNER_ROLE, user1);

        // Freeze half of user1's tokens
        uint256 frozenAmount = MINT_AMOUNT / 2;
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, frozenAmount);

        // Force transfer more than unfrozen (should reduce frozen amount)
        uint256 unfrozenBalance = token.balanceOf(user1, TOKEN_ID_1) - frozenAmount;
        uint256 forceTransferAmount = unfrozenBalance + 20;

        vm.prank(forceTransferrer);
        token.forcedTransfer(user1, user2, TOKEN_ID_1, forceTransferAmount);

        // Now burn remaining tokens
        uint256 remainingBalance = token.balanceOf(user1, TOKEN_ID_1);
        vm.prank(user1);
        token.burn(TOKEN_ID_1, remainingBalance);

        assertEq(token.balanceOf(user1, TOKEN_ID_1), 0);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), 0);
    }

    function test_EdgeCase_MultipleTokensFreezingIndependently() public {
        // Freeze only TOKEN_ID_1
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, FREEZE_AMOUNT);

        // TOKEN_ID_1 should be frozen, TOKEN_ID_2 should not
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_1), FREEZE_AMOUNT);
        assertEq(token.getFrozenTokens(user1, TOKEN_ID_2), 0);

        // Transfer TOKEN_ID_2 should work
        vm.prank(user1);
        token.safeTransferFrom(user1, user2, TOKEN_ID_2, TRANSFER_AMOUNT, "");
        assertEq(token.balanceOf(user2, TOKEN_ID_2), TRANSFER_AMOUNT);

        // Transfer TOKEN_ID_1 beyond unfrozen should fail
        uint256 availableToTransfer = MINT_AMOUNT - FREEZE_AMOUNT;
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943InsufficientUnfrozenBalance.selector, user1, TOKEN_ID_1, availableToTransfer + 1, availableToTransfer));
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, availableToTransfer + 1, "");
    }

    // --- Redundant Balance Check Coverage ---

    function test_Transfer_RedundantBalanceCheckCoverage() public {
        // This test ensures the redundant balance check in _update is covered
        uint256 transferAmount = MINT_AMOUNT + 1;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InsufficientBalance.selector, user1, MINT_AMOUNT, transferAmount, TOKEN_ID_1));
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, transferAmount, "");
    }

    function test_Transfer_FrozenBalanceCheckAfterRedundantCheck() public {
        // Freeze tokens so that the frozen balance check triggers after redundant check
        vm.prank(freezer);
        token.setFrozenTokens(user1, TOKEN_ID_1, MINT_AMOUNT / 2);

        uint256 unfrozenBalance = token.balanceOf(user1, TOKEN_ID_1) - token.getFrozenTokens(user1, TOKEN_ID_1);
        uint256 transferAmount = unfrozenBalance + 1;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC7943MultiToken.ERC7943InsufficientUnfrozenBalance.selector, user1, TOKEN_ID_1, transferAmount, unfrozenBalance));
        token.safeTransferFrom(user1, user2, TOKEN_ID_1, transferAmount, "");
    }

    function test_BatchTransfer_ToContractReceiver() public {
        // This test will trigger onERC1155BatchReceived and supportsInterface in MockERC1155Receiver
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](2);
        ids[0] = TOKEN_ID_1;
        ids[1] = TOKEN_ID_2;
        amounts[0] = 10;
        amounts[1] = 20;

        vm.prank(user1);
        token.safeBatchTransferFrom(user1, address(receiverContract), ids, amounts, "");

        // Verify the transfers worked
        assertEq(token.balanceOf(address(receiverContract), TOKEN_ID_1), 10);
        assertEq(token.balanceOf(address(receiverContract), TOKEN_ID_2), 20);
    }

    function test_MockReceiver_SupportsInterface() public view {
        // This test will trigger supportsInterface in MockERC1155Receiver
        assertTrue(receiverContract.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertTrue(receiverContract.supportsInterface(type(IERC165).interfaceId));
        assertFalse(receiverContract.supportsInterface(bytes4(0x12345678))); // Random interface
    }

    function test_BatchTransfer_ToContractReceiver_Rejection() public {
        // This test will trigger onERC1155BatchReceived rejection path
        receiverContract.setShouldReject(true);
        
        uint256[] memory ids = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        ids[0] = TOKEN_ID_1;
        amounts[0] = 10;

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IERC1155Errors.ERC1155InvalidReceiver.selector, address(receiverContract)));
        token.safeBatchTransferFrom(user1, address(receiverContract), ids, amounts, "");
        
        // Reset for other tests
        receiverContract.setShouldReject(false);
    }

    // --- Helper Functions ---

    function _setupUserWithFrozenTokens(address user, uint256 tokenId, uint256 totalBalance, uint256 frozenAmount) internal {
        vm.prank(minter);
        token.mint(user, tokenId, totalBalance);

        vm.prank(admin);
        token.changeWhitelist(user, true);

        if (frozenAmount > 0) {
            vm.prank(freezer);
            token.setFrozenTokens(user, tokenId, frozenAmount);
        }
    }

    function _verifyBalanceAndFrozenState(
        address user,
        uint256 tokenId,
        uint256 expectedBalance,
        uint256 expectedFrozen,
        string memory errorMsg
    ) internal view {
        assertEq(token.balanceOf(user, tokenId), expectedBalance, string.concat(errorMsg, " - Balance mismatch"));
        assertEq(token.getFrozenTokens(user, tokenId), expectedFrozen, string.concat(errorMsg, " - Frozen amount mismatch"));
    }
}
