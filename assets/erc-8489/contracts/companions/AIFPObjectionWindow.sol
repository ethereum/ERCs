// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAIFPChannelRegistry} from "../interfaces/IAIFPChannelRegistry.sol";
import {IAIFPParticipationRegistry} from "../interfaces/IAIFPParticipationRegistry.sol";
import {IERC6372} from "../interfaces/IERC6372.sol";
import {AIFPRoles} from "../libraries/AIFPRoles.sol";
import {AIFPOutcomes} from "../libraries/AIFPOutcomes.sol";
import {AIFPSubject} from "../libraries/AIFPSubject.sol";

/// @dev What the companion needs beyond the kernel interface: a way to tell that the state of a channel has
///      not changed between two positions in the chain. The reference channel registry counts state changes
///      (`AIFPChannelRegistry.stateChanges`); IAIFPChannelRegistry itself exposes the current state only.
interface IAIFPChannelStateChanges {
    function stateChanges(bytes32 channelId) external view returns (uint32);
}

/// @title AIFPObjectionWindow (companion, not part of the kernel)
/// @notice Absence semantics done honestly. A proposer opens an objection window on a proposal; holders of
///         the objection role register objections inside the window; after the deadline `resolve` reports
///         one of:
///           OBJECTED           at least one valid objection was registered inside the window (an objection
///                              is a recorded fact and counts whatever else happened to the channel),
///           DEFAULT_TRIGGERED  no objection was registered and the integrity of the window is confirmed,
///           UNDETERMINABLE     no objection was registered and the integrity cannot be confirmed.
///         DEFAULT_TRIGGERED proves that the agreed condition occurred. It proves neither that any
///         participant read the proposal nor that anyone consented.
/// @dev Integrity is confirmed, not presumed: the channel has to be Active when the window is opened and
///      when it is resolved, and its state must not have changed in between (`stateChanges` is the same at
///      both positions), which shows that the channel was Active throughout the window. The condition is
///      stricter than "active from start to deadline": a state change before the start or after the deadline
///      also leaves the integrity unconfirmed, because the count says that the state changed and not when.
///      A window is therefore best resolved soon after its deadline. Whatever cannot be seen on chain - a
///      transport that was unreachable, a proposal that was never served - is outside this contract.
///
///      The window records the proposal by reference: the default consequence is part of what `proposalRef`
///      identifies, and it is carried out by the channel's own rules, not by this contract. Whether the
///      role, the length and the default of a window are the ones the channel's paradigm declares under
///      `extensions.absence` is for readers to check against the descriptor; the contract only requires the
///      proposer to hold SUBMIT for the whole channel.
///
///      Opening a window and registering an objection are decisions taken when the transaction executes.
///      Their events name the role binding that satisfied the check, like the records of the event-anchor
///      profile: a binding revoked or suspended later within the same timepoint no longer evaluates as
///      SATISFIED at that timepoint, and the objection it supported still counts.
contract AIFPObjectionWindow {
    // Status of a window. These are not outcome codes (AIFPOutcomes): the numbers do not correspond.
    uint8 public constant STATUS_OPEN = 0;
    uint8 public constant STATUS_DEFAULT_TRIGGERED = 1;
    uint8 public constant STATUS_OBJECTED = 2;
    uint8 public constant STATUS_UNDETERMINABLE = 3;

    struct Window {
        bytes32 channelId;
        bytes32 proposalRef;
        bytes32 proposer;
        uint16 objectionRole;
        uint48 start;
        uint48 deadline;
        uint48 openedAt;
        uint32 objections;
        uint8 status;
        uint32 stateChangesAtOpen; // the channel's count of state changes when the window was opened
    }

    IAIFPChannelRegistry public immutable channelRegistry;
    IAIFPParticipationRegistry public immutable participationRegistry;

    Window[] private _windows;
    mapping(uint256 => mapping(bytes32 => bool)) public objected; // windowId => subject => objected

    event WindowOpened(
        uint256 indexed windowId,
        bytes32 indexed channelId,
        bytes32 indexed proposalRef,
        bytes32 proposer,
        bytes32 bindingId,
        uint48 openedAt,
        uint48 start,
        uint48 deadline,
        uint16 objectionRole
    );
    event ObjectionRegistered(uint256 indexed windowId, bytes32 indexed subject, bytes32 reasonRef, bytes32 bindingId, uint48 at);
    event WindowResolved(uint256 indexed windowId, uint8 status, uint32 objections);

    error NotOpen();
    error OutsideWindow();
    error RoleNotHeld(uint8 outcome);
    error AlreadyObjected();
    error NotYetDue();
    error InvalidWindow();
    error ChannelNotActive();

    constructor(IAIFPChannelRegistry channelRegistry_, IAIFPParticipationRegistry participationRegistry_) {
        channelRegistry = channelRegistry_;
        participationRegistry = participationRegistry_;
    }

    function clock() public view returns (uint48) {
        return IERC6372(address(channelRegistry)).clock();
    }

    /// @notice Opens a window. `start` may not precede the opening (a window cannot cover a period in
    ///         which objections could not have been registered), `objectionRole` has to be a single defined
    ///         role bit (otherwise no objection could ever be registered and the default would follow from
    ///         a window nobody could object to), the channel has to be Active, and the proposer has to hold
    ///         SUBMIT for the whole channel.
    function open(bytes32 channelId, bytes32 proposalRef, uint48 start, uint48 deadline, uint16 objectionRole)
        external
        returns (uint256 windowId)
    {
        uint48 now_ = clock();
        if (start < now_ || deadline <= start) revert InvalidWindow();
        if (!AIFPRoles.isSingle(objectionRole)) revert InvalidWindow();
        if (!_isActive(channelId)) revert ChannelNotActive();
        bytes32 proposer = AIFPSubject.self(msg.sender);
        bytes32 bindingId = _requireRole(channelId, proposer, AIFPRoles.SUBMIT, now_);
        _windows.push(
            Window({
                channelId: channelId,
                proposalRef: proposalRef,
                proposer: proposer,
                objectionRole: objectionRole,
                start: start,
                deadline: deadline,
                openedAt: now_,
                objections: 0,
                status: STATUS_OPEN,
                stateChangesAtOpen: _stateChanges(channelId)
            })
        );
        windowId = _windows.length - 1;
        emit WindowOpened(windowId, channelId, proposalRef, proposer, bindingId, now_, start, deadline, objectionRole);
    }

    function object(uint256 windowId, bytes32 reasonRef) external {
        Window storage w = _windows[windowId];
        if (w.status != STATUS_OPEN) revert NotOpen();
        uint48 now_ = clock();
        if (now_ < w.start || now_ >= w.deadline) revert OutsideWindow();
        bytes32 subject = AIFPSubject.self(msg.sender);
        bytes32 bindingId = _requireRole(w.channelId, subject, w.objectionRole, now_);
        if (objected[windowId][subject]) revert AlreadyObjected();
        objected[windowId][subject] = true;
        w.objections++;
        emit ObjectionRegistered(windowId, subject, reasonRef, bindingId, now_);
    }

    /// @notice True while the integrity of the window can still be confirmed: the channel is Active and its
    ///         state has not changed since the window was opened. Once false it stays false.
    function integrityHolds(uint256 windowId) public view returns (bool) {
        Window storage w = _windows[windowId];
        return _isActive(w.channelId) && _stateChanges(w.channelId) == w.stateChangesAtOpen;
    }

    function resolve(uint256 windowId) external returns (uint8 status) {
        Window storage w = _windows[windowId];
        if (w.status != STATUS_OPEN) revert NotOpen();
        uint48 now_ = clock();
        if (now_ < w.deadline) revert NotYetDue();
        if (w.objections > 0) {
            status = STATUS_OBJECTED;
        } else if (integrityHolds(windowId)) {
            status = STATUS_DEFAULT_TRIGGERED;
        } else {
            status = STATUS_UNDETERMINABLE;
        }
        w.status = status;
        emit WindowResolved(windowId, status, w.objections);
    }

    /// @dev Reverts unless `subject` holds `role` in the whole channel now; returns the binding relied on.
    function _requireRole(bytes32 channelId, bytes32 subject, uint16 role, uint48 now_) internal view returns (bytes32 bindingId) {
        uint8 outcome;
        (outcome, bindingId) = participationRegistry.evaluateWithBinding(channelId, subject, role, bytes32(0), now_);
        if (outcome != AIFPOutcomes.SATISFIED) revert RoleNotHeld(outcome);
    }

    function _isActive(bytes32 channelId) internal view returns (bool) {
        return channelRegistry.channel(channelId).state == IAIFPChannelRegistry.ChannelState.Active;
    }

    function _stateChanges(bytes32 channelId) internal view returns (uint32) {
        return IAIFPChannelStateChanges(address(channelRegistry)).stateChanges(channelId);
    }

    function window(uint256 windowId) external view returns (Window memory) {
        return _windows[windowId];
    }

    function windowCount() external view returns (uint256) {
        return _windows.length;
    }
}
