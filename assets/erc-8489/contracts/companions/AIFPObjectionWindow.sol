// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IAIFPChannelRegistry} from "../interfaces/IAIFPChannelRegistry.sol";
import {IAIFPParticipationRegistry} from "../interfaces/IAIFPParticipationRegistry.sol";
import {IERC6372} from "../interfaces/IERC6372.sol";
import {AIFPRoles} from "../libraries/AIFPRoles.sol";
import {AIFPOutcomes} from "../libraries/AIFPOutcomes.sol";
import {AIFPSubject} from "../libraries/AIFPSubject.sol";

/// @title AIFPObjectionWindow (companion, not part of the kernel)
/// @notice Absence semantics done honestly. A proposer opens an authoritative objection window agreed in
///         advance by the channel's rules; holders of the objection role register objections inside the
///         window; after the deadline `resolve` reports one of:
///           DEFAULT_TRIGGERED  no valid objection was registered in a complete window,
///           OBJECTED           at least one valid objection was registered,
///           UNDETERMINABLE     the window's integrity cannot be confirmed (it was not open for its whole
///                              duration, or the channel was not active throughout).
///         DEFAULT_TRIGGERED proves that the agreed condition occurred. It proves neither that any
///         participant read the proposal nor that anyone consented.
contract AIFPObjectionWindow {
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
        bool integrityBroken;
    }

    IAIFPChannelRegistry public immutable channelRegistry;
    IAIFPParticipationRegistry public immutable participationRegistry;

    Window[] private _windows;
    mapping(uint256 => mapping(bytes32 => bool)) public objected; // windowId => subject => objected

    event WindowOpened(uint256 indexed windowId, bytes32 indexed channelId, bytes32 indexed proposalRef, bytes32 proposer, uint48 start, uint48 deadline, uint16 objectionRole);
    event ObjectionRegistered(uint256 indexed windowId, bytes32 indexed subject, bytes32 reasonRef, uint48 at);
    event IntegrityBroken(uint256 indexed windowId, uint48 at);
    event WindowResolved(uint256 indexed windowId, uint8 status, uint32 objections);

    error NotOpen();
    error OutsideWindow();
    error RoleNotHeld();
    error AlreadyObjected();
    error NotYetDue();
    error InvalidWindow();

    constructor(IAIFPChannelRegistry channelRegistry_, IAIFPParticipationRegistry participationRegistry_) {
        channelRegistry = channelRegistry_;
        participationRegistry = participationRegistry_;
    }

    function clock() public view returns (uint48) {
        return IERC6372(address(channelRegistry)).clock();
    }

    /// @notice Opens a window. `start` may not precede the opening (a window cannot cover a period in
    ///         which objections could not have been registered).
    function open(bytes32 channelId, bytes32 proposalRef, uint48 start, uint48 deadline, uint16 objectionRole)
        external
        returns (uint256 windowId)
    {
        uint48 now_ = clock();
        if (start < now_ || deadline <= start) revert InvalidWindow();
        bytes32 proposer = AIFPSubject.self(msg.sender);
        if (participationRegistry.evaluate(channelId, proposer, AIFPRoles.SUBMIT, bytes32(0), now_) != AIFPOutcomes.SATISFIED) revert RoleNotHeld();
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
                integrityBroken: false
            })
        );
        windowId = _windows.length - 1;
        emit WindowOpened(windowId, channelId, proposalRef, proposer, start, deadline, objectionRole);
    }

    function object(uint256 windowId, bytes32 reasonRef) external {
        Window storage w = _windows[windowId];
        if (w.status != STATUS_OPEN) revert NotOpen();
        uint48 now_ = clock();
        if (now_ < w.start || now_ >= w.deadline) revert OutsideWindow();
        bytes32 subject = AIFPSubject.self(msg.sender);
        if (participationRegistry.evaluate(w.channelId, subject, w.objectionRole, bytes32(0), now_) != AIFPOutcomes.SATISFIED) revert RoleNotHeld();
        if (objected[windowId][subject]) revert AlreadyObjected();
        objected[windowId][subject] = true;
        w.objections++;
        emit ObjectionRegistered(windowId, subject, reasonRef, now_);
    }

    /// @notice Anyone may flag that the window was not observable for its whole duration (for example the
    ///         channel was frozen). The flag is checked against the channel state at call time.
    function reportIntegrityBreak(uint256 windowId) external {
        Window storage w = _windows[windowId];
        if (w.status != STATUS_OPEN) revert NotOpen();
        uint48 now_ = clock();
        if (now_ < w.start || now_ >= w.deadline) revert OutsideWindow();
        if (channelRegistry.channel(w.channelId).state == IAIFPChannelRegistry.ChannelState.Active) revert InvalidWindow();
        w.integrityBroken = true;
        emit IntegrityBroken(windowId, now_);
    }

    function resolve(uint256 windowId) external returns (uint8 status) {
        Window storage w = _windows[windowId];
        if (w.status != STATUS_OPEN) revert NotOpen();
        uint48 now_ = clock();
        if (now_ < w.deadline) revert NotYetDue();
        if (w.integrityBroken || channelRegistry.channel(w.channelId).state != IAIFPChannelRegistry.ChannelState.Active) {
            status = STATUS_UNDETERMINABLE;
        } else if (w.objections > 0) {
            status = STATUS_OBJECTED;
        } else {
            status = STATUS_DEFAULT_TRIGGERED;
        }
        w.status = status;
        emit WindowResolved(windowId, status, w.objections);
    }

    function window(uint256 windowId) external view returns (Window memory) {
        return _windows[windowId];
    }

    function windowCount() external view returns (uint256) {
        return _windows.length;
    }
}
