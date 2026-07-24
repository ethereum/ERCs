// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC7943Fungible} from "../contracts/regulated-asset-mock/IERC7943.sol";

import {AgentExecutor} from "../contracts/AgentExecutor.sol";
import {AgentMandate} from "../contracts/AgentMandate.sol";
import {ComplianceProvider} from "../contracts/ComplianceProvider.sol";
import {IAgentMandate} from "../contracts/interfaces/IAgentMandate.sol";
import {uRWA20} from "../contracts/regulated-asset-mock/uRWA20.sol";

/// @notice Tests the executor venue against the real registry, compliance provider, and a uRWA-20 asset.
contract AgentExecutorTest is Test {
    AgentExecutor executor;
    AgentMandate mandate;
    ComplianceProvider compliance;
    uRWA20 token;

    address admin = makeAddr("admin");
    address complianceOwner = makeAddr("complianceOwner");
    address executorOwner = makeAddr("executorOwner");
    address enforcer = makeAddr("enforcer");
    address principal = makeAddr("principal");
    address agent = makeAddr("agent");
    address recipient = makeAddr("recipient");
    address stranger = makeAddr("stranger");
    address spender = makeAddr("spender");

    bytes32 constant IDREF = keccak256("kyc-principal");
    bytes4 constant TRANSFER_FROM = IERC20.transferFrom.selector;
    bytes4 constant APPROVE = IERC20.approve.selector;
    bytes4 constant SWAP = uRWA20.swap.selector;

    function setUp() public {
        compliance = new ComplianceProvider(complianceOwner);
        mandate = new AgentMandate(admin);
        token = new uRWA20("Regulated", "RWA", admin);
        executor = new AgentExecutor(IAgentMandate(address(mandate)), principal, executorOwner);

        vm.prank(complianceOwner);
        compliance.grantPrincipal(principal, IDREF, 0);

        vm.startPrank(admin);
        token.changeSendWhitelist(principal, true);
        token.changeReceiveWhitelist(principal, true);
        token.changeReceiveWhitelist(recipient, true);
        token.mint(principal, 10_000);
        vm.stopPrank();

        bytes32[] memory actions = new bytes32[](3);
        actions[0] = bytes32(TRANSFER_FROM);
        actions[1] = bytes32(APPROVE);
        actions[2] = bytes32(SWAP);
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

        vm.startPrank(admin);
        mandate.grantRole(mandate.RECORDER_ROLE(), address(executor));
        vm.stopPrank();
        vm.prank(executorOwner);
        executor.setAction(TRANSFER_FROM, true, true, 2);

        vm.prank(principal);
        token.approve(address(executor), type(uint256).max);
    }

    function _transfer(address to, uint256 amount) internal {
        vm.prank(agent);
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER_FROM, principal, to, amount));
    }

    function test_AmountArgReadByIndexWithDynamicArgBefore() public {
        // swap(uint256 a, uint256[] t, uint256 amount): amount is arg index 2. The dynamic `t` at index 1
        // only stores an offset in its head slot, so amount still sits at 4 + 32*2 and must decode as 42.
        vm.prank(executorOwner);
        executor.setAction(SWAP, true, true, 2);

        uint256[] memory arr = new uint256[](3);
        arr[0] = 1;
        arr[1] = 2;
        arr[2] = 3;
        vm.prank(agent);
        executor.execute(address(token), abi.encodeWithSelector(SWAP, uint256(111), arr, uint256(42)));

        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 42);
    }

    function test_ApproveWithAmountAtDifferentIndex() public {
        // A second action whose amount sits at arg index 1 (approve(spender, amount)).
        vm.prank(executorOwner);
        executor.setAction(APPROVE, true, true, 1);

        vm.prank(agent);
        executor.execute(address(token), abi.encodeWithSelector(APPROVE, spender, uint256(400)));

        assertEq(token.allowance(address(executor), spender), 400);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 400);
    }

    function test_Misconfig_ValueBearingActionAsValueless_BypassesCap() public {
        // RISK: registering a value-bearing action (approve) as hasAmount=false makes the executor gate it
        // at amount 0, bypassing maxTransactionValue. Owners MUST register value-bearing actions as hasAmount=true.
        vm.prank(executorOwner);
        executor.setAction(APPROVE, true, false, 0);

        vm.prank(agent);
        executor.execute(address(token), abi.encodeWithSelector(APPROVE, spender, uint256(700)));

        assertEq(token.allowance(address(executor), spender), 700); // the forwarded call still ran
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 0); // but the cap was untouched
    }

    function test_RevertsOverCumulativeCap() public {
        _transfer(recipient, 1000); // cumulative 1000
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentExecutor.CannotExecute.selector, agent, address(token), TRANSFER_FROM, uint256(1000)
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, uint256(1000)));
    }

    function test_RevertsOverPerTxCap() public {
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentExecutor.CannotExecute.selector, agent, address(token), TRANSFER_FROM, uint256(1500)
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, uint256(1500)));
    }

    function test_RevertsUnsupportedSelector() public {
        bytes4 unknown = bytes4(keccak256("foo()"));
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentExecutor.UnsupportedAction.selector, unknown));
        executor.execute(address(token), abi.encodeWithSelector(unknown));
    }

    function test_RevertsWhenFrozen() public {
        vm.startPrank(admin);
        mandate.grantRole(mandate.ENFORCER_ROLE(), enforcer);
        vm.stopPrank();
        vm.prank(enforcer);
        mandate.freezeAgent(agent);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentExecutor.CannotExecute.selector, agent, address(token), TRANSFER_FROM, uint256(500)
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, uint256(500)));
    }

    function test_RevertsWhenRevoked() public {
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, 0, "");
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentExecutor.CannotExecute.selector, agent, address(token), TRANSFER_FROM, uint256(500)
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, uint256(500)));
    }

    function test_SetActionCanDisable() public {
        vm.prank(executorOwner);
        executor.setAction(TRANSFER_FROM, false, true, 2);

        (bool supported,,) = executor.actions(TRANSFER_FROM);
        assertFalse(supported);

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentExecutor.UnsupportedAction.selector, TRANSFER_FROM));
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, uint256(100)));
    }

    function test_SetActionOnlyOwner() public {
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, agent));
        executor.setAction(TRANSFER_FROM, true, true, 2);
    }

    function test_SetActionRegisters() public {
        vm.prank(executorOwner);
        executor.setAction(APPROVE, true, true, 1);

        (bool supported, bool hasAmount, uint8 amountIndex) = executor.actions(APPROVE);
        assertTrue(supported);
        assertTrue(hasAmount);
        assertEq(amountIndex, 1);
    }

    function test_TokenComplianceBlocksIndependently() public {
        bytes memory inner = abi.encodeWithSelector(IERC7943Fungible.ERC7943CannotReceive.selector, stranger);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentExecutor.CallFailed.selector, inner));
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER_FROM, principal, stranger, uint256(500)));
    }

    function test_TransfersAndRecords() public {
        _transfer(recipient, 500);
        assertEq(token.balanceOf(recipient), 500);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 500);
    }
}
