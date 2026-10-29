// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFDisputeRegistry} from "../interfaces/IADRFDisputeRegistry.sol";
import {IADRFObligationSource} from "../interfaces/IADRFObligationSource.sol";
import {IADRFExecutor} from "../interfaces/IADRFExecutor.sol";
import {ISettlementLedger} from "./DuplicateSettlementVerifier.sol";

/// @title  ADRFServiceEscrow — worked example of a bound business contract (obligation source + executor)
/// @notice A toy escrow for a model API service: a client (any account — an enterprise, a person, an agent)
///         funds a balance and opens a call against a provider (any account that runs the service) under agreed
///         terms that commit a model version; the provider delivers, declaring the version it used, and charges
///         the call. No agent identity, task token or swarm is involved anywhere. Two events of a call are
///         disputable: a settlement (payment obligation of kind LIMIT: charge at most once) and a delivery
///         (result obligation: the deliverable conforms to the terms, including the committed version). The
///         escrow attests event instants, its own adoption deadline (the dispute period of the call), the
///         obligation each event belongs to, the norm (the terms hash, declared at call creation) and the
///         parties. It binds itself to a dispute policy, and as executor it enacts a REFUND ruling within its own
///         authority, idempotently, and reports the enactment. Its NoDecision disposition is the status quo:
///         balances stay where the call left them. The committed version (part of the terms), the version the
///         provider declared and the version actually used are three different things: the first two are on
///         chain, the third is a fact a dispute may have to establish by evidence.
contract ADRFServiceEscrow is IADRFObligationSource, IADRFExecutor, ISettlementLedger {
    uint8 public constant KIND_RESULT = 1;
    uint8 public constant KIND_PROCESS = 2;
    uint8 public constant KIND_LIMIT = 3;
    uint8 public constant KIND_STATISTICAL = 4;

    bytes32 public constant EVENT_SETTLEMENT = keccak256("settlement");
    bytes32 public constant EVENT_DELIVERY = keccak256("delivery");
    bytes32 public constant EFFECT_REFUND = keccak256("adrf:effect/refund");
    bytes32 public constant DISPOSITION_STATUS_QUO = keccak256("adrf:disposition/status-quo");

    struct Call {
        address client;
        address provider;
        uint256 amount;
        bytes32 termsHash;
        bytes32 committedVersion;  // the model version the terms commit the provider to
        bytes32 declaredVersion;   // the version the provider declared at delivery (0 until delivered)
        uint64  createdAt;
        uint64  deliveredAt;
        uint64  lastSettledAt;
        uint64  disputePeriod;
        uint32  settlements;
    }

    IADRFDisputeRegistry public immutable adrf;
    address public immutable admin;
    bytes32 public bindingId;

    uint256 public nextCallId = 1;
    mapping(uint256 => Call) public calls;
    mapping(address => uint256) public balanceOf;
    mapping(bytes32 => bool) public refunded; // caseId => enacted

    event CallOpened(uint256 indexed callId, address indexed client, address indexed provider, uint256 amount, bytes32 termsHash, bytes32 committedVersion);
    event Delivered(uint256 indexed callId, uint64 at, bytes32 declaredVersion);
    event Settled(uint256 indexed callId, uint32 count, uint64 at);
    event Refunded(bytes32 indexed caseId, uint256 indexed callId, uint256 amount);

    error Escrow_NotAdmin();
    error Escrow_NotProvider();
    error Escrow_Insufficient();
    error Escrow_UnknownCall();
    error Escrow_NotBound();
    error Escrow_NotEnactable(bytes32 caseId);

    constructor(IADRFDisputeRegistry adrf_) {
        adrf = adrf_;
        admin = msg.sender;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 || interfaceId == type(IADRFObligationSource).interfaceId;
    }

    // ------------------------------------------------------------------ business

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdrawBalance(uint256 amount) external {
        if (balanceOf[msg.sender] < amount) revert Escrow_Insufficient();
        balanceOf[msg.sender] -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer");
    }

    /// Opens a call under the given terms. `committedVersion` is the model version the terms commit the provider
    /// to (part of the norm, declared before any event of the call).
    function openCall(address provider, uint256 amount, bytes32 termsHash, bytes32 committedVersion, uint64 disputePeriod)
        external returns (uint256 callId)
    {
        callId = nextCallId++;
        calls[callId] = Call({
            client: msg.sender, provider: provider, amount: amount, termsHash: termsHash,
            committedVersion: committedVersion, declaredVersion: bytes32(0),
            createdAt: uint64(block.timestamp), deliveredAt: 0, lastSettledAt: 0,
            disputePeriod: disputePeriod, settlements: 0
        });
        emit CallOpened(callId, msg.sender, provider, amount, termsHash, committedVersion);
    }

    /// The provider delivers and declares the version it used. The declaration is the provider's statement, not
    /// a fact: whether the service actually ran that version is what a dispute may have to establish.
    function deliver(uint256 callId, bytes32 declaredVersion) external {
        Call storage c = _call(callId);
        if (msg.sender != c.provider) revert Escrow_NotProvider();
        c.deliveredAt = uint64(block.timestamp);
        c.declaredVersion = declaredVersion;
        emit Delivered(callId, c.deliveredAt, declaredVersion);
    }

    function versionsOf(uint256 callId) external view returns (bytes32 committed, bytes32 declared) {
        Call storage c = calls[callId];
        return (c.committedVersion, c.declaredVersion);
    }

    /// Charges the client's balance for the call. Nothing stops a provider from charging twice: that is the
    /// business bug the formal dispute of the worked example catches.
    function settle(uint256 callId) external {
        Call storage c = _call(callId);
        if (msg.sender != c.provider) revert Escrow_NotProvider();
        if (balanceOf[c.client] < c.amount) revert Escrow_Insufficient();
        balanceOf[c.client] -= c.amount;
        balanceOf[c.provider] += c.amount;
        c.settlements += 1;
        c.lastSettledAt = uint64(block.timestamp);
        emit Settled(callId, c.settlements, c.lastSettledAt);
    }

    function settlementCount(uint256 callId) external view returns (uint32) {
        return calls[callId].settlements;
    }

    // ------------------------------------------------------------------ binding (admin)

    function bindTo(T.BindingInput calldata input) external returns (bytes32) {
        if (msg.sender != admin) revert Escrow_NotAdmin();
        bindingId = adrf.bind(input);
        return bindingId;
    }

    function revokeBinding() external {
        if (msg.sender != admin) revert Escrow_NotAdmin();
        adrf.revokeBinding(bindingId);
    }

    // ------------------------------------------------------------------ obligation source

    function objectOf(uint256 callId) public view returns (T.ObjectRef memory) {
        Call storage c = calls[callId];
        return T.ObjectRef({chainId: block.chainid, target: address(this), id: callId, versionHash: keccak256(abi.encode(callId, c.termsHash, c.committedVersion))});
    }

    function eventInfo(T.ObjectRef calldata object, bytes32 eventRef) external view returns (T.EventInfo memory info) {
        if (object.target != address(this) || object.chainId != block.chainid) return info;
        Call storage c = calls[object.id];
        if (c.client == address(0)) return info;
        if (object.versionHash != keccak256(abi.encode(object.id, c.termsHash, c.committedVersion))) return info;
        info.normRef = c.termsHash;
        info.normDeclaredAt = c.createdAt;
        if (eventRef == EVENT_SETTLEMENT && c.lastSettledAt != 0) {
            info.known = true;
            info.eventAt = c.lastSettledAt;
            info.adoptionDeadline = c.lastSettledAt + c.disputePeriod;
            info.obligationRef = keccak256(abi.encode(object.id, "payment"));
            info.obligationKind = KIND_LIMIT;
        } else if (eventRef == EVENT_DELIVERY && c.deliveredAt != 0) {
            info.known = true;
            info.eventAt = c.deliveredAt;
            info.adoptionDeadline = c.deliveredAt + c.disputePeriod;
            info.obligationRef = keccak256(abi.encode(object.id, "delivery"));
            info.obligationKind = KIND_RESULT;
        }
    }

    function isParty(T.ObjectRef calldata object, bytes32, address account) external view returns (bool) {
        if (object.target != address(this)) return false;
        Call storage c = calls[object.id];
        return account != address(0) && (account == c.client || account == c.provider);
    }

    // ------------------------------------------------------------------ executor

    /// Enacts a Final REFUND ruling on a call of this escrow: a sustained payment claim refunds one charge, a
    /// sustained delivery claim refunds the call amount. The executor checks finality, effect class, the allowed
    /// effect, its own object, the remaining provider balance and its own anti-duplication record; it reports
    /// Enacted or Failed and never touches the ruling.
    function enact(bytes32 caseId, bytes32 effectId) external {
        if (bindingId == bytes32(0)) revert Escrow_NotBound();
        T.Ruling memory u = adrf.getRuling(caseId);
        T.CaseHeader memory h = adrf.getCase(caseId);
        if (u.state != T.ProcedureState.Final || u.effectClass != T.EffectClass.Binding) revert Escrow_NotEnactable(caseId);
        if (effectId != EFFECT_REFUND || u.allowedEffect != EFFECT_REFUND) revert Escrow_NotEnactable(caseId);
        if (h.source != address(this) || h.object.target != address(this) || h.bindingId != bindingId) revert Escrow_NotEnactable(caseId);
        if (refunded[caseId]) revert Escrow_NotEnactable(caseId);

        Call storage c = calls[h.object.id];
        uint256 amount = c.amount;
        if (balanceOf[c.provider] < amount) {
            adrf.reportEnactment(caseId, EFFECT_REFUND, T.EnactmentStatus.Failed, keccak256("provider balance insufficient"));
            return;
        }
        refunded[caseId] = true;
        balanceOf[c.provider] -= amount;
        balanceOf[c.client] += amount;
        emit Refunded(caseId, h.object.id, amount);
        adrf.reportEnactment(caseId, EFFECT_REFUND, T.EnactmentStatus.Enacted, keccak256(abi.encode(h.object.id, amount)));
    }

    function _call(uint256 callId) private view returns (Call storage c) {
        c = calls[callId];
        if (c.client == address(0)) revert Escrow_UnknownCall();
    }
}
