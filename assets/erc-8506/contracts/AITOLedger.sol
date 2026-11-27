// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IAITOInstrument} from "./interfaces/IAITOInstrument.sol";
import {IAITOConsumption} from "./interfaces/IAITOConsumption.sol";
import {IAITOBinding} from "./interfaces/IAITOBinding.sol";
import {
    SeriesTerms,
    Authorization,
    ConsumptionRequest,
    RequestRecord,
    RequestState,
    Outcome,
    AcceptanceRule,
    BindingType,
    ConsumptionPath
} from "./interfaces/AITOTypes.sol";

/// @title Reference home ledger for AI Inference Token Onchain
/// @notice Core conformance (series, issuance, authorized consumption with hold, settlement and
/// release) together with the native ERC-1155 binding: the token id of a unit is its series id.
/// A hold moves units from the holder to the ledger's own address, so a unit is never both
/// available and held. A settlement burns what was accepted and returns the rest.
/// The stock-quota entitlement shape is implemented. Periodic allowances and reserved capacity
/// are not implemented, and this contract does not report them as supported.
contract AITOLedger is ERC1155, EIP712, IAITOInstrument, IAITOConsumption, IAITOBinding {
    /// @notice Scale of deduction weights: 1e6 means one denomination unit per component unit.
    uint256 public constant WEIGHT_SCALE = 1e6;
    /// @notice Largest number of usage components a series may declare.
    uint256 public constant MAX_COMPONENTS = 32;
    /// @notice Number of outcome classes; a series declares one charging mask per class.
    uint256 public constant OUTCOME_COUNT = 6;

    bytes32 public constant AUTHORIZATION_TYPEHASH = keccak256(
        "Authorization(address holder,address consumer,uint256 seriesId,uint256 cap,uint64 validAfter,uint64 validUntil,bytes32 scope,uint256 nonce)"
    );
    bytes32 public constant REQUEST_TYPEHASH = keccak256(
        "ConsumptionRequest(bytes32 authorizationId,bytes32 requestId,address fulfiller,uint256 maxAmount,uint64 holdUntil,bytes32 scope)"
    );
    bytes32 public constant ACCEPTANCE_TYPEHASH =
        keccak256("UsageAcceptance(bytes32 requestKey,bytes32 claimHash,uint256 amount)");

    mapping(uint256 seriesId => SeriesTerms) private _series;
    mapping(uint256 seriesId => string) private _termsURI;
    mapping(uint256 seriesId => bool) private _accepted;
    mapping(uint256 seriesId => mapping(address => bool)) private _fulfiller;

    mapping(uint256 seriesId => uint256) private _issued;
    mapping(uint256 seriesId => uint256) private _consumed;
    mapping(uint256 seriesId => uint256) private _retired;
    mapping(uint256 seriesId => uint256) private _lapsed;
    mapping(uint256 seriesId => uint256) private _held;
    mapping(uint256 seriesId => mapping(address holder => uint256)) private _heldBy;

    mapping(bytes32 authorizationId => bool) private _registered;
    mapping(bytes32 authorizationId => bool) private _revoked;
    mapping(bytes32 authorizationId => uint256) private _used;

    mapping(bytes32 requestKey => RequestRecord) private _requests;
    mapping(bytes32 receiptHash => bool) private _receipt;

    error NotIssuer();
    error NotResponsibleParty();
    error NotFulfiller();
    error NotHolder();
    error NotConsumerOrHolder();
    error NotResolver();
    error UnknownSeries(uint256 seriesId);
    error SeriesExists(uint256 seriesId);
    /// @param member Name of the member of the terms that is missing or inconsistent.
    error InvalidTerms(bytes32 member);
    error UnsupportedTerm(bytes32 member);
    error UnknownCriticalExtension(bytes32 extension);
    error ResponsibilityNotAccepted(uint256 seriesId);
    error SeriesNotConsumable(uint256 seriesId);
    error SeriesNotExpired(uint256 seriesId);
    error CapExceeded();
    error MissingBasis();
    error ReceiptIsNotABasis(bytes32 basisRef);
    error NonTransferable(uint256 seriesId);
    error EscrowAccount();
    error AuthorizationMismatch();
    error AuthorizationRevoked(bytes32 authorizationId);
    error AuthorizationNotActive(bytes32 authorizationId);
    error AuthorizationCapExceeded(bytes32 authorizationId);
    error InvalidHolderSignature();
    error InvalidConsumerSignature();
    error ScopeMismatch();
    error InvalidHold();
    error RequestExists(bytes32 requestKey);
    error WrongState(RequestState state);
    error HoldExpired();
    error UsageLengthMismatch();
    error AmountAboveClaim();
    error RuleMismatch();
    error ObjectionWindowClosed();
    error ObjectionWindowOpen();
    error ResolutionWindowClosed();
    error NotReleasable();

    constructor() ERC1155("") EIP712("AITO", "1") {}

    // ------------------------------------------------------------------
    // Series
    // ------------------------------------------------------------------

    /// @inheritdoc IAITOInstrument
    function createSeries(SeriesTerms calldata terms, string calldata termsURI_) external returns (uint256 seriesId) {
        if (msg.sender != terms.issuer) revert NotIssuer();
        _validateTerms(terms);

        seriesId = seriesIdOf(terms);
        if (_series[seriesId].issuer != address(0)) revert SeriesExists(seriesId);

        _series[seriesId] = terms;
        _termsURI[seriesId] = termsURI_;
        emit SeriesCreated(seriesId, terms.issuer, terms.responsibleParty, terms.termsHash, termsURI_);

        if (terms.issuer == terms.responsibleParty) {
            _accepted[seriesId] = true;
            emit ResponsibilityAccepted(seriesId, terms.responsibleParty);
        }
    }

    /// @inheritdoc IAITOInstrument
    function seriesIdOf(SeriesTerms calldata terms) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(terms)));
    }

    /// @inheritdoc IAITOInstrument
    function acceptResponsibility(uint256 seriesId) external {
        SeriesTerms storage t = _get(seriesId);
        if (msg.sender != t.responsibleParty) revert NotResponsibleParty();
        if (!_accepted[seriesId]) {
            _accepted[seriesId] = true;
            emit ResponsibilityAccepted(seriesId, msg.sender);
        }
    }

    /// @inheritdoc IAITOInstrument
    function setFulfiller(uint256 seriesId, address fulfiller, bool allowed) external {
        SeriesTerms storage t = _get(seriesId);
        if (msg.sender != t.responsibleParty) revert NotResponsibleParty();
        _fulfiller[seriesId][fulfiller] = allowed;
        emit FulfillerSet(seriesId, fulfiller, allowed);
    }

    /// @inheritdoc IAITOInstrument
    function issue(uint256 seriesId, address to, uint256 amount, bytes32 basisRef) external {
        SeriesTerms storage t = _get(seriesId);
        if (msg.sender != t.issuer) revert NotIssuer();
        if (!_accepted[seriesId]) revert ResponsibilityNotAccepted(seriesId);
        if (block.timestamp > t.validUntil) revert SeriesNotConsumable(seriesId);
        if (basisRef == bytes32(0)) revert MissingBasis();
        // A record of past usage is never a ground for new entitlements.
        if (_receipt[basisRef]) revert ReceiptIsNotABasis(basisRef);

        uint256 issued = _issued[seriesId] + amount;
        if (issued > t.cap) revert CapExceeded();
        _issued[seriesId] = issued;

        _mint(to, seriesId, amount, "");
        emit Issued(seriesId, to, amount, basisRef);
    }

    /// @inheritdoc IAITOInstrument
    function retire(uint256 seriesId, uint256 amount) external {
        _get(seriesId);
        _retired[seriesId] += amount;
        _move(msg.sender, address(0), seriesId, amount);
        emit Retired(seriesId, msg.sender, amount);
    }

    /// @inheritdoc IAITOInstrument
    function lapse(uint256 seriesId, address holder) external {
        SeriesTerms storage t = _get(seriesId);
        if (block.timestamp <= t.validUntil) revert SeriesNotExpired(seriesId);
        // Units reserved by holds are settled or released first; they are not lapsed from escrow.
        if (holder == address(this)) revert EscrowAccount();
        uint256 amount = balanceOf(holder, seriesId);
        if (amount == 0) return;
        _lapsed[seriesId] += amount;
        _move(holder, address(0), seriesId, amount);
        emit Lapsed(seriesId, holder, amount);
    }

    // ------------------------------------------------------------------
    // Consumption
    // ------------------------------------------------------------------

    /// @inheritdoc IAITOConsumption
    function hashAuthorization(Authorization calldata a) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    AUTHORIZATION_TYPEHASH,
                    a.holder,
                    a.consumer,
                    a.seriesId,
                    a.cap,
                    a.validAfter,
                    a.validUntil,
                    a.scope,
                    a.nonce
                )
            )
        );
    }

    /// @inheritdoc IAITOConsumption
    function hashRequest(ConsumptionRequest calldata r) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    REQUEST_TYPEHASH, r.authorizationId, r.requestId, r.fulfiller, r.maxAmount, r.holdUntil, r.scope
                )
            )
        );
    }

    /// @inheritdoc IAITOConsumption
    function hashAcceptance(bytes32 requestKey, bytes32 claimHash, uint256 amount) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(ACCEPTANCE_TYPEHASH, requestKey, claimHash, amount)));
    }

    /// @inheritdoc IAITOConsumption
    function requestKeyOf(address consumer, bytes32 requestId) public pure returns (bytes32) {
        return keccak256(abi.encode(consumer, requestId));
    }

    /// @inheritdoc IAITOConsumption
    function authorize(Authorization calldata a) external returns (bytes32 authorizationId) {
        if (msg.sender != a.holder) revert NotHolder();
        _get(a.seriesId);
        authorizationId = hashAuthorization(a);
        _registered[authorizationId] = true;
        emit Authorized(
            authorizationId, a.holder, a.consumer, a.seriesId, a.cap, a.validAfter, a.validUntil, a.scope, a.nonce
        );
    }

    /// @inheritdoc IAITOConsumption
    function revoke(Authorization calldata a) external {
        if (msg.sender != a.holder) revert NotHolder();
        bytes32 authorizationId = hashAuthorization(a);
        _revoked[authorizationId] = true;
        emit Revoked(authorizationId, a.holder);
    }

    /// @inheritdoc IAITOConsumption
    function hold(
        Authorization calldata a,
        bytes calldata holderSig,
        ConsumptionRequest calldata r,
        bytes calldata consumerSig
    ) external returns (bytes32 requestKey) {
        bytes32 authorizationId = hashAuthorization(a);
        if (r.authorizationId != authorizationId) revert AuthorizationMismatch();
        _checkAuthorization(a, authorizationId, holderSig);
        if (!SignatureChecker.isValidSignatureNow(a.consumer, hashRequest(r), consumerSig)) {
            revert InvalidConsumerSignature();
        }
        if (a.scope != bytes32(0) && a.scope != r.scope) revert ScopeMismatch();
        if (msg.sender != r.fulfiller || !_fulfiller[a.seriesId][msg.sender]) revert NotFulfiller();
        _checkHoldTerms(a.seriesId, r.maxAmount, r.holdUntil);

        requestKey = requestKeyOf(a.consumer, r.requestId);
        _placeHold(requestKey, authorizationId, a, r);
    }

    function _checkAuthorization(Authorization calldata a, bytes32 authorizationId, bytes calldata holderSig)
        private
        view
    {
        if (_revoked[authorizationId]) revert AuthorizationRevoked(authorizationId);
        if (block.timestamp < a.validAfter || block.timestamp > a.validUntil) {
            revert AuthorizationNotActive(authorizationId);
        }
        // A transfer approval is not a consumption authorization: only this signature or an
        // explicit on-chain registration by the holder lets units be reserved.
        if (
            !_registered[authorizationId]
                && !SignatureChecker.isValidSignatureNow(a.holder, authorizationId, holderSig)
        ) revert InvalidHolderSignature();
    }

    function _checkHoldTerms(uint256 seriesId, uint256 maxAmount, uint64 holdUntil) private view {
        SeriesTerms storage t = _get(seriesId);
        if (!_consumable(seriesId, t)) revert SeriesNotConsumable(seriesId);
        if (
            maxAmount == 0 || holdUntil <= block.timestamp || holdUntil > block.timestamp + t.maxHoldDuration
                || holdUntil > t.validUntil
        ) revert InvalidHold();
    }

    function _placeHold(
        bytes32 requestKey,
        bytes32 authorizationId,
        Authorization calldata a,
        ConsumptionRequest calldata r
    ) private {
        RequestRecord storage q = _requests[requestKey];
        if (q.state != RequestState.None) revert RequestExists(requestKey);

        uint256 used = _used[authorizationId] + r.maxAmount;
        if (used > a.cap) revert AuthorizationCapExceeded(authorizationId);
        _used[authorizationId] = used;

        q.state = RequestState.Held;
        q.holdUntil = r.holdUntil;
        q.seriesId = a.seriesId;
        q.holder = a.holder;
        q.consumer = a.consumer;
        q.fulfiller = msg.sender;
        q.authorizationId = authorizationId;
        q.held = r.maxAmount;

        _heldBy[a.seriesId][a.holder] += r.maxAmount;
        _held[a.seriesId] += r.maxAmount;
        _move(a.holder, address(this), a.seriesId, r.maxAmount);

        emit Held(
            requestKey,
            authorizationId,
            msg.sender,
            a.consumer,
            r.requestId,
            a.seriesId,
            a.holder,
            r.maxAmount,
            r.holdUntil
        );
    }

    /// @inheritdoc IAITOConsumption
    function claimUsage(bytes32 requestKey, uint256[] calldata usage, Outcome outcome, bytes32 evidenceRoot)
        external
    {
        RequestRecord storage q = _requests[requestKey];
        if (q.state != RequestState.Held) revert WrongState(q.state);
        if (msg.sender != q.fulfiller) revert NotFulfiller();
        if (block.timestamp > q.holdUntil) revert HoldExpired();

        SeriesTerms storage t = _series[q.seriesId];
        uint256 computed = _charge(t, usage, outcome);
        // The hold is the budget of the request. A claim never reaches beyond it.
        uint256 claimed = computed > q.held ? q.held : computed;
        bytes32 claimHash = keccak256(abi.encode(requestKey, usage, outcome, evidenceRoot));

        q.state = RequestState.Claimed;
        q.outcome = outcome;
        q.claimedAt = uint64(block.timestamp);
        q.computed = computed;
        q.claimed = claimed;
        q.claimHash = claimHash;
        q.evidenceRoot = evidenceRoot;
        emit UsageClaimed(requestKey, msg.sender, outcome, usage, computed, claimed, claimHash, evidenceRoot);

        if (t.acceptanceRule == AcceptanceRule.ProviderMetered) {
            _settle(requestKey, q, claimed, msg.sender);
        }
    }

    /// @inheritdoc IAITOConsumption
    function accept(bytes32 requestKey, bytes calldata consumerSig) external {
        RequestRecord storage q = _requests[requestKey];
        if (q.state != RequestState.Claimed && q.state != RequestState.Disputed) revert WrongState(q.state);
        bytes32 digest = hashAcceptance(requestKey, q.claimHash, q.claimed);
        if (!SignatureChecker.isValidSignatureNow(q.consumer, digest, consumerSig)) {
            revert InvalidConsumerSignature();
        }
        _settle(requestKey, q, q.claimed, q.consumer);
    }

    /// @inheritdoc IAITOConsumption
    function object(bytes32 requestKey, bytes32 reason) external {
        RequestRecord storage q = _requests[requestKey];
        if (q.state != RequestState.Claimed) revert WrongState(q.state);
        if (msg.sender != q.consumer && msg.sender != q.holder) revert NotConsumerOrHolder();
        SeriesTerms storage t = _series[q.seriesId];
        if (t.acceptanceRule != AcceptanceRule.Optimistic) revert RuleMismatch();
        if (block.timestamp > uint256(q.claimedAt) + t.objectionWindow) revert ObjectionWindowClosed();

        emit Objected(requestKey, msg.sender, reason);
        if (t.resolver == address(0)) {
            // No resolver was named in the terms: an objected claim deducts nothing.
            _release(requestKey, q);
        } else {
            q.state = RequestState.Disputed;
            q.disputedAt = uint64(block.timestamp);
        }
    }

    /// @inheritdoc IAITOConsumption
    function resolve(bytes32 requestKey, uint256 amount) external {
        RequestRecord storage q = _requests[requestKey];
        if (q.state != RequestState.Disputed) revert WrongState(q.state);
        SeriesTerms storage t = _series[q.seriesId];
        if (msg.sender != t.resolver) revert NotResolver();
        if (block.timestamp > uint256(q.disputedAt) + t.resolutionWindow) revert ResolutionWindowClosed();
        if (amount > q.claimed) revert AmountAboveClaim();
        _settle(requestKey, q, amount, msg.sender);
    }

    /// @inheritdoc IAITOConsumption
    function finalize(bytes32 requestKey) external {
        RequestRecord storage q = _requests[requestKey];
        if (q.state != RequestState.Claimed) revert WrongState(q.state);
        SeriesTerms storage t = _series[q.seriesId];
        if (t.acceptanceRule != AcceptanceRule.Optimistic) revert RuleMismatch();
        if (block.timestamp <= uint256(q.claimedAt) + t.objectionWindow) revert ObjectionWindowOpen();
        _settle(requestKey, q, q.claimed, address(0));
    }

    /// @inheritdoc IAITOConsumption
    function release(bytes32 requestKey) external {
        RequestRecord storage q = _requests[requestKey];
        RequestState s = q.state;
        // The fulfiller may always give a reservation back. Anyone else may do so only once
        // the request can no longer be settled under the series terms.
        if (msg.sender != q.fulfiller) {
            if (s == RequestState.Held) {
                if (block.timestamp <= q.holdUntil) revert NotReleasable();
            } else if (s == RequestState.Claimed) {
                if (
                    _series[q.seriesId].acceptanceRule != AcceptanceRule.CoSign || block.timestamp <= q.holdUntil
                ) revert NotReleasable();
            } else if (s == RequestState.Disputed) {
                if (block.timestamp <= uint256(q.disputedAt) + _series[q.seriesId].resolutionWindow) {
                    revert NotReleasable();
                }
            } else {
                revert WrongState(s);
            }
        } else if (s != RequestState.Held && s != RequestState.Claimed && s != RequestState.Disputed) {
            revert WrongState(s);
        }
        _release(requestKey, q);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    /// @inheritdoc IAITOInstrument
    function seriesOf(uint256 seriesId) external view returns (SeriesTerms memory) {
        return _get(seriesId);
    }

    /// @inheritdoc IAITOInstrument
    function termsURI(uint256 seriesId) external view returns (string memory) {
        _get(seriesId);
        return _termsURI[seriesId];
    }

    /// @notice ERC-1155 metadata URI: the terms document of the series.
    function uri(uint256 seriesId) public view override returns (string memory) {
        return _termsURI[seriesId];
    }

    /// @inheritdoc IAITOInstrument
    function responsibilityAccepted(uint256 seriesId) external view returns (bool) {
        return _accepted[seriesId];
    }

    /// @inheritdoc IAITOInstrument
    function isFulfiller(uint256 seriesId, address account) external view returns (bool) {
        return _fulfiller[seriesId][account];
    }

    /// @inheritdoc IAITOInstrument
    function supportsExtension(bytes32) public view virtual returns (bool) {
        return false;
    }

    /// @inheritdoc IAITOInstrument
    function quoteCharge(uint256 seriesId, uint256[] calldata usage, Outcome outcome)
        external
        view
        returns (uint256)
    {
        return _charge(_get(seriesId), usage, outcome);
    }

    /// @inheritdoc IAITOInstrument
    function issuedOf(uint256 seriesId) external view returns (uint256) {
        return _issued[seriesId];
    }

    /// @inheritdoc IAITOInstrument
    function consumedOf(uint256 seriesId) external view returns (uint256) {
        return _consumed[seriesId];
    }

    /// @inheritdoc IAITOInstrument
    function retiredOf(uint256 seriesId) external view returns (uint256) {
        return _retired[seriesId];
    }

    /// @inheritdoc IAITOInstrument
    function lapsedOf(uint256 seriesId) external view returns (uint256) {
        return _lapsed[seriesId];
    }

    /// @inheritdoc IAITOInstrument
    function heldOf(uint256 seriesId) external view returns (uint256) {
        return _held[seriesId];
    }

    /// @inheritdoc IAITOInstrument
    function heldBy(uint256 seriesId, address holder) external view returns (uint256) {
        return _heldBy[seriesId][holder];
    }

    /// @inheritdoc IAITOInstrument
    function availableOf(uint256 seriesId, address holder) public view returns (uint256) {
        if (holder == address(this)) return 0;
        return balanceOf(holder, seriesId);
    }

    /// @inheritdoc IAITOInstrument
    function consumableOf(uint256 seriesId, address holder) external view returns (uint256) {
        SeriesTerms storage t = _series[seriesId];
        if (t.issuer == address(0) || !_consumable(seriesId, t)) return 0;
        return availableOf(seriesId, holder);
    }

    /// @inheritdoc IAITOConsumption
    function isRevoked(bytes32 authorizationId) external view returns (bool) {
        return _revoked[authorizationId];
    }

    /// @inheritdoc IAITOConsumption
    function usedOf(bytes32 authorizationId) external view returns (uint256) {
        return _used[authorizationId];
    }

    /// @inheritdoc IAITOConsumption
    function requestOf(bytes32 requestKey) external view returns (RequestRecord memory) {
        return _requests[requestKey];
    }

    /// @inheritdoc IAITOConsumption
    function isReceipt(bytes32 hash) external view returns (bool) {
        return _receipt[hash];
    }

    /// @inheritdoc IAITOBinding
    function aitoBinding(uint256 carrierId)
        external
        view
        returns (address ledger, uint256 seriesId, BindingType bindingType, uint256 carrierPerUnit, ConsumptionPath path)
    {
        _get(carrierId);
        return (address(this), carrierId, BindingType.Native, 1, ConsumptionPath.Direct);
    }

    /// @notice ERC-165. Only what this contract implements is reported.
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAITOInstrument).interfaceId || interfaceId == type(IAITOConsumption).interfaceId
            || interfaceId == type(IAITOBinding).interfaceId || super.supportsInterface(interfaceId);
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _get(uint256 seriesId) private view returns (SeriesTerms storage t) {
        t = _series[seriesId];
        if (t.issuer == address(0)) revert UnknownSeries(seriesId);
    }

    function _consumable(uint256 seriesId, SeriesTerms storage t) private view returns (bool) {
        return _accepted[seriesId] && block.timestamp >= t.validFrom && block.timestamp <= t.validUntil;
    }

    function _validateTerms(SeriesTerms calldata t) private view {
        // Every term that decides what a holder may consume must be determined.
        if (t.issuer == address(0)) revert InvalidTerms("issuer");
        if (t.responsibleParty == address(0)) revert InvalidTerms("responsibleParty");
        if (t.unit == bytes32(0)) revert InvalidTerms("unit");
        if (t.grade == bytes32(0)) revert InvalidTerms("grade");
        if (t.source == bytes32(0)) revert InvalidTerms("source");
        if (t.termsHash == bytes32(0)) revert InvalidTerms("termsHash");
        if (t.cap == 0) revert InvalidTerms("cap");
        if (t.validUntil <= t.validFrom || t.validUntil <= block.timestamp) revert InvalidTerms("validUntil");
        if (t.maxHoldDuration == 0) revert InvalidTerms("maxHoldDuration");
        if (t.acceptanceRule == AcceptanceRule.Optimistic && t.objectionWindow == 0) {
            revert InvalidTerms("objectionWindow");
        }
        if (t.resolver != address(0) && t.resolutionWindow == 0) revert InvalidTerms("resolutionWindow");

        uint256 n = t.components.length;
        if (n == 0 || n > MAX_COMPONENTS) revert InvalidTerms("components");
        if (t.weights.length != n) revert InvalidTerms("weights");
        if (t.outcomeMasks.length != OUTCOME_COUNT) revert InvalidTerms("outcomeMasks");
        for (uint256 i; i < n; ++i) {
            if (t.components[i] == bytes32(0)) revert InvalidTerms("components");
            for (uint256 j; j < i; ++j) {
                if (t.components[i] == t.components[j]) revert InvalidTerms("components");
            }
        }
        for (uint256 i; i < OUTCOME_COUNT; ++i) {
            if (t.outcomeMasks[i] >> n != 0) revert InvalidTerms("outcomeMasks");
        }

        // This ledger keeps the schedule inside the series identifier, so it cannot change.
        if (t.scheduleMutable) revert UnsupportedTerm("scheduleMutable");

        // A critical extension that is not understood blocks the operation. Other extensions
        // this ledger does not know are carried in the terms and have no effect here.
        for (uint256 i; i < t.extensions.length; ++i) {
            if (t.extensions[i].id == bytes32(0)) revert InvalidTerms("extensions");
            if (t.extensions[i].critical && !supportsExtension(t.extensions[i].id)) {
                revert UnknownCriticalExtension(t.extensions[i].id);
            }
        }
    }

    function _charge(SeriesTerms storage t, uint256[] calldata usage, Outcome outcome)
        private
        view
        returns (uint256)
    {
        uint256 n = t.components.length;
        if (usage.length != n) revert UsageLengthMismatch();
        uint256 mask = t.outcomeMasks[uint8(outcome)];
        uint256 scaled;
        for (uint256 i; i < n; ++i) {
            if ((mask >> i) & 1 == 1) scaled += usage[i] * t.weights[i];
        }
        return t.roundUp ? Math.ceilDiv(scaled, WEIGHT_SCALE) : scaled / WEIGHT_SCALE;
    }

    function _settle(bytes32 requestKey, RequestRecord storage q, uint256 amount, address acceptedBy) private {
        uint256 seriesId = q.seriesId;
        address holder = q.holder;
        uint256 held = q.held;
        uint256 released = held - amount;

        q.state = RequestState.Settled;
        q.deducted = amount;
        _heldBy[seriesId][holder] -= held;
        _held[seriesId] -= held;
        _consumed[seriesId] += amount;
        // The unused part of the reservation returns to the authorization's ceiling.
        _used[q.authorizationId] -= released;

        bytes32 receiptHash = _receiptHash(requestKey, q, amount, released);
        q.receiptHash = receiptHash;
        _receipt[receiptHash] = true;

        if (amount != 0) _move(address(this), address(0), seriesId, amount);
        if (released != 0) _move(address(this), holder, seriesId, released);

        emit Accepted(requestKey, acceptedBy, _series[seriesId].acceptanceRule, amount);
        emit Settled(requestKey, seriesId, holder, amount, released, receiptHash);
    }

    function _release(bytes32 requestKey, RequestRecord storage q) private {
        uint256 seriesId = q.seriesId;
        address holder = q.holder;
        uint256 held = q.held;

        q.state = RequestState.Released;
        _heldBy[seriesId][holder] -= held;
        _held[seriesId] -= held;
        _used[q.authorizationId] -= held;

        _move(address(this), holder, seriesId, held);
        emit Released(requestKey, seriesId, holder, held);
    }

    function _receiptHash(bytes32 requestKey, RequestRecord storage q, uint256 deducted, uint256 released)
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                requestKey,
                q.seriesId,
                q.holder,
                q.consumer,
                q.fulfiller,
                q.authorizationId,
                q.claimHash,
                deducted,
                released
            )
        );
    }

    function _move(address from, address to, uint256 seriesId, uint256 value) private {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        ids[0] = seriesId;
        values[0] = value;
        _update(from, to, ids, values);
    }

    /// @dev Transfers between accounts require a transferable series. Issuance, retirement and
    /// the ledger's own escrow movements are not transfers between holders.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal override {
        if (from != address(0) && to != address(0) && from != address(this) && to != address(this)) {
            for (uint256 i; i < ids.length; ++i) {
                if (!_series[ids[i]].transferable) revert NonTransferable(ids[i]);
            }
        }
        super._update(from, to, ids, values);
    }
}
