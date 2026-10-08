// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {AgentMandate} from "../contracts/AgentMandate.sol";
import {ComplianceProvider} from "../contracts/ComplianceProvider.sol";
import {IAgentMandate} from "../contracts/interfaces/IAgentMandate.sol";
import {RamsGated} from "../contracts/RamsGated.sol";
import {RamsGatedURWA20} from "../contracts/mocks/RamsGatedURWA20.sol";

contract RamsGatedURWA20Test is Test {
    AgentMandate mandate;
    ComplianceProvider compliance;
    RamsGatedURWA20 token;

    address admin = makeAddr("admin");
    address complianceOwner = makeAddr("complianceOwner");
    address agent = makeAddr("agent");
    address recipient = makeAddr("recipient");
    address spender = makeAddr("spender");
    address enforcer = makeAddr("enforcer");
    address principal = makeAddr("principal");

    bytes32 constant IDREF = keccak256("kyc-principal");

    /// @dev One label per gated function, in the order the token declares them.
    bytes32[] actions;

    function setUp() public {
        mandate = new AgentMandate(admin);
        compliance = new ComplianceProvider(complianceOwner);
        token = new RamsGatedURWA20("Regulated", "RWA", admin, mandate);

        actions.push(bytes32(IERC20.transferFrom.selector));
        actions.push(bytes32(token.approveFor.selector));
        actions.push(bytes32(token.mintFor.selector));

        vm.prank(complianceOwner);
        compliance.grantPrincipal(principal, IDREF, 0);

        vm.startPrank(admin);
        mandate.grantRole(mandate.ENFORCER_ROLE(), enforcer);
        token.changeSendWhitelist(principal, true);
        token.changeReceiveWhitelist(principal, true);
        token.changeReceiveWhitelist(recipient, true);
        token.mint(principal, 5000);
        vm.stopPrank();

        vm.prank(principal);
        token.approve(agent, type(uint256).max);
    }

    function _grant() internal {
        IAgentMandate.GrantMandateParams memory p = IAgentMandate.GrantMandateParams({
            agent: agent,
            validFrom: 0,
            validUntil: uint48(block.timestamp + 1 days),
            principal: principal,
            complianceProvider: address(compliance),
            identityRef: IDREF,
            asset: address(token),
            maxTransactionValue: 1000,
            maxCumulativeValue: 1500,
            metadata: bytes32(0),
            actions: actions,
            deadline: 0
        });
        vm.prank(principal);
        mandate.grantMandate(p, "");
    }

    // --- the gated path ---

    function test_AgentTransferAdvancesUsedOnce() public {
        _grant();

        vm.prank(agent);
        token.transferFrom(principal, recipient, 400);

        assertEq(token.balanceOf(recipient), 400);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 400);
    }

    function test_ApproveForRecordsWithoutMovingTokens() public {
        _grant();
        uint256 supply = token.totalSupply();

        vm.prank(agent);
        token.approveFor(principal, spender, 700);

        assertEq(token.allowance(principal, spender), 700);
        assertEq(token.totalSupply(), supply);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 700);
    }

    function test_MintForNeedsRoleAndMandate() public {
        _grant();
        bytes32 minterRole = token.MINTER_ROLE();

        // The role is checked before the mandate, so the mandate alone is not enough.
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, agent, minterRole)
        );
        vm.prank(agent);
        token.mintFor(principal, 300);

        vm.prank(admin);
        token.grantRole(minterRole, agent);

        vm.prank(agent);
        token.mintFor(principal, 300);

        assertEq(token.balanceOf(principal), 5300);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 300);
    }

    function test_EachActionSpendsTheSameBudget() public {
        _grant();

        vm.startPrank(agent);
        token.transferFrom(principal, recipient, 900);
        token.approveFor(principal, spender, 600);
        vm.stopPrank();

        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 1500);

        vm.expectRevert(
            abi.encodeWithSelector(RamsGated.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_CUMULATIVE_CAP)
        );
        vm.prank(agent);
        token.transferFrom(principal, recipient, 1);
    }

    // --- each reason surfaces through MandateBlocked ---

    function test_BlockedNonexistent() public {
        vm.expectRevert(
            abi.encodeWithSelector(RamsGated.MandateBlocked.selector, IAgentMandate.MandateReason.NONEXISTENT)
        );
        vm.prank(agent);
        token.transferFrom(principal, recipient, 1);
    }

    function test_BlockedExpired() public {
        _grant();
        vm.warp(block.timestamp + 2 days);

        vm.expectRevert(abi.encodeWithSelector(RamsGated.MandateBlocked.selector, IAgentMandate.MandateReason.EXPIRED));
        vm.prank(agent);
        token.transferFrom(principal, recipient, 1);
    }

    function test_BlockedRevoked() public {
        _grant();
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, 0, "");

        vm.expectRevert(abi.encodeWithSelector(RamsGated.MandateBlocked.selector, IAgentMandate.MandateReason.REVOKED));
        vm.prank(agent);
        token.transferFrom(principal, recipient, 1);
    }

    function test_BlockedOverTxCap() public {
        _grant();

        vm.expectRevert(
            abi.encodeWithSelector(RamsGated.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_TX_CAP)
        );
        vm.prank(agent);
        token.transferFrom(principal, recipient, 1001);
    }

    function test_BlockedFrozen() public {
        _grant();
        vm.prank(enforcer);
        mandate.freezeAgent(agent);

        vm.expectRevert(
            abi.encodeWithSelector(RamsGated.MandateBlocked.selector, IAgentMandate.MandateReason.AGENT_FROZEN)
        );
        vm.prank(agent);
        token.transferFrom(principal, recipient, 1);
    }

    function test_BlockedActionNotEnabled() public {
        actions.pop(); // mintFor
        actions.pop(); // approveFor, leaving transferFrom as the only label
        _grant();

        vm.expectRevert(
            abi.encodeWithSelector(RamsGated.MandateBlocked.selector, IAgentMandate.MandateReason.ACTION_NOT_ENABLED)
        );
        vm.prank(agent);
        token.approveFor(principal, spender, 1);
    }

    // --- ungated paths ---

    function test_HolderNeedsNoMandate() public {
        vm.startPrank(principal);
        token.transfer(recipient, 100);
        token.approve(principal, 100);
        token.transferFrom(principal, recipient, 100);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), 200);
    }

    function test_RoleFunctionsStayUngated() public {
        vm.startPrank(admin);
        token.mint(principal, 100);
        token.forcedTransfer(principal, recipient, 100);
        token.setFrozenTokens(principal, 50);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), 100);
        assertEq(token.getFrozenTokens(principal), 50);
    }

    function test_CanTransferIgnoresTheMandate() public view {
        // No mandate exists, and canTransfer still answers about the holder alone.
        assertTrue(token.canTransfer(principal, recipient, 100));
    }

    function test_ZeroRegistryReverts() public {
        vm.expectRevert(RamsGated.ZeroRegistry.selector);
        new RamsGatedURWA20("Regulated", "RWA", admin, IAgentMandate(address(0)));
    }
}
