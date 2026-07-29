// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {AgentMandate} from "../contracts/AgentMandate.sol";
import {ComplianceProvider} from "../contracts/ComplianceProvider.sol";
import {IComplianceProvider} from "../contracts/interfaces/IComplianceProvider.sol";
import {IAgentMandate} from "../contracts/interfaces/IAgentMandate.sol";
import {uRWA20} from "../contracts/regulated-asset-mock/uRWA20.sol";

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
        "GrantMandate(address agent,uint48 validFrom,uint48 validUntil,address principal,address complianceProvider,bytes32 identityRef,address asset,uint256 maxTransactionValue,uint256 maxCumulativeValue,bytes32 metadata,bytes32[] actions,uint256 nonce,uint256 deadline)"
    );
    bytes32 constant REVOKE_TYPEHASH =
        keccak256("RevokeMandate(address agent,address principal,uint256 nonce,uint256 deadline)");
    bytes32 constant EXTEND_TYPEHASH =
        keccak256("ExtendMandate(address agent,address principal,uint48 newValidUntil,uint256 nonce,uint256 deadline)");
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

    function _params() internal view returns (IAgentMandate.GrantMandateParams memory p) {
        bytes32[] memory actions = new bytes32[](1);
        actions[0] = ACTION;
        p = IAgentMandate.GrantMandateParams({
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

    function _grantStructHash(IAgentMandate.GrantMandateParams memory p, uint256 nonce)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                GRANT_TYPEHASH,
                p.agent,
                p.validFrom,
                p.validUntil,
                p.principal,
                p.complianceProvider,
                p.identityRef,
                p.asset,
                p.maxTransactionValue,
                p.maxCumulativeValue,
                p.metadata,
                keccak256(abi.encodePacked(p.actions)),
                nonce,
                p.deadline
            )
        );
    }

    function test_AdminCannotAlsoBeEnforcer() public {
        vm.startPrank(admin);
        vm.expectRevert(AgentMandate.AdminEnforcerOverlap.selector);
        mandate.grantRole(enforcerRole, admin);
        vm.stopPrank();
    }

    function test_CanExecuteActionNotEnabled() public {
        _grant();
        assertFalse(mandate.canExecute(agent, principal, address(token), OTHER_ACTION, 100));
    }

    function test_CanExecuteNonexistentMandate() public view {
        assertFalse(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_CanExecuteOutsideWindow() public {
        _grant();
        vm.warp(block.timestamp + 2 days);
        assertFalse(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_CanExecuteWrongAsset() public {
        _grant();
        assertFalse(mandate.canExecute(agent, principal, address(0xBEEF), ACTION, 100));
    }

    function test_EnforcerCannotAlsoBeAdmin() public {
        vm.startPrank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.expectRevert(AgentMandate.AdminEnforcerOverlap.selector);
        mandate.grantRole(adminRole, enforcer);
        vm.stopPrank();
    }

    function test_ExtendByOperator() public {
        _grant();
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");
        uint48 newUntil = uint48(block.timestamp + 10 days);
        vm.prank(operator);
        mandate.extendMandate(agent, principal, newUntil, 0, "");
        assertEq(mandate.getMandate(agent, principal).validUntil, newUntil);
    }

    function test_ExtendByPrincipal() public {
        _grant();
        uint48 newUntil = uint48(block.timestamp + 10 days);
        vm.prank(principal);
        mandate.extendMandate(agent, principal, newUntil, 0, "");
        assertEq(mandate.getMandate(agent, principal).validUntil, newUntil);
    }

    function test_ExtendBySignature() public {
        _grant();
        uint48 newUntil = uint48(block.timestamp + 10 days);
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            principalPk,
            keccak256(abi.encode(EXTEND_TYPEHASH, agent, principal, newUntil, mandate.nonces(principal), deadline))
        );
        vm.prank(relayer);
        mandate.extendMandate(agent, principal, newUntil, deadline, sig);
        assertEq(mandate.getMandate(agent, principal).validUntil, newUntil);
    }

    function test_ExtendPreservesCumulativeUsed() public {
        _grant();
        vm.prank(principal);
        mandate.recordExecution(agent, principal, ACTION, 500);
        vm.prank(principal);
        mandate.extendMandate(agent, principal, uint48(block.timestamp + 10 days), 0, "");
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 500);
    }

    function test_ExtendRevertsInvalidExpiry() public {
        _grant();
        uint48 current = mandate.getMandate(agent, principal).validUntil;
        vm.prank(principal);
        vm.expectRevert(AgentMandate.InvalidExpiry.selector);
        mandate.extendMandate(agent, principal, current, 0, "");
    }

    function test_ExtendRevertsWhenExpired() public {
        IAgentMandate.GrantMandateParams memory p = _params();
        p.validUntil = uint48(block.timestamp + 100);
        vm.prank(principal);
        mandate.grantMandate(p, "");

        vm.warp(block.timestamp + 101);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.NoActiveMandate.selector);
        mandate.extendMandate(agent, principal, uint48(block.timestamp + 10 days), 0, "");
    }

    function test_FreezeByEnforcerBlocksAndUnfreeze() public {
        _grant();
        vm.startPrank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.stopPrank();

        vm.prank(enforcer);
        mandate.freezeAgent(agent);
        assertTrue(mandate.isFrozen(agent));
        assertFalse(mandate.canExecute(agent, principal, address(token), ACTION, 100));

        vm.prank(enforcer);
        mandate.unfreezeAgent(agent);
        assertTrue(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_FreezeOnlyEnforcer() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, enforcerRole)
        );
        mandate.freezeAgent(agent);
    }

    function test_GrantByContractWallet_EIP1271() public {
        (address walletOwner, uint256 walletOwnerPk) = makeAddrAndKey("walletOwner");
        MockWallet wallet = new MockWallet(walletOwner);

        vm.prank(complianceOwner);
        compliance.grantPrincipal(address(wallet), IDREF, 0);

        IAgentMandate.GrantMandateParams memory p = _params();
        p.principal = address(wallet);
        p.deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(walletOwnerPk, _grantStructHash(p, mandate.nonces(address(wallet))));

        vm.prank(relayer);
        mandate.grantMandate(p, sig);

        assertTrue(mandate.canExecute(agent, address(wallet), address(token), ACTION, 100));
    }

    function test_GrantBySignature() public {
        IAgentMandate.GrantMandateParams memory p = _params();
        p.deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(principalPk, _grantStructHash(p, mandate.nonces(principal)));

        vm.prank(relayer);
        mandate.grantMandate(p, sig);

        assertTrue(mandate.canExecute(agent, principal, address(token), ACTION, 100));
        assertEq(mandate.nonces(principal), 1);
    }

    function test_GrantDirectByPrincipal() public {
        _grant();
        assertEq(mandate.getMandate(agent, principal).principal, principal);
        assertTrue(mandate.isActionEnabled(agent, principal, ACTION));
        assertTrue(mandate.canExecute(agent, principal, address(token), ACTION, 1000));
    }

    function test_GrantRevertsAlreadyActive() public {
        _grant();
        vm.prank(principal);
        vm.expectRevert(AgentMandate.MandateAlreadyActive.selector);
        mandate.grantMandate(_params(), "");
    }

    function test_GrantRevertsBadSignature() public {
        (, uint256 wrongPk) = makeAddrAndKey("wrong");
        IAgentMandate.GrantMandateParams memory p = _params();
        p.deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(wrongPk, _grantStructHash(p, mandate.nonces(principal)));
        vm.prank(relayer);
        vm.expectRevert(AgentMandate.InvalidSignature.selector);
        mandate.grantMandate(p, sig);
    }

    function test_GrantRevertsInvalidExpiry() public {
        IAgentMandate.GrantMandateParams memory p = _params();
        p.validUntil = uint48(block.timestamp);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.InvalidExpiry.selector);
        mandate.grantMandate(p, "");
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
        vm.expectRevert(AgentMandate.NotPrincipal.selector);
        mandate.grantMandate(_params(), "");
    }

    function test_GrantRevertsZeroProvider() public {
        IAgentMandate.GrantMandateParams memory p = _params();
        p.complianceProvider = address(0);
        vm.prank(principal);
        vm.expectRevert(AgentMandate.ZeroComplianceProvider.selector);
        mandate.grantMandate(p, "");
    }

    function test_NoLimitCapsAllowHugeAmount() public {
        IAgentMandate.GrantMandateParams memory p = _params();
        p.maxTransactionValue = type(uint256).max;
        p.maxCumulativeValue = type(uint256).max;
        vm.prank(principal);
        mandate.grantMandate(p, "");

        uint256 huge = type(uint256).max;
        assertTrue(mandate.canExecute(agent, principal, address(token), ACTION, huge));
        vm.prank(principal);
        mandate.recordExecution(agent, principal, ACTION, huge);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, huge);
    }

    function test_OperatorCannotGrant() public {
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");
        vm.prank(operator);
        vm.expectRevert(AgentMandate.NotPrincipal.selector);
        mandate.grantMandate(_params(), "");
    }

    function test_RecordByAsset() public {
        _grant();
        vm.prank(address(token));
        mandate.recordExecution(agent, principal, ACTION, 100);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 100);
    }

    function test_RecordByPrincipal() public {
        _grant();
        vm.prank(principal);
        mandate.recordExecution(agent, principal, ACTION, 100);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 100);
    }

    function test_RecordByRecorderRole() public {
        _grant();
        vm.startPrank(admin);
        mandate.grantRole(recorderRole, recorder);
        vm.stopPrank();
        vm.prank(recorder);
        mandate.recordExecution(agent, principal, ACTION, 100);
        assertEq(mandate.getMandate(agent, principal).cumulativeUsed, 100);
    }

    function test_RecordRevertsActionNotEnabled() public {
        _grant();
        vm.prank(principal);
        vm.expectRevert(AgentMandate.NotExecutable.selector);
        mandate.recordExecution(agent, principal, OTHER_ACTION, 100);
    }

    function test_RecordRevertsOverCumulativeCap() public {
        _grant();
        vm.startPrank(principal);
        mandate.recordExecution(agent, principal, ACTION, 1000);
        vm.expectRevert(AgentMandate.ExceedsCumulativeCap.selector);
        mandate.recordExecution(agent, principal, ACTION, 1000);
        vm.stopPrank();
    }

    function test_RecordRevertsOverTxCap() public {
        _grant();
        vm.prank(principal);
        vm.expectRevert(AgentMandate.ExceedsTransactionCap.selector);
        mandate.recordExecution(agent, principal, ACTION, 1001);
    }

    function test_RecordRevertsUnauthorized() public {
        _grant();
        vm.prank(stranger);
        vm.expectRevert(AgentMandate.UnauthorizedRecorder.selector);
        mandate.recordExecution(agent, principal, ACTION, 100);
    }

    function test_RecordRevertsWhenFrozen() public {
        _grant();
        vm.startPrank(admin);
        mandate.grantRole(enforcerRole, enforcer);
        vm.stopPrank();
        vm.prank(enforcer);
        mandate.freezeAgent(agent);

        vm.prank(principal);
        vm.expectRevert(AgentMandate.NotExecutable.selector);
        mandate.recordExecution(agent, principal, ACTION, 100);
    }

    function test_RecordRevertsWhenRevoked() public {
        _grant();
        vm.startPrank(principal);
        mandate.revokeMandate(agent, principal, 0, "");
        vm.expectRevert(AgentMandate.NotExecutable.selector);
        mandate.recordExecution(agent, principal, ACTION, 100);
        vm.stopPrank();
    }

    function test_RegrantAfterExpiry() public {
        IAgentMandate.GrantMandateParams memory p = _params();
        p.validUntil = uint48(block.timestamp + 100);
        vm.prank(principal);
        mandate.grantMandate(p, "");

        vm.warp(block.timestamp + 101);
        vm.prank(principal);
        mandate.grantMandate(_params(), "");
        assertTrue(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_RegrantAfterRevoke() public {
        _grant();
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, 0, "");
        vm.prank(principal);
        mandate.grantMandate(_params(), "");
        assertTrue(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_RevokeByOperator() public {
        _grant();
        vm.prank(principal);
        mandate.setOperator(principal, operator, true, 0, "");
        vm.prank(operator);
        mandate.revokeMandate(agent, principal, 0, "");
        assertFalse(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_RevokeByPrincipal() public {
        _grant();
        vm.prank(principal);
        mandate.revokeMandate(agent, principal, 0, "");
        assertFalse(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_RevokeBySignature() public {
        _grant();
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _sign(
            principalPk, keccak256(abi.encode(REVOKE_TYPEHASH, agent, principal, mandate.nonces(principal), deadline))
        );
        vm.prank(relayer);
        mandate.revokeMandate(agent, principal, deadline, sig);
        assertFalse(mandate.canExecute(agent, principal, address(token), ACTION, 100));
    }

    function test_RevokeRevertsNoActiveMandate() public {
        vm.prank(principal);
        vm.expectRevert(AgentMandate.NoActiveMandate.selector);
        mandate.revokeMandate(agent, principal, 0, "");
    }

    function test_RevokeRevertsNotAuthorized() public {
        _grant();
        vm.prank(stranger);
        vm.expectRevert(AgentMandate.NotAuthorized.selector);
        mandate.revokeMandate(agent, principal, 0, "");
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

    function test_SupportsInterface() public view {
        assertTrue(mandate.supportsInterface(type(IAgentMandate).interfaceId));
        assertTrue(mandate.supportsInterface(type(IERC165).interfaceId));
        assertFalse(mandate.supportsInterface(0xffffffff));
    }

    function test_UnfreezeOnlyEnforcer() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, enforcerRole)
        );
        mandate.unfreezeAgent(agent);
    }
}
