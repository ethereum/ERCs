// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {CoupledCredentialGuard} from "../CoupledCredentialGuard.sol";
import {DomainRegistry} from "../DomainRegistry.sol";
import {IUnclonableCredential} from "../IUnclonableCredential.sol";
import {CapabilityCommitment} from "../CapabilityCommitment.sol";
import {BindingVerifier, ActionTarget} from "./Harness.sol";

/// @title ERC-8380 Test Cases
/// @notice One test per row of the Test Cases table in the specification, in the same order.
///         The table currently opens with "The reference implementation covers the following
///         cases" while `assets/erc-8380/` carries no tests, so this file is that coverage.
contract ERC8380Test {
    CoupledCredentialGuard guard;
    DomainRegistry registry;
    BindingVerifier verifier;
    ActionTarget target;

    uint256 constant AGENT = 5;
    uint256 constant DOMAIN = 1;
    uint256 constant OTHER_DOMAIN = 2;
    uint256 constant INDEX = 3;
    uint256 constant EXPIRY = 1900000000;
    address constant EXECUTOR = address(0xE0);

    function setUp() public {
        registry = new DomainRegistry();
        registry.registerDomain(DOMAIN);
        verifier = new BindingVerifier();
        target = new ActionTarget();
        guard = new CoupledCredentialGuard(address(verifier), address(registry), address(this));
    }

    // ── helpers ──────────────────────────────────────────────────────────────

    function _callData() internal pure returns (bytes memory) {
        return abi.encodeWithSignature("act()");
    }

    function _cap(bytes32 salt, uint256 domainId, uint256 index, address executor, uint256 expiry)
        internal view returns (IUnclonableCredential.Capability memory c)
    {
        bytes32 action = keccak256(abi.encode(address(target), _callData()));
        c = IUnclonableCredential.Capability({
            nullifier: CapabilityCommitment.computeNullifier(salt),
            capabilityCommitment: CapabilityCommitment.computeCapabilityCommitment(
                salt, AGENT, block.chainid, domainId, index, action, executor, expiry
            ),
            agentId: AGENT,
            homeChainId: block.chainid,
            homeDomainId: domainId,
            capabilityIndex: index,
            actionCommitment: action,
            executor: executor,
            expiry: expiry
        });
    }

    function _inputs(IUnclonableCredential.Capability memory c)
        internal pure returns (bytes32[] memory a)
    {
        a = new bytes32[](9);
        a[0] = c.capabilityCommitment;
        a[1] = bytes32(c.agentId);
        a[2] = bytes32(c.homeChainId);
        a[3] = bytes32(c.homeDomainId);
        a[4] = bytes32(c.capabilityIndex);
        a[5] = c.actionCommitment;
        a[6] = bytes32(uint256(uint160(c.executor)));
        a[7] = bytes32(c.expiry);
        a[8] = c.nullifier;
    }

    /// Issue the capability on chain and mint a proof bound to exactly its public inputs.
    function _arm(IUnclonableCredential.Capability memory c, bytes memory proof) internal {
        guard.issue(c.capabilityCommitment, c.agentId, c.capabilityIndex);
        verifier.issueProof(proof, _inputs(c));
    }

    function _expectRevert(IUnclonableCredential.Capability memory c, bytes memory proof, string memory why)
        internal
    {
        (bool ok,) = address(guard).call(
            abi.encodeWithSelector(guard.execute.selector, c, proof, address(target), _callData())
        );
        require(!ok, why);
    }

    // ── 1. Happy path ────────────────────────────────────────────────────────
    function test_01_HappyPath() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(1)), DOMAIN, INDEX, address(this), EXPIRY);
        _arm(c, "p1");
        guard.execute(c, "p1", address(target), _callData());
        require(guard.isConsumed(c.nullifier), "nullifier must read as consumed");
        require(target.runs() == 1, "the action must have run");
    }

    // ── 2. Double spend ──────────────────────────────────────────────────────
    function test_02_DoubleSpend() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(2)), DOMAIN, INDEX, address(this), EXPIRY);
        _arm(c, "p2");
        guard.execute(c, "p2", address(target), _callData());
        _expectRevert(c, "p2", "a second spend must revert");
        require(target.runs() == 1, "the action must not run twice");
    }

    // ── 3. Clone replay: a submitter that is not the executor ────────────────
    function test_03_CloneReplay() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(3)), DOMAIN, INDEX, EXECUTOR, EXPIRY);
        _arm(c, "p3");
        _expectRevert(c, "p3", "a submitter that is not the executor must revert");
        require(target.runs() == 0, "no action on a refused spend");
    }

    // ── 4. Wrong chain ───────────────────────────────────────────────────────
    function test_04_WrongChain() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(4)), DOMAIN, INDEX, address(this), EXPIRY);
        c.homeChainId = block.chainid + 1;
        _arm(c, "p4");
        _expectRevert(c, "p4", "a homeChainId other than block.chainid must revert");
    }

    // ── 5. Expired ───────────────────────────────────────────────────────────
    function test_05_Expired() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(5)), DOMAIN, INDEX, address(this), 0);
        require(block.timestamp > 0, "the harness needs a nonzero timestamp for this case to mean anything");
        _arm(c, "p5");
        _expectRevert(c, "p5", "an expiry in the past must revert");
    }

    // ── 6. Executor mismatch ─────────────────────────────────────────────────
    function test_06_ExecutorMismatch() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(6)), DOMAIN, INDEX, address(0xBEEF), EXPIRY);
        _arm(c, "p6");
        _expectRevert(c, "p6", "a capability naming a different executor must revert");
    }

    // ── 7. Executor or expiry tamper ─────────────────────────────────────────
    // Both sit inside capabilityCommitment, so swapping either in calldata changes the
    // commitment the circuit proved and the proof no longer verifies.
    function test_07_ExecutorOrExpiryTamper() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(7)), DOMAIN, INDEX, EXECUTOR, EXPIRY);
        _arm(c, "p7");

        IUnclonableCredential.Capability memory swapped = c;
        swapped.executor = address(this);
        _expectRevert(swapped, "p7", "a proof must not verify under a swapped executor");

        IUnclonableCredential.Capability memory stretched = c;
        stretched.executor = address(this);
        stretched.expiry = EXPIRY + 365 days;
        _expectRevert(stretched, "p7", "a proof must not verify under a stretched expiry");
    }

    // ── 8. Nullifier substitution ────────────────────────────────────────────
    function test_08_NullifierSubstitution() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(8)), DOMAIN, INDEX, address(this), EXPIRY);
        _arm(c, "p8");
        IUnclonableCredential.Capability memory sub = c;
        sub.nullifier = keccak256("unrelated");
        _expectRevert(sub, "p8", "a proof must not verify against a substituted nullifier");
    }

    // ── 9. Front run with a lifted proof ─────────────────────────────────────
    // Worth knowing which mechanism carries this row. Swap the verifier for one that returns
    // true unconditionally and 7 and 8 fail while this one still passes, so a lifted proof is
    // stopped by `msg.sender != cap.executor` and not by the circuit. That is sufficient, but
    // it means the guarantee rests on the executor check alone.
    function test_09_FrontRunWithLiftedProof() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(9)), DOMAIN, INDEX, EXECUTOR, EXPIRY);
        _arm(c, "p9");
        _expectRevert(c, "p9", "an observed proof resubmitted by a third party must revert");
    }

    // ── 10. Unregistered domain ──────────────────────────────────────────────
    function test_10_UnregisteredDomain() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(10)), OTHER_DOMAIN, INDEX, address(this), EXPIRY);
        _arm(c, "p10");
        _expectRevert(c, "p10", "an unregistered homeDomainId must revert");
    }

    // ── 11. Commitment parity ────────────────────────────────────────────────
    // The specification publishes the inputs and the formula but no expected digest, so a
    // circuit author has nothing to check against. These are the values the reference
    // Solidity produces for the published vector.
    function test_11_CommitmentParity() public pure {
        bytes32 salt = bytes32(uint256(7));
        require(
            CapabilityCommitment.computeNullifier(salt)
                == 0x387e1b17665773c440b8c1e1091763c9b9c2d2733eeaeaf1fdac1d17aa957338,
            "nullifier vector"
        );
        require(
            CapabilityCommitment.computeCapabilityCommitment(
                salt, 5, 11155111, 1, 3, bytes32(uint256(0x63)), address(1), 1900000000
            ) == 0x0ca20742a17fa240d3abf6146f61981ee649b937a992f87bb599c1c1899f88cf,
            "capabilityCommitment vector"
        );
    }

    // ── 12. Race ─────────────────────────────────────────────────────────────
    // Exactly one of two spends of the same nullifier lands. Ordering within a block is the
    // proposer's, so the Guard must not determine which, only that the second fails.
    function test_12_Race() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(12)), DOMAIN, INDEX, address(this), EXPIRY);
        _arm(c, "p12");
        guard.execute(c, "p12", address(target), _callData());
        _expectRevert(c, "p12", "the loser of the race must revert");
        require(target.runs() == 1, "exactly one spend lands");
    }

    // ── 13. Grief on an unissued action ──────────────────────────────────────
    function test_13_GriefOnUnissuedAction() public {
        setUp();
        IUnclonableCredential.Capability memory bad = _cap(bytes32(uint256(13)), DOMAIN, INDEX, address(this), EXPIRY);
        verifier.issueProof("p13", _inputs(bad)); // proof exists, issuance does not
        _expectRevert(bad, "p13", "a spend against a never-issued commitment must revert");

        IUnclonableCredential.Capability memory good = _cap(bytes32(uint256(14)), DOMAIN, INDEX + 1, address(this), EXPIRY);
        _arm(good, "p13b");
        guard.execute(good, "p13b", address(target), _callData());
        require(target.runs() == 1, "the honest action still runs afterwards");
    }

    // ── 14. Burn implies execution ───────────────────────────────────────────
    // If the action reverts, the burn must revert with it.
    function test_14_BurnImpliesExecution() public {
        setUp();
        bytes memory bad = abi.encodeWithSignature("boom()");
        bytes32 action = keccak256(abi.encode(address(target), bad));
        bytes32 salt = bytes32(uint256(15));
        IUnclonableCredential.Capability memory c = IUnclonableCredential.Capability({
            nullifier: CapabilityCommitment.computeNullifier(salt),
            capabilityCommitment: CapabilityCommitment.computeCapabilityCommitment(
                salt, AGENT, block.chainid, DOMAIN, INDEX, action, address(this), EXPIRY
            ),
            agentId: AGENT, homeChainId: block.chainid, homeDomainId: DOMAIN,
            capabilityIndex: INDEX, actionCommitment: action,
            executor: address(this), expiry: EXPIRY
        });
        _arm(c, "p14");
        (bool ok,) = address(guard).call(
            abi.encodeWithSelector(guard.execute.selector, c, bytes("p14"), address(target), bad)
        );
        require(!ok, "a reverting action must revert the whole call");
        require(!guard.isConsumed(c.nullifier), "a consumed nullifier must always mean the action ran");
    }

    // ── 15. Premature spend ──────────────────────────────────────────────────
    // An early spend performs the authorized action rather than destroying the capability.
    function test_15_PrematureSpend() public {
        setUp();
        IUnclonableCredential.Capability memory c = _cap(bytes32(uint256(16)), DOMAIN, INDEX, address(this), EXPIRY);
        _arm(c, "p15");
        guard.execute(c, "p15", address(target), _callData());
        require(target.runs() == 1, "an early spend must still perform the action");
        require(guard.isConsumed(c.nullifier), "and burn the nullifier");
    }

    // ── 16. Collision classification ─────────────────────────────────────────
    // This case asserts what row 16 of the table promises, not what the reference implementation
    // currently does, so it FAILS on the current keying. That failure is the point: it is the
    // regression artifact the fix has to turn green.
    //
    // The Specification puts the index space on the pair of `agentId` and `homeDomainId`, and
    // the salt derivation agrees. `highestIssuedIndex` is keyed on `agentId` alone and `issue`
    // never receives a domain, so once an agent operates in two domains the ceiling is shared.
    // Domain A issuing up to index 10 makes a genuine clone colliding at index 4 in domain B
    // read as "an index the orchestrator did issue", which the Security Considerations classify
    // as the orchestrator's own reissue bug. The classification inverts in the one case the
    // mechanism exists for.
    //
    // Moving the ceiling to [agentId][homeDomainId] and passing a domain to `issue` turns this
    // green. Both are interface changes, so this case is rewritten in the same commit as the fix.
    function test_16_CollisionClassificationIsPerDomain() public {
        setUp();
        registry.registerDomain(OTHER_DOMAIN);

        for (uint256 i = 1; i <= 10; i++) {
            guard.issue(keccak256(abi.encode(DOMAIN, i)), AGENT, i);
        }

        require(
            guard.highestIssuedIndex(AGENT) == 10,
            "domain A raised the agent-keyed ceiling"
        );

        // OTHER_DOMAIN has issued nothing for this agent, so row 16's answer for index 4 is
        // "never issued here, therefore a clone". The shared ceiling says otherwise.
        require(
            !(4 <= guard.highestIssuedIndex(AGENT)),
            "index 4 was never issued in OTHER_DOMAIN, but the agent-keyed ceiling reads it as issued, so a clone is classified as an orchestrator reissue bug"
        );
    }

    // ── 17. Recovery ─────────────────────────────────────────────────────────
    function test_17_Recovery() public {
        setUp();
        IUnclonableCredential.Capability memory first = _cap(bytes32(uint256(17)), DOMAIN, INDEX, address(this), EXPIRY);
        _arm(first, "p17");
        guard.execute(first, "p17", address(target), _callData());

        _expectRevert(first, "p17", "a burned index stays burned");

        IUnclonableCredential.Capability memory next = _cap(bytes32(uint256(18)), DOMAIN, INDEX + 1, address(this), EXPIRY);
        _arm(next, "p17b");
        guard.execute(next, "p17b", address(target), _callData());
        require(target.runs() == 2, "the capability is reauthorized at the next index");
    }
}
