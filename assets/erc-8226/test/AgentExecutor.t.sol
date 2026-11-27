// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC7943Fungible} from "../contracts/mocks/IERC7943.sol";

import {AgentExecutor} from "../contracts/AgentExecutor.sol";
import {AgentMandate} from "../contracts/AgentMandate.sol";
import {ComplianceProvider} from "../contracts/ComplianceProvider.sol";
import {IAgentMandate} from "../contracts/interfaces/IAgentMandate.sol";
import {uRWA20} from "../contracts/mocks/uRWA20.sol";

/// @notice Tests the executor as the principal's EIP-7702 code against the real registry, compliance provider, and a
///         uRWA-20 asset.
contract AgentExecutorTest is Test {
    AgentExecutor executor;
    AgentMandate mandate;
    ComplianceProvider compliance;
    uRWA20 token;
    uRWA20 tokenB;

    address admin = makeAddr("admin");
    address complianceOwner = makeAddr("complianceOwner");
    address enforcer = makeAddr("enforcer");
    address principal;
    address agent = makeAddr("agent");
    address recipient = makeAddr("recipient");
    address stranger = makeAddr("stranger");
    address spender = makeAddr("spender");

    bytes32 constant IDREF = keccak256("kyc-principal");
    bytes4 constant APPROVE = IERC20.approve.selector;
    bytes4 constant TRANSFER = IERC20.transfer.selector;
    bytes4 constant DEPOSIT = this.deposit.selector;

    function setUp() public {
        compliance = new ComplianceProvider(complianceOwner);
        mandate = new AgentMandate(admin);
        token = new uRWA20("Regulated", "RWA", admin);
        uint256 principalKey;
        (principal, principalKey) = makeAddrAndKey("principal");

        vm.prank(complianceOwner);
        compliance.grantPrincipal(principal, IDREF, 0);

        vm.startPrank(admin);
        token.changeSendWhitelist(principal, true);
        token.changeReceiveWhitelist(principal, true);
        token.changeReceiveWhitelist(recipient, true);
        token.mint(principal, 10_000);
        vm.stopPrank();

        IAgentMandate.Action[] memory actions = new IAgentMandate.Action[](2);
        actions[0].action = bytes32(TRANSFER);
        actions[1].action = bytes32(APPROVE);
        actions[1].constraints = new IAgentMandate.Constraint[](1);
        actions[1].constraints[0] =
            IAgentMandate.Constraint(0, IAgentMandate.Check.EQUALS, bytes32(uint256(uint160(spender))));
        IAgentMandate.Limit[] memory limits = new IAgentMandate.Limit[](1);
        limits[0] = IAgentMandate.Limit(address(token), IAgentMandate.Direction.OUTFLOW, 1000, 1500, 0);
        IAgentMandate.GrantMandateParams memory params = IAgentMandate.GrantMandateParams({
            agent: agent,
            validFrom: 0,
            validUntil: uint48(block.timestamp + 1 days),
            principal: principal,
            complianceProvider: address(compliance),
            identityRef: IDREF,
            target: address(token),
            actions: actions,
            limits: limits,
            metadata: bytes32(0),
            deadline: 0
        });
        // The principal delegates its account to the shared executor code. No RECORDER_ROLE and no approve: the token
        // sees the principal as msg.sender, and the registry accepts the principal as its own recorder.
        vm.signAndAttachDelegation(address(new AgentExecutor(IAgentMandate(address(mandate)))), principalKey);
        vm.prank(principal);
        mandate.grantMandate(params, "");
        executor = AgentExecutor(payable(principal));
    }

    function _transfer(address to, uint256 amount) internal {
        vm.prank(agent);
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER, to, amount));
    }

    /// @dev A target that pulls two tokens from the principal that are not in its calldata, like a staking deposit.
    function deposit(uint256 amount, uint256 amountB) external {
        token.transferFrom(principal, address(this), amount);
        tokenB.transferFrom(principal, address(this), amountB);
    }

    function test_TransfersAndRecords() public {
        _transfer(recipient, 500);
        assertEq(token.balanceOf(recipient), 500);
        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, 500);
    }

    function test_RevertsOverPerTxCap() public {
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_TX_CAP)
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER, recipient, uint256(1001)));
        assertEq(token.balanceOf(principal), 10_000);
    }

    function test_RevertsOverCumulativeCap() public {
        _transfer(recipient, 1000);
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_CUMULATIVE_CAP
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER, recipient, uint256(1000)));
    }

    function test_ApproveSpendsNothingAndIsGatedBySpender() public {
        vm.prank(agent);
        executor.execute(address(token), abi.encodeWithSelector(APPROVE, spender, uint256(5000)));
        assertEq(token.allowance(principal, spender), 5000);
        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, 0);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentExecutor.CannotExecute.selector,
                agent,
                address(token),
                APPROVE,
                IAgentMandate.MandateReason.CONSTRAINT_FAILED
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(APPROVE, stranger, uint256(5000)));
    }

    function test_TwoTokensNotInCalldataCountedApart() public {
        tokenB = new uRWA20("Regulated B", "RWB", admin);
        vm.startPrank(admin);
        token.changeReceiveWhitelist(address(this), true);
        tokenB.changeSendWhitelist(principal, true);
        tokenB.changeReceiveWhitelist(principal, true);
        tokenB.changeReceiveWhitelist(address(this), true);
        tokenB.mint(principal, 10_000);
        vm.stopPrank();
        vm.startPrank(principal);
        token.approve(address(this), type(uint256).max);
        tokenB.approve(address(this), type(uint256).max);
        vm.stopPrank();

        IAgentMandate.Action[] memory actions = new IAgentMandate.Action[](1);
        actions[0].action = bytes32(DEPOSIT);
        IAgentMandate.Limit[] memory limits = new IAgentMandate.Limit[](2);
        limits[0] = IAgentMandate.Limit(address(token), IAgentMandate.Direction.OUTFLOW, 2, 10, 0);
        limits[1] = IAgentMandate.Limit(address(tokenB), IAgentMandate.Direction.OUTFLOW, 20, 100, 0);
        IAgentMandate.GrantMandateParams memory params = IAgentMandate.GrantMandateParams({
            agent: agent,
            validFrom: 0,
            validUntil: uint48(block.timestamp + 1 days),
            principal: principal,
            complianceProvider: address(compliance),
            identityRef: IDREF,
            target: address(this),
            actions: actions,
            limits: limits,
            metadata: bytes32(0),
            deadline: 0
        });
        vm.prank(principal);
        mandate.grantMandate(params, "");

        vm.prank(agent);
        executor.execute(address(this), abi.encodeWithSelector(DEPOSIT, 1, 15));
        IAgentMandate.Limit[] memory used = mandate.getLimits(agent, principal, address(this));
        assertEq(used[0].cumulativeUsed, 1);
        assertEq(used[1].cumulativeUsed, 15);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_TX_CAP)
        );
        executor.execute(address(this), abi.encodeWithSelector(DEPOSIT, 3, 1));
    }

    function test_InflowLimitCountsWhatEntersThePrincipal() public {
        vm.startPrank(admin);
        token.changeSendWhitelist(stranger, true);
        token.changeReceiveWhitelist(stranger, true);
        token.mint(stranger, 10_000);
        vm.stopPrank();
        vm.prank(stranger);
        token.approve(principal, type(uint256).max);

        IAgentMandate.Action[] memory actions = new IAgentMandate.Action[](1);
        actions[0].action = bytes32(IERC20.transferFrom.selector);
        IAgentMandate.Limit[] memory limits = new IAgentMandate.Limit[](2);
        limits[0] = IAgentMandate.Limit(address(token), IAgentMandate.Direction.OUTFLOW, 0, 0, 0);
        limits[1] = IAgentMandate.Limit(address(token), IAgentMandate.Direction.INFLOW, 500, 800, 0);
        IAgentMandate.GrantMandateParams memory params = IAgentMandate.GrantMandateParams({
            agent: agent,
            validFrom: 0,
            validUntil: uint48(block.timestamp + 1 days),
            principal: principal,
            complianceProvider: address(compliance),
            identityRef: IDREF,
            target: address(token),
            actions: actions,
            limits: limits,
            metadata: bytes32(0),
            deadline: 0
        });
        vm.startPrank(principal);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
        mandate.grantMandate(params, "");
        vm.stopPrank();

        vm.prank(agent);
        executor.execute(address(token), abi.encodeCall(IERC20.transferFrom, (stranger, principal, 500)));
        IAgentMandate.Limit[] memory used = mandate.getLimits(agent, principal, address(token));
        assertEq(used[0].cumulativeUsed, 0);
        assertEq(used[1].cumulativeUsed, 500);

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_TX_CAP)
        );
        executor.execute(address(token), abi.encodeCall(IERC20.transferFrom, (stranger, principal, 501)));

        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_CUMULATIVE_CAP
            )
        );
        executor.execute(address(token), abi.encodeCall(IERC20.transferFrom, (stranger, principal, 301)));
    }

    function test_RevertsShortCalldata() public {
        vm.prank(agent);
        vm.expectRevert(AgentExecutor.InvalidData.selector);
        executor.execute(address(token), hex"001122");
    }

    function test_RevertsActionNotEnabled() public {
        bytes4 unknown = bytes4(keccak256("foo()"));
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentExecutor.CannotExecute.selector,
                agent,
                address(token),
                unknown,
                IAgentMandate.MandateReason.ACTION_NOT_ENABLED
            )
        );
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
                AgentExecutor.CannotExecute.selector,
                agent,
                address(token),
                TRANSFER,
                IAgentMandate.MandateReason.AGENT_FROZEN
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER, recipient, uint256(500)));
    }

    function test_RevertsWhenRevoked() public {
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentExecutor.CannotExecute.selector,
                agent,
                address(token),
                TRANSFER,
                IAgentMandate.MandateReason.REVOKED
            )
        );
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER, recipient, uint256(500)));
    }

    function test_TokenComplianceBlocksIndependently() public {
        bytes memory inner = abi.encodeWithSelector(IERC7943Fungible.ERC7943CannotReceive.selector, stranger);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentExecutor.CallFailed.selector, inner));
        executor.execute(address(token), abi.encodeWithSelector(TRANSFER, stranger, uint256(500)));
    }

    function test_AcceptsEthAndSafeTransfers() public {
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        (bool ok,) = address(executor).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(executor).balance, 1 ether);
        assertEq(executor.onERC721Received(stranger, stranger, 1, ""), executor.onERC721Received.selector);
    }

    function test_DelegatedPrincipalSigns() public {
        (, uint256 principalKey) = makeAddrAndKey("principal");
        address operator = makeAddr("operator");
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "SetOperator(address principal,address operator,bool approved,uint256 nonce,uint256 deadline)"
                ),
                principal,
                operator,
                true,
                mandate.nonces(principal),
                deadline
            )
        );
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(principalKey, keccak256(abi.encodePacked(hex"1901", mandate.DOMAIN_SEPARATOR(), structHash)));

        vm.prank(stranger);
        mandate.setOperator(principal, operator, true, deadline, abi.encodePacked(r, s, v));
        assertTrue(mandate.isOperator(principal, operator));
    }
}
