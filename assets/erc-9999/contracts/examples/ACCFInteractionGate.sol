// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "../interfaces/ACCFTypes.sol";
import {IACCFUnits} from "../interfaces/IACCFUnits.sol";
import {IACCFStatements} from "../interfaces/IACCFStatements.sol";

/// @title ACCFInteractionGate
/// @notice Example consumer, not part of the specification. Two units agree on terms under a rule set they
///         both declare for a function, an authorized actor of each side takes each step, and the exchange
///         ends in a receipt. A step that cannot go ahead is refused with a recorded ground instead of a
///         revert, so that a refusal is part of the record of the interaction.
/// @dev    It shows three things a consumer has to check for itself: that the two sides are compatible on the
///         function at hand, that the acting account is authorized for its side on this path, and, when the
///         gate was deployed with a policy, that both sides are cell-complete under that policy.
contract ACCFInteractionGate {
    /// @dev Application scope an actor needs on its unit to act through this gate.
    uint256 public constant SCOPE_INTERACT = uint256(1) << 128;

    enum Refusal {
        None,
        UnknownBinding, // a side declared no rule set for the function
        Incompatible, // the declared rule sets do not match and neither side declared an adaptation
        NotAuthorized, // the acting account holds no authorization for its side on this path
        NotComplete // a side is not cell-complete under the gate's policy
    }

    enum Stage {
        None,
        Offered,
        Accepted,
        Delivered,
        Receipted
    }

    struct Binding {
        bytes32 standard; // identifier of the rule set, for example keccak256("ERC-8414")
        uint32 version;
    }

    struct Interaction {
        bytes32 initiator;
        bytes32 responder;
        bytes32 slot;
        bytes32 termsHash;
        bytes32 deliveryHash;
        bytes32 receiptHash;
        Stage stage;
    }

    IACCFUnits public immutable units;
    IACCFStatements public immutable statements;
    /// @notice Policy both sides are evaluated under; zero when the gate does not ask for completeness.
    bytes32 public immutable policyId;

    mapping(bytes32 => mapping(bytes32 => Binding)) private _bindings;
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => bool))) private _adaptations;
    mapping(bytes32 => Interaction) private _interactions;
    uint256 private _nonce;

    event BindingDeclared(bytes32 indexed unitId, bytes32 indexed slot, bytes32 standard, uint32 version);
    event AdaptationDeclared(bytes32 indexed unitId, bytes32 indexed slot, bytes32 standard, uint32 version, bool supported);
    event Offered(
        bytes32 indexed interactionId, bytes32 indexed initiator, bytes32 indexed responder, bytes32 slot, bytes32 termsHash, address actor
    );
    event Accepted(bytes32 indexed interactionId, address actor);
    event Delivered(bytes32 indexed interactionId, bytes32 deliveryHash, address actor);
    event Receipted(bytes32 indexed interactionId, bytes32 receiptHash, address actor);
    event Refused(
        bytes32 indexed initiator, bytes32 indexed responder, bytes32 indexed slot, Refusal ground, address actor
    );

    error NotController(bytes32 unitId, address account);
    error WrongStage(bytes32 interactionId);

    constructor(address unitRegistry, address statementRegistry, bytes32 policy) {
        units = IACCFUnits(unitRegistry);
        statements = IACCFStatements(statementRegistry);
        policyId = policy;
    }

    /// @notice Declares the rule set `unitId` uses for the function `slot`. Controller or manifest operator.
    function declareBinding(bytes32 unitId, bytes32 slot, bytes32 standard, uint32 version) external {
        if (!units.isAuthorized(unitId, msg.sender, T.SCOPE_MANIFEST)) revert NotController(unitId, msg.sender);
        _bindings[unitId][slot] = Binding(standard, version);
        emit BindingDeclared(unitId, slot, standard, version);
    }

    /// @notice Declares that `unitId` can also work with a counterparty that uses another rule set for `slot`.
    function declareAdaptation(bytes32 unitId, bytes32 slot, bytes32 standard, uint32 version, bool supported) external {
        if (!units.isAuthorized(unitId, msg.sender, T.SCOPE_MANIFEST)) revert NotController(unitId, msg.sender);
        _adaptations[unitId][slot][keccak256(abi.encode(standard, version))] = supported;
        emit AdaptationDeclared(unitId, slot, standard, version, supported);
    }

    /// @notice Offers terms from `initiator` to `responder` for the function `slot`.
    /// @return interactionId Zero when the offer was refused.
    function offer(bytes32 initiator, bytes32 responder, bytes32 slot, bytes32 termsHash)
        external
        returns (bytes32 interactionId, Refusal ground)
    {
        ground = _check(initiator, responder, slot, initiator);
        if (ground != Refusal.None) {
            emit Refused(initiator, responder, slot, ground, msg.sender);
            return (bytes32(0), ground);
        }
        interactionId = keccak256(abi.encode(block.chainid, address(this), ++_nonce));
        _interactions[interactionId] = Interaction({
            initiator: initiator,
            responder: responder,
            slot: slot,
            termsHash: termsHash,
            deliveryHash: bytes32(0),
            receiptHash: bytes32(0),
            stage: Stage.Offered
        });
        emit Offered(interactionId, initiator, responder, slot, termsHash, msg.sender);
    }

    /// @notice The responder accepts the offered terms.
    function accept(bytes32 interactionId) external returns (Refusal ground) {
        Interaction storage x = _interactions[interactionId];
        if (x.stage != Stage.Offered) revert WrongStage(interactionId);
        ground = _check(x.initiator, x.responder, x.slot, x.responder);
        if (ground != Refusal.None) {
            emit Refused(x.initiator, x.responder, x.slot, ground, msg.sender);
            return ground;
        }
        x.stage = Stage.Accepted;
        emit Accepted(interactionId, msg.sender);
    }

    /// @notice The responder records what it delivered.
    function deliver(bytes32 interactionId, bytes32 deliveryHash) external returns (Refusal ground) {
        Interaction storage x = _interactions[interactionId];
        if (x.stage != Stage.Accepted) revert WrongStage(interactionId);
        if (!units.isAuthorized(x.responder, msg.sender, SCOPE_INTERACT)) {
            emit Refused(x.initiator, x.responder, x.slot, Refusal.NotAuthorized, msg.sender);
            return Refusal.NotAuthorized;
        }
        x.deliveryHash = deliveryHash;
        x.stage = Stage.Delivered;
        emit Delivered(interactionId, deliveryHash, msg.sender);
    }

    /// @notice The initiator acknowledges the delivery with a receipt.
    function acknowledge(bytes32 interactionId, bytes32 receiptHash) external returns (Refusal ground) {
        Interaction storage x = _interactions[interactionId];
        if (x.stage != Stage.Delivered) revert WrongStage(interactionId);
        if (!units.isAuthorized(x.initiator, msg.sender, SCOPE_INTERACT)) {
            emit Refused(x.initiator, x.responder, x.slot, Refusal.NotAuthorized, msg.sender);
            return Refusal.NotAuthorized;
        }
        x.receiptHash = receiptHash;
        x.stage = Stage.Receipted;
        emit Receipted(interactionId, receiptHash, msg.sender);
    }

    function bindingOf(bytes32 unitId, bytes32 slot) external view returns (Binding memory) {
        return _bindings[unitId][slot];
    }

    function interactionOf(bytes32 interactionId) external view returns (Interaction memory) {
        return _interactions[interactionId];
    }

    /// @notice Whether the two sides can work together on `slot`: the same rule set and version, or an
    ///         adaptation declared by either side for the other side's rule set.
    function compatible(bytes32 a, bytes32 b, bytes32 slot) public view returns (bool known, bool matches) {
        Binding memory x = _bindings[a][slot];
        Binding memory y = _bindings[b][slot];
        if (x.standard == bytes32(0) || y.standard == bytes32(0)) return (false, false);
        if (x.standard == y.standard && x.version == y.version) return (true, true);
        if (_adaptations[a][slot][keccak256(abi.encode(y.standard, y.version))]) return (true, true);
        if (_adaptations[b][slot][keccak256(abi.encode(x.standard, x.version))]) return (true, true);
        return (true, false);
    }

    /// @dev A shared rule set is necessary and not sufficient: authorization and, when asked for,
    ///      completeness are checked on top of it.
    function _check(bytes32 initiator, bytes32 responder, bytes32 slot, bytes32 actingSide) private view returns (Refusal) {
        (bool known, bool matches) = compatible(initiator, responder, slot);
        if (!known) return Refusal.UnknownBinding;
        if (!matches) return Refusal.Incompatible;
        if (!units.isAuthorized(actingSide, msg.sender, SCOPE_INTERACT)) return Refusal.NotAuthorized;
        if (policyId != bytes32(0)) {
            if (!statements.isCellComplete(initiator, policyId) || !statements.isCellComplete(responder, policyId)) {
                return Refusal.NotComplete;
            }
        }
        return Refusal.None;
    }
}
