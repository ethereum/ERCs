// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {ITrustRegistry, TrustLevel, ValidationParams, TrustPath} from "../../contracts/ITrustRegistry.sol";
import {RegistrationBoundary as RB} from "./RegistrationBoundary.sol";

interface IENSOwner {
    function owner(bytes32 node) external view returns (address);
}

interface INameWrapperOwner {
    function ownerOf(uint256 id) external view returns (address);
}

interface IBaseRegistrarExpiry {
    function nameExpires(uint256 id) external view returns (uint256);
    function GRACE_PERIOD() external view returns (uint256);
}

/// @title Reference coordinator (non-normative)
/// @notice One coordinator that applies every check ERC-8107 recommends to a path it
///         relies on, from the decision through execution. `verifyPath` alone is not
///         enough: it reads stored records, not registration history or the control of
///         the names it passes through.
///
///         At the decision, block B, the operator calls `decide` off-chain (`eth_call` at
///         B) with the complete history to B:
///         1. the gate, which validates with `enforceExpiry` set;
///         2. the continuity check under "Wrapped Name Lifecycle", via RegistrationBoundary;
///         3. the liveness check: every wrapped trustor on the path has a controller;
///         and it records the BaseRegistrar expiry at B of every `.eth` second-level name
///         the path depends on, as pins.
///
///         At execution, `execute` applies, in the executing transaction:
///         1. for each pin, the deadline from the pinned expiry, or the expiry unchanged,
///            which together show that no such name has been registered since B;
///         2. the liveness check again, which the gate does not perform for trustors;
///         3. the gate again.
///
///         It does not close the window for a name below a second-level name being wrapped
///         again after B, for which ENSv1 offers no on-chain equivalent, and it does not
///         detect a change of control within a registration (see Monitoring Control
///         Changes) or exclude an address through its aliases (see Address Aliases).
contract ReferenceCoordinator {
    enum Stage {
        Ok,
        Gate,
        Continuity,
        Liveness
    }

    /// The BaseRegistrar expiry the operator read at B for one `.eth` second-level name
    struct ExpiryPin {
        uint256 labelhash;
        uint256 expires;
    }

    error NotOperator();
    error RegisteredSinceDecision(uint256 labelhash);
    error NoController(bytes32 node);
    error GateRejected();

    bytes32 public constant TYPE = keccak256("ERC8107.reference-coordinator");

    ITrustRegistry public immutable registry;
    IENSOwner public immutable ens;
    IBaseRegistrarExpiry public immutable base;
    INameWrapperOwner public immutable nameWrapper; // zero where the network has none
    uint256 public immutable grace;
    address public immutable operator;
    bytes32 public immutable scope;
    uint256 public executions;

    constructor(
        ITrustRegistry registry_,
        IENSOwner ens_,
        IBaseRegistrarExpiry base_,
        INameWrapperOwner nameWrapper_,
        bytes32 gatekeeper,
        ValidationParams memory params
    ) {
        require(params.enforceExpiry, "validate with enforceExpiry set");
        (registry, ens, base, nameWrapper) = (registry_, ens_, base_, nameWrapper_);
        grace = base_.GRACE_PERIOD();
        operator = msg.sender;
        scope = params.scope;
        registry_.setIdentityGate(TYPE, gatekeeper, params);
    }

    /// The decision at the current block. `participant` is zero to identify the
    /// participant by node, the terminal of `nodes`. `h` MUST be the complete history to
    /// this block (see RegistrationBoundary.History)
    function decide(
        address participant,
        bytes32[] memory nodes,
        RB.NameProof[] memory proofs,
        RB.History memory h
    ) external view returns (Stage stage, RB.Result memory continuity, ExpiryPin[] memory pins) {
        if (!_gate(participant, nodes)) return (Stage.Gate, continuity, pins);
        continuity = RB.evaluate(
            RB.Query(registry, address(base), address(nameWrapper), nodes, scope, proofs, uint64(block.number)), h
        );
        if (continuity.verdict != RB.Verdict.Eligible) return (Stage.Continuity, continuity, pins);
        (bool live,) = _live(nodes);
        if (!live) return (Stage.Liveness, continuity, pins);
        return (Stage.Ok, continuity, _pins(proofs));
    }

    /// Executes on a decision `decide` returned `Ok` for. Only the operator may supply
    /// pins: they are its own reading at B, and a caller choosing them would choose the
    /// deadline
    function execute(address participant, bytes32[] calldata nodes, ExpiryPin[] calldata pins) external {
        if (msg.sender != operator) revert NotOperator();
        for (uint256 i = 0; i < pins.length; i++) {
            // A registration needs block.timestamp past the expiry plus grace, and moves
            // the expiry; nothing lowers it. Either condition rules one out since B
            bool inDeadline = block.timestamp <= pins[i].expires + grace;
            if (!inDeadline && base.nameExpires(pins[i].labelhash) != pins[i].expires) {
                revert RegisteredSinceDecision(pins[i].labelhash);
            }
        }
        (bool live, bytes32 dead) = _live(nodes);
        if (!live) revert NoController(dead);
        if (!_gate(participant, nodes)) revert GateRejected();
        executions++;
    }

    function _gate(address participant, bytes32[] memory nodes) internal view returns (bool) {
        if (participant != address(0)) {
            return registry.validateParticipantAddress(address(this), TYPE, participant, TrustPath(nodes));
        }
        return registry.validateParticipantWithPath(address(this), TYPE, nodes[nodes.length - 1], TrustPath(nodes));
    }

    /// Requires a holder in the NameWrapper for every wrapped trustor on the path, that
    /// is every node but the terminal. The gate reads control for the terminal node
    /// only, and only when identifying the participant by address
    function _live(bytes32[] memory nodes) internal view returns (bool, bytes32) {
        if (address(nameWrapper) == address(0)) return (true, bytes32(0));
        for (uint256 i = 0; i + 1 < nodes.length; i++) {
            if (ens.owner(nodes[i]) == address(nameWrapper) && nameWrapper.ownerOf(uint256(nodes[i])) == address(0)) {
                return (false, nodes[i]);
            }
        }
        return (true, bytes32(0));
    }

    /// The `.eth` second-level name of every node under `.eth`, itself or its ancestor.
    /// The proofs are verified against the nodes by the continuity check
    function _pins(RB.NameProof[] memory proofs) internal view returns (ExpiryPin[] memory pins) {
        uint256 n;
        pins = new ExpiryPin[](proofs.length);
        for (uint256 i = 0; i < proofs.length; i++) {
            string[] memory l = proofs[i].labels;
            if (l.length < 2 || keccak256(bytes(l[l.length - 1])) != keccak256("eth")) continue;
            uint256 id = uint256(keccak256(bytes(l[l.length - 2])));
            pins[n++] = ExpiryPin(id, base.nameExpires(id));
        }
        assembly {
            mstore(pins, n)
        }
    }
}
