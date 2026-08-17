// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {ComplianceProvider} from "../contracts/ComplianceProvider.sol";
import {IComplianceProvider} from "../contracts/interfaces/IComplianceProvider.sol";

contract ComplianceProviderTest is Test {
    ComplianceProvider provider;

    address complianceOwner = makeAddr("complianceOwner");
    address principal = makeAddr("principal");
    address stranger = makeAddr("stranger");

    bytes32 constant IDREF = keccak256("kyc-1");
    bytes32 constant OTHER_REF = keccak256("kyc-2");

    event PrincipalGranted(address indexed principal, bytes32 indexed identityRef);
    event PrincipalRevoked(
        address indexed principal, bytes32 indexed identityRef, IComplianceProvider.ReasonCode reason
    );

    function setUp() public {
        provider = new ComplianceProvider(complianceOwner);
    }

    function _check(bytes32 ref)
        internal
        view
        returns (bool eligible, IComplianceProvider.ReasonCode reason, uint48 expiresAt)
    {
        return provider.checkPrincipal(principal, ref);
    }

    function _reason(IComplianceProvider.ReasonCode r) internal pure returns (uint256) {
        return uint256(r);
    }

    function test_CheckUnknownPrincipal() public view {
        (bool eligible, IComplianceProvider.ReasonCode reason,) = _check(IDREF);
        assertFalse(eligible);
        assertEq(_reason(reason), _reason(IComplianceProvider.ReasonCode.IDENTITY_NOT_FOUND));
    }

    function test_CheckWrongIdentityRef() public {
        vm.prank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, 0);

        (bool eligible, IComplianceProvider.ReasonCode reason,) = _check(OTHER_REF);
        assertFalse(eligible);
        assertEq(_reason(reason), _reason(IComplianceProvider.ReasonCode.IDENTITY_NOT_FOUND));
    }

    function test_ExpiryBlocksAfterDeadline() public {
        uint48 expiry = uint48(block.timestamp + 100);
        vm.prank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, expiry);

        (bool okBefore,, uint48 e1) = _check(IDREF);
        assertTrue(okBefore);
        assertEq(e1, expiry);

        vm.warp(block.timestamp + 101);
        (bool okAfter, IComplianceProvider.ReasonCode reason, uint48 e2) = _check(IDREF);
        assertFalse(okAfter);
        assertEq(_reason(reason), _reason(IComplianceProvider.ReasonCode.KYC_EXPIRED));
        assertEq(e2, expiry);
    }

    function test_GrantMakesEligibleAndEmits() public {
        vm.expectEmit(true, true, false, true, address(provider));
        emit PrincipalGranted(principal, IDREF);
        vm.prank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, 0);

        (bool eligible, IComplianceProvider.ReasonCode reason, uint48 expiresAt) = _check(IDREF);
        assertTrue(eligible);
        assertEq(_reason(reason), _reason(IComplianceProvider.ReasonCode.COMPLIANT));
        assertEq(expiresAt, 0);
    }

    function test_GrantOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        provider.grantPrincipal(principal, IDREF, 0);
    }

    function test_GrantRevertsZeroIdentityRef() public {
        vm.prank(complianceOwner);
        vm.expectRevert(ComplianceProvider.ZeroIdentityRef.selector);
        provider.grantPrincipal(principal, bytes32(0), 0);
    }

    function test_NoExpiryNeverExpires() public {
        vm.prank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, 0);

        vm.warp(block.timestamp + 365 days);
        (bool eligible,,) = _check(IDREF);
        assertTrue(eligible);
    }

    function test_RegrantAfterRevoke() public {
        vm.startPrank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, 0);
        provider.revokePrincipal(principal, IComplianceProvider.ReasonCode.AML_FLAG);
        provider.grantPrincipal(principal, OTHER_REF, 0); // overwrites the revoked record
        vm.stopPrank();

        (bool eligible, IComplianceProvider.ReasonCode reason,) = _check(OTHER_REF);
        assertTrue(eligible);
        assertEq(_reason(reason), _reason(IComplianceProvider.ReasonCode.COMPLIANT));
    }

    function test_RevokeBlocksAndEmits() public {
        vm.prank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, 0);

        vm.expectEmit(true, true, false, true, address(provider));
        emit PrincipalRevoked(principal, IDREF, IComplianceProvider.ReasonCode.AML_FLAG);
        vm.prank(complianceOwner);
        provider.revokePrincipal(principal, IComplianceProvider.ReasonCode.AML_FLAG);

        (bool eligible, IComplianceProvider.ReasonCode reason,) = _check(IDREF);
        assertFalse(eligible);
        assertEq(_reason(reason), _reason(IComplianceProvider.ReasonCode.AML_FLAG));
    }

    function test_RevokeOnlyOwner() public {
        vm.prank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, 0);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        provider.revokePrincipal(principal, IComplianceProvider.ReasonCode.AML_FLAG);
    }

    function test_RevokeRevertsWhenAlreadyRevoked() public {
        vm.startPrank(complianceOwner);
        provider.grantPrincipal(principal, IDREF, 0);
        provider.revokePrincipal(principal, IComplianceProvider.ReasonCode.AML_FLAG);
        vm.expectRevert(abi.encodeWithSelector(ComplianceProvider.NotActive.selector, principal));
        provider.revokePrincipal(principal, IComplianceProvider.ReasonCode.OTHER);
        vm.stopPrank();
    }

    function test_RevokeRevertsWhenNeverGranted() public {
        vm.prank(complianceOwner);
        vm.expectRevert(abi.encodeWithSelector(ComplianceProvider.NotActive.selector, principal));
        provider.revokePrincipal(principal, IComplianceProvider.ReasonCode.AML_FLAG);
    }

    function test_SupportsInterface() public view {
        assertTrue(provider.supportsInterface(type(IComplianceProvider).interfaceId));
        assertTrue(provider.supportsInterface(type(IERC165).interfaceId));
        assertFalse(provider.supportsInterface(0xffffffff));
    }
}
