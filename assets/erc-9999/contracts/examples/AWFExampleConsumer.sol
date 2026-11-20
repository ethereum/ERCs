// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAWFGuard} from "../interfaces/IAWFGuard.sol";
import {Outcome, Disposition, SubjectRef} from "../interfaces/AWFTypes.sol";

/// @title Example consumer
/// @notice The smallest contract that puts a binding to use: a venue whose actions (bidding for a
/// task, joining a group, invoking a service) go through the guard before they take effect.
/// The deployer becomes the adopter: it writes the bindings that govern this contract.
/// A refused request does not revert, so that the refusal is on record.
contract AWFExampleConsumer {
    IAWFGuard public immutable guard;
    string public name;

    /// @dev How often an action was carried out for a subject in a context, and how often it was not.
    mapping(bytes32 => mapping(bytes32 => mapping(bytes32 => uint256))) public done;
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

    constructor(IAWFGuard guard_, string memory name_) {
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
        if (disposition == Disposition.PROCEED || disposition == Disposition.PROCEED_RESTRICTED) {
            done[context][action][key] += 1;
            emit Carried(context, action, key, msg.sender, disposition == Disposition.PROCEED_RESTRICTED);
        } else {
            refused[context][action][key] += 1;
            emit Refused(context, action, key, msg.sender, outcome, disposition, reason);
        }
    }
}
