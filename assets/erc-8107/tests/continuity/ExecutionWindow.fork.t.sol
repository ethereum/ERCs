// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TrustRegistry} from "../../contracts/TrustRegistry.sol";
import {TrustLevel, TrustAttestation, ValidationParams, TrustPath} from "../../contracts/ITrustRegistry.sol";
import {RegistrationBoundary as RB} from "./RegistrationBoundary.sol";
import {BoundaryRecorder} from "./BoundaryRecorder.sol";

struct Registration {
    string label;
    address owner;
    uint256 duration;
    bytes32 secret;
    address resolver;
    bytes[] data;
    uint8 reverseRecord;
    bytes32 referrer;
}

struct RentPrice {
    uint256 base;
    uint256 premium;
}

interface IController {
    function rentPrice(string calldata label, uint256 duration) external view returns (RentPrice memory);
    function makeCommitment(Registration calldata registration) external pure returns (bytes32);
    function commit(bytes32 commitment) external;
    function register(Registration calldata registration) external payable;
    function renew(string calldata label, uint256 duration, bytes32 referrer) external payable;
    function minCommitmentAge() external view returns (uint256);
}

interface IBase {
    function nameExpires(uint256 id) external view returns (uint256);
    function available(uint256 id) external view returns (bool);
    function ownerOf(uint256 id) external view returns (address);
}

interface IENS {
    function owner(bytes32 node) external view returns (address);
}

/// The BaseRegistrar expiry a coordinator observed for one `.eth` second-level name on
/// its path, at the block its off-chain continuity check ran to
struct ExpiryPin {
    uint256 labelhash;
    uint256 expires;
}

error PathRejected();
error RegisteredSincePin(uint256 labelhash, uint256 pinned, uint256 current);

/// A minimal coordinator: one gate, and an execute step that re-evaluates the gate in
/// the executing transaction, as the spec recommends. With `pins` empty it relies on
/// the registry's verdict alone; with pins it also asserts that no pinned name has been
/// registered since the off-chain check.
contract Coordinator {
    bytes32 public constant TYPE = keccak256("ERC8107.execution-window");
    TrustRegistry public immutable registry;
    IBase public immutable base;
    uint256 public executions;

    constructor(TrustRegistry registry_, IBase base_, bytes32 gatekeeper) {
        registry = registry_;
        base = base_;
        registry_.setIdentityGate(
            TYPE, gatekeeper, ValidationParams(3, TrustLevel.Marginal, bytes32(0), true, new bytes32[](0))
        );
    }

    function execute(bytes32 participant, bytes32[] calldata nodes, ExpiryPin[] calldata pins) external {
        // A registration sets the expiry to its own timestamp plus a positive duration,
        // and may only happen once the old expiry plus grace has passed; a renewal never
        // lowers it. So an unchanged expiry means no NameRegistered since the pin.
        for (uint256 i = 0; i < pins.length; i++) {
            uint256 current = base.nameExpires(pins[i].labelhash);
            if (current != pins[i].expires) revert RegisteredSincePin(pins[i].labelhash, pins[i].expires, current);
        }
        if (!registry.validateParticipantWithPath(address(this), TYPE, participant, TrustPath(nodes))) {
            revert PathRejected();
        }
        executions++;
    }
}

/// Execution-window evidence for the ERC-8107 continuity check, on deployed mainnet ENS
/// (unwrapped .eth names). The coordinator runs the off-chain registration-boundary
/// check at block B; in block B+1 the trustee is registered again by another party in
/// the transaction immediately before the coordinator's execute transaction.
/// Run: forge test --fork-url <mainnet> --fork-block-number 26194700 --match-contract ExecutionWindowForkTest -vv
contract ExecutionWindowForkTest is BoundaryRecorder {
    uint256 constant PINNED_BLOCK = 26_194_700;
    address constant ENS = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant NAME_WRAPPER = 0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401;
    IBase constant BASE = IBase(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
    IController constant CONTROLLER = IController(0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547);
    uint256 constant GRACE = 90 days;

    string constant G_LABEL = "erc8107-window-gate";
    string constant X_LABEL = "erc8107-window-x";
    string constant M_LABEL = "erc8107-window-m";

    uint256 constant G_KEY = uint256(keccak256("erc-8107 window G"));
    uint256 constant H1_KEY = uint256(keccak256("erc-8107 window H1"));
    uint256 constant H2_KEY = uint256(keccak256("erc-8107 window H2"));

    TrustRegistry registry;
    Coordinator coordinator;
    bytes32 G;
    bytes32 X;
    bytes32 M;
    uint256 xId;
    uint256 gId;
    uint64 firstBlock;

    // Commitments made before block B, revealable in block B+1: H2's, and H1's own
    Registration pending;
    Registration pendingH1;

    function setUp() public {
        // Needs a mainnet fork at the pinned block; skipped in a plain local run
        if (block.chainid != 1 || block.number != PINNED_BLOCK) vm.skip(true);
        registry = new TrustRegistry(ENS, NAME_WRAPPER);
        (G, X, M) = (_node(RB.ETH_NODE, G_LABEL), _node(RB.ETH_NODE, X_LABEL), _node(RB.ETH_NODE, M_LABEL));
        (gId, xId) = (uint256(keccak256(bytes(G_LABEL))), uint256(keccak256(bytes(X_LABEL))));
        assertTrue(BASE.available(xId), "label unused at the pinned block");
        firstBlock = uint64(block.number) + 1;
        vm.recordLogs();
        _step(block.timestamp);
        _register(G_LABEL, vm.addr(G_KEY), 3650 days);
        _register(X_LABEL, vm.addr(H1_KEY), 28 days);
        _attest(G_KEY, G, X); // G -> X while H1 holds X
        _attest(H1_KEY, X, M); // X -> M by H1
        coordinator = new Coordinator(registry, BASE, G);

        // X lapses: past grace and the premium. H2 commits to registering it
        _step(BASE.nameExpires(xId) + GRACE + 22 days);
        assertTrue(BASE.available(xId), "X available");
        pending = _registration(X_LABEL, vm.addr(H2_KEY), 365 days);
        pendingH1 = _registration(X_LABEL, vm.addr(H1_KEY), 365 days);
        _commit(pending);
        _commit(pendingH1);

        // Block B: the commitment is old enough to reveal. The coordinator decides here
        _step(block.timestamp + CONTROLLER.minCommitmentAge() + 1);
    }

    // ── harness ────────────────────────────────────────────────────────────────

    function _step(uint256 t) internal {
        vm.warp(t);
        vm.roll(block.number + 1);
        _beginBlock(uint64(block.number));
    }

    function _registration(string memory label, address owner, uint256 duration)
        internal
        view
        returns (Registration memory)
    {
        return Registration({
            label: label,
            owner: owner,
            duration: duration,
            secret: keccak256(abi.encode(label, owner, block.timestamp)),
            resolver: address(0),
            data: new bytes[](0),
            reverseRecord: 0,
            referrer: bytes32(0)
        });
    }

    function _reveal(Registration memory r) internal {
        RentPrice memory p = CONTROLLER.rentPrice(r.label, r.duration);
        vm.deal(r.owner, p.base + p.premium);
        _nextTx();
        vm.prank(r.owner);
        CONTROLLER.register{value: p.base + p.premium}(r);
        _pushRecorded();
    }

    function _commit(Registration memory r) internal {
        _nextTx();
        vm.prank(r.owner);
        CONTROLLER.commit(CONTROLLER.makeCommitment(r));
        _pushRecorded();
    }

    function _register(string memory label, address owner, uint256 duration) internal {
        Registration memory r = _registration(label, owner, duration);
        _commit(r);
        _step(block.timestamp + CONTROLLER.minCommitmentAge() + 1);
        _reveal(r);
    }

    function _attest(uint256 key, bytes32 from, bytes32 to) internal {
        TrustAttestation memory att =
            TrustAttestation(from, to, TrustLevel.Full, bytes32(0), 0, registry.getNonce(from) + 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, registry.hashAttestation(att));
        _nextTx();
        registry.setTrust(att, abi.encodePacked(r, s, v));
        _pushRecorded();
    }

    function _p(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory n) {
        n = new bytes32[](2);
        (n[0], n[1]) = (a, b);
    }

    function _p(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory n) {
        n = new bytes32[](3);
        (n[0], n[1], n[2]) = (a, b, c);
    }

    function _proofs(bytes32[] memory nodes) internal view returns (RB.NameProof[] memory p) {
        p = new RB.NameProof[](nodes.length);
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i] == G) p[i] = _proof(RB.ETH_NODE, G_LABEL);
            else if (nodes[i] == X) p[i] = _proof(RB.ETH_NODE, X_LABEL);
            else if (nodes[i] == M) p[i] = _proof(RB.ETH_NODE, M_LABEL);
        }
    }

    /// The off-chain registration-boundary check, over the complete history to `head`
    function _check(bytes32[] memory nodes, uint64 head) internal view returns (RB.Result memory) {
        return RB.evaluate(registry, address(BASE), nodes, bytes32(0), _proofs(nodes), _history(firstBlock, head), head);
    }

    /// What the coordinator pins at the block its check ran to: every .eth 2LD on the path
    function _pins() internal view returns (ExpiryPin[] memory p) {
        p = new ExpiryPin[](2);
        p[0] = ExpiryPin(gId, BASE.nameExpires(gId));
        p[1] = ExpiryPin(xId, BASE.nameExpires(xId));
    }

    function _assert(RB.Result memory r, RB.Verdict v, RB.Reason why, bytes32 node) internal pure {
        assertEq(uint8(r.verdict), uint8(v), "verdict");
        assertEq(uint8(r.reason), uint8(why), "reason");
        assertEq(r.node, node, "node");
    }

    /// Block B: the coordinator's off-chain check passes for both paths it will supply
    function _decideAtB() internal view returns (uint64 b) {
        b = uint64(block.number);
        _assert(_check(_p(G, X), b), RB.Verdict.Eligible, RB.Reason.None, bytes32(0));
        _assert(_check(_p(G, X, M), b), RB.Verdict.Eligible, RB.Reason.None, bytes32(0));
        // Unwrapped and lapsed: the registry owner, which controllerOf returns, is still H1
        assertEq(IENS(ENS).owner(X), vm.addr(H1_KEY), "H1 still controls the lapsed X");
    }

    // ── cases ──────────────────────────────────────────────────────────────────

    /// The reviewer's case. Re-registration is the transaction immediately before the
    /// coordinator's execute transaction in block B+1. The execution-time gate check
    /// reads registry state only and accepts both stored edges of H1's registration.
    function test_SameBlockReRegistrationBeforeExecution_RegistryAccepts() public {
        uint64 b = _decideAtB();

        _step(block.timestamp + 12);
        uint64 e = uint64(block.number);
        assertEq(e, b + 1);
        _reveal(pending); // tx k: H2 registers X
        assertEq(BASE.ownerOf(xId), vm.addr(H2_KEY), "H2 holds X");
        assertEq(IENS(ENS).owner(X), vm.addr(H2_KEY), "and controls it");

        _nextTx(); // tx k+1, same block: the coordinator executes on the decision made at B
        coordinator.execute(X, _p(G, X), new ExpiryPin[](0));
        coordinator.execute(M, _p(G, X, M), new ExpiryPin[](0));
        assertEq(coordinator.executions(), 2, "both executions went through");

        // The same check over the history to B+1 rejects both: the window was real
        _assert(_check(_p(G, X), e), RB.Verdict.Ineligible, RB.Reason.ReRegistered, X);
        _assert(_check(_p(G, X, M), e), RB.Verdict.Ineligible, RB.Reason.ReRegistered, X);
    }

    /// A re-registration by the same holder lands the same way, and is equally invisible
    function test_SameBlockSameHolderReRegistration_RegistryAccepts() public {
        uint64 b = _decideAtB();
        _step(block.timestamp + 12);
        _reveal(pendingH1);
        assertEq(BASE.ownerOf(xId), vm.addr(H1_KEY), "same holder");
        _nextTx();
        coordinator.execute(M, _p(G, X, M), new ExpiryPin[](0));
        assertEq(coordinator.executions(), 1);
        _assert(_check(_p(G, X, M), b + 1), RB.Verdict.Ineligible, RB.Reason.ReRegistered, X);
    }

    /// The pinned coordinator: the expiries read at B travel in the execute call, and
    /// the same-block re-registration makes it revert
    function test_SameBlockReRegistrationBeforeExecution_ExpiryPinReverts() public {
        _decideAtB();
        ExpiryPin[] memory pins = _pins();

        _step(block.timestamp + 12);
        _reveal(pending);
        uint256 now_ = BASE.nameExpires(xId);
        assertGt(now_, pins[1].expires, "registration moved the expiry");

        _nextTx();
        vm.expectRevert(abi.encodeWithSelector(RegisteredSincePin.selector, xId, pins[1].expires, now_));
        coordinator.execute(X, _p(G, X), pins);
        vm.expectRevert(abi.encodeWithSelector(RegisteredSincePin.selector, xId, pins[1].expires, now_));
        coordinator.execute(M, _p(G, X, M), pins);
        assertEq(coordinator.executions(), 0);
    }

    /// Execution first, registration second, in one block: the attestation was eligible
    /// when relied on, and the pinned coordinator executes
    function test_SameBlockExecutionBeforeReRegistration_PinnedExecutes() public {
        _decideAtB();
        ExpiryPin[] memory pins = _pins();
        _step(block.timestamp + 12);
        _nextTx();
        coordinator.execute(M, _p(G, X, M), pins);
        _reveal(pending);
        assertEq(coordinator.executions(), 1);
        assertEq(BASE.ownerOf(xId), vm.addr(H2_KEY));
    }

    /// No registration in the window: the pinned coordinator executes
    function test_NoReRegistration_PinnedExecutes() public {
        _decideAtB();
        ExpiryPin[] memory pins = _pins();
        _step(block.timestamp + 12);
        _nextTx();
        coordinator.execute(X, _p(G, X), pins);
        coordinator.execute(M, _p(G, X, M), pins);
        assertEq(coordinator.executions(), 2);
    }

    /// The pin fails closed on a renewal in the window too. That is a false alarm, not a
    /// false accept: the coordinator re-runs its check and pins again
    function test_RenewalInWindow_PinFailsClosed() public {
        _decideAtB();
        ExpiryPin[] memory pins = _pins();
        _step(block.timestamp + 12);
        uint256 cost = CONTROLLER.rentPrice(G_LABEL, 28 days).base;
        vm.deal(address(0xFEE), cost);
        _nextTx();
        vm.prank(address(0xFEE));
        CONTROLLER.renew{value: cost}(G_LABEL, 28 days, bytes32(0));
        _pushRecorded();
        _nextTx();
        vm.expectRevert(
            abi.encodeWithSelector(RegisteredSincePin.selector, gId, pins[0].expires, pins[0].expires + 28 days)
        );
        coordinator.execute(X, _p(G, X), pins);
        // Re-check and re-pin: the renewal does not end eligibility
        _assert(_check(_p(G, X), uint64(block.number)), RB.Verdict.Eligible, RB.Reason.None, bytes32(0));
        coordinator.execute(X, _p(G, X), _pins());
        assertEq(coordinator.executions(), 1);
    }
}
