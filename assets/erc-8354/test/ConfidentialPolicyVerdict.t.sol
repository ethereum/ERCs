// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ConfidentialPolicyVerdict} from "../src/ConfidentialPolicyVerdict.sol";
import {PolicyDomainRegistry} from "../src/PolicyDomainRegistry.sol";
import {IConfidentialPolicyVerdict, Verdict, PolicyKind} from "../src/IConfidentialPolicyVerdict.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";
import {GuardedExecutor} from "../src/GuardedExecutor.sol";
import {PolicyAttestation, VerdictAttestation} from "../src/IPolicyAttestation.sol";
import {MockValidationRegistry} from "../src/mocks/MockValidationRegistry.sol";

/// @notice Minimal call target for GuardedExecutor tests.
contract Sink {
    uint256 public pings;

    function ping() external {
        pings++;
    }
}

/// @notice The Test Cases from the ERC spec, as an executable Foundry suite.
contract CAPVTest is Test {
    PolicyDomainRegistry registry;
    ConfidentialPolicyVerdict guard;
    MockVerifier verifier;

    bytes32 constant DOMAIN = keccak256("acme-compliance");
    bytes32 constant ROOT = keccak256("root-v1");
    bytes32 constant PROGRAM = keccak256("interpreter-vkey");
    address constant EXECUTOR = address(0xE0);

    function setUp() public {
        vm.warp(1_700_000_000);
        registry = new PolicyDomainRegistry();
        verifier = new MockVerifier();
        guard = new ConfidentialPolicyVerdict(registry);
        registry.registerDomain(DOMAIN, address(0xA11CE), address(verifier), PROGRAM, 1 hours);
        registry.updateRoot(DOMAIN, ROOT);
    }

    function _verdict() internal view returns (Verdict memory v) {
        v = Verdict({
            agentId: 1,
            domainId: DOMAIN,
            policyRoot: ROOT,
            actionCommitment: keccak256("action"),
            executor: EXECUTOR,
            expiry: uint64(block.timestamp + 1 hours),
            nullifier: keccak256("nf-1"),
            decision: 1,
            policyKind: PolicyKind.ALLOWED
        });
    }

    // 1. Happy path
    function test_HappyPath() public {
        Verdict memory v = _verdict();
        vm.prank(EXECUTOR);
        guard.consume(v, "proof");
        assertTrue(guard.isConsumed(DOMAIN, v.nullifier));
    }

    // 2. Replay
    function test_Replay() public {
        Verdict memory v = _verdict();
        vm.startPrank(EXECUTOR);
        guard.consume(v, "proof");
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.VerdictReplayed.selector, v.nullifier));
        guard.consume(v, "proof");
        vm.stopPrank();
    }

    // 3. Expiry
    function test_Expired() public {
        Verdict memory v = _verdict();
        vm.warp(v.expiry); // block.timestamp >= expiry
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.VerdictExpired.selector, v.expiry));
        guard.consume(v, "proof");
    }

    // 4. Executor mismatch
    function test_ExecutorMismatch() public {
        Verdict memory v = _verdict();
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(IConfidentialPolicyVerdict.ExecutorMismatch.selector, EXECUTOR, address(0xBAD))
        );
        guard.consume(v, "proof");
    }

    // 5. DENY not consumable
    function test_DenyNotConsumable() public {
        Verdict memory v = _verdict();
        v.decision = 0;
        v.policyKind = PolicyKind.DENIED; // a well-formed refusal, not a malformed envelope
        vm.prank(EXECUTOR);
        vm.expectRevert(IConfidentialPolicyVerdict.VerdictDenied.selector);
        guard.consume(v, "proof");
    }

    // 5b. A verdict whose decision and kind disagree is refused before anything else is read.
    // Flipping `decision` alone used to produce a consumable-looking envelope; the kind is what
    // stops a refusal from being re-labelled, so the two MUST agree.
    function test_DecisionKindMismatchRefused() public {
        Verdict memory v = _verdict(); // decision 1, kind ALLOWED
        v.decision = 0; // claims a refusal while still carrying the ALLOWED kind
        vm.prank(EXECUTOR);
        vm.expectRevert(
            abi.encodeWithSelector(IConfidentialPolicyVerdict.VerdictKindMismatch.selector, uint8(0), PolicyKind.ALLOWED)
        );
        guard.consume(v, "proof");
    }

    // 5c. The mirror: an ALLOW that carries a refusal kind is equally malformed.
    function test_AllowCarryingRefusalKindRefused() public {
        Verdict memory v = _verdict();
        v.policyKind = PolicyKind.NOT_PERMITTED;
        vm.prank(EXECUTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfidentialPolicyVerdict.VerdictKindMismatch.selector, uint8(1), PolicyKind.NOT_PERMITTED
            )
        );
        guard.consume(v, "proof");
    }

    // 8. Stale-root grace, then rejection past maxRootAge
    function test_StaleRootGraceThenReject() public {
        Verdict memory v = _verdict(); // against ROOT
        registry.updateRoot(DOMAIN, keccak256("root-v2")); // ROOT becomes previous
        vm.prank(EXECUTOR);
        guard.consume(v, "proof"); // within grace → ok

        vm.warp(block.timestamp + 2 hours); // past maxRootAge
        Verdict memory v2 = _verdict(); // built after warp → fresh expiry, still points at old ROOT
        v2.nullifier = keccak256("nf-2");
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.PolicyRootRejected.selector, ROOT));
        guard.consume(v2, "proof");
    }

    // 9. Revocation is immediate, no grace
    function test_RevocationImmediate() public {
        registry.revokeDomain(DOMAIN);
        Verdict memory v = _verdict();
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.DomainInactive.selector, DOMAIN));
        guard.consume(v, "proof");
    }

    // 10. Malformed proof → verify returns false (no revert)
    function test_VerifyMalformedReturnsFalse() public {
        verifier.setRevert(true);
        Verdict memory v = _verdict();
        assertFalse(guard.verify(v, "garbage"));
    }

    // Invalid proof → consume reverts InvalidProof
    function test_InvalidProofReverts() public {
        verifier.setResult(false);
        Verdict memory v = _verdict();
        vm.prank(EXECUTOR);
        vm.expectRevert(IConfidentialPolicyVerdict.InvalidProof.selector);
        guard.consume(v, "proof");
    }

    // verify() returns true on a clean verdict
    function test_VerifyHappy() public view {
        assertTrue(guard.verify(_verdict(), "proof"));
    }

    // --- Signature-relay path (Zidan resolution: cryptographic executor binding) ---

    // 11. Relayer consumes on behalf of an EOA executor with a valid EIP-712 signature
    function test_RelayedConsumeWithSignature() public {
        uint256 pk = 0xA11CE;
        address exec = vm.addr(pk);
        Verdict memory v = _verdict();
        v.executor = exec;

        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(pk, guard.verdictDigest(v));
        bytes memory sig = abi.encodePacked(sr, ss, sv);

        vm.prank(address(0xBEEF)); // relayer, not the executor
        guard.consume(v, "proof", sig);
        assertTrue(guard.isConsumed(DOMAIN, v.nullifier));
    }

    // 12. Wrong signer → ExecutorAuthInvalid
    function test_RelayedConsumeBadSignature() public {
        uint256 pk = 0xA11CE;
        Verdict memory v = _verdict();
        v.executor = vm.addr(pk);

        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(uint256(0xB0B), guard.verdictDigest(v)); // wrong key
        bytes memory sig = abi.encodePacked(sr, ss, sv);

        vm.prank(address(0xBEEF));
        vm.expectRevert(IConfidentialPolicyVerdict.ExecutorAuthInvalid.selector);
        guard.consume(v, "proof", sig);
    }

    // 13. Relayer with no signature → ExecutorMismatch (direct-path error preserved)
    function test_RelayNoAuthReverts() public {
        Verdict memory v = _verdict(); // executor == EXECUTOR
        vm.prank(address(0xBEEF));
        vm.expectRevert(
            abi.encodeWithSelector(IConfidentialPolicyVerdict.ExecutorMismatch.selector, EXECUTOR, address(0xBEEF))
        );
        guard.consume(v, "proof", "");
    }

    // --- Canonical action-commitment binding through a guarded contract ---

    // 14. GuardedExecutor recomputes the canonical commitment, consumes (direct), executes
    function test_GuardedExecutorCanonicalCommitment() public {
        GuardedExecutor gx = new GuardedExecutor(guard, DOMAIN);
        Sink sink = new Sink();
        bytes memory cd = abi.encodeWithSignature("ping()");

        Verdict memory v = _verdict();
        v.executor = address(gx); // consumes on its own behalf
        v.actionCommitment = gx.actionCommitmentOf(v.agentId, address(sink), 0, cd);

        gx.execute(v, "proof", "", address(sink), 0, cd);
        assertEq(sink.pings(), 1);
        assertTrue(guard.isConsumed(DOMAIN, v.nullifier));
    }

    // 15. Full resolved design: EOA executor signs, GuardedExecutor relays it
    function test_GuardedExecutorRelayedByEOA() public {
        GuardedExecutor gx = new GuardedExecutor(guard, DOMAIN);
        Sink sink = new Sink();
        bytes memory cd = abi.encodeWithSignature("ping()");

        uint256 pk = 0xA11CE;
        Verdict memory v = _verdict();
        v.executor = vm.addr(pk); // the end user
        v.actionCommitment = gx.actionCommitmentOf(v.agentId, address(sink), 0, cd);

        (uint8 sv, bytes32 sr, bytes32 ss) = vm.sign(pk, guard.verdictDigest(v));
        bytes memory sig = abi.encodePacked(sr, ss, sv);

        gx.execute(v, "proof", sig, address(sink), 0, cd);
        assertEq(sink.pings(), 1);
        assertTrue(guard.isConsumed(DOMAIN, v.nullifier));
    }

    // 16. Wrong action → canonical commitment mismatch, nothing consumed
    function test_GuardedExecutorCommitmentMismatch() public {
        GuardedExecutor gx = new GuardedExecutor(guard, DOMAIN);
        Sink sink = new Sink();
        bytes memory cd = abi.encodeWithSignature("ping()");

        Verdict memory v = _verdict();
        v.executor = address(gx);
        v.actionCommitment = bytes32(uint256(1)); // wrong
        bytes32 expected = gx.actionCommitmentOf(v.agentId, address(sink), 0, cd);

        vm.expectRevert(
            abi.encodeWithSelector(GuardedExecutor.ActionCommitmentMismatch.selector, expected, v.actionCommitment)
        );
        gx.execute(v, "proof", "", address(sink), 0, cd);
    }

    // --- ERC-165 ---

    // 17. supportsInterface true for the standard + IERC165, false otherwise
    function test_SupportsInterface() public view {
        assertTrue(guard.supportsInterface(type(IConfidentialPolicyVerdict).interfaceId), "own");
        assertTrue(guard.supportsInterface(type(IERC165).interfaceId), "erc165");
        assertFalse(guard.supportsInterface(0xffffffff), "0xffffffff must be false");
        assertFalse(guard.supportsInterface(0xdeadbeef), "random");
    }

    // Emit the canonical interfaceId (run with -vv) so it can be recorded in the docs/spec.
    function test_LogInterfaceId() public pure {
        console2.logBytes4(type(IConfidentialPolicyVerdict).interfaceId);
    }

    // --- ERC-8004 Validation Registry handoff (attestation schema) ---

    // 18. A consumed verdict produces a well-formed attestation: artifactHash == actionCommitment,
    //     mechanism tagged as zk-secret-policy, written to the (mock) 8004 Validation Registry.
    function test_VerdictAttestationHandoff() public {
        Verdict memory v = _verdict();
        vm.prank(EXECUTOR);
        guard.consume(v, "proof");

        // A guarded contract / adapter builds the canonical attestation and writes it to ERC-8004.
        VerdictAttestation memory att = PolicyAttestation.attestationFor(v);
        MockValidationRegistry vr = new MockValidationRegistry();
        vr.recordVerdict(att);

        VerdictAttestation memory got = vr.get(v.agentId, v.nullifier);
        assertEq(got.artifactHash, v.actionCommitment, "artifactHash must be the action commitment");
        assertEq(got.mechanism, keccak256("zk-secret-policy"), "mechanism must be tagged");
        assertEq(got.policyRoot, v.policyRoot);
        assertEq(uint256(got.decision), 1);
        assertEq(got.agentId, v.agentId);
    }

    // 19. Malformed proof reaching consume reverts with InvalidProof, matching what the
    // ordered check names, rather than propagating the verifier's own error.
    function test_ConsumeMalformedProofRevertsInvalidProof() public {
        verifier.setRevert(true);
        Verdict memory v = _verdict();
        vm.prank(EXECUTOR);
        vm.expectRevert(IConfidentialPolicyVerdict.InvalidProof.selector);
        guard.consume(v, "garbage");
    }

    // 20. Well-formedness is checked before anything that could mask it. An inactive domain
    // would otherwise hide a decision/policyKind disagreement behind DomainInactive.
    function test_KindMismatchBeatsInactiveDomain() public {
        registry.revokeDomain(DOMAIN);
        Verdict memory v = _verdict();
        v.policyKind = PolicyKind.NOT_PERMITTED;
        vm.prank(EXECUTOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                IConfidentialPolicyVerdict.VerdictKindMismatch.selector, uint8(1), PolicyKind.NOT_PERMITTED
            )
        );
        guard.consume(v, "proof");
    }
}
