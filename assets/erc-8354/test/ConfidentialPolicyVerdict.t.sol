// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ConfidentialPolicyVerdict} from "../src/ConfidentialPolicyVerdict.sol";
import {PolicyDomainRegistry} from "../src/PolicyDomainRegistry.sol";
import {IConfidentialPolicyVerdict, Verdict, PolicyKind} from "../src/IConfidentialPolicyVerdict.sol";
import {PolicyAction, PolicyActionLib} from "../src/PolicyAction.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";
import {GuardedExecutor} from "../src/GuardedExecutor.sol";
import {PolicyAttestation, VerdictAttestation} from "../src/IPolicyAttestation.sol";
import {MockValidationRegistry} from "../src/mocks/MockValidationRegistry.sol";
import {MockIdentityRegistry} from "../src/mocks/MockIdentityRegistry.sol";

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

    // 8b. Grace is generation-agnostic. Two rotations inside maxRootAge must not drop the
    // oldest root: the spec says a root is acceptable if it is current or superseded less
    // than maxRootAge ago, and says nothing about how many rotations have happened since.
    // Each retained root is measured against its OWN supersession time, not the current
    // root's, so ROOT and root-v2 fall out of the window at different moments.
    function test_TwoRapidRotationsKeepEveryRootInsideItsOwnWindow() public {
        uint256 t0 = block.timestamp; // ROOT became current here, maxRootAge is 1 hour

        vm.warp(t0 + 10 minutes);
        registry.updateRoot(DOMAIN, keccak256("root-v2")); // ROOT superseded at t0 + 10m
        vm.warp(t0 + 20 minutes);
        registry.updateRoot(DOMAIN, keccak256("root-v3")); // root-v2 superseded at t0 + 20m

        // ROOT was superseded 10 minutes ago. It is two generations back, but still inside
        // its own grace window, so it is still acceptable.
        assertTrue(registry.isRootAcceptable(DOMAIN, ROOT), "ROOT is inside its own maxRootAge");
        assertTrue(registry.isRootAcceptable(DOMAIN, keccak256("root-v2")), "root-v2 is inside its own window");

        // And it is acceptable end to end, through the guard.
        Verdict memory v = _verdict(); // built after the warp, so expiry is fresh; still points at ROOT
        vm.prank(EXECUTOR);
        guard.consume(v, "proof");
        assertTrue(guard.isConsumed(DOMAIN, v.nullifier));

        // One second past ROOT's own window, ROOT is rejected while root-v2 — superseded
        // 10 minutes later — is still inside its own.
        vm.warp(t0 + 10 minutes + 1 hours);
        assertFalse(registry.isRootAcceptable(DOMAIN, ROOT), "ROOT is past its own maxRootAge");
        assertTrue(registry.isRootAcceptable(DOMAIN, keccak256("root-v2")), "root-v2 has 10 more minutes");

        Verdict memory v2 = _verdict();
        v2.nullifier = keccak256("nf-2");
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.PolicyRootRejected.selector, ROOT));
        guard.consume(v2, "proof");
    }

    // 8c. Retained history is bounded at eight superseded generations, so the grace rule is
    // approximated from below: a domain that rotates more often than that inside one window
    // loses its oldest roots early. They are rejected sooner than maxRootAge, never later,
    // so the overflow fails closed.
    function test_RotationsBeyondRetainedHistoryFailClosed() public {
        for (uint256 i = 2; i <= 10; ++i) {
            vm.warp(block.timestamp + 1 minutes);
            registry.updateRoot(DOMAIN, keccak256(abi.encodePacked("root-v", i))); // 9 supersessions
        }

        // ROOT stopped being current nine minutes ago, well inside its one-hour window, but it
        // is nine generations back and only eight are retained.
        assertFalse(registry.isRootAcceptable(DOMAIN, ROOT), "the oldest generation ages out early");
        assertTrue(
            registry.isRootAcceptable(DOMAIN, keccak256(abi.encodePacked("root-v", uint256(2)))),
            "the eight retained generations are unaffected"
        );

        Verdict memory v = _verdict();
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.PolicyRootRejected.selector, ROOT));
        guard.consume(v, "proof");
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

    // 7. Cross-chain / cross-domain replay. `chainId` and `domainId` are the two leading fields of
    // the commitment preimage, so the identical action commits to a different value on another
    // chain or under another policy domain, and a verdict minted for one never matches the
    // commitment a guarded contract recomputes on the other.
    function test_CrossChainAndCrossDomainCommitmentsDiffer() public pure {
        PolicyAction memory a = PolicyAction({
            chainId: 1,
            domainId: DOMAIN,
            agentId: 1,
            target: address(0x51E),
            value: 0,
            callDataHash: keccak256(abi.encodeWithSignature("ping()")),
            actionNonce: 0
        });
        bytes32 onChainOne = PolicyActionLib.commit(a);

        a.chainId = 2; // same action, different chain
        assertTrue(PolicyActionLib.commit(a) != onChainOne, "chainId must separate the commitment");

        a.chainId = 1;
        a.domainId = keccak256("other-compliance"); // same action, different policy domain
        assertTrue(PolicyActionLib.commit(a) != onChainOne, "domainId must separate the commitment");
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

    // --- ERC-8004 identity binding (ordered check 2) ---

    // 21. A domain that declares an ERC-8004 Identity Registry rejects an agentId that does not
    // exist there, and `verify` short-circuits on the same condition.
    function test_UnknownAgentRefusedWhenDomainDeclaresIdentityRegistry() public {
        MockIdentityRegistry identity = new MockIdentityRegistry();
        identity.register(1, address(0xA6E7)); // agent 1 exists; agent 2 was never registered
        registry.setIdentityRegistry(DOMAIN, address(identity));

        Verdict memory unknown = _verdict();
        unknown.agentId = 2;
        assertFalse(guard.verify(unknown, "proof"), "verify must refuse an unknown agent");
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.AgentUnknown.selector, uint256(2)));
        guard.consume(unknown, "proof");

        // The registered agent is unaffected.
        Verdict memory known = _verdict(); // agentId 1
        vm.prank(EXECUTOR);
        guard.consume(known, "proof");
        assertTrue(guard.isConsumed(DOMAIN, known.nullifier));
    }

    // 22. A domain that declares no registry leaves agentId unresolved rather than unresolvable:
    // the check is conditional, so the standard stays usable on chains hosting no ERC-8004.
    function test_AgentUnresolvedWhenDomainDeclaresNoIdentityRegistry() public {
        assertEq(registry.domain(DOMAIN).identityRegistry, address(0), "fixture declares no registry");
        Verdict memory v = _verdict();
        v.agentId = 999_999; // no registry anywhere minted this id
        vm.prank(EXECUTOR);
        guard.consume(v, "proof");
        assertTrue(guard.isConsumed(DOMAIN, v.nullifier));
    }

    // 23. A declared address holding no code names no agents: the domain is misconfigured, and
    // the Guard says so with AgentUnknown rather than reverting without data.
    function test_IdentityRegistryWithoutCodeRefusesEveryAgent() public {
        registry.setIdentityRegistry(DOMAIN, address(0xDEAD)); // no code at this address
        Verdict memory v = _verdict();
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.AgentUnknown.selector, uint256(1)));
        guard.consume(v, "proof");
    }

    // 24. Check 2 sits ahead of everything that could mask it: an inactive domain must not hide
    // an unknown agent behind DomainInactive.
    function test_UnknownAgentBeatsInactiveDomain() public {
        MockIdentityRegistry identity = new MockIdentityRegistry();
        registry.setIdentityRegistry(DOMAIN, address(identity));
        registry.revokeDomain(DOMAIN);

        Verdict memory v = _verdict(); // agentId 1, never registered in `identity`
        vm.prank(EXECUTOR);
        vm.expectRevert(abi.encodeWithSelector(IConfidentialPolicyVerdict.AgentUnknown.selector, uint256(1)));
        guard.consume(v, "proof");
    }

}
