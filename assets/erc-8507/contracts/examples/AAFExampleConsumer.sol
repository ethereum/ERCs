// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAAFGuard} from "../interfaces/IAAFGuard.sol";
import {Outcome, Disposition, SubjectRef} from "../interfaces/AAFTypes.sol";

/// @title Example consumer
/// @notice The smallest contract that puts a binding to use: a venue whose actions (bidding for a
/// task, joining a group, invoking a service) go through the guard before they take effect.
/// The deployer becomes the adopter: it writes the bindings that govern this contract.
/// A refused request does not revert, so that the refusal is on record.
/// The decision is taken in the call that carries out the action, and it is used for that action
/// and for nothing else: a venue through which value moves checks the amount, the target and the
/// call data of the operation itself, which no list decides.
contract AAFExampleConsumer {
    IAAFGuard public immutable guard;
    string public name;

    /// @notice The limit this venue applies under PROCEED_RESTRICTED: an action is carried out at
    /// most this many times for a subject in a context. The limit is applied here, in the call
    /// that carries out the action, which is what entitles a binding of this venue to declare
    /// PROCEED_RESTRICTED at all.
    uint256 public constant RESTRICTED_LIMIT = 1;

    bytes32 internal constant R_LIMIT_REACHED = "LIMIT_REACHED";

    /// @dev How often an action was carried out for a subject in a context, how often of these
    /// under a restriction, and how often it was not carried out.
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => uint256))) public done;
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => uint256))) public restricted;
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => uint256))) public refused;

    event Carried(bytes32 indexed context, bytes32 indexed action, bytes32 indexed subjectKey, address presenter, bool restricted);
    event Refused(
        bytes32 indexed context,
        bytes32 indexed action,
        bytes32 indexed subjectKey,
        address presenter,
        Outcome outcome,
        Disposition disposition,
        bytes32 reason
    );

    constructor(IAAFGuard guard_, string memory name_) {
        guard = guard_;
        name = name_;
        guard_.setAdopter(msg.sender);
    }

    /// @notice Carries out `action` for `subject` if the binding lets it proceed. The caller is the
    /// presenter: the guard checks that it may act for the subject where the subject is the actor.
    function act(bytes32 bindingId, bytes32 action, bytes32 context, SubjectRef calldata subject, bytes[] calldata evidence)
        external
        returns (Disposition disposition, Outcome outcome, bytes32 reason)
    {
        (disposition, outcome, reason) = guard.enforce(bindingId, subject, msg.sender, action, context, evidence);
        bytes32 key = keccak256(abi.encode(subject.kind, subject.chainId, subject.namespace, subject.id));
        bool limited = disposition == Disposition.PROCEED_RESTRICTED;
        if (limited && restricted[context][action][key] >= RESTRICTED_LIMIT) {
            // The restriction is used up. What the venue does is refuse, and the record says why.
            disposition = Disposition.REFUSE;
            reason = R_LIMIT_REACHED;
        }
        if (disposition == Disposition.PROCEED || disposition == Disposition.PROCEED_RESTRICTED) {
            done[context][action][key] += 1;
            if (limited) restricted[context][action][key] += 1;
            emit Carried(context, action, key, msg.sender, limited);
        } else {
            refused[context][action][key] += 1;
            emit Refused(context, action, key, msg.sender, outcome, disposition, reason);
        }
    }
}
