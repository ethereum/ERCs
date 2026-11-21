// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {PolicyEnforcedRegistry, IERC165} from "../src/peaa/PolicyEnforcedRegistry.sol";
import {IPolicyEnforcedAccount} from "../src/peaa/IPolicyEnforcedAccount.sol";

contract PolicyEnforcedRegistryTest is Test {
    PolicyEnforcedRegistry reg;
    address account = makeAddr("account");
    address other = makeAddr("other");
    address cosigner = makeAddr("cosigner");
    address publisher = makeAddr("publisher");
    address receipt = makeAddr("receipt");
    address attacker = makeAddr("attacker");
    bytes32 constant H1 = keccak256("policy v1");
    bytes32 constant H2 = keccak256("policy v2");
    bytes32 constant H3 = keccak256("policy v3");
    string constant SCHEMA = "https://palisec.tech/schemas/policy-1.2.json";

    function setUp() public {
        vm.warp(1_800_000_000);
        reg = new PolicyEnforcedRegistry();
        vm.prank(account);
        reg.declare(cosigner, publisher, receipt);
    }

    function _activate(address acct, bytes32 h, uint64 v) internal {
        vm.prank(publisher);
        reg.activate(acct, h, v, "", SCHEMA);
    }

    // ----- ERC-165 -----

    function test_supportsInterface() public view {
        assertTrue(reg.supportsInterface(type(IPolicyEnforcedAccount).interfaceId));
        assertTrue(reg.supportsInterface(type(IERC165).interfaceId));
        assertFalse(reg.supportsInterface(0xffffffff));
        assertFalse(reg.supportsInterface(0x12345678));
    }

    function test_interfaceIdIsStable() public pure {
        // Published in the ERC text and the client library; changes to the interface must change this.
        assertEq(type(IPolicyEnforcedAccount).interfaceId, bytes4(0xcc16d336));
    }

    // ----- declare -----

    function test_declare_setsSignersAndEmits() public {
        vm.expectEmit(true, false, false, true);
        emit IPolicyEnforcedAccount.SignersDeclared(other, cosigner, publisher, receipt);
        vm.prank(other);
        reg.declare(cosigner, publisher, receipt);
        IPolicyEnforcedAccount.Signers memory s = reg.policySigner(other);
        assertEq(s.policySigner, cosigner);
        assertEq(s.publisher, publisher);
        assertEq(s.receiptSigner, receipt);
        assertEq(s.since, block.timestamp);
    }

    function test_declare_requiresPublisherAndReceiptSigner() public {
        vm.prank(other);
        vm.expectRevert(PolicyEnforcedRegistry.ZeroSigner.selector);
        reg.declare(cosigner, address(0), receipt);
        vm.prank(other);
        vm.expectRevert(PolicyEnforcedRegistry.ZeroSigner.selector);
        reg.declare(cosigner, publisher, address(0));
    }

    function test_undeclaredAccountReadsZero() public view {
        IPolicyEnforcedAccount.Signers memory s = reg.policySigner(other);
        assertEq(s.policySigner, address(0));
        IPolicyEnforcedAccount.PolicyCommitment memory c = reg.policyOf(other);
        assertEq(c.policyHash, bytes32(0));
        (bool exists,) = reg.pendingPolicyOf(other);
        assertFalse(exists);
        assertFalse(reg.isStopped(other));
    }

    function test_rotation_signersAtHistory() public {
        uint64 t0 = uint64(block.timestamp);
        address receipt2 = makeAddr("receipt2");
        vm.warp(t0 + 100);
        vm.prank(account);
        reg.declare(cosigner, publisher, receipt2);
        assertEq(reg.signersAt(account, t0 + 50).receiptSigner, receipt);
        assertEq(reg.signersAt(account, t0 + 100).receiptSigner, receipt2);
        assertEq(reg.signersAt(account, t0 - 1).receiptSigner, address(0));
        assertEq(reg.policySigner(account).receiptSigner, receipt2);
    }

    function test_optOut_blocksPublisher() public {
        vm.prank(account);
        reg.declare(address(0), address(0), address(0));
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.activate(account, H1, 1, "", SCHEMA);
    }

    // ----- no write path can change another account's data -----

    function test_onlyPublisherWrites() public {
        vm.startPrank(attacker);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.activate(account, H1, 1, "", SCHEMA);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.setPending(account, H1, 1, uint64(block.timestamp + 60), "", SCHEMA);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.cancelPending(account, "x");
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.setStopped(account, true, "x");
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.setMandate(account, "x", bytes32(0));
        vm.stopPrank();
    }

    function test_publisherOfOneAccountCannotWriteAnother() public {
        address pub2 = makeAddr("pub2");
        vm.prank(other);
        reg.declare(cosigner, pub2, receipt);
        vm.prank(pub2);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.activate(account, H1, 1, "", SCHEMA);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.activate(other, H1, 1, "", SCHEMA);
    }

    function testFuzz_strangerCannotWrite(address stranger, bytes32 h, uint64 v) public {
        vm.assume(stranger != publisher);
        vm.prank(stranger);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.activate(account, h, v, "", SCHEMA);
    }

    function testFuzz_declareOnlyAffectsCaller(address caller) public {
        vm.assume(caller != account);
        vm.prank(caller);
        reg.declare(attacker, attacker, attacker);
        assertEq(reg.policySigner(account).publisher, publisher);
    }

    // ----- activation -----

    function test_activate_emitsAndReads() public {
        vm.expectEmit(true, true, false, true);
        emit IPolicyEnforcedAccount.PolicyActivated(account, H1, 1, uint64(block.timestamp), "https://x/p/1", SCHEMA);
        vm.prank(publisher);
        reg.activate(account, H1, 1, "https://x/p/1", SCHEMA);
        IPolicyEnforcedAccount.PolicyCommitment memory c = reg.policyOf(account);
        assertEq(c.policyHash, H1);
        assertEq(c.version, 1);
        assertEq(c.effectiveAt, block.timestamp);
        assertEq(c.policyURI, "https://x/p/1");
        assertEq(c.schemaURI, SCHEMA);
    }

    function test_activate_rejectsRollbackAndConflictingSameVersion() public {
        _activate(account, H2, 2);
        vm.startPrank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.StaleVersion.selector);
        reg.activate(account, H1, 1, "", SCHEMA);
        vm.expectRevert(PolicyEnforcedRegistry.StaleVersion.selector);
        reg.activate(account, H3, 2, "", SCHEMA);
        reg.activate(account, H2, 2, "", SCHEMA); // idempotent
        vm.stopPrank();
    }

    // ----- pending loosening -----

    function test_pending_thenEffectiveWithoutPublisher() public {
        _activate(account, H1, 1);
        uint64 eff = uint64(block.timestamp + 3600);
        vm.expectEmit(true, true, false, true);
        emit IPolicyEnforcedAccount.PolicyPending(account, H2, 2, eff, "", SCHEMA);
        vm.prank(publisher);
        reg.setPending(account, H2, 2, eff, "", SCHEMA);
        (bool exists, IPolicyEnforcedAccount.PolicyCommitment memory p) = reg.pendingPolicyOf(account);
        assertTrue(exists);
        assertEq(p.policyHash, H2);
        assertEq(reg.policyOf(account).policyHash, H1, "current rules keep deciding");
        vm.warp(eff);
        assertEq(reg.policyOf(account).policyHash, H2, "due pending decides");
        (exists,) = reg.pendingPolicyOf(account);
        assertFalse(exists);
        // publisher confirms later: same version, effectiveAt preserved
        vm.warp(eff + 500);
        _activate(account, H2, 2);
        assertEq(reg.policyOf(account).effectiveAt, eff);
    }

    function test_pending_mustBeInFutureAndNewer() public {
        _activate(account, H2, 2);
        vm.startPrank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NotInFuture.selector);
        reg.setPending(account, H3, 3, uint64(block.timestamp), "", SCHEMA);
        vm.expectRevert(PolicyEnforcedRegistry.StaleVersion.selector);
        reg.setPending(account, H3, 2, uint64(block.timestamp + 60), "", SCHEMA);
        vm.stopPrank();
    }

    function test_cancelPending() public {
        _activate(account, H1, 1);
        vm.prank(publisher);
        reg.setPending(account, H2, 2, uint64(block.timestamp + 3600), "", SCHEMA);
        vm.expectEmit(true, true, false, true);
        emit IPolicyEnforcedAccount.PolicyCancelled(account, H2, 2, "owner cancelled");
        vm.prank(publisher);
        reg.cancelPending(account, "owner cancelled");
        (bool exists,) = reg.pendingPolicyOf(account);
        assertFalse(exists);
        vm.warp(block.timestamp + 7200);
        assertEq(reg.policyOf(account).policyHash, H1);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NoPending.selector);
        reg.cancelPending(account, "again");
    }

    function test_cannotCancelAfterEffective() public {
        vm.prank(publisher);
        reg.setPending(account, H2, 2, uint64(block.timestamp + 60), "", SCHEMA);
        vm.warp(block.timestamp + 61);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NoPending.selector);
        reg.cancelPending(account, "late");
    }

    function test_tighteningSupersedesPending() public {
        _activate(account, H1, 1);
        vm.prank(publisher);
        reg.setPending(account, H2, 2, uint64(block.timestamp + 3600), "", SCHEMA);
        vm.expectEmit(true, true, false, true);
        emit IPolicyEnforcedAccount.PolicyCancelled(account, H2, 2, "superseded");
        _activate(account, H3, 3);
        (bool exists,) = reg.pendingPolicyOf(account);
        assertFalse(exists);
        vm.warp(block.timestamp + 7200);
        assertEq(reg.policyOf(account).policyHash, H3);
    }

    // ----- stop and mandate -----

    function test_stopAndLift() public {
        vm.expectEmit(true, false, false, true);
        emit IPolicyEnforcedAccount.EmergencyStop(account, "incident");
        vm.prank(publisher);
        reg.setStopped(account, true, "incident");
        assertTrue(reg.isStopped(account));
        vm.recordLogs();
        vm.prank(publisher);
        reg.setStopped(account, true, "again"); // no-op, no event
        assertEq(vm.getRecordedLogs().length, 0);
        vm.expectEmit(true, false, false, false);
        emit IPolicyEnforcedAccount.EmergencyStopLifted(account);
        vm.prank(publisher);
        reg.setStopped(account, false, "");
        assertFalse(reg.isStopped(account));
    }

    function test_mandate() public {
        bytes32 h = keccak256("mandate config");
        vm.expectEmit(true, false, false, true);
        emit IPolicyEnforcedAccount.MandateSet(account, "https://palisec.tech/m/palisec-demo", h);
        vm.prank(publisher);
        reg.setMandate(account, "https://palisec.tech/m/palisec-demo", h);
        (string memory uri, bytes32 got) = reg.mandateOf(account);
        assertEq(uri, "https://palisec.tech/m/palisec-demo");
        assertEq(got, h);
    }

    function test_holdsNoFunds() public {
        (bool ok,) = address(reg).call{value: 1}("");
        assertFalse(ok);
    }
}
