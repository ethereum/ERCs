// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import {Test, Vm} from "forge-std/Test.sol";
import {PolicyEnforcedRegistry, IERC165} from "../src/peaa/PolicyEnforcedRegistry.sol";
import {IPolicyEnforcedAccount} from "../src/peaa/IPolicyEnforcedAccount.sol";
import {PolicyEnforcedRegistry as RegistryV1} from "../src/peaa/v1/PolicyEnforcedRegistry.sol";
import {IPolicyEnforcedAccount as IV1} from "../src/peaa/v1/IPolicyEnforcedAccount.sol";

contract PolicyEnforcedRegistryTest is Test {
    PolicyEnforcedRegistry reg;
    address account = makeAddr("account");
    address other = makeAddr("other");
    address cosigner = makeAddr("cosigner");
    address cosigner2 = makeAddr("cosigner2");
    address publisher = makeAddr("publisher");
    address publisher2 = makeAddr("publisher2");
    address receipt = makeAddr("receipt");
    address attacker = makeAddr("attacker");
    bytes32 constant H1 = keccak256("policy v1");
    bytes32 constant H2 = keccak256("policy v2");
    bytes32 constant H3 = keccak256("policy v3");
    string constant SCHEMA = "https://palisec.tech/schemas/palisec-policy.json";
    uint32 constant DELAY = 900; // 15 minutes
    uint64 t0 = 1_800_000_000;

    function setUp() public {
        vm.warp(t0);
        reg = new PolicyEnforcedRegistry();
        vm.prank(account);
        reg.declare(cosigner, publisher, receipt, DELAY, 1);
    }

    function _now() internal view returns (uint64) {
        return uint64(vm.getBlockTimestamp());
    }

    function _pending(bytes32 h, uint64 v, uint64 at) internal {
        vm.prank(publisher);
        reg.setPending(account, h, v, at, "", SCHEMA);
    }

    /// Publishes version `v` through the delay and confirms it.
    function _publish(bytes32 h, uint64 v) internal {
        uint64 at = _now() + DELAY;
        _pending(h, v, at);
        vm.warp(at);
        vm.prank(publisher);
        reg.activate(account, h, v, "", SCHEMA);
    }

    // ----- ERC-165 and declaration -----

    function test_supportsInterface() public view {
        assertTrue(reg.supportsInterface(type(IPolicyEnforcedAccount).interfaceId));
        assertTrue(reg.supportsInterface(type(IERC165).interfaceId));
        assertFalse(reg.supportsInterface(type(IV1).interfaceId), "v2 is a different interface");
        assertFalse(reg.supportsInterface(0xffffffff));
    }

    function test_firstDeclarationAppliesAtOnce() public view {
        IPolicyEnforcedAccount.Signers memory s = reg.policySigner(account);
        assertEq(s.policySigner, cosigner);
        assertEq(s.publisher, publisher);
        assertEq(s.receiptSigner, receipt);
        assertEq(s.since, t0);
        assertEq(s.minDelay, DELAY);
        assertEq(s.signerType, 1);
    }

    function test_declareRejectsBadInput() public {
        vm.startPrank(other);
        vm.expectRevert(PolicyEnforcedRegistry.ZeroSigner.selector);
        reg.declare(cosigner, address(0), receipt, DELAY, 1);
        vm.expectRevert(PolicyEnforcedRegistry.BadSignerType.selector);
        reg.declare(cosigner, publisher, receipt, DELAY, 0);
        vm.expectRevert(PolicyEnforcedRegistry.BadSignerType.selector);
        reg.declare(cosigner, publisher, receipt, DELAY, 5);
        vm.expectRevert(PolicyEnforcedRegistry.DelayTooLong.selector);
        reg.declare(cosigner, publisher, receipt, 30 days + 1, 1);
        vm.expectRevert(PolicyEnforcedRegistry.ZeroSigner.selector);
        reg.declare(address(0), publisher, address(0), 0, 0);
        vm.stopPrank();
    }

    // ----- S2: signer changes wait -----

    function test_S2_signerChangeWaitsMinDelay() public {
        uint64 start = _now();
        vm.prank(account);
        vm.expectEmit(true, false, false, true);
        emit IPolicyEnforcedAccount.SignersPending(account, cosigner2, publisher2, receipt, DELAY, 2, start + DELAY);
        reg.declare(cosigner2, publisher2, receipt, DELAY, 2);
        assertEq(reg.policySigner(account).policySigner, cosigner, "old set still in effect");
        (bool exists, IPolicyEnforcedAccount.Signers memory p) = reg.pendingSignersOf(account);
        assertTrue(exists);
        assertEq(p.policySigner, cosigner2);
        // The old publisher still governs until the change is effective; the new one cannot write yet.
        vm.prank(publisher2);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.setPending(account, H1, 1, start + DELAY, "", SCHEMA);
        vm.warp(start + DELAY);
        assertEq(reg.policySigner(account).policySigner, cosigner2);
        assertEq(reg.signersAt(account, start + DELAY - 1).policySigner, cosigner, "history follows time");
        (exists,) = reg.pendingSignersOf(account);
        assertFalse(exists);
    }

    function test_S2_v1SignerChangeIsImmediate() public {
        RegistryV1 v1 = new RegistryV1();
        vm.startPrank(account);
        v1.declare(cosigner, publisher, receipt);
        v1.declare(cosigner2, publisher2, receipt);
        vm.stopPrank();
        assertEq(v1.policySigner(account).policySigner, cosigner2, "v1: the change applies in the same block");
    }

    function test_S2_clearingAppliesAtOnce() public {
        vm.prank(account);
        reg.declare(address(0), address(0), address(0), 0, 0);
        assertEq(reg.policySigner(account).policySigner, address(0), "not enforced, so nobody is misled");
        // Re-declaring while nothing is enforced applies at once (nothing to loosen).
        vm.prank(account);
        reg.declare(cosigner2, publisher2, receipt, DELAY, 1);
        assertEq(reg.policySigner(account).policySigner, cosigner2);
    }

    function test_S2_loweringMinDelayWaitsTheCurrentDelay() public {
        uint64 start = _now();
        vm.prank(account);
        reg.declare(cosigner, publisher, receipt, 0, 1);
        assertEq(reg.policySigner(account).minDelay, DELAY);
        vm.warp(start + DELAY - 1);
        assertEq(reg.policySigner(account).minDelay, DELAY);
        vm.warp(start + DELAY);
        assertEq(reg.policySigner(account).minDelay, 0);
    }

    function test_S2_accountCancelsPendingSigners() public {
        vm.startPrank(account);
        reg.declare(cosigner2, publisher2, receipt, DELAY, 1);
        reg.cancelSigners();
        vm.expectRevert(PolicyEnforcedRegistry.NoPending.selector);
        reg.cancelSigners();
        vm.stopPrank();
        vm.warp(_now() + DELAY);
        assertEq(reg.policySigner(account).policySigner, cosigner);
    }

    function test_S2_newerSignerRequestReplacesPending() public {
        vm.startPrank(account);
        reg.declare(cosigner2, publisher2, receipt, DELAY, 1);
        vm.recordLogs();
        reg.declare(cosigner2, publisher, receipt, DELAY, 3);
        vm.stopPrank();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[0].topics[0], IPolicyEnforcedAccount.SignersCancelled.selector);
        vm.warp(_now() + DELAY);
        assertEq(reg.policySigner(account).signerType, 3);
    }

    function test_S2_clearingDropsAPendingChange() public {
        vm.startPrank(account);
        reg.declare(cosigner2, attacker, receipt, DELAY, 1);
        reg.declare(address(0), address(0), address(0), 0, 0);
        vm.stopPrank();
        vm.warp(_now() + DELAY);
        assertEq(reg.policySigner(account).publisher, address(0));
    }

    // ----- Z1/Z2/Z3: publisher changes always wait -----

    function test_Z1_publisherCannotActivateANewVersionAtOnce() public {
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NoPending.selector);
        reg.activate(account, H1, 1, "", SCHEMA);
    }

    function test_Z1_v1PublisherActivatesALooseningAtOnce() public {
        RegistryV1 v1 = new RegistryV1();
        vm.prank(account);
        v1.declare(cosigner, publisher, receipt);
        vm.prank(publisher);
        v1.activate(account, H1, 1, "", SCHEMA);
        assertEq(v1.policyOf(account).version, 1, "v1: decides from now, no delay");
    }

    function test_Z2_confirmingEarlyReverts() public {
        uint64 at = _now() + DELAY;
        _pending(H1, 1, at);
        vm.warp(at - 1);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NotDue.selector);
        reg.activate(account, H1, 1, "", SCHEMA);
        vm.warp(at);
        vm.prank(publisher);
        reg.activate(account, H1, 1, "", SCHEMA);
        IPolicyEnforcedAccount.PolicyCommitment memory c = reg.policyOf(account);
        assertEq(c.version, 1);
        assertEq(c.effectiveAt, at, "keeps its effectiveAt");
    }

    function test_Z2_v1ConfirmsAPendingChangeEarly() public {
        RegistryV1 v1 = new RegistryV1();
        vm.prank(account);
        v1.declare(cosigner, publisher, receipt);
        vm.startPrank(publisher);
        v1.setPending(account, H1, 1, uint64(_now() + 3600), "", SCHEMA);
        v1.activate(account, H1, 1, "", SCHEMA);
        vm.stopPrank();
        assertEq(v1.policyOf(account).version, 1, "v1: the pending change decides before its time");
    }

    function test_Z3_setPendingNeedsMinDelay() public {
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.TooSoon.selector);
        reg.setPending(account, H1, 1, _now() + DELAY - 1, "", SCHEMA);
        _pending(H1, 1, _now() + DELAY);
        assertEq(reg.policyOf(account).version, 0);
    }

    function test_Z3_zeroDelayStillNotInThePast() public {
        vm.prank(other);
        reg.declare(cosigner, publisher, receipt, 0, 1);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.TooSoon.selector);
        reg.setPending(other, H1, 1, _now(), "", SCHEMA);
        vm.prank(publisher);
        reg.setPending(other, H1, 1, _now() + 1, "", SCHEMA);
    }

    function test_policyFollowsTimeWithoutConfirmation() public {
        uint64 at = _now() + DELAY;
        _pending(H1, 1, at);
        assertEq(reg.policyOf(account).version, 0);
        (bool exists,) = reg.pendingPolicyOf(account);
        assertTrue(exists);
        vm.warp(at);
        assertEq(reg.policyOf(account).version, 1);
        (exists,) = reg.pendingPolicyOf(account);
        assertFalse(exists);
    }

    function test_dueUnconfirmedChangeIsNotLostByANewPending() public {
        uint64 at = _now() + DELAY;
        _pending(H1, 1, at);
        vm.warp(at + 10);
        _pending(H2, 2, _now() + DELAY);
        IPolicyEnforcedAccount.PolicyCommitment memory c = reg.policyOf(account);
        assertEq(c.version, 1, "the due change stays in effect");
        assertEq(c.policyHash, H1);
    }

    function test_dueUnconfirmedChangeIsLostOnV1() public {
        RegistryV1 v1 = new RegistryV1();
        vm.prank(account);
        v1.declare(cosigner, publisher, receipt);
        vm.prank(publisher);
        v1.setPending(account, H1, 1, uint64(_now() + 100), "", SCHEMA);
        vm.warp(_now() + 200);
        assertEq(v1.policyOf(account).version, 1);
        vm.prank(publisher);
        v1.setPending(account, H2, 2, uint64(_now() + 100), "", SCHEMA);
        assertEq(v1.policyOf(account).version, 0, "v1: the due change disappears");
    }

    function test_staleVersionsRejected() public {
        _publish(H1, 2);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.StaleVersion.selector);
        reg.setPending(account, H2, 2, _now() + DELAY, "", SCHEMA);
        vm.prank(account);
        vm.expectRevert(PolicyEnforcedRegistry.StaleVersion.selector);
        reg.activate(account, H2, 1, "", SCHEMA);
        vm.prank(account);
        vm.expectRevert(PolicyEnforcedRegistry.StaleVersion.selector);
        reg.activate(account, H2, 2, "", SCHEMA);
    }

    function test_confirmIsIdempotent() public {
        _publish(H1, 1);
        vm.recordLogs();
        vm.prank(publisher);
        reg.activate(account, H1, 1, "", SCHEMA);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    // ----- the account itself -----

    function test_accountActivatesAtOnce() public {
        vm.prank(account);
        reg.activate(account, H1, 1, "", SCHEMA);
        assertEq(reg.policyOf(account).version, 1);
        assertEq(reg.policyOf(account).effectiveAt, _now());
    }

    function test_accountActivationSupersedesPendingWithCancelEvent() public {
        _pending(H1, 1, _now() + DELAY);
        vm.recordLogs();
        vm.prank(account);
        reg.activate(account, H2, 2, "", SCHEMA);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[0].topics[0], IPolicyEnforcedAccount.PolicyCancelled.selector);
        assertEq(logs[1].topics[0], IPolicyEnforcedAccount.PolicyActivated.selector);
        (bool exists,) = reg.pendingPolicyOf(account);
        assertFalse(exists);
    }

    function test_accountActivationKeepsANewerPending() public {
        _pending(H3, 3, _now() + DELAY);
        vm.prank(account);
        reg.activate(account, H1, 1, "", SCHEMA);
        (bool exists, IPolicyEnforcedAccount.PolicyCommitment memory p) = reg.pendingPolicyOf(account);
        assertTrue(exists);
        assertEq(p.version, 3);
    }

    // ----- every removal of a pending entry emits PolicyCancelled -----

    function test_replacedPendingEmitsCancelled() public {
        _pending(H1, 1, _now() + DELAY);
        vm.expectEmit(true, true, false, true);
        emit IPolicyEnforcedAccount.PolicyCancelled(account, H1, 1, "superseded");
        _pending(H2, 2, _now() + DELAY);
    }

    function test_cancelPendingByPublisherOrAccount() public {
        _pending(H1, 1, _now() + DELAY);
        vm.expectEmit(true, true, false, true);
        emit IPolicyEnforcedAccount.PolicyCancelled(account, H1, 1, "owner");
        vm.prank(account);
        reg.cancelPending(account, "owner");
        _pending(H2, 2, _now() + DELAY);
        vm.prank(publisher);
        reg.cancelPending(account, "publisher");
        vm.prank(attacker);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisherOrAccount.selector);
        reg.cancelPending(account, "x");
    }

    function test_cannotCancelOnceEffective() public {
        uint64 at = _now() + DELAY;
        _pending(H1, 1, at);
        vm.warp(at);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NoPending.selector);
        reg.cancelPending(account, "late");
        assertEq(reg.policyOf(account).version, 1);
    }

    // ----- emergency stop -----

    function test_stopByPublisherOrAccount() public {
        vm.prank(account);
        reg.setStopped(account, true, "key leaked");
        assertTrue(reg.isStopped(account));
        vm.prank(publisher);
        reg.setStopped(account, false, "");
        assertFalse(reg.isStopped(account));
        vm.prank(publisher);
        reg.setStopped(account, true, "paused");
        vm.prank(account);
        reg.setStopped(account, false, "");
        assertFalse(reg.isStopped(account));
        vm.prank(attacker);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisherOrAccount.selector);
        reg.setStopped(account, true, "x");
    }

    function test_accountCannotBeStoppedByTheIncomingPublisherEarly() public {
        vm.prank(account);
        reg.declare(cosigner2, publisher2, receipt, DELAY, 1);
        vm.prank(publisher2);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisherOrAccount.selector);
        reg.setStopped(account, true, "x");
    }

    // ----- isolation -----

    function test_nobodyWritesAnotherAccount() public {
        vm.startPrank(attacker);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisherOrAccount.selector);
        reg.activate(account, H1, 1, "", SCHEMA);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.setPending(account, H1, 1, _now() + DELAY, "", SCHEMA);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.setMandate(account, "https://x", bytes32(0));
        vm.stopPrank();
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisherOrAccount.selector);
        reg.activate(other, H1, 1, "", SCHEMA);
    }

    function test_clearedAccountHasNoPublisher() public {
        vm.prank(account);
        reg.declare(address(0), address(0), address(0), 0, 0);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NotPublisher.selector);
        reg.setPending(account, H1, 1, _now() + 1, "", SCHEMA);
    }

    function test_mandate() public {
        vm.prank(publisher);
        reg.setMandate(account, "https://palisec.tech/m/x", H3);
        (string memory uri, bytes32 h) = reg.mandateOf(account);
        assertEq(uri, "https://palisec.tech/m/x");
        assertEq(h, H3);
    }

    // ----- fuzz -----

    function testFuzz_publisherNeverDecidesBeforeMinDelay(uint32 delay, uint64 offset, uint64 v) public {
        delay = uint32(bound(delay, 0, 30 days));
        v = uint64(bound(v, 1, type(uint64).max));
        vm.prank(other);
        reg.declare(cosigner, publisher, receipt, delay, 1);
        offset = uint64(bound(offset, 0, uint64(delay) + 10));
        uint64 at = _now() + offset;
        vm.prank(publisher);
        if (offset == 0 || offset < delay) {
            vm.expectRevert(PolicyEnforcedRegistry.TooSoon.selector);
            reg.setPending(other, H1, v, at, "", SCHEMA);
            return;
        }
        reg.setPending(other, H1, v, at, "", SCHEMA);
        vm.warp(at - 1);
        assertEq(reg.policyOf(other).version, 0);
        vm.prank(publisher);
        vm.expectRevert(PolicyEnforcedRegistry.NotDue.selector);
        reg.activate(other, H1, v, "", SCHEMA);
        vm.warp(at);
        assertEq(reg.policyOf(other).version, v);
    }

    function testFuzz_signerChangeNeverEarly(uint32 delay, uint32 wait) public {
        delay = uint32(bound(delay, 1, 30 days));
        vm.prank(other);
        reg.declare(cosigner, publisher, receipt, delay, 1);
        uint64 start = _now();
        vm.prank(other);
        reg.declare(cosigner2, attacker, receipt, 0, 1);
        wait = uint32(bound(wait, 0, uint64(delay) * 2));
        vm.warp(start + wait);
        assertEq(reg.policySigner(other).publisher, wait < delay ? publisher : attacker);
    }
}
