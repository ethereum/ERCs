// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";
import {IADRFDisputeRegistry} from "../interfaces/IADRFDisputeRegistry.sol";
import {IADRFObligationSource} from "../interfaces/IADRFObligationSource.sol";
import {IADRFExecutor} from "../interfaces/IADRFExecutor.sol";
import {ISettlementLedger, DuplicateSettlementStatement} from "./DuplicateSettlementVerifier.sol";
import {DeclaredVersionStatement} from "./DeclaredVersionVerifier.sol";

/// @title  ADRFServiceEscrow — worked example of a bound business contract (obligation source + executor)
/// @notice A toy escrow for a model API service: a client (any account — an enterprise, a person, an agent)
///         funds a balance and opens a call against a provider (any account that runs the service) under agreed
///         terms that commit a model version; the provider delivers, declaring the version it used, and charges
///         the call. No agent identity, task token or swarm is involved anywhere.
///
///         Two kinds of events of a call are disputable. Every settlement is an event of its own (payment
///         obligation of kind LIMIT: charge at most once, so the second and every later settlement is a breach
///         with its own contested point), and the delivery is an event (result obligation: the deliverable
///         conforms to the terms, including the committed version). The escrow attests event instants, the
///         obligation each event belongs to, the norm (the terms hash, declared at call creation), the parties,
///         which propositions in which direction are breaches under those terms, and its own adoption deadline:
///         each settlement is held in the escrow until `settledAt + disputePeriod`, so that the value a ruling
///         could touch stays enactable until the deadline the escrow attests; only released settlements can be
///         withdrawn by the provider. It binds itself to a dispute policy, and as executor it enacts a REFUND ruling
///         within its own authority, idempotently, and reports the enactment. Its NoDecision disposition is the
///         status quo: balances stay where the call left them. The committed version (part of the terms), the
///         version the provider declared and the version actually used are three different things: the first two
///         are on chain, the third is a fact a dispute may have to establish by evidence.
contract ADRFServiceEscrow is IADRFObligationSource, IADRFExecutor, ISettlementLedger {
    uint8 public constant KIND_RESULT = 1;
    uint8 public constant KIND_PROCESS = 2;
    uint8 public constant KIND_LIMIT = 3;
    uint8 public constant KIND_STATISTICAL = 4;

    bytes32 public constant EVENT_SETTLEMENT = keccak256("settlement");   // tag; the event of settlement n is settlementEventRef(n)
    bytes32 public constant EVENT_DELIVERY = keccak256("delivery");
    bytes32 public constant EFFECT_REFUND = keccak256("adrf:effect/refund");
    bytes32 public constant DISPOSITION_STATUS_QUO = keccak256("adrf:disposition/status-quo");

    /// Statements about a delivery that the terms recognize as breaches of the result obligation when FALSE.
    bytes32 public constant STATEMENT_CONFORMS = keccak256("the deliverable conforms to the acceptance criteria");
    bytes32 public constant STATEMENT_PERFORMED = keccak256("the service was actually performed");
    bytes32 public constant STATEMENT_ACTUAL_VERSION = keccak256("the version actually used for the call matches the committed version");

    enum SettlementState { Held, Released, Refunded }

    struct Settlement {
        uint64 at;
        SettlementState state;
    }

    struct Call {
        address client;
        address provider;
        uint256 amount;
        bytes32 termsHash;
        bytes32 committedVersion;  // the model version the terms commit the provider to
        bytes32 declaredVersion;   // the version the provider declared at delivery (0 until delivered)
        uint64  createdAt;
        uint64  deliveredAt;
        uint64  disputePeriod;
    }

    IADRFDisputeRegistry public immutable adrf;
    address public immutable admin;
    bytes32 public bindingId;

    uint256 public nextCallId = 1;
    mapping(uint256 => Call) public calls;
    mapping(uint256 => Settlement[]) private _settlements;   // index = ordinal - 1
    mapping(address => uint256) public balanceOf;             // deposits, refunds and released settlements
    mapping(bytes32 => bool) public refunded;                 // caseId => enacted

    event CallOpened(uint256 indexed callId, address indexed client, address indexed provider, uint256 amount, bytes32 termsHash, bytes32 committedVersion);
    event Delivered(uint256 indexed callId, uint64 at, bytes32 declaredVersion);
    event Settled(uint256 indexed callId, uint32 ordinal, uint64 at);
    event Released(uint256 indexed callId, uint32 ordinal, uint256 amount);
    event Refunded(bytes32 indexed caseId, uint256 indexed callId, uint32 ordinal, uint256 amount);

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

    /// Withdraws from the free balance: deposits, refunds and settlements released after their dispute period.
    function withdrawBalance(uint256 amount) external {
        if (balanceOf[msg.sender] < amount) revert Escrow_Insufficient();
        balanceOf[msg.sender] -= amount;
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer");
    }

    /// Opens a call under the given terms. `committedVersion` is the model version the terms commit the provider
    /// to (part of the norm, declared before any event of the call). `disputePeriod` is how long each settlement
    /// stays held: the adoption deadline the escrow attests for it.
    function openCall(address provider, uint256 amount, bytes32 termsHash, bytes32 committedVersion, uint64 disputePeriod)
        external returns (uint256 callId)
    {
        callId = nextCallId++;
        calls[callId] = Call({
            client: msg.sender, provider: provider, amount: amount, termsHash: termsHash,
            committedVersion: committedVersion, declaredVersion: bytes32(0),
            createdAt: uint64(block.timestamp), deliveredAt: 0, disputePeriod: disputePeriod
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

    /// Charges the client's balance for the call and holds the charge until its dispute period lapses. Nothing
    /// stops a provider from charging twice: that is the business bug the formal dispute of the worked example
    /// catches, and each charge beyond the first is its own event and its own contested point.
    function settle(uint256 callId) external {
        Call storage c = _call(callId);
        if (msg.sender != c.provider) revert Escrow_NotProvider();
        if (balanceOf[c.client] < c.amount) revert Escrow_Insufficient();
        balanceOf[c.client] -= c.amount;
        _settlements[callId].push(Settlement({at: uint64(block.timestamp), state: SettlementState.Held}));
        emit Settled(callId, uint32(_settlements[callId].length), uint64(block.timestamp));
    }

    /// Releases to the provider every held settlement whose dispute period has lapsed. Anyone may call it: the
    /// hold is a rule of the terms, not a favour of the client.
    function release(uint256 callId) external {
        Call storage c = _call(callId);
        Settlement[] storage ss = _settlements[callId];
        for (uint256 i = 0; i < ss.length; i++) {
            if (ss[i].state == SettlementState.Held && uint64(block.timestamp) >= ss[i].at + c.disputePeriod) {
                ss[i].state = SettlementState.Released;
                balanceOf[c.provider] += c.amount;
                emit Released(callId, uint32(i + 1), c.amount);
            }
        }
    }

    function settlementCount(uint256 callId) external view returns (uint32) {
        return uint32(_settlements[callId].length);
    }

    function settlementOf(uint256 callId, uint32 ordinal) external view returns (uint64 at, SettlementState state) {
        Settlement storage s = _settlements[callId][ordinal - 1];
        return (s.at, s.state);
    }

    /// The value of the call still held: the settlements neither released nor refunded.
    function heldOf(uint256 callId) external view returns (uint256 held) {
        Settlement[] storage ss = _settlements[callId];
        for (uint256 i = 0; i < ss.length; i++) if (ss[i].state == SettlementState.Held) held += calls[callId].amount;
    }

    /// The event reference of settlement number `ordinal` (1 = the first charge) of any call of this escrow.
    function settlementEventRef(uint32 ordinal) public pure returns (bytes32) {
        return keccak256(abi.encode(EVENT_SETTLEMENT, ordinal));
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
        if (!_isObject(object)) return info;
        Call storage c = calls[object.id];
        info.normRef = c.termsHash;
        info.normDeclaredAt = c.createdAt;
        uint32 n = _settlementOrdinal(object.id, eventRef);
        if (n != 0) {
            Settlement storage s = _settlements[object.id][n - 1];
            info.known = true;
            info.eventAt = s.at;
            info.adoptionDeadline = s.at + c.disputePeriod;   // the settlement is held until then
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

    /// The breaches the terms recognize. For settlement n (n >= 2): the verifier's canonical proposition for
    /// (this ledger, the call, n) being TRUE. For the delivery: the deliverable not conforming, the service not
    /// having been performed, the version actually used not matching the committed one (each FALSE), and the
    /// declared version differing from the committed one (TRUE, the declared-version verifier's proposition).
    function recognizesBreach(T.ObjectRef calldata object, bytes32 eventRef, uint8 obligationKind, bytes32 proposition, T.Value breachWhen)
        external view returns (bool)
    {
        if (!_isObject(object)) return false;
        uint32 n = _settlementOrdinal(object.id, eventRef);
        if (n != 0) {
            return obligationKind == KIND_LIMIT && n >= 2 && breachWhen == T.Value.TRUE
                && proposition == DuplicateSettlementStatement.propositionFor(address(this), object.id, n);
        }
        if (eventRef != EVENT_DELIVERY || obligationKind != KIND_RESULT) return false;
        if (breachWhen == T.Value.FALSE) {
            return proposition == STATEMENT_CONFORMS || proposition == STATEMENT_PERFORMED || proposition == STATEMENT_ACTUAL_VERSION;
        }
        if (breachWhen == T.Value.TRUE) {
            return proposition == DeclaredVersionStatement.propositionFor(address(this), object.id);
        }
        return false;
    }

    // ------------------------------------------------------------------ executor

    /// Enacts a Final REFUND ruling on a call of this escrow: a sustained payment claim refunds the settlement the
    /// case was about, a sustained delivery claim refunds the earliest charge of the call. The executor checks
    /// finality, effect class, the allowed effect, its own object and binding, its own anti-duplication record
    /// and that the settlement is still held; it reports Enacted, or Failed with the reason, and never touches
    /// the ruling. A settlement released before enactment is the executor's own failure against the deadline it
    /// attested, and the Failed report says so.
    function enact(bytes32 caseId, bytes32 effectId) external {
        if (bindingId == bytes32(0)) revert Escrow_NotBound();
        T.Ruling memory u = adrf.getRuling(caseId);
        T.CaseHeader memory h = adrf.getCase(caseId);
        if (u.state != T.ProcedureState.Final || u.effectClass != T.EffectClass.Binding) revert Escrow_NotEnactable(caseId);
        if (effectId != EFFECT_REFUND || u.allowedEffect != EFFECT_REFUND) revert Escrow_NotEnactable(caseId);
        if (h.source != address(this) || h.object.target != address(this) || h.bindingId != bindingId) revert Escrow_NotEnactable(caseId);
        if (refunded[caseId]) revert Escrow_NotEnactable(caseId);

        uint256 callId = h.object.id;
        Call storage c = calls[callId];
        uint32 n = _settlementOrdinal(callId, h.eventRef);
        if (n == 0 && h.eventRef == EVENT_DELIVERY) n = _earliestHeld(callId);
        if (n == 0) {
            adrf.reportEnactment(caseId, EFFECT_REFUND, T.EnactmentStatus.Failed, keccak256("no settlement to refund"));
            return;
        }
        Settlement storage s = _settlements[callId][n - 1];
        if (s.state != SettlementState.Held) {
            adrf.reportEnactment(caseId, EFFECT_REFUND, T.EnactmentStatus.Failed,
                s.state == SettlementState.Released ? keccak256("settlement released before enactment") : keccak256("settlement already refunded"));
            return;
        }
        refunded[caseId] = true;
        s.state = SettlementState.Refunded;
        balanceOf[c.client] += c.amount;
        emit Refunded(caseId, callId, n, c.amount);
        adrf.reportEnactment(caseId, EFFECT_REFUND, T.EnactmentStatus.Enacted, keccak256(abi.encode(callId, n, c.amount)));
    }

    // ------------------------------------------------------------------ internals

    function _call(uint256 callId) private view returns (Call storage c) {
        c = calls[callId];
        if (c.client == address(0)) revert Escrow_UnknownCall();
    }

    function _isObject(T.ObjectRef calldata object) private view returns (bool) {
        if (object.target != address(this) || object.chainId != block.chainid) return false;
        Call storage c = calls[object.id];
        if (c.client == address(0)) return false;
        return object.versionHash == keccak256(abi.encode(object.id, c.termsHash, c.committedVersion));
    }

    /// The ordinal of the settlement an event reference names, or 0 when it names none that exists.
    function _settlementOrdinal(uint256 callId, bytes32 eventRef) private view returns (uint32) {
        uint256 count = _settlements[callId].length;
        for (uint32 n = 1; n <= count; n++) {
            if (eventRef == settlementEventRef(n)) return n;
        }
        return 0;
    }

    function _earliestHeld(uint256 callId) private view returns (uint32) {
        Settlement[] storage ss = _settlements[callId];
        for (uint256 i = 0; i < ss.length; i++) if (ss[i].state == SettlementState.Held) return uint32(i + 1);
        return 0;
    }
}
