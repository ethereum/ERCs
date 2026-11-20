// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {AgentMandate} from "../contracts/AgentMandate.sol";
import {ComplianceProvider} from "../contracts/ComplianceProvider.sol";
import {IComplianceProvider} from "../contracts/interfaces/IComplianceProvider.sol";
import {IAgentMandate} from "../contracts/interfaces/IAgentMandate.sol";
import {uRWA20} from "../contracts/mocks/uRWA20.sol";

contract MockWallet {
    using ECDSA for bytes32;

    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 hash, bytes calldata sig) external view returns (bytes4) {
        return hash.recover(sig) == owner ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

contract AgentMandateTest is Test {
    AgentMandate mandate;
    ComplianceProvider compliance;
    uRWA20 token;

    address admin = makeAddr("admin");
    address complianceOwner = makeAddr("complianceOwner");
    address agent = makeAddr("agent");
    address recipient = makeAddr("recipient");
    address operator = makeAddr("operator");
    address relayer = makeAddr("relayer");
    address stranger = makeAddr("stranger");
    address recorder = makeAddr("recorder");
    address enforcer = makeAddr("enforcer");

    address principal;
    uint256 principalPk;

    bytes32 enforcerRole;
    bytes32 recorderRole;
    bytes32 adminRole;

    bytes32 constant IDREF = keccak256("kyc-principal");
    bytes4 constant TRANSFER_FROM = IERC20.transferFrom.selector;
    bytes32 constant ACTION = bytes32(IERC20.transferFrom.selector);
    bytes32 constant OTHER_ACTION = bytes32(uint256(0xdead));

    bytes32 constant GRANT_TYPEHASH = keccak256(
        "GrantMandate(address agent,uint48 validFrom,uint48 validUntil,address principal,address complianceProvider,bytes32 identityRef,address target,Action[] actions,Limit[] limits,bytes32 metadata,uint256 nonce,uint256 deadline)Action(bytes32 action,Constraint[] constraints)Constraint(uint8 index,uint8 check,bytes32 value)Limit(address asset,uint8 direction,uint256 maxTransactionValue,uint256 maxCumulativeValue,uint256 cumulativeUsed)"
    );
    bytes32 constant ACTION_TYPEHASH =
        keccak256("Action(bytes32 action,Constraint[] constraints)Constraint(uint8 index,uint8 check,bytes32 value)");
    bytes32 constant LIMIT_TYPEHASH = keccak256(
        "Limit(address asset,uint8 direction,uint256 maxTransactionValue,uint256 maxCumulativeValue,uint256 cumulativeUsed)"
    );
    bytes32 constant REVOKE_TYPEHASH =
        keccak256("RevokeMandate(address agent,address principal,address target,uint256 nonce,uint256 deadline)");
    bytes32 constant EXTEND_TYPEHASH = keccak256(
        "ExtendMandate(address agent,address principal,address target,uint48 newValidUntil,uint256 nonce,uint256 deadline)"
    );
    bytes32 constant SETOP_TYPEHASH =
        keccak256("SetOperator(address principal,address operator,bool approved,uint256 nonce,uint256 deadline)");

    function setUp() public {
        (principal, principalPk) = makeAddrAndKey("principal");

        mandate = new AgentMandate(admin);
        compliance = new ComplianceProvider(complianceOwner);
        token = new uRWA20("Regulated", "RWA", admin);

        enforcerRole = mandate.ENFORCER_ROLE();
        recorderRole = mandate.RECORDER_ROLE();
        adminRole = mandate.DEFAULT_ADMIN_ROLE();

        vm.prank(complianceOwner);
        compliance.grantPrincipal(principal, IDREF, 0);
    }

    function _params() internal view returns (IAgentMandate.GrantMandateParams memory params) {
        IAgentMandate.Action[] memory actions = new IAgentMandate.Action[](1);
        actions[0].action = ACTION;
        IAgentMandate.Limit[] memory limits = new IAgentMandate.Limit[](1);
        limits[0] = IAgentMandate.Limit(address(token), IAgentMandate.Direction.OUTFLOW, 1000, 1500, 0);
        params = IAgentMandate.GrantMandateParams({
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
    }

    function _grant() internal {
        vm.prank(principal);
        mandate.grantMandate(_params(), "");
    }

    function _sign(uint256 pk, bytes32 structHash) internal view returns (bytes memory) {
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", mandate.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _grantStructHash(IAgentMandate.GrantMandateParams memory params, uint256 nonce)
        internal
        pure
        returns (bytes32)
    {
        // _params() has one action with no constraints and one limit.
        bytes32 actionsHash = keccak256(
            abi.encodePacked(keccak256(abi.encode(ACTION_TYPEHASH, params.actions[0].action, keccak256(""))))
        );
        IAgentMandate.Limit memory limit = params.limits[0];
        bytes32 limitsHash = keccak256(
            abi.encodePacked(
                keccak256(
                    abi.encode(
                        LIMIT_TYPEHASH,
                        limit.asset,
                        uint8(limit.direction),
                        limit.maxTransactionValue,
                        limit.maxCumulativeValue,
                        limit.cumulativeUsed
                    )
                )
            )
        );
        return keccak256(
            bytes.concat(
                abi.encode(
                    GRANT_TYPEHASH,
                    params.agent,
                    params.validFrom,
                    params.validUntil,
                    params.principal,
                    params.complianceProvider,
                    params.identityRef,
                    params.target
                ),
                abi.encode(actionsHash, limitsHash, params.metadata, nonce, params.deadline)
            )
        );
    }

    function test_AdminCannotAlsoBeEnforcer() public {
        vm.startPrank(admin);
        vm.expectRevert(AgentMandate.AdminEnforcerOverlap.selector);
        mandate.grantRole(enforcerRole, admin);
        vm.stopPrank();
    }

    function test_EnforcerCannotAlsoBeAdmin() public {
        vm.startPrank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.expectRevert(AgentMandate.AdminEnforcerOverlap.selector);
        mandate.grantRole(adminRole, enforcer);
        vm.stopPrank();
    }

    function test_SupportsInterface() public view {
        assertTrue(mandate.supportsInterface(type(IAgentMandate).interfaceId));
        assertTrue(mandate.supportsInterface(type(IERC165).interfaceId));
        assertFalse(mandate.supportsInterface(0xffffffff));
    }

    function test_GrantDirectByPrincipal() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        assertEq(mandate.getMandate(agent, principal, address(token)).principal, principal);
        assertTrue(mandate.isActionEnabled(agent, principal, address(token), ACTION));
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 1000);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
    }

    function test_GrantBySignature() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        IAgentMandate.GrantMandateParams memory params = _params();
        params.deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(principalPk, _grantStructHash(params, mandate.nonces(principal)));

        vm.prank(relayer);
        mandate.grantMandate(params, sig);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);

        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
        assertEq(mandate.nonces(principal), 1);
    }

    function test_GrantByContractWallet_EIP1271() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        (address walletOwner, uint256 walletOwnerPk) = makeAddrAndKey("walletOwner");
        MockWallet wallet = new MockWallet(walletOwner);

        vm.prank(complianceOwner);
        compliance.grantPrincipal(address(wallet), IDREF, 0);

        IAgentMandate.GrantMandateParams memory params = _params();
        params.principal = address(wallet);
        params.deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(walletOwnerPk, _grantStructHash(params, mandate.nonces(address(wallet))));

        vm.prank(relayer);
        mandate.grantMandate(params, sig);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);

        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, address(wallet), address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
    }

    function test_GrantWithCumulativeUsed() public {
        IAgentMandate.GrantMandateParams memory params = _params();
        params.limits[0].cumulativeUsed = 1400;
        vm.prank(principal);
        mandate.grantMandate(params, "");

        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 200);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OVER_CUMULATIVE_CAP));
    }

    function test_GetActions() public {
        _grant();
        bytes32[] memory actions = mandate.getActions(agent, principal, address(token));
        assertEq(actions.length, 1);
        assertEq(actions[0], ACTION);
    }

    function test_GrantRevertsAlreadyActive() public {
        _grant();
        vm.prank(principal);
        vm.expectRevert(AgentMandate.MandateAlreadyActive.selector);
        mandate.grantMandate(_params(), "");
    }

    function test_GrantRevertsBadSignature() public {
        (, uint256 wrongPk) = makeAddrAndKey("wrong");
        IAgentMandate.GrantMandateParams memory params = _params();
        params.deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(wrongPk, _grantStructHash(params, mandate.nonces(principal)));
        vm.prank(relayer);
        vm.expectRevert(AgentMandate.InvalidSignature.selector);
        mandate.grantMandate(params, sig);
    }

    function test_GrantRevertsInvalidExpiry() public {
        IAgentMandate.GrantMandateParams memory params = _params();
        params.validUntil = uint48(block.timestamp);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.InvalidExpiry.selector);
        mandate.grantMandate(params, "");
    }

    function test_GrantRevertsAfterComplianceExpiry() public {
        vm.prank(complianceOwner);
        compliance.grantPrincipal(principal, IDREF, uint48(block.timestamp + 1 hours));

        vm.prank(principal);
        vm.expectRevert(AgentMandate.InvalidExpiry.selector);
        mandate.grantMandate(_params(), "");
    }

    function test_GrantRevertsNotEligible() public {
        vm.prank(complianceOwner);
        compliance.revokePrincipal(principal, IComplianceProvider.ReasonCode.AML_FLAG);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.PrincipalNotEligible.selector);
        mandate.grantMandate(_params(), "");
    }

    function test_GrantRevertsNotPrincipalWhenNoSig() public {
        vm.prank(stranger);
        vm.expectRevert(AgentMandate.NotAuthorized.selector);
        mandate.grantMandate(_params(), "");
    }

    function test_GrantRevertsZeroProvider() public {
        IAgentMandate.GrantMandateParams memory params = _params();
        params.complianceProvider = address(0);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.ZeroComplianceProvider.selector);
        mandate.grantMandate(params, "");
    }

    function test_GrantRevertsZeroAction() public {
        IAgentMandate.GrantMandateParams memory params = _params();
        params.actions[0].action = bytes32(0);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.ZeroAction.selector);
        mandate.grantMandate(params, "");
    }

    function test_GrantRevertsWhenUsedAboveCap() public {
        IAgentMandate.GrantMandateParams memory params = _params();
        params.limits[0].cumulativeUsed = params.limits[0].maxCumulativeValue + 1;
        vm.prank(principal);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentMandate.CumulativeUsedAboveCap.selector, address(token), IAgentMandate.Direction.OUTFLOW
            )
        );
        mandate.grantMandate(params, "");
    }

    function test_RegrantAfterExpiry() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        IAgentMandate.GrantMandateParams memory params = _params();
        params.validUntil = uint48(block.timestamp + 100);
        vm.prank(principal);
        mandate.grantMandate(params, "");

        vm.warp(block.timestamp + 101);
        vm.prank(principal);
        mandate.grantMandate(_params(), "");
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
    }

    function test_RegrantAfterRevoke() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
        vm.prank(principal);
        mandate.grantMandate(_params(), "");
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
    }

    function test_RegrantClearsPriorActions() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, address(token), 0, "");

        IAgentMandate.GrantMandateParams memory params = _params();
        params.actions[0].action = OTHER_ACTION;
        vm.prank(principal);
        mandate.grantMandate(params, "");

        assertFalse(mandate.isActionEnabled(agent, principal, address(token), ACTION));
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.ACTION_NOT_ENABLED));
    }

    function test_ExtendByPrincipal() public {
        _grant();
        uint48 newUntil = uint48(block.timestamp + 10 days);
        vm.prank(principal);
        mandate.extendMandate(agent, principal, address(token), newUntil, 0, "");
        assertEq(mandate.getMandate(agent, principal, address(token)).validUntil, newUntil);
    }

    function test_ExtendByOperator() public {
        _grant();
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");
        uint48 newUntil = uint48(block.timestamp + 10 days);
        vm.prank(operator);
        mandate.extendMandate(agent, principal, address(token), newUntil, 0, "");
        assertEq(mandate.getMandate(agent, principal, address(token)).validUntil, newUntil);
    }

    function test_ExtendBySignature() public {
        _grant();
        uint48 newUntil = uint48(block.timestamp + 10 days);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            principalPk,
            keccak256(
                abi.encode(
                    EXTEND_TYPEHASH, agent, principal, address(token), newUntil, mandate.nonces(principal), deadline
                )
            )
        );
        vm.prank(relayer);
        mandate.extendMandate(agent, principal, address(token), newUntil, deadline, sig);
        assertEq(mandate.getMandate(agent, principal, address(token)).validUntil, newUntil);
    }

    function test_ExtendPreservesCumulativeUsed() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 500);
        vm.prank(principal);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        vm.prank(principal);
        mandate.extendMandate(agent, principal, address(token), uint48(block.timestamp + 10 days), 0, "");
        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, 500);
    }

    function test_ExtendRevertsAfterComplianceExpiry() public {
        vm.prank(complianceOwner);
        compliance.grantPrincipal(principal, IDREF, uint48(block.timestamp + 2 days));
        _grant();

        vm.prank(principal);
        vm.expectRevert(AgentMandate.InvalidExpiry.selector);
        mandate.extendMandate(agent, principal, address(token), uint48(block.timestamp + 5 days), 0, "");
    }

    function test_ExtendRevertsWhenPrincipalIneligible() public {
        _grant();
        vm.prank(complianceOwner);
        compliance.revokePrincipal(principal, IComplianceProvider.ReasonCode.AML_FLAG);

        vm.prank(principal);
        vm.expectRevert(AgentMandate.PrincipalNotEligible.selector);
        mandate.extendMandate(agent, principal, address(token), uint48(block.timestamp + 10 days), 0, "");
    }

    function test_ExtendRevertsInvalidExpiry() public {
        _grant();
        uint48 current = mandate.getMandate(agent, principal, address(token)).validUntil;
        vm.prank(principal);
        vm.expectRevert(AgentMandate.InvalidExpiry.selector);
        mandate.extendMandate(agent, principal, address(token), current, 0, "");
    }

    function test_ExtendRevertsWhenExpired() public {
        IAgentMandate.GrantMandateParams memory params = _params();
        params.validUntil = uint48(block.timestamp + 100);
        vm.prank(principal);
        mandate.grantMandate(params, "");

        vm.warp(block.timestamp + 101);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.NoActiveMandate.selector);
        mandate.extendMandate(agent, principal, address(token), uint48(block.timestamp + 10 days), 0, "");
    }

    function test_RevokeByPrincipal() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.REVOKED));
    }

    function test_RevokeByOperator() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");
        vm.prank(operator);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.REVOKED));
    }

    function test_RevokeBySignature() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            principalPk,
            keccak256(
                abi.encode(REVOKE_TYPEHASH, agent, principal, address(token), mandate.nonces(principal), deadline)
            )
        );
        vm.prank(relayer);
        mandate.revokeMandate(agent, principal, address(token), deadline, sig);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.REVOKED));
    }

    function test_RevokeRevertsNoActiveMandate() public {
        vm.prank(principal);
        vm.expectRevert(AgentMandate.NoActiveMandate.selector);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
    }

    function test_RevokeRevertsNotAuthorized() public {
        _grant();
        vm.prank(stranger);
        vm.expectRevert(AgentMandate.NotAuthorized.selector);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
    }

    function test_OperatorCanGrant() public {
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");
        vm.prank(operator);
        mandate.grantMandate(_params(), "");
        assertEq(mandate.getMandate(agent, principal, address(token)).principal, principal);
    }

    function test_GrantByOperatorSignature() public {
        (address signer, uint256 signerPk) = makeAddrAndKey("signer");
        IAgentMandate.GrantMandateParams memory params = _params();
        params.deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(signerPk, _grantStructHash(params, mandate.nonces(principal)));

        vm.prank(relayer);
        vm.expectRevert(AgentMandate.InvalidSignature.selector);
        mandate.grantMandate(params, sig);

        vm.prank(principal);
        mandate.setOperator(principal, signer, true, 0, "");
        vm.prank(relayer);
        mandate.grantMandate(params, sig);
        assertEq(mandate.getMandate(agent, principal, address(token)).principal, principal);
        assertEq(mandate.nonces(principal), 1);
    }

    function test_SetOperatorBySignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            principalPk,
            keccak256(abi.encode(SETOP_TYPEHASH, principal, operator, true, mandate.nonces(principal), deadline))
        );
        vm.prank(relayer);
        mandate.setOperator(principal, operator, true, deadline, sig);
        assertTrue(mandate.isOperator(principal, operator));
    }

    function test_OperatorCannotSetOperator() public {
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");
        vm.prank(operator);
        vm.expectRevert(AgentMandate.NotPrincipal.selector);
        mandate.setOperator(principal, stranger, true, 0, "");
    }

    function test_EnforcerCanOnlyRemoveOperator() public {
        vm.prank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");

        vm.prank(enforcer);
        vm.expectRevert(AgentMandate.NotPrincipal.selector);
        mandate.setOperator(principal, stranger, true, 0, "");

        vm.prank(admin);
        vm.expectRevert(AgentMandate.NotPrincipal.selector);
        mandate.setOperator(principal, operator, false, 0, "");

        vm.prank(enforcer);
        mandate.setOperator(principal, operator, false, 0, "");
        assertFalse(mandate.isOperator(principal, operator));
    }

    function test_SignatureExpired() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            principalPk,
            keccak256(abi.encode(SETOP_TYPEHASH, principal, operator, true, mandate.nonces(principal), deadline))
        );
        vm.warp(deadline + 1);
        vm.prank(relayer);
        vm.expectRevert(AgentMandate.SignatureExpired.selector);
        mandate.setOperator(principal, operator, true, deadline, sig);
    }

    function test_SignatureReplayRejected() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            principalPk,
            keccak256(abi.encode(SETOP_TYPEHASH, principal, operator, true, mandate.nonces(principal), deadline))
        );
        vm.prank(relayer);
        mandate.setOperator(principal, operator, true, deadline, sig);

        vm.prank(relayer);
        vm.expectRevert(AgentMandate.InvalidSignature.selector);
        mandate.setOperator(principal, operator, true, deadline, sig);
    }

    function test_CanExecuteNonexistentMandate() public view {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.NONEXISTENT));
    }

    function test_CanExecuteNotYetValid() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        IAgentMandate.GrantMandateParams memory params = _params();
        params.validFrom = uint48(block.timestamp + 1 hours);
        params.validUntil = uint48(block.timestamp + 2 hours);
        vm.prank(principal);
        mandate.grantMandate(params, "");
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);

        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.NOT_YET_VALID));
    }

    function test_CanExecuteOutsideWindow() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.warp(block.timestamp + 2 days);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.EXPIRED));
    }

    function test_CanExecuteActionNotEnabled() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), OTHER_ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.ACTION_NOT_ENABLED));
    }

    function test_Constraints() public {
        // transferFrom(from, to, value): to is recipient or operator, value is between 1 and 500, from is not stranger.
        IAgentMandate.GrantMandateParams memory params = _params();
        params.actions[0].constraints = new IAgentMandate.Constraint[](5);
        params.actions[0].constraints[0] =
            IAgentMandate.Constraint(1, IAgentMandate.Check.EQUALS, bytes32(uint256(uint160(recipient))));
        params.actions[0].constraints[1] =
            IAgentMandate.Constraint(1, IAgentMandate.Check.EQUALS, bytes32(uint256(uint160(operator))));
        params.actions[0].constraints[2] =
            IAgentMandate.Constraint(2, IAgentMandate.Check.AT_MOST, bytes32(uint256(500)));
        params.actions[0].constraints[3] =
            IAgentMandate.Constraint(2, IAgentMandate.Check.AT_LEAST, bytes32(uint256(1)));
        params.actions[0].constraints[4] =
            IAgentMandate.Constraint(0, IAgentMandate.Check.NOT_EQUALS, bytes32(uint256(uint160(stranger))));
        vm.prank(principal);
        mandate.grantMandate(params, "");
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](0);

        (bool ok,) = mandate.canExecute(
            agent,
            principal,
            address(token),
            ACTION,
            abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, 500),
            flows
        );
        assertTrue(ok);
        (ok,) = mandate.canExecute(
            agent,
            principal,
            address(token),
            ACTION,
            abi.encodeWithSelector(TRANSFER_FROM, principal, operator, 1),
            flows
        );
        assertTrue(ok);

        bytes[4] memory refused = [
            abi.encodeWithSelector(TRANSFER_FROM, principal, agent, 100),
            abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, 501),
            abi.encodeWithSelector(TRANSFER_FROM, principal, recipient, 0),
            abi.encodeWithSelector(TRANSFER_FROM, stranger, recipient, 100)
        ];
        for (uint256 index = 0; index < refused.length; index++) {
            (bool refusedOk, IAgentMandate.MandateReason reason) =
                mandate.canExecute(agent, principal, address(token), ACTION, refused[index], flows);
            assertFalse(refusedOk);
            assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.CONSTRAINT_FAILED));
        }
    }

    function test_CanExecuteNoLimit() public {
        _grant();
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        flows[0] = IAgentMandate.Flow(address(0xBEEF), IAgentMandate.Direction.OUTFLOW, 1);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.NO_LIMIT));
    }

    function test_CanExecuteOverTxCap() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 2000);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OVER_TX_CAP));
    }

    function test_CanExecuteOverCumulativeCap() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 1000);
        vm.prank(principal);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OVER_CUMULATIVE_CAP));
    }

    function test_NoLimitCapsAllowHugeAmount() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        IAgentMandate.GrantMandateParams memory params = _params();
        params.limits[0].maxTransactionValue = type(uint256).max;
        params.limits[0].maxCumulativeValue = type(uint256).max;
        vm.prank(principal);
        mandate.grantMandate(params, "");

        uint256 huge = type(uint256).max;
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, huge);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
        vm.prank(principal);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, huge);
    }

    function test_CanExecuteOtherAssetIsNonexistent() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(0xBEEF), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(0xBEEF), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.NONEXISTENT));
    }

    function test_LimitsCountPerAsset() public {
        uRWA20 tokenB = new uRWA20("Regulated B", "RWB", admin);
        IAgentMandate.GrantMandateParams memory params = _params();
        params.limits = new IAgentMandate.Limit[](2);
        params.limits[0] = IAgentMandate.Limit(address(token), IAgentMandate.Direction.OUTFLOW, 1000, 1500, 0);
        params.limits[1] = IAgentMandate.Limit(address(tokenB), IAgentMandate.Direction.OUTFLOW, 10, 15, 0);
        vm.prank(principal);
        mandate.grantMandate(params, "");

        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](2);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 700);
        flows[1] = IAgentMandate.Flow(address(tokenB), IAgentMandate.Direction.OUTFLOW, 8);
        vm.prank(principal);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);

        IAgentMandate.Limit[] memory limits = mandate.getLimits(agent, principal, address(token));
        assertEq(limits[0].cumulativeUsed, 700);
        assertEq(limits[1].cumulativeUsed, 8);

        flows[0].amount = 1;
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OVER_CUMULATIVE_CAP));
    }

    function test_MultiAssetMandatesAreIndependent() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        uRWA20 tokenB = new uRWA20("Regulated B", "RWB", admin);
        _grant();
        IAgentMandate.GrantMandateParams memory params = _params();
        params.target = address(tokenB);
        params.limits[0].asset = address(tokenB);
        vm.prank(principal);
        mandate.grantMandate(params, "");

        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 1000);
        vm.prank(principal);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);

        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, 1000);
        assertEq(mandate.getLimits(agent, principal, address(tokenB))[0].cumulativeUsed, 0);
        flows[0] = IAgentMandate.Flow(address(tokenB), IAgentMandate.Direction.OUTFLOW, 1000);
        (bool ok,) = mandate.canExecute(agent, principal, address(tokenB), ACTION, "", flows);
        assertTrue(ok);
    }

    function test_MultiAssetRevokeOneKeepsOther() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        uRWA20 tokenB = new uRWA20("Regulated B", "RWB", admin);
        _grant();
        IAgentMandate.GrantMandateParams memory params = _params();
        params.target = address(tokenB);
        params.limits[0].asset = address(tokenB);
        vm.prank(principal);
        mandate.grantMandate(params, "");

        vm.prank(principal);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);

        (, IAgentMandate.MandateReason reason) = mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.REVOKED));
        flows[0] = IAgentMandate.Flow(address(tokenB), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok,) = mandate.canExecute(agent, principal, address(tokenB), ACTION, "", flows);
        assertTrue(ok);
    }

    function test_RevertsRepeatedLimit() public {
        _grant();
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](2);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 600);
        flows[1] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 600);
        vm.prank(principal);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentMandate.DuplicateLimit.selector, address(token), IAgentMandate.Direction.OUTFLOW
            )
        );
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
    }

    function test_RepeatedFlowRevertsWithoutMandate() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](2);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 1);
        flows[1] = flows[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentMandate.DuplicateLimit.selector, address(token), IAgentMandate.Direction.OUTFLOW
            )
        );
        mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
    }

    function test_RecordByAsset() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(address(token));
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, 100);
    }

    function test_RecordByPrincipal() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(principal);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, 100);
    }

    function test_RecordByRecorderRole() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.startPrank(admin);
        mandate.grantRole(recorderRole, recorder);
        vm.stopPrank();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(recorder);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        assertEq(mandate.getLimits(agent, principal, address(token))[0].cumulativeUsed, 100);
    }

    function test_RecordRevertsUnauthorized() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(stranger);
        vm.expectRevert(AgentMandate.UnauthorizedRecorder.selector);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
    }

    function test_RecordRevertsAssetCallerForOtherAsset() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        uRWA20 tokenB = new uRWA20("Regulated B", "RWB", admin);
        _grant();
        IAgentMandate.GrantMandateParams memory params = _params();
        params.target = address(tokenB);
        params.limits[0].asset = address(tokenB);
        vm.prank(principal);
        mandate.grantMandate(params, "");

        flows[0] = IAgentMandate.Flow(address(tokenB), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(address(token));
        vm.expectRevert(AgentMandate.UnauthorizedRecorder.selector);
        mandate.recordExecution(agent, principal, address(tokenB), ACTION, "", flows);
    }

    function test_RecordRevertsActionNotEnabled() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(principal);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.ACTION_NOT_ENABLED
            )
        );
        mandate.recordExecution(agent, principal, address(token), OTHER_ACTION, "", flows);
    }

    function test_RecordRevertsOverTxCap() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 1001);
        vm.prank(principal);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_TX_CAP)
        );
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
    }

    function test_RecordRevertsOverCumulativeCap() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.startPrank(principal);
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 1000);
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.OVER_CUMULATIVE_CAP
            )
        );
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        vm.stopPrank();
    }

    function test_RecordRevertsWhenFrozen() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.startPrank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.stopPrank();
        vm.prank(enforcer);
        mandate.freezeAgent(agent);

        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(principal);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.AGENT_FROZEN)
        );
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
    }

    function test_RecordRevertsWhenRevoked() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.startPrank(principal);
        mandate.revokeMandate(agent, principal, address(token), 0, "");
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.REVOKED)
        );
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
        vm.stopPrank();
    }

    function test_FreezeByEnforcerBlocksAndUnfreeze() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.startPrank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.stopPrank();

        vm.prank(enforcer);
        mandate.freezeAgent(agent);
        assertTrue(mandate.isAgentFrozen(agent));
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.AGENT_FROZEN));

        vm.prank(enforcer);
        mandate.unfreezeAgent(agent);
        (ok, reason) = mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
    }

    function test_FreezeOnlyEnforcer() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, enforcerRole)
        );
        mandate.freezeAgent(agent);
    }

    function test_UnfreezeOnlyEnforcer() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, enforcerRole)
        );
        mandate.unfreezeAgent(agent);
    }

    function test_FreezePrincipalByEnforcerBlocksAndUnfreeze() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.prank(admin);
        mandate.grantRole(enforcerRole, enforcer);

        vm.prank(enforcer);
        mandate.freezePrincipal(principal);
        assertTrue(mandate.isPrincipalFrozen(principal));
        assertFalse(mandate.isAgentFrozen(agent));
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);

        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.PRINCIPAL_FROZEN));

        vm.prank(enforcer);
        mandate.unfreezePrincipal(principal);
        (ok, reason) = mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertTrue(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.OK));
    }

    function test_FreezePrincipalBlocksRecordExecution() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.prank(admin);
        mandate.grantRole(enforcerRole, enforcer);

        vm.prank(enforcer);
        mandate.freezePrincipal(principal);

        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);
        vm.prank(principal);
        vm.expectRevert(
            abi.encodeWithSelector(IAgentMandate.MandateBlocked.selector, IAgentMandate.MandateReason.PRINCIPAL_FROZEN)
        );
        mandate.recordExecution(agent, principal, address(token), ACTION, "", flows);
    }

    function test_FreezePrincipalCoversMandatesGrantedLater() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        vm.prank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.prank(enforcer);
        mandate.freezePrincipal(principal);

        _grant();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);

        (bool ok, IAgentMandate.MandateReason reason) =
            mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertFalse(ok);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.PRINCIPAL_FROZEN));
    }

    function test_AgentFreezeReportedBeforePrincipalFreeze() public {
        IAgentMandate.Flow[] memory flows = new IAgentMandate.Flow[](1);
        _grant();
        vm.startPrank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.stopPrank();

        vm.startPrank(enforcer);
        mandate.freezeAgent(agent);
        mandate.freezePrincipal(principal);
        vm.stopPrank();
        flows[0] = IAgentMandate.Flow(address(token), IAgentMandate.Direction.OUTFLOW, 100);

        (, IAgentMandate.MandateReason reason) = mandate.canExecute(agent, principal, address(token), ACTION, "", flows);
        assertEq(uint8(reason), uint8(IAgentMandate.MandateReason.AGENT_FROZEN));
    }

    function test_FreezePrincipalDoesNotRevoke() public {
        _grant();
        vm.prank(admin);
        mandate.grantRole(enforcerRole, enforcer);

        vm.prank(enforcer);
        mandate.freezePrincipal(principal);

        assertFalse(mandate.getMandate(agent, principal, address(token)).revoked);
    }

    function test_FreezePrincipalEmitsEvents() public {
        vm.prank(admin);
        mandate.grantRole(enforcerRole, enforcer);

        vm.expectEmit(true, true, false, false);
        emit IAgentMandate.PrincipalFrozen(principal, enforcer);
        vm.prank(enforcer);
        mandate.freezePrincipal(principal);

        vm.expectEmit(true, true, false, false);
        emit IAgentMandate.PrincipalUnfrozen(principal, enforcer);
        vm.prank(enforcer);
        mandate.unfreezePrincipal(principal);
    }

    function test_FreezePrincipalOnlyEnforcer() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, enforcerRole)
        );
        mandate.freezePrincipal(principal);
    }

    function test_UnfreezePrincipalOnlyEnforcer() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, enforcerRole)
        );
        mandate.unfreezePrincipal(principal);
    }
}
