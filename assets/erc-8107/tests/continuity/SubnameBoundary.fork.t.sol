// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {TrustRegistry} from "../../contracts/TrustRegistry.sol";
import {TrustLevel, TrustAttestation} from "../../contracts/ITrustRegistry.sol";
import {RegistrationBoundary as RB} from "./RegistrationBoundary.sol";
import {BoundaryRecorder} from "./BoundaryRecorder.sol";
import {Registration, RentPrice, IController} from "./ExecutionWindow.fork.t.sol";

interface IBaseS {
    function nameExpires(uint256 id) external view returns (uint256);
    function available(uint256 id) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
}

interface IRegistryS {
    function owner(bytes32 node) external view returns (address);
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external returns (bytes32);
    function setApprovalForAll(address operator, bool approved) external;
}

interface IWrapperS {
    function wrapETH2LD(string calldata label, address wrappedOwner, uint16 ownerControlledFuses, address resolver)
        external
        returns (uint64);
    function setSubnodeOwner(bytes32 parentNode, string calldata label, address owner, uint32 fuses, uint64 expiry)
        external
        returns (bytes32);
    function unwrap(bytes32 parentNode, bytes32 labelhash, address controller) external;
    function wrap(bytes calldata name, address wrappedOwner, address resolver) external;
    function ownerOf(uint256 id) external view returns (address);
    function getData(uint256 id) external view returns (address, uint32, uint64);
}

/// The continuity check for names below a `.eth` second-level name, on deployed mainnet
/// ENS: re-registration of the second-level ancestor, and `NameWrapped` for the name or
/// an ancestor below the second-level name. G and M are unwrapped 2LDs; P is a wrapped
/// 2LD with CANNOT_UNWRAP burned, so it can emancipate subnames; Q is an unwrapped 2LD
/// whose subname lives in the registry only. No wrapped name is renewed.
/// Run: forge test --fork-url <mainnet> --fork-block-number 26194700 --match-contract SubnameBoundaryForkTest -vv
contract SubnameBoundaryForkTest is BoundaryRecorder {
    uint256 constant PINNED_BLOCK = 26_194_700;
    address constant ENS = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
    address constant NAME_WRAPPER = 0xD4416b13d2b3a9aBae7AcD5D6C2BbDBE25686401;
    IBaseS constant BASE = IBaseS(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
    IController constant CONTROLLER = IController(0x59E16fcCd424Cc24e280Be16E11Bcd56fb0CE547);
    IWrapperS constant WRAPPER = IWrapperS(NAME_WRAPPER);
    uint256 constant GRACE = 90 days;
    uint16 constant CANNOT_UNWRAP = 1;
    uint32 constant PARENT_CANNOT_CONTROL = 1 << 16;

    string constant G_LABEL = "erc8107-sub-gate";
    string constant M_LABEL = "erc8107-sub-m";
    string constant P_LABEL = "erc8107-sub-parent";
    string constant Q_LABEL = "erc8107-sub-plain";

    uint256 constant G_KEY = uint256(keccak256("erc-8107 sub G"));
    uint256 constant M_KEY = uint256(keccak256("erc-8107 sub M"));
    uint256 constant P_KEY = uint256(keccak256("erc-8107 sub P"));
    uint256 constant S_KEY = uint256(keccak256("erc-8107 sub S"));
    uint256 constant B_KEY = uint256(keccak256("erc-8107 sub B"));
    address immutable H2 = vm.addr(uint256(keccak256("erc-8107 sub H2")));

    TrustRegistry registry;
    bytes32 G;
    bytes32 M;
    bytes32 P;
    bytes32 Q;
    uint64 firstBlock;
    mapping(bytes32 => string[]) labelsOf;

    function setUp() public {
        if (block.chainid != 1 || block.number != PINNED_BLOCK) vm.skip(true);
        registry = new TrustRegistry(ENS, NAME_WRAPPER);
        G = _name2LD(G_LABEL);
        M = _name2LD(M_LABEL);
        P = _name2LD(P_LABEL);
        Q = _name2LD(Q_LABEL);
        assertTrue(BASE.available(uint256(keccak256(bytes(P_LABEL)))), "label unused at the pinned block");
        firstBlock = uint64(block.number) + 1;
        vm.recordLogs();
        _step(block.timestamp);
        _register(G_LABEL, vm.addr(G_KEY), 3650 days);
        _register(M_LABEL, vm.addr(M_KEY), 3650 days);
        _register(P_LABEL, vm.addr(P_KEY), 365 days);
        _register(Q_LABEL, vm.addr(P_KEY), 28 days);
        _nextTx();
        vm.startPrank(vm.addr(P_KEY));
        BASE.setApprovalForAll(NAME_WRAPPER, true);
        WRAPPER.wrapETH2LD(P_LABEL, vm.addr(P_KEY), CANNOT_UNWRAP, address(0));
        vm.stopPrank();
        _pushRecorded();
    }

    // ── harness ────────────────────────────────────────────────────────────────

    function _step(uint256 t) internal {
        vm.warp(t);
        vm.roll(block.number + 1);
        _beginBlock(uint64(block.number));
    }

    function _register(string memory label, address owner, uint256 duration) internal {
        Registration memory r = Registration({
            label: label,
            owner: owner,
            duration: duration,
            secret: keccak256(abi.encode(label, owner, block.timestamp)),
            resolver: address(0),
            data: new bytes[](0),
            reverseRecord: 0,
            referrer: bytes32(0)
        });
        _nextTx();
        vm.prank(owner);
        CONTROLLER.commit(CONTROLLER.makeCommitment(r));
        _pushRecorded();
        _step(block.timestamp + CONTROLLER.minCommitmentAge() + 1);
        RentPrice memory p = CONTROLLER.rentPrice(label, duration);
        vm.deal(owner, p.base + p.premium);
        _nextTx();
        vm.prank(owner);
        CONTROLLER.register{value: p.base + p.premium}(r);
        _pushRecorded();
    }

    function _name2LD(string memory label) internal returns (bytes32 node) {
        node = _node(RB.ETH_NODE, label);
        labelsOf[node].push(label);
        labelsOf[node].push("eth");
    }

    /// Records the name of `label`.`parent` for the name proofs
    function _nameBelow(bytes32 parent, string memory label) internal returns (bytes32 node) {
        node = _node(parent, label);
        labelsOf[node].push(label);
        for (uint256 i = 0; i < labelsOf[parent].length; i++) {
            labelsOf[node].push(labelsOf[parent][i]);
        }
    }

    /// DNS wire format of a recorded name, as NameWrapper.wrap takes it
    function _dns(bytes32 node) internal view returns (bytes memory out) {
        string[] storage ls = labelsOf[node];
        for (uint256 i = 0; i < ls.length; i++) {
            out = abi.encodePacked(out, uint8(bytes(ls[i]).length), ls[i]);
        }
        out = abi.encodePacked(out, uint8(0));
    }

    /// The holder of `parent` creates or reassigns `label` in the NameWrapper
    function _subnode(
        uint256 parentKey,
        bytes32 parent,
        string memory label,
        address owner,
        uint32 fuses,
        uint64 expiry
    ) internal returns (bytes32 node) {
        node = labelsOf[_node(parent, label)].length == 0 ? _nameBelow(parent, label) : _node(parent, label);
        _nextTx();
        vm.prank(vm.addr(parentKey));
        WRAPPER.setSubnodeOwner(parent, label, owner, fuses, expiry);
        _pushRecorded();
        assertEq(WRAPPER.ownerOf(uint256(node)), owner, "subname holder");
    }

    function _unwrap(uint256 key, bytes32 parent, string memory label) internal {
        _nextTx();
        vm.prank(vm.addr(key));
        WRAPPER.unwrap(parent, keccak256(bytes(label)), vm.addr(key));
        _pushRecorded();
    }

    function _wrap(uint256 key, bytes32 node) internal {
        _nextTx();
        vm.startPrank(vm.addr(key));
        IRegistryS(ENS).setApprovalForAll(NAME_WRAPPER, true);
        WRAPPER.wrap(_dns(node), vm.addr(key), address(0));
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

    function _p(bytes32 a, bytes32 b) internal pure returns (bytes32[] memory n) {
        n = new bytes32[](2);
        (n[0], n[1]) = (a, b);
    }

    function _p(bytes32 a, bytes32 b, bytes32 c) internal pure returns (bytes32[] memory n) {
        n = new bytes32[](3);
        (n[0], n[1], n[2]) = (a, b, c);
    }

    function _check(bytes32[] memory nodes) internal view returns (RB.Result memory) {
        RB.NameProof[] memory p = new RB.NameProof[](nodes.length);
        for (uint256 i = 0; i < nodes.length; i++) {
            p[i] = _proof(labelsOf[nodes[i]]);
        }
        uint64 head = uint64(block.number);
        return
            RB.evaluate(registry, address(BASE), NAME_WRAPPER, nodes, bytes32(0), p, _history(firstBlock, head), head);
    }

    function _assert(RB.Result memory r, RB.Verdict v, RB.Reason why, uint256 edge, bytes32 node) internal pure {
        assertEq(uint8(r.verdict), uint8(v), "verdict");
        assertEq(uint8(r.reason), uint8(why), "reason");
        assertEq(r.edge, edge, "edge");
        assertEq(r.node, node, "node");
    }

    function _eligible(bytes32[] memory nodes) internal view {
        _assert(_check(nodes), RB.Verdict.Eligible, RB.Reason.None, 0, bytes32(0));
    }

    // ── cases ──────────────────────────────────────────────────────────────────

    /// A subname, as trustee and as trustor, ends with its second-level ancestor's next
    /// registration. Past the grace period with nothing registered it stays eligible:
    /// the check concerns registration, and liveness is a separate check
    function test_AncestorReRegistered() public {
        bytes32 S = _subnode(P_KEY, P, "s", vm.addr(S_KEY), 0, type(uint64).max);
        _attest(G_KEY, G, S);
        _attest(S_KEY, S, M);
        _eligible(_p(G, S, M));

        uint256 pId = uint256(keccak256(bytes(P_LABEL)));
        _step(BASE.nameExpires(pId) + GRACE + 22 days);
        assertTrue(BASE.available(pId), "P available");
        _eligible(_p(G, S, M));

        _register(P_LABEL, H2, 365 days);
        _assert(_check(_p(G, S, M)), RB.Verdict.Ineligible, RB.Reason.ReRegistered, 0, S);
        _assert(_check(_p(S, M)), RB.Verdict.Ineligible, RB.Reason.ReRegistered, 0, S);
    }

    /// A registry-only subname of an unwrapped 2LD: renewals of the ancestor leave it
    /// eligible, and the ancestor's next registration ends it
    function test_UnwrappedSubname_RenewalKeeps_RegistrationEnds() public {
        bytes32 U = _nameBelow(Q, "u");
        _nextTx();
        vm.prank(vm.addr(P_KEY));
        IRegistryS(ENS).setSubnodeOwner(Q, keccak256("u"), vm.addr(S_KEY));
        _pushRecorded();
        _attest(G_KEY, G, U);
        _attest(S_KEY, U, M);

        uint256 qId = uint256(keccak256(bytes(Q_LABEL)));
        for (uint256 i = 0; i < 3; i++) {
            uint256 cost = CONTROLLER.rentPrice(Q_LABEL, 28 days).base;
            vm.deal(address(0xFEE), cost);
            _nextTx();
            vm.prank(address(0xFEE));
            CONTROLLER.renew{value: cost}(Q_LABEL, 28 days, bytes32(0));
            _pushRecorded();
            _step(block.timestamp + 1 days);
        }
        _eligible(_p(G, U, M));

        _step(BASE.nameExpires(qId) + GRACE + 22 days);
        _register(Q_LABEL, vm.addr(P_KEY), 365 days); // the same holder
        _assert(_check(_p(G, U, M)), RB.Verdict.Ineligible, RB.Reason.ReRegistered, 0, U);
    }

    /// An emancipated subname past its NameWrapper expiry, created again by its live
    /// parent for another holder: NameWrapped ends the attestation, and a new signature
    /// restores it
    function test_EmancipatedSubname_RecreatedByLiveParent() public {
        uint64 exp = uint64(block.timestamp + 30 days);
        bytes32 E = _subnode(P_KEY, P, "e", vm.addr(S_KEY), PARENT_CANNOT_CONTROL, exp);
        _attest(G_KEY, G, E);
        _attest(S_KEY, E, M);

        _step(exp + 1);
        assertEq(WRAPPER.ownerOf(uint256(E)), address(0), "E expired");
        _eligible(_p(G, E, M));

        _subnode(P_KEY, P, "e", H2, 0, type(uint64).max);
        _assert(_check(_p(G, E, M)), RB.Verdict.Ineligible, RB.Reason.ReWrapped, 0, E);

        _attest(G_KEY, G, E);
        _eligible(_p(G, E));
        // E -> M was set by the previous holder and stays ineligible
        _assert(_check(_p(G, E, M)), RB.Verdict.Ineligible, RB.Reason.ReWrapped, 1, E);
    }

    /// A parent reassigning a subname that still has a holder emits no NameWrapped. The
    /// attestation stays eligible: the standard treats this as a change of control
    function test_LiveReassignmentByParent_IsChangeOfControl() public {
        bytes32 S = _subnode(P_KEY, P, "s", vm.addr(S_KEY), 0, type(uint64).max);
        _attest(G_KEY, G, S);
        _subnode(P_KEY, P, "s", H2, 0, type(uint64).max);
        _eligible(_p(G, S));
    }

    /// An ancestor below the 2LD unwrapped and wrapped again ends attestations to the
    /// names below it. Unwrapping alone emits no NameWrapped
    function test_ReWrappedAncestorBelow2LD() public {
        bytes32 A = _subnode(P_KEY, P, "a", vm.addr(S_KEY), 0, type(uint64).max);
        bytes32 B = _subnode(S_KEY, A, "b", vm.addr(B_KEY), 0, type(uint64).max);
        _attest(G_KEY, G, B);
        _attest(B_KEY, B, M);
        _eligible(_p(G, B, M));

        _unwrap(S_KEY, P, "a");
        assertEq(IRegistryS(ENS).owner(A), vm.addr(S_KEY), "A unwrapped");
        _eligible(_p(G, B, M));

        _wrap(S_KEY, A);
        _assert(_check(_p(G, B, M)), RB.Verdict.Ineligible, RB.Reason.ReWrapped, 0, B);
    }

    /// The holder unwraps its subname and wraps it again: its trustors sign again
    function test_UnwrapThenWrap_SignAgain() public {
        bytes32 S = _subnode(P_KEY, P, "s", vm.addr(S_KEY), 0, type(uint64).max);
        _attest(G_KEY, G, S);
        _unwrap(S_KEY, P, "s");
        _wrap(S_KEY, S);
        assertEq(WRAPPER.ownerOf(uint256(S)), vm.addr(S_KEY), "same holder");
        _assert(_check(_p(G, S)), RB.Verdict.Ineligible, RB.Reason.ReWrapped, 0, S);

        _attest(G_KEY, G, S);
        _eligible(_p(G, S));
    }

    /// A sibling created under the same parent, an unwrap, and a child of the name wrapped
    /// for the first time leave its attestations alone
    function test_SiblingAndChildWrapIgnored() public {
        bytes32 S = _subnode(P_KEY, P, "s", vm.addr(S_KEY), 0, type(uint64).max);
        _attest(G_KEY, G, S);
        _subnode(P_KEY, P, "sibling", H2, 0, type(uint64).max);
        _unwrap(S_KEY, P, "s");
        bytes32 C = _nameBelow(S, "c");
        _nextTx();
        vm.startPrank(vm.addr(S_KEY));
        IRegistryS(ENS).setSubnodeOwner(S, keccak256("c"), vm.addr(S_KEY));
        IRegistryS(ENS).setApprovalForAll(NAME_WRAPPER, true);
        WRAPPER.wrap(_dns(C), vm.addr(S_KEY), address(0)); // a child of S, not S
        vm.stopPrank();
        _pushRecorded();
        _eligible(_p(G, S));
    }

    /// A proof that does not hash to the node, such as one that drops a label, fails closed
    function test_NameProofWithoutAncestorFailsClosed() public {
        bytes32 S = _subnode(P_KEY, P, "s", vm.addr(S_KEY), 0, type(uint64).max);
        _attest(G_KEY, G, S);
        RB.NameProof[] memory p = new RB.NameProof[](2);
        p[0] = _proof(G_LABEL);
        p[1] = _proof("s"); // "s.eth"
        uint64 head = uint64(block.number);
        _assert(
            RB.evaluate(
                registry, address(BASE), NAME_WRAPPER, _p(G, S), bytes32(0), p, _history(firstBlock, head), head
            ),
            RB.Verdict.Unknown,
            RB.Reason.NameProofMismatch,
            1,
            S
        );
    }
}
