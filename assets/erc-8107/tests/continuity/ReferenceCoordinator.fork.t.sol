// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TrustRegistry} from "../../contracts/TrustRegistry.sol";
import {ITrustRegistry, TrustLevel, TrustAttestation, ValidationParams, TrustPath} from "../../contracts/ITrustRegistry.sol";
import {RegistrationBoundary as RB} from "./RegistrationBoundary.sol";
import {BoundaryRecorder} from "./BoundaryRecorder.sol";
import {Registration, RentPrice, IController} from "./ExecutionWindow.fork.t.sol";
import {
    ReferenceCoordinator as RC,
    IENSOwner,
    IBaseRegistrarExpiry,
    INameWrapperOwner
} from "./ReferenceCoordinator.sol";

interface IBaseC {
    function nameExpires(uint256 id) external view returns (uint256);
    function available(uint256 id) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
}

interface IENSC {
    function owner(bytes32 node) external view returns (address);
    function setResolver(bytes32 node, address resolver) external;
}

interface IWrapperC {
    function wrapETH2LD(string calldata label, address wrappedOwner, uint16 ownerControlledFuses, address resolver)
        external
        returns (uint64);
    function setSubnodeOwner(bytes32 parentNode, string calldata label, address owner, uint32 fuses, uint64 expiry)
        external
        returns (bytes32);
    function ownerOf(uint256 id) external view returns (address);
    function getData(uint256 id) external view returns (address, uint32, uint64);
}

interface IAddrSetter {
    function setAddr(bytes32 node, address a) external;
}

/// The reference coordinator on deployed mainnet ENS, from the decision at block B
/// through execution. Paths run from the gatekeeper G to the participant M through one
/// trustor: T, a wrapped `.eth` 2LD; S, an emancipated subname of the wrapped 2LD P; or
/// X, an unwrapped 2LD. No wrapped name is renewed.
/// Run: forge test --fork-url <mainnet> --fork-block-number 26194700 --match-contract ReferenceCoordinatorForkTest -vv
contract ReferenceCoordinatorForkTest is BoundaryRecorder {
    uint256 constant PINNED_BLOCK = 26_194_700;
    address constant ENS = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant NAME_WRAPPER = 0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401;
    address constant PUBLIC_RESOLVER = 0x231b0Ee14048e9dCcD1d247744d114a4EB5E8E63;
    IBaseC constant BASE = IBaseC(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
    IController constant CONTROLLER = IController(0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547);
    IWrapperC constant WRAPPER = IWrapperC(NAME_WRAPPER);
    uint256 constant GRACE = 90 days;
    uint16 constant CANNOT_UNWRAP = 1;
    uint32 constant PARENT_CANNOT_CONTROL = 1 << 16;

    string constant G_LABEL = "erc8107-coord-gate";
    string constant M_LABEL = "erc8107-coord-m";
    string constant T_LABEL = "erc8107-coord-t";
    string constant P_LABEL = "erc8107-coord-parent";
    string constant X_LABEL = "erc8107-coord-x";

    uint256 constant G_KEY = uint256(keccak256("erc-8107 coord G"));
    uint256 constant M_KEY = uint256(keccak256("erc-8107 coord M"));
    uint256 constant H1_KEY = uint256(keccak256("erc-8107 coord H1"));
    uint256 constant P_KEY = uint256(keccak256("erc-8107 coord P"));
    uint256 constant S_KEY = uint256(keccak256("erc-8107 coord S"));
    uint256 constant H2_KEY = uint256(keccak256("erc-8107 coord H2"));
    address immutable AGENT = vm.addr(uint256(keccak256("erc-8107 coord agent")));

    TrustRegistry registry;
    RC coordinator;
    bytes32 G;
    bytes32 M;
    bytes32 T;
    bytes32 P;
    bytes32 S;
    bytes32 X;
    uint64 sExpiry;
    uint64 firstBlock;
    mapping(bytes32 => string[]) labelsOf;

    function setUp() public {
        // Needs a mainnet fork at the pinned block; skipped in a plain local run
        if (block.chainid != 1 || block.number != PINNED_BLOCK) vm.skip(true);
        registry = new TrustRegistry(ENS, NAME_WRAPPER);
        (G, M, T, P, X) = (_name2LD(G_LABEL), _name2LD(M_LABEL), _name2LD(T_LABEL), _name2LD(P_LABEL), _name2LD(X_LABEL));
        S = _nameBelow(P, "agent");
        assertTrue(BASE.available(_id(T_LABEL)), "label unused at the pinned block");
        firstBlock = uint64(block.number) + 1;
        vm.recordLogs();
        _step(block.timestamp);
        _register(G_LABEL, vm.addr(G_KEY), 3650 days);
        _register(M_LABEL, vm.addr(M_KEY), 3650 days);
        _register(T_LABEL, vm.addr(H1_KEY), 28 days);
        _register(P_LABEL, vm.addr(P_KEY), 365 days);
        _register(X_LABEL, vm.addr(H1_KEY), 28 days);

        // M resolves to the agent's address, for identification by address
        _nextTx();
        vm.startPrank(vm.addr(M_KEY));
        IENSC(ENS).setResolver(M, PUBLIC_RESOLVER);
        IAddrSetter(PUBLIC_RESOLVER).setAddr(M, AGENT);
        vm.stopPrank();
        _pushRecorded();

        // T wrapped by H1; P wrapped with CANNOT_UNWRAP, and S emancipated below it
        _wrap2LD(H1_KEY, T_LABEL, 0);
        _wrap2LD(P_KEY, P_LABEL, CANNOT_UNWRAP);
        sExpiry = uint64(block.timestamp + 10 days);
        _nextTx();
        vm.prank(vm.addr(P_KEY));
        WRAPPER.setSubnodeOwner(P, "agent", vm.addr(S_KEY), PARENT_CANNOT_CONTROL, sExpiry);
        _pushRecorded();
        assertEq(WRAPPER.ownerOf(uint256(S)), vm.addr(S_KEY));

        _attest(G_KEY, G, T);
        _attest(H1_KEY, T, M);
        _attest(G_KEY, G, S);
        _attest(S_KEY, S, M);
        _attest(G_KEY, G, X);
        _attest(H1_KEY, X, M);

        coordinator = new RC(
            ITrustRegistry(address(registry)),
            IENSOwner(ENS),
            IBaseRegistrarExpiry(address(BASE)),
            INameWrapperOwner(NAME_WRAPPER),
            G,
            ValidationParams(3, TrustLevel.Marginal, bytes32(0), true, new bytes32[](0))
        );
        _step(block.timestamp + 12);
    }

    // ── harness ────────────────────────────────────────────────────────────────

    function _step(uint256 t) internal {
        vm.warp(t);
        vm.roll(block.number + 1);
        _beginBlock(uint64(block.number));
    }

    function _id(string memory label) internal pure returns (uint256) {
        return uint256(keccak256(bytes(label)));
    }

    function _name2LD(string memory label) internal returns (bytes32 node) {
        node = _node(RB.ETH_NODE, label);
        labelsOf[node].push(label);
        labelsOf[node].push("eth");
    }

    function _nameBelow(bytes32 parent, string memory label) internal returns (bytes32 node) {
        node = _node(parent, label);
        labelsOf[node].push(label);
        for (uint256 i = 0; i < labelsOf[parent].length; i++) {
            labelsOf[node].push(labelsOf[parent][i]);
        }
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

    function _wrap2LD(uint256 key, string memory label, uint16 fuses) internal {
        _nextTx();
        vm.startPrank(vm.addr(key));
        BASE.setApprovalForAll(NAME_WRAPPER, true);
        WRAPPER.wrapETH2LD(label, vm.addr(key), fuses, address(0));
        vm.stopPrank();
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

    function _p(bytes32 trustor) internal view returns (bytes32[] memory n) {
        n = new bytes32[](3);
        (n[0], n[1], n[2]) = (G, trustor, M);
    }

    /// The operator's off-chain decision at the current block, over the complete history
    function _decide(address participant, bytes32[] memory nodes)
        internal
        view
        returns (RC.Stage stage, RB.Result memory r, RC.ExpiryPin[] memory pins)
    {
        RB.NameProof[] memory proofs = new RB.NameProof[](nodes.length);
        for (uint256 i = 0; i < nodes.length; i++) {
            proofs[i] = _proof(labelsOf[nodes[i]]);
        }
        return coordinator.decide(participant, nodes, proofs, _history(firstBlock, uint64(block.number)));
    }

    function _decideOk(address participant, bytes32[] memory nodes) internal view returns (RC.ExpiryPin[] memory pins) {
        RC.Stage stage;
        (stage,, pins) = _decide(participant, nodes);
        assertEq(uint8(stage), uint8(RC.Stage.Ok), "decision at B");
    }

    function _registryAccepts(bytes32[] memory nodes) internal view returns (bool) {
        return registry.validateParticipantWithPath(address(coordinator), coordinator.TYPE(), M, TrustPath(nodes));
    }

    // ── cases ──────────────────────────────────────────────────────────────────

    /// Every check passes at B and at execution, by node and by address, through each
    /// kind of trustor. The pins cover the 2LDs on the path, P for S
    function test_CleanRun_Executes() public {
        bytes32[3] memory trustors = [T, S, X];
        for (uint256 i = 0; i < 3; i++) {
            RC.ExpiryPin[] memory byNode = _decideOk(address(0), _p(trustors[i]));
            RC.ExpiryPin[] memory byAddr = _decideOk(AGENT, _p(trustors[i]));
            assertEq(byNode.length, 3, "G, the trustor's 2LD, M");
            _nextTx();
            coordinator.execute(address(0), _p(trustors[i]), byNode);
            coordinator.execute(AGENT, _p(trustors[i]), byAddr);
        }
        assertEq(coordinator.executions(), 6);
    }

    /// The reviewer's case: an emancipated subname trustor passes its NameWrapper expiry
    /// between the decision and execution. The registry and the continuity check both
    /// still accept the path, and the pins hold; only the liveness check at execution
    /// rejects it
    function test_EmancipatedTrustorExpiresBeforeExecution() public {
        RC.ExpiryPin[] memory pins = _decideOk(AGENT, _p(S));
        _step(sExpiry + 1);
        assertEq(WRAPPER.ownerOf(uint256(S)), address(0), "S has no controller");
        assertTrue(_registryAccepts(_p(S)), "the registry still accepts");
        assertTrue(
            registry.validateParticipantAddress(address(coordinator), coordinator.TYPE(), AGENT, TrustPath(_p(S))),
            "by address too: the terminal M still has a controller"
        );
        (RC.Stage stage, RB.Result memory r,) = _decide(AGENT, _p(S));
        assertEq(uint8(r.verdict), uint8(RB.Verdict.Eligible), "continuity: nothing registered or wrapped again");
        assertEq(uint8(stage), uint8(RC.Stage.Liveness));
        _nextTx();
        vm.expectRevert(abi.encodeWithSelector(RC.NoController.selector, S));
        coordinator.execute(AGENT, _p(S), pins);
    }

    /// A wrapped 2LD trustor decided on in its grace period loses its holder at its
    /// NameWrapper expiry. Nothing is registered, so the unchanged expiry satisfies the
    /// pin past the deadline; the liveness check rejects
    function test_Wrapped2LDTrustorPastWrapperExpiry() public {
        uint256 e = BASE.nameExpires(_id(T_LABEL));
        _step(e + 30 days);
        RC.ExpiryPin[] memory pins = _decideOk(address(0), _p(T));
        _step(e + GRACE + 1);
        assertEq(WRAPPER.ownerOf(uint256(T)), address(0), "T has no controller");
        assertEq(BASE.nameExpires(_id(T_LABEL)), e, "nothing registered");
        assertTrue(_registryAccepts(_p(T)));
        _nextTx();
        vm.expectRevert(abi.encodeWithSelector(RC.NoController.selector, T));
        coordinator.execute(address(0), _p(T), pins);
    }

    /// X, lapsed and unwrapped, is registered again by another party in the block after
    /// the decision, before execution. The registry accepts; the pin rejects
    function test_ReRegistrationInWindow() public {
        _step(BASE.nameExpires(_id(X_LABEL)) + GRACE + 22 days);
        Registration memory r = _registration(X_LABEL, vm.addr(H2_KEY), 365 days);
        _commit(r);
        _step(block.timestamp + CONTROLLER.minCommitmentAge() + 1);
        RC.ExpiryPin[] memory pins = _decideOk(address(0), _p(X));

        _step(block.timestamp + 12);
        _reveal(r);
        assertEq(IENSC(ENS).owner(X), vm.addr(H2_KEY), "H2 controls X");
        assertTrue(_registryAccepts(_p(X)), "the registry still accepts");
        _nextTx();
        vm.expectRevert(abi.encodeWithSelector(RC.RegisteredSinceDecision.selector, _id(X_LABEL)));
        coordinator.execute(address(0), _p(X), pins);
    }

    /// Registered again before B: the decision fails at the continuity check while the
    /// gate passes
    function test_ReRegisteredBeforeDecision() public {
        _step(BASE.nameExpires(_id(X_LABEL)) + GRACE + 22 days);
        _register(X_LABEL, vm.addr(H2_KEY), 365 days);
        _step(block.timestamp + 12);
        assertTrue(_registryAccepts(_p(X)));
        (RC.Stage stage, RB.Result memory r,) = _decide(address(0), _p(X));
        assertEq(uint8(stage), uint8(RC.Stage.Continuity));
        assertEq(uint8(r.reason), uint8(RB.Reason.ReRegistered));
        assertEq(r.node, X);
    }

    /// Only the operator executes: the pins are its own reading at B
    function test_OnlyOperatorExecutes() public {
        RC.ExpiryPin[] memory pins = _decideOk(address(0), _p(T));
        vm.prank(AGENT);
        vm.expectRevert(RC.NotOperator.selector);
        coordinator.execute(address(0), _p(T), pins);
    }
}
