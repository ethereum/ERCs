// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TrustRegistry} from "../../contracts/TrustRegistry.sol";
import {TrustLevel, TrustAttestation, ValidationParams, TrustPath} from "../../contracts/ITrustRegistry.sol";
import {RegistrationBoundary as RB} from "./RegistrationBoundary.sol";
import {BoundaryRecorder} from "./BoundaryRecorder.sol";
import {Registration, RentPrice, IController, IENS, ExpiryPin} from "./ExecutionWindow.fork.t.sol";

interface IBaseG {
    function nameExpires(uint256 id) external view returns (uint256);
    function available(uint256 id) external view returns (bool);
    function ownerOf(uint256 id) external view returns (address);
    function GRACE_PERIOD() external view returns (uint256);
    function setApprovalForAll(address operator, bool approved) external;
}

interface IWrapper {
    function wrapETH2LD(string calldata label, address wrappedOwner, uint16 ownerControlledFuses, address resolver)
        external
        returns (uint64);
    function ownerOf(uint256 id) external view returns (address);
    function getData(uint256 id) external view returns (address, uint32, uint64);
}

enum Mode {
    Pin, // nameExpires unchanged since B
    Deadline, // block.timestamp <= pinned expiry + grace
    Strict, // block.timestamp < pinned expiry (the reviewer's bound)
    Union, // Deadline or Pin
    Current // mutant: deadline from the expiry read at execution, not the pinned one
}

error Rejected(Mode mode, uint256 labelhash);
error PathRejected2();

contract ModalCoordinator {
    bytes32 public constant TYPE = keccak256("ERC8107.expiry-deadline");
    TrustRegistry public immutable registry;
    IBaseG public immutable base;
    uint256 public executions;

    constructor(TrustRegistry registry_, IBaseG base_, bytes32 gatekeeper) {
        registry = registry_;
        base = base_;
        registry_.setIdentityGate(
            TYPE, gatekeeper, ValidationParams(3, TrustLevel.Marginal, bytes32(0), true, new bytes32[](0))
        );
    }

    function ok(Mode mode, ExpiryPin calldata p) public view returns (bool) {
        uint256 current = base.nameExpires(p.labelhash);
        uint256 grace = base.GRACE_PERIOD();
        // available() is `expires + grace < block.timestamp`, and expires never falls
        // without a registration, so no registration can land at or before pinned + grace
        if (mode == Mode.Pin) return current == p.expires;
        if (mode == Mode.Deadline) return block.timestamp <= p.expires + grace;
        if (mode == Mode.Strict) return block.timestamp < p.expires;
        if (mode == Mode.Union) return block.timestamp <= p.expires + grace || current == p.expires;
        return block.timestamp <= current + grace;
    }

    function execute(Mode mode, bytes32 participant, bytes32[] calldata nodes, ExpiryPin[] calldata pins) external {
        for (uint256 i = 0; i < pins.length; i++) {
            if (!ok(mode, pins[i])) revert Rejected(mode, pins[i].labelhash);
        }
        if (!registry.validateParticipantWithPath(address(this), TYPE, participant, TrustPath(nodes))) {
            revert PathRejected2();
        }
        executions++;
    }
}

/// A deadline derived from the expiry pinned at block B, against exact pinning, on
/// deployed mainnet ENS. Unlike ExecutionWindowForkTest, X is live at B. X is unwrapped
/// except in the two cases marked Wrapped, where H1 wraps it before B.
/// Run: forge test --fork-url <mainnet> --fork-block-number 26194700 --match-contract ExpiryDeadlineForkTest -vv
contract ExpiryDeadlineForkTest is BoundaryRecorder {
    uint256 constant PINNED_BLOCK = 26_194_700;
    address constant ENS = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant NAME_WRAPPER = 0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401;
    IBaseG constant BASE = IBaseG(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
    IController constant CONTROLLER = IController(0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547);

    string constant G_LABEL = "erc8107-deadline-gate";
    string constant X_LABEL = "erc8107-deadline-x";
    string constant M_LABEL = "erc8107-deadline-m";

    uint256 constant G_KEY = uint256(keccak256("erc-8107 deadline G"));
    uint256 constant H1_KEY = uint256(keccak256("erc-8107 deadline H1"));
    uint256 constant H2_KEY = uint256(keccak256("erc-8107 deadline H2"));

    TrustRegistry registry;
    ModalCoordinator coordinator;
    bytes32 G;
    bytes32 X;
    bytes32 M;
    uint256 xId;
    uint256 gId;
    uint256 grace;
    uint64 firstBlock;

    function setUp() public {
        if (block.chainid != 1 || block.number != PINNED_BLOCK) vm.skip(true);
        registry = new TrustRegistry(ENS, NAME_WRAPPER);
        (G, X, M) = (_node(RB.ETH_NODE, G_LABEL), _node(RB.ETH_NODE, X_LABEL), _node(RB.ETH_NODE, M_LABEL));
        (gId, xId) = (uint256(keccak256(bytes(G_LABEL))), uint256(keccak256(bytes(X_LABEL))));
        assertTrue(BASE.available(xId), "label unused at the pinned block");
        grace = BASE.GRACE_PERIOD();
        assertEq(grace, 90 days);
        firstBlock = uint64(block.number) + 1;
        vm.recordLogs();
        _step(block.timestamp);
        _register(G_LABEL, vm.addr(G_KEY), 3650 days);
        _register(X_LABEL, vm.addr(H1_KEY), 28 days);
        _attest(G_KEY, G, X);
        _attest(H1_KEY, X, M);
        coordinator = new ModalCoordinator(registry, BASE, G);
        // Block B: X is live, a week before its expiry
        _step(BASE.nameExpires(xId) - 7 days);
    }

    // ── harness (as ExecutionWindowForkTest) ───────────────────────────────────

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

    function _commit(Registration memory r) internal {
        _nextTx();
        vm.prank(r.owner);
        CONTROLLER.commit(CONTROLLER.makeCommitment(r));
        _pushRecorded();
    }

    function _reveal(Registration memory r) internal {
        RentPrice memory p = CONTROLLER.rentPrice(r.label, r.duration);
        vm.deal(r.owner, p.base + p.premium);
        _nextTx();
        vm.prank(r.owner);
        CONTROLLER.register{value: p.base + p.premium}(r);
        _pushRecorded();
    }

    function _register(string memory label, address owner, uint256 duration) internal {
        Registration memory r = _registration(label, owner, duration);
        _commit(r);
        _step(block.timestamp + CONTROLLER.minCommitmentAge() + 1);
        _reveal(r);
    }

    function _renew(string memory label, uint256 duration) internal {
        uint256 cost = CONTROLLER.rentPrice(label, duration).base;
        vm.deal(address(0xFEE), cost);
        _nextTx();
        vm.prank(address(0xFEE));
        CONTROLLER.renew{value: cost}(label, duration, bytes32(0));
        _pushRecorded();
    }

    function _attest(uint256 key, bytes32 from, bytes32 to) internal {
        TrustAttestation memory att =
            TrustAttestation(from, to, TrustLevel.Full, bytes32(0), 0, registry.getNonce(from) + 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, registry.hashAttestation(att));
        _nextTx();
        registry.setTrust(att, abi.encodePacked(r, s, v));
        _pushRecorded();
    }

    /// H1 wraps X through the NameWrapper, which sets its expiry to the registrar
    /// expiry plus grace; controllerOf then reads the NameWrapper
    function _wrapX() internal {
        _nextTx();
        vm.startPrank(vm.addr(H1_KEY));
        BASE.setApprovalForAll(NAME_WRAPPER, true);
        IWrapper(NAME_WRAPPER).wrapETH2LD(X_LABEL, vm.addr(H1_KEY), 0, address(0));
        vm.stopPrank();
        _pushRecorded();
        assertEq(IENS(ENS).owner(X), NAME_WRAPPER);
        (,, uint64 wexp) = IWrapper(NAME_WRAPPER).getData(uint256(X));
        assertEq(wexp, BASE.nameExpires(xId) + grace, "wrapper expiry = registrar expiry + grace");
    }

    function _path() internal view returns (bytes32[] memory n) {
        n = new bytes32[](3);
        (n[0], n[1], n[2]) = (G, X, M);
    }

    function _check(uint64 head) internal view returns (RB.Result memory) {
        RB.NameProof[] memory p = new RB.NameProof[](3);
        (p[0], p[1], p[2]) = (_proof(G_LABEL), _proof(X_LABEL), _proof(M_LABEL));
        return
            RB.evaluate(registry, address(BASE), NAME_WRAPPER, _path(), bytes32(0), p, _history(firstBlock, head), head);
    }

    function _pins() internal view returns (ExpiryPin[] memory p) {
        p = new ExpiryPin[](2);
        p[0] = ExpiryPin(gId, BASE.nameExpires(gId));
        p[1] = ExpiryPin(xId, BASE.nameExpires(xId));
    }

    function _decideAtB() internal view returns (ExpiryPin[] memory) {
        assertEq(uint8(_check(uint64(block.number)).verdict), uint8(RB.Verdict.Eligible), "eligible at B");
        return _pins();
    }

    function _eligible(uint64 head) internal view returns (bool) {
        return _check(head).verdict == RB.Verdict.Eligible;
    }

    function _accepts(Mode mode, ExpiryPin[] memory pins) internal returns (bool) {
        uint256 before = coordinator.executions();
        try coordinator.execute(mode, M, _path(), pins) {
            assertEq(coordinator.executions(), before + 1);
            return true;
        } catch (bytes memory err) {
            assertEq(bytes4(err), Rejected.selector, "only the expiry check may reject");
            return false;
        }
    }

    /// Each mode against the same state, in the executing transaction. try/catch keeps
    /// the state; executions only count up
    function _verdicts(ExpiryPin[] memory pins) internal returns (bool[5] memory v) {
        _nextTx();
        for (uint256 i = 0; i < 5; i++) {
            v[i] = _accepts(Mode(i), pins);
        }
    }

    // ── cases ──────────────────────────────────────────────────────────────────

    /// The reviewer's motivating case: a renewal in the window no longer forces a retry
    function test_RenewalInWindow_DeadlineExecutes() public {
        ExpiryPin[] memory pins = _decideAtB();
        _step(block.timestamp + 12);
        _renew(X_LABEL, 28 days);
        assertTrue(_eligible(uint64(block.number)), "a renewal keeps eligibility");
        bool[5] memory v = _verdicts(pins);
        assertFalse(v[uint256(Mode.Pin)], "pin: false alarm");
        assertTrue(v[uint256(Mode.Deadline)]);
        assertTrue(v[uint256(Mode.Strict)]);
        assertTrue(v[uint256(Mode.Union)]);
    }

    /// The last second of grace: registration is not yet possible, the unwrapped holder
    /// still controls X, and the registry accepts. Strict rejects; Deadline does not
    function test_LastSecondOfGrace() public {
        ExpiryPin[] memory pins = _decideAtB();
        _step(pins[1].expires + grace);
        assertFalse(BASE.available(xId), "not registrable at expiry + grace");
        assertTrue(_eligible(uint64(block.number)));
        bool[5] memory v = _verdicts(pins);
        assertTrue(v[uint256(Mode.Pin)]);
        assertTrue(v[uint256(Mode.Deadline)]);
        assertFalse(v[uint256(Mode.Strict)], "strict: rejects the grace period");
        assertTrue(v[uint256(Mode.Union)]);
    }

    /// Re-registration at the first second it is possible, ordered before execution in
    /// the same block. Every mode bound to the pinned expiry rejects; the mutant that
    /// reads the expiry at execution accepts
    function test_ReRegistrationAtFirstPossibleSecond() public {
        ExpiryPin[] memory pins = _decideAtB();
        uint256 t = pins[1].expires + grace + 1;
        _step(t - 120);
        Registration memory r = _registration(X_LABEL, vm.addr(H2_KEY), 365 days);
        _commit(r);
        _step(t);
        assertTrue(BASE.available(xId), "registrable at expiry + grace + 1");
        _reveal(r);
        assertEq(BASE.ownerOf(xId), vm.addr(H2_KEY));
        assertFalse(_eligible(uint64(block.number)), "the window was real");
        bool[5] memory v = _verdicts(pins);
        assertFalse(v[uint256(Mode.Pin)]);
        assertFalse(v[uint256(Mode.Deadline)]);
        assertFalse(v[uint256(Mode.Strict)]);
        assertFalse(v[uint256(Mode.Union)]);
        assertTrue(v[uint256(Mode.Current)], "mutant: unbound deadline accepts the new registration");
    }

    /// Execution after grace with nothing registered: the deadline has passed, but the
    /// unchanged expiry still shows no registration. Only Pin and Union execute
    function test_AfterGraceNothingRegistered() public {
        ExpiryPin[] memory pins = _decideAtB();
        _step(pins[1].expires + grace + 1);
        assertTrue(BASE.available(xId));
        assertTrue(_eligible(uint64(block.number)), "unwrapped holder still controls X");
        bool[5] memory v = _verdicts(pins);
        assertTrue(v[uint256(Mode.Pin)]);
        assertFalse(v[uint256(Mode.Deadline)], "deadline: false alarm");
        assertFalse(v[uint256(Mode.Strict)]);
        assertTrue(v[uint256(Mode.Union)]);
    }

    /// Renew in the window, lapse past the renewed expiry, re-register. The deadline
    /// stays anchored at the expiry pinned at B, so the renewal cannot carry it forward
    function test_RenewThenLapseThenReRegister() public {
        ExpiryPin[] memory pins = _decideAtB();
        _step(block.timestamp + 12);
        _renew(X_LABEL, 28 days);
        uint256 t = BASE.nameExpires(xId) + grace + 1;
        _step(t - 120);
        Registration memory r = _registration(X_LABEL, vm.addr(H1_KEY), 365 days);
        _commit(r);
        _step(t);
        _reveal(r);
        assertFalse(_eligible(uint64(block.number)), "same-holder re-registration ends eligibility");
        bool[5] memory v = _verdicts(pins);
        assertFalse(v[uint256(Mode.Pin)]);
        assertFalse(v[uint256(Mode.Deadline)]);
        assertFalse(v[uint256(Mode.Strict)]);
        assertFalse(v[uint256(Mode.Union)]);
        assertTrue(v[uint256(Mode.Current)], "mutant accepts");
    }

    /// Wrapped: at the last second of grace the NameWrapper still reports H1 and the
    /// registry accepts; every mode but Strict executes
    function test_Wrapped_LastSecondOfGrace() public {
        _wrapX();
        ExpiryPin[] memory pins = _decideAtB();
        _step(pins[1].expires + grace);
        assertEq(IWrapper(NAME_WRAPPER).ownerOf(uint256(X)), vm.addr(H1_KEY), "holder through grace");
        assertFalse(BASE.available(xId));
        bool[5] memory v = _verdicts(pins);
        assertTrue(v[uint256(Mode.Pin)]);
        assertTrue(v[uint256(Mode.Deadline)]);
        assertFalse(v[uint256(Mode.Strict)]);
        assertTrue(v[uint256(Mode.Union)]);
    }

    /// Wrapped: a registration at the first possible second, ordered before execution,
    /// is rejected by every mode bound to the pinned expiry
    function test_Wrapped_ReRegistrationAtFirstPossibleSecond() public {
        _wrapX();
        ExpiryPin[] memory pins = _decideAtB();
        uint256 t = pins[1].expires + grace + 1;
        _step(t - 120);
        Registration memory r = _registration(X_LABEL, vm.addr(H2_KEY), 365 days);
        _commit(r);
        _step(t);
        _reveal(r);
        assertEq(IENS(ENS).owner(X), vm.addr(H2_KEY), "H2 controls X");
        assertFalse(_eligible(uint64(block.number)));
        bool[5] memory v = _verdicts(pins);
        assertFalse(v[uint256(Mode.Pin)]);
        assertFalse(v[uint256(Mode.Deadline)]);
        assertFalse(v[uint256(Mode.Strict)]);
        assertFalse(v[uint256(Mode.Union)]);
        assertTrue(v[uint256(Mode.Current)], "mutant accepts");
    }
}
