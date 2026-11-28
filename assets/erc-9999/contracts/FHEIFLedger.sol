// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IFHEIFLedger} from "./interfaces/IFHEIFLedger.sol";
import {IFHEIFRegistry} from "./interfaces/IFHEIFRegistry.sol";
import {IFHEIFAuthorizer} from "./interfaces/IFHEIFAuthorizer.sol";
import {
    FHEIF,
    InputSubmission,
    OutputSubmission,
    ProtectedObject,
    ObjectOrigin,
    ObjectStatus,
    OperationRequest,
    Operation,
    OperationStatus,
    DisclosureRequest,
    Disclosure,
    DisclosureStatus,
    Evidence,
    Anchor,
    Scope,
    ScopeStatus,
    Policy,
    SuccessorRight,
    KeyEpoch,
    EpochStatus,
    CarryOver,
    ViewDefinition
} from "./interfaces/FHEIFTypes.sol";

/// @title Reference ledger of the FHE Interaction Framework
/// @notice Records protected objects, operations on them, disclosures of them and evidence about
/// them. It never holds plaintext, keys or shares, and it does not require ciphertext: an object is
/// known to it by a commitment. Authority is asked of the authorizer of the scope's policy version;
/// the ledger has no owner and no privileged account.
contract FHEIFLedger is IFHEIFLedger {
    bytes32 public constant OPERATION_REQUEST_TYPEHASH = keccak256(
        "OperationRequest(bytes32 scopeId,uint64 policyVersion,bytes32 keyContextId,uint32 inputEpoch,uint32 outputEpoch,bytes32 programHash,bytes32 viewId,bytes32 outputClass,bytes32[] inputs,address requester,address executor,uint256 nonce,uint64 validUntil)"
    );
    bytes32 public constant DISCLOSURE_REQUEST_TYPEHASH = keccak256(
        "DisclosureRequest(bytes32 scopeId,bytes32 objectId,bytes32 viewId,bytes32 keyContextId,uint32 keyEpoch,uint64 policyVersion,address audience,bytes32 deliveryKeyHash,address requester,uint256 nonce,uint64 validAfter,uint64 validUntil)"
    );
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _NAME_HASH = keccak256("FHE Interaction Framework");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    bytes4 private constant _ERC1271_MAGIC = 0x1626ba7e;
    uint256 private constant _HALF_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    IFHEIFRegistry private immutable _registry;
    uint256 private immutable _deploymentChainId;
    bytes32 private immutable _deploymentSeparator;

    mapping(bytes32 => ProtectedObject) private _objects;
    mapping(bytes32 => Operation) private _operations;
    mapping(bytes32 => Disclosure) private _disclosures;
    mapping(bytes32 => mapping(address => bool)) private _approved;
    mapping(bytes32 => mapping(address => bool)) private _attested;
    mapping(bytes32 => Evidence[]) private _evidence;
    mapping(bytes32 => Anchor) private _anchors;

    constructor(address registry_) {
        if (registry_ == address(0)) revert InvalidRequest();
        _registry = IFHEIFRegistry(registry_);
        _deploymentChainId = block.chainid;
        _deploymentSeparator = _separator();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IFHEIFLedger).interfaceId || interfaceId == 0x01ffc9a7;
    }

    function registry() external view returns (address) {
        return address(_registry);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _deploymentChainId ? _deploymentSeparator : _separator();
    }

    function hashOperationRequest(OperationRequest calldata request) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                OPERATION_REQUEST_TYPEHASH,
                request.scopeId,
                request.policyVersion,
                request.keyContextId,
                request.inputEpoch,
                request.outputEpoch,
                request.programHash,
                request.viewId,
                request.outputClass,
                keccak256(abi.encodePacked(request.inputs)),
                request.requester,
                request.executor,
                request.nonce,
                request.validUntil
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
    }

    function hashDisclosureRequest(DisclosureRequest calldata request) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                DISCLOSURE_REQUEST_TYPEHASH,
                request.scopeId,
                request.objectId,
                request.viewId,
                request.keyContextId,
                request.keyEpoch,
                request.policyVersion,
                request.audience,
                request.deliveryKeyHash,
                request.requester,
                request.nonce,
                request.validAfter,
                request.validUntil
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
    }

    // Protected objects

    function submitInput(InputSubmission calldata submission) external returns (bytes32 objectId) {
        Scope memory scope = _activeScope(submission.scopeId);
        _requireEpoch(submission.scopeId, submission.keyContextId, submission.keyEpoch, true);
        if (submission.commitment == bytes32(0)) revert InvalidRequest();
        if (
            !_ask(
                submission.scopeId, scope.policyVersion, msg.sender, FHEIF.CAP_SUBMIT_INPUT, submission.classId, bytes32(0)
            )
        ) revert NotAuthorized(msg.sender, FHEIF.CAP_SUBMIT_INPUT);

        bytes32 originId = bytes32(uint256(uint160(msg.sender)));
        objectId = keccak256(
            abi.encode(
                address(this),
                submission.scopeId,
                submission.keyContextId,
                submission.keyEpoch,
                submission.classId,
                submission.commitment,
                ObjectOrigin.INPUT,
                originId,
                uint256(0)
            )
        );
        if (_objects[objectId].status != ObjectStatus.NONE) revert ObjectExists(objectId);
        _objects[objectId] = ProtectedObject({
            scopeId: submission.scopeId,
            keyContextId: submission.keyContextId,
            keyEpoch: submission.keyEpoch,
            classId: submission.classId,
            viewId: bytes32(0),
            commitment: submission.commitment,
            originId: originId,
            submitter: msg.sender,
            policyVersion: scope.policyVersion,
            origin: ObjectOrigin.INPUT,
            status: ObjectStatus.ACCEPTED
        });
        emit InputSubmitted(
            objectId,
            submission.scopeId,
            msg.sender,
            submission.classId,
            submission.keyContextId,
            submission.keyEpoch,
            submission.commitment,
            submission.locator
        );
    }

    function objectOf(bytes32 objectId) external view returns (ProtectedObject memory object) {
        object = _objects[objectId];
        if (object.status == ObjectStatus.NONE) revert UnknownSubject(objectId);
    }

    // Operations

    function requestOperation(OperationRequest calldata request) external returns (bytes32 operationId) {
        if (msg.sender != request.requester) revert NotRequester(msg.sender);
        return _admitOperation(request, hashOperationRequest(request));
    }

    function requestOperationWithSignature(OperationRequest calldata request, bytes calldata signature)
        external
        returns (bytes32 operationId)
    {
        operationId = hashOperationRequest(request);
        _checkSignature(request.requester, operationId, signature);
        _admitOperation(request, operationId);
    }

    function submitResult(bytes32 operationId, OutputSubmission[] calldata outputs)
        external
        returns (bytes32[] memory objectIds)
    {
        Operation storage operation = _operations[operationId];
        if (operation.status != OperationStatus.ADMITTED) revert InvalidState(operationId);
        OperationRequest storage request = operation.request;
        _requireCurrent(request.scopeId, request.policyVersion, request.validUntil, operationId);
        _requireEpoch(request.scopeId, request.keyContextId, request.outputEpoch, true);
        if (request.executor != address(0) && request.executor != msg.sender) revert NotDesignatedExecutor(msg.sender);
        if (
            !_ask(
                request.scopeId,
                request.policyVersion,
                msg.sender,
                FHEIF.CAP_EXECUTE_OPERATION,
                request.outputClass,
                request.programHash
            )
        ) revert NotAuthorized(msg.sender, FHEIF.CAP_EXECUTE_OPERATION);
        uint256 count = outputs.length;
        if (count == 0) revert InvalidRequest();

        objectIds = new bytes32[](count);
        for (uint256 i = 0; i < count; ++i) {
            if (outputs[i].commitment == bytes32(0)) revert InvalidRequest();
            bytes32 objectId = keccak256(
                abi.encode(
                    address(this),
                    request.scopeId,
                    request.keyContextId,
                    request.outputEpoch,
                    request.outputClass,
                    outputs[i].commitment,
                    ObjectOrigin.OUTPUT,
                    operationId,
                    i
                )
            );
            if (_objects[objectId].status != ObjectStatus.NONE) revert ObjectExists(objectId);
            _objects[objectId] = ProtectedObject({
                scopeId: request.scopeId,
                keyContextId: request.keyContextId,
                keyEpoch: request.outputEpoch,
                classId: request.outputClass,
                viewId: request.viewId,
                commitment: outputs[i].commitment,
                originId: operationId,
                submitter: msg.sender,
                policyVersion: 0,
                origin: ObjectOrigin.OUTPUT,
                status: ObjectStatus.PROPOSED
            });
            objectIds[i] = objectId;
            operation.outputs.push(objectId);
            emit OutputProposed(objectId, operationId, outputs[i].commitment, outputs[i].locator);
        }
        operation.status = OperationStatus.RESULT_SUBMITTED;
        operation.submittedBy = msg.sender;
        emit ResultSubmitted(operationId, msg.sender, objectIds);
    }

    function acceptResult(bytes32 operationId) external {
        Operation storage operation = _operations[operationId];
        if (operation.status != OperationStatus.RESULT_SUBMITTED) revert InvalidState(operationId);
        OperationRequest storage request = operation.request;
        _requireCurrent(request.scopeId, request.policyVersion, request.validUntil, operationId);
        _requireEpoch(request.scopeId, request.keyContextId, request.outputEpoch, true);
        _requireAcceptor(request);
        uint256 count = operation.outputs.length;
        for (uint256 i = 0; i < count; ++i) {
            ProtectedObject storage object = _objects[operation.outputs[i]];
            object.status = ObjectStatus.ACCEPTED;
            object.policyVersion = request.policyVersion;
        }
        operation.status = OperationStatus.ACCEPTED;
        emit ResultAccepted(operationId, msg.sender);
    }

    function rejectResult(bytes32 operationId, bytes32 reason) external {
        Operation storage operation = _operations[operationId];
        if (operation.status != OperationStatus.RESULT_SUBMITTED) revert InvalidState(operationId);
        _requireAcceptor(operation.request);
        _rejectOutputs(operation);
        operation.status = OperationStatus.REJECTED;
        emit ResultRejected(operationId, msg.sender, reason);
    }

    function failOperation(bytes32 operationId, bytes32 reason) external {
        Operation storage operation = _operations[operationId];
        if (operation.status != OperationStatus.ADMITTED) revert InvalidState(operationId);
        OperationRequest storage request = operation.request;
        if (request.executor != address(0)) {
            if (request.executor != msg.sender) revert NotDesignatedExecutor(msg.sender);
        } else if (
            !_ask(
                request.scopeId,
                request.policyVersion,
                msg.sender,
                FHEIF.CAP_EXECUTE_OPERATION,
                request.outputClass,
                request.programHash
            )
        ) {
            revert NotAuthorized(msg.sender, FHEIF.CAP_EXECUTE_OPERATION);
        }
        operation.status = OperationStatus.FAILED;
        emit OperationFailed(operationId, msg.sender, reason);
    }

    function cancelOperation(bytes32 operationId) external {
        Operation storage operation = _operations[operationId];
        if (operation.status != OperationStatus.ADMITTED) revert InvalidState(operationId);
        if (operation.request.requester != msg.sender) revert NotRequester(msg.sender);
        operation.status = OperationStatus.CANCELLED;
        emit OperationCancelled(operationId);
    }

    function expireOperation(bytes32 operationId) external {
        Operation storage operation = _operations[operationId];
        if (operation.status != OperationStatus.ADMITTED && operation.status != OperationStatus.RESULT_SUBMITTED) {
            revert InvalidState(operationId);
        }
        OperationRequest storage request = operation.request;
        Scope memory scope = _registry.scopeOf(request.scopeId);
        bytes32 reason;
        if (block.timestamp > request.validUntil) {
            reason = FHEIF.REASON_EXPIRED;
        } else if (scope.status == ScopeStatus.CLOSED) {
            reason = FHEIF.REASON_SCOPE_CLOSED;
        } else if (scope.policyVersion != request.policyVersion) {
            reason = FHEIF.REASON_POLICY_SUPERSEDED;
        } else if (_registry.epochOf(request.keyContextId, request.outputEpoch).status != EpochStatus.ACTIVE) {
            reason = FHEIF.REASON_EPOCH_NOT_USABLE;
        } else {
            revert NotExpired(operationId);
        }
        _rejectOutputs(operation);
        operation.status = OperationStatus.EXPIRED;
        emit OperationExpired(operationId, reason);
    }

    function operationOf(bytes32 operationId) external view returns (Operation memory operation) {
        operation = _operations[operationId];
        if (operation.status == OperationStatus.NONE) revert UnknownSubject(operationId);
    }

    // Disclosures

    function requestDisclosure(DisclosureRequest calldata request) external returns (bytes32 disclosureId) {
        if (msg.sender != request.requester) revert NotRequester(msg.sender);
        return _admitDisclosure(request, hashDisclosureRequest(request));
    }

    function requestDisclosureWithSignature(DisclosureRequest calldata request, bytes calldata signature)
        external
        returns (bytes32 disclosureId)
    {
        disclosureId = hashDisclosureRequest(request);
        _checkSignature(request.requester, disclosureId, signature);
        _admitDisclosure(request, disclosureId);
    }

    function approveDisclosure(bytes32 disclosureId) external {
        Disclosure storage disclosure = _disclosures[disclosureId];
        if (disclosure.status != DisclosureStatus.REQUESTED) revert InvalidState(disclosureId);
        (bool standing, bytes32 reason,) = _standing(disclosure.request);
        if (!standing && reason != FHEIF.REASON_NOT_YET_VALID) revert NotReleasable(disclosureId, reason);
        if (!_approver(disclosure.request, msg.sender)) revert NotAuthorized(msg.sender, FHEIF.CAP_APPROVE_DISCLOSURE);
        if (_approved[disclosureId][msg.sender]) revert AlreadyRecorded(msg.sender);
        _approved[disclosureId][msg.sender] = true;
        uint16 approvals = ++disclosure.approvals;
        emit DisclosureApproved(disclosureId, msg.sender, approvals);
        if (approvals >= disclosure.approvalsRequired) {
            disclosure.status = DisclosureStatus.AUTHORIZED;
            emit DisclosureAuthorized(disclosureId);
        }
    }

    function attestRelease(bytes32 disclosureId) external {
        Disclosure storage disclosure = _disclosures[disclosureId];
        if (disclosure.status != DisclosureStatus.AUTHORIZED) revert InvalidState(disclosureId);
        DisclosureRequest storage request = disclosure.request;
        (bool standing, bytes32 reason,) = _standing(request);
        if (!standing) revert NotReleasable(disclosureId, reason);
        if (!_registry.isHolder(request.keyContextId, request.keyEpoch, msg.sender)) revert NotKeyHolder(msg.sender);
        if (_attested[disclosureId][msg.sender]) revert AlreadyRecorded(msg.sender);
        _attested[disclosureId][msg.sender] = true;
        uint16 attestations = ++disclosure.attestations;
        emit ReleaseAttested(disclosureId, msg.sender, attestations);
        if (attestations >= _registry.epochOf(request.keyContextId, request.keyEpoch).releaseQuorum) {
            disclosure.status = DisclosureStatus.RELEASED;
            emit DisclosureReleased(disclosureId);
        }
    }

    function refuseDisclosure(bytes32 disclosureId, bytes32 reason) external {
        Disclosure storage disclosure = _disclosures[disclosureId];
        if (disclosure.status != DisclosureStatus.REQUESTED && disclosure.status != DisclosureStatus.AUTHORIZED) {
            revert InvalidState(disclosureId);
        }
        if (!_approver(disclosure.request, msg.sender)) {
            (bool standing, bytes32 why, bool permanent) = _standing(disclosure.request);
            if (standing || !permanent || why == FHEIF.REASON_EXPIRED) revert StillReleasable(disclosureId);
            reason = why;
        }
        disclosure.status = DisclosureStatus.REFUSED;
        emit DisclosureRefused(disclosureId, msg.sender, reason);
    }

    function expireDisclosure(bytes32 disclosureId) external {
        Disclosure storage disclosure = _disclosures[disclosureId];
        if (disclosure.status != DisclosureStatus.REQUESTED && disclosure.status != DisclosureStatus.AUTHORIZED) {
            revert InvalidState(disclosureId);
        }
        if (block.timestamp <= disclosure.request.validUntil) revert NotExpired(disclosureId);
        disclosure.status = DisclosureStatus.EXPIRED;
        emit DisclosureExpired(disclosureId);
    }

    function isReleasable(bytes32 disclosureId) external view returns (bool releasable, bytes32 reason) {
        Disclosure storage disclosure = _disclosures[disclosureId];
        if (disclosure.status == DisclosureStatus.NONE) revert UnknownSubject(disclosureId);
        if (disclosure.status != DisclosureStatus.AUTHORIZED) return (false, bytes32(0));
        (releasable, reason,) = _standing(disclosure.request);
    }

    function disclosureOf(bytes32 disclosureId) external view returns (Disclosure memory disclosure) {
        disclosure = _disclosures[disclosureId];
        if (disclosure.status == DisclosureStatus.NONE) revert UnknownSubject(disclosureId);
    }

    function hasApproved(bytes32 disclosureId, address approver) external view returns (bool) {
        return _approved[disclosureId][approver];
    }

    function hasAttested(bytes32 disclosureId, address holder) external view returns (bool) {
        return _attested[disclosureId][holder];
    }

    // Evidence

    function recordEvidence(
        bytes32 subjectId,
        bytes32 proposition,
        bytes32 mechanism,
        bytes32 payloadHash,
        string calldata uri
    ) external returns (uint256 index) {
        if (
            _objects[subjectId].status == ObjectStatus.NONE && _operations[subjectId].status == OperationStatus.NONE
                && _disclosures[subjectId].status == DisclosureStatus.NONE && _anchors[subjectId].anchoredAt == 0
        ) revert UnknownSubject(subjectId);
        if (proposition == bytes32(0) || mechanism == bytes32(0)) revert InvalidRequest();
        index = _evidence[subjectId].length;
        _evidence[subjectId].push(Evidence(proposition, mechanism, msg.sender, payloadHash, uint64(block.timestamp)));
        emit EvidenceRecorded(subjectId, proposition, mechanism, msg.sender, payloadHash, uri, index);
    }

    function evidenceCount(bytes32 subjectId) external view returns (uint256) {
        return _evidence[subjectId].length;
    }

    function evidenceAt(bytes32 subjectId, uint256 index) external view returns (Evidence memory) {
        return _evidence[subjectId][index];
    }

    // Committed records

    function anchorRecord(bytes32 scopeId, bytes32 recordKind, bytes32 commitment) external {
        Scope memory scope = _activeScope(scopeId);
        if (commitment == bytes32(0) || recordKind == bytes32(0)) revert InvalidRequest();
        if (!_ask(scopeId, scope.policyVersion, msg.sender, FHEIF.CAP_ANCHOR_RECORD, bytes32(0), recordKind)) {
            revert NotAuthorized(msg.sender, FHEIF.CAP_ANCHOR_RECORD);
        }
        if (_anchors[commitment].anchoredAt != 0) revert RequestAlreadyUsed(commitment);
        _anchors[commitment] = Anchor(scopeId, recordKind, msg.sender, uint64(block.timestamp));
        emit RecordAnchored(commitment, scopeId, recordKind, msg.sender);
    }

    function anchorOf(bytes32 commitment) external view returns (Anchor memory anchor) {
        anchor = _anchors[commitment];
        if (anchor.anchoredAt == 0) revert UnknownSubject(commitment);
    }

    function verifyRecordOpening(bytes32 commitment, bytes32 recordHash, bytes32 salt) external pure returns (bool) {
        return commitment == keccak256(abi.encode(recordHash, salt));
    }

    function verifyBatchMembership(bytes32 root, bytes32 leaf, bytes32[] calldata proof) external pure returns (bool) {
        bytes32 node = leaf;
        for (uint256 i = 0; i < proof.length; ++i) {
            bytes32 sibling = proof[i];
            node = node < sibling ? keccak256(abi.encode(node, sibling)) : keccak256(abi.encode(sibling, node));
        }
        return node == root;
    }

    // Internal: operations

    function _admitOperation(OperationRequest calldata request, bytes32 operationId) private returns (bytes32) {
        if (_operations[operationId].status != OperationStatus.NONE) revert RequestAlreadyUsed(operationId);
        _requireCurrent(request.scopeId, request.policyVersion, request.validUntil, operationId);
        uint256 count = request.inputs.length;
        if (count == 0 || request.programHash == bytes32(0) || request.requester == address(0)) revert InvalidRequest();
        _requireEpoch(request.scopeId, request.keyContextId, request.outputEpoch, true);
        if (request.inputEpoch != request.outputEpoch) {
            KeyEpoch memory target = _registry.epochOf(request.keyContextId, request.outputEpoch);
            KeyEpoch memory source = _registry.epochOf(request.keyContextId, request.inputEpoch);
            if (
                target.carryOver != CarryOver.CONVERT || source.status != EpochStatus.RETIRED
                    || request.outputEpoch != request.inputEpoch + 1
            ) revert ConversionNotDeclared(request.keyContextId, request.inputEpoch, request.outputEpoch);
        }

        ViewDefinition memory definition;
        if (request.viewId != bytes32(0)) {
            definition = _registry.viewOf(request.viewId);
            if (
                definition.scopeId != request.scopeId || definition.retired
                    || definition.keyContextId != request.keyContextId || definition.programHash != request.programHash
            ) revert ViewMismatch(request.viewId);
        }

        for (uint256 i = 0; i < count; ++i) {
            bytes32 inputId = request.inputs[i];
            ProtectedObject storage input = _objects[inputId];
            if (input.status != ObjectStatus.ACCEPTED) revert ObjectNotAccepted(inputId);
            if (input.scopeId != request.scopeId) revert ObjectScopeMismatch(inputId);
            if (input.keyContextId != request.keyContextId || input.keyEpoch != request.inputEpoch) {
                revert KeyContextMismatch(inputId);
            }
            if (request.viewId != bytes32(0) && !_inRange(definition.inputClasses, input.classId)) {
                revert InputOutOfRange(inputId, request.viewId);
            }
            if (
                !_holds(
                    request.scopeId,
                    request.policyVersion,
                    input,
                    request.requester,
                    FHEIF.CAP_REQUEST_OPERATION,
                    request.programHash
                )
            ) revert NotAuthorized(request.requester, FHEIF.CAP_REQUEST_OPERATION);
        }

        Operation storage operation = _operations[operationId];
        operation.request = request;
        operation.status = OperationStatus.ADMITTED;
        emit OperationAdmitted(operationId, request.scopeId, request.requester, request.programHash, request.viewId);
        return operationId;
    }

    function _requireAcceptor(OperationRequest storage request) private view {
        if (
            !_ask(
                request.scopeId,
                request.policyVersion,
                msg.sender,
                FHEIF.CAP_ACCEPT_RESULT,
                request.outputClass,
                request.programHash
            )
        ) revert NotAuthorized(msg.sender, FHEIF.CAP_ACCEPT_RESULT);
    }

    function _rejectOutputs(Operation storage operation) private {
        uint256 count = operation.outputs.length;
        for (uint256 i = 0; i < count; ++i) {
            _objects[operation.outputs[i]].status = ObjectStatus.REJECTED;
        }
    }

    // Internal: disclosures

    function _admitDisclosure(DisclosureRequest calldata request, bytes32 disclosureId) private returns (bytes32) {
        if (_disclosures[disclosureId].status != DisclosureStatus.NONE) revert RequestAlreadyUsed(disclosureId);
        Scope memory scope = _activeScope(request.scopeId);
        if (scope.recordMode != FHEIF.RECORD_OPEN) revert RecordModeMismatch(request.scopeId);
        if (request.policyVersion != scope.policyVersion) {
            revert PolicyVersionMismatch(request.policyVersion, scope.policyVersion);
        }
        if (block.timestamp > request.validUntil) revert RequestExpired(disclosureId);
        if (request.validAfter > request.validUntil || request.audience == address(0) || request.requester == address(0))
        {
            revert InvalidRequest();
        }

        ProtectedObject storage object = _objects[request.objectId];
        if (object.status != ObjectStatus.ACCEPTED) revert ObjectNotAccepted(request.objectId);
        if (object.scopeId != request.scopeId) revert ObjectScopeMismatch(request.objectId);
        if (object.keyContextId != request.keyContextId || object.keyEpoch != request.keyEpoch) {
            revert KeyContextMismatch(request.objectId);
        }
        _requireEpoch(request.scopeId, request.keyContextId, request.keyEpoch, false);

        ViewDefinition memory definition = _registry.viewOf(request.viewId);
        if (definition.scopeId != request.scopeId || definition.retired || definition.keyContextId != object.keyContextId)
        {
            revert ViewMismatch(request.viewId);
        }
        if (definition.programHash == FHEIF.PROGRAM_IDENTITY) {
            if (!_inRange(definition.inputClasses, object.classId)) revert InputOutOfRange(request.objectId, request.viewId);
        } else if (object.viewId != request.viewId) {
            revert ViewMismatch(request.viewId);
        }

        if (
            !_holds(
                request.scopeId,
                scope.policyVersion,
                object,
                request.requester,
                FHEIF.CAP_REQUEST_DISCLOSURE,
                request.viewId
            )
        ) revert NotAuthorized(request.requester, FHEIF.CAP_REQUEST_DISCLOSURE);
        if (
            !_holds(request.scopeId, scope.policyVersion, object, request.audience, FHEIF.CAP_RECEIVE_VIEW, request.viewId)
        ) revert NotAuthorized(request.audience, FHEIF.CAP_RECEIVE_VIEW);

        uint256 required = _requiredApprovals(request.scopeId, scope.policyVersion, object, request.viewId, request.audience);
        if (required > type(uint16).max) revert InvalidRequest();

        Disclosure storage disclosure = _disclosures[disclosureId];
        disclosure.request = request;
        disclosure.approvalsRequired = uint16(required);
        disclosure.status = required == 0 ? DisclosureStatus.AUTHORIZED : DisclosureStatus.REQUESTED;
        emit DisclosureRequested(
            disclosureId,
            request.scopeId,
            request.objectId,
            request.viewId,
            request.audience,
            request.requester,
            required
        );
        if (required == 0) emit DisclosureAuthorized(disclosureId);
        return disclosureId;
    }

    /// @dev Whether a recorded disclosure could be released now. `permanent` tells that the reason
    /// cannot be cured without a new request.
    function _standing(DisclosureRequest storage request)
        private
        view
        returns (bool standing, bytes32 reason, bool permanent)
    {
        Scope memory scope = _registry.scopeOf(request.scopeId);
        if (scope.status == ScopeStatus.CLOSED) return (false, FHEIF.REASON_SCOPE_CLOSED, true);
        if (scope.policyVersion != request.policyVersion) return (false, FHEIF.REASON_POLICY_SUPERSEDED, true);
        EpochStatus epochStatus = _registry.epochOf(request.keyContextId, request.keyEpoch).status;
        if (
            (epochStatus != EpochStatus.ACTIVE && epochStatus != EpochStatus.RETIRED)
                || !_registry.isKeyContextAdmitted(request.scopeId, request.keyContextId)
        ) return (false, FHEIF.REASON_EPOCH_NOT_USABLE, true);
        if (_registry.viewOf(request.viewId).retired) return (false, FHEIF.REASON_VIEW_RETIRED, true);
        if (block.timestamp > request.validUntil) return (false, FHEIF.REASON_EXPIRED, true);
        ProtectedObject storage object = _objects[request.objectId];
        if (
            !_holds(
                request.scopeId,
                scope.policyVersion,
                object,
                request.requester,
                FHEIF.CAP_REQUEST_DISCLOSURE,
                request.viewId
            )
                || !_holds(
                    request.scopeId, scope.policyVersion, object, request.audience, FHEIF.CAP_RECEIVE_VIEW, request.viewId
                )
        ) return (false, FHEIF.REASON_NOT_AUTHORIZED, true);
        if (scope.status == ScopeStatus.PAUSED) return (false, FHEIF.REASON_SCOPE_PAUSED, false);
        if (block.timestamp < request.validAfter) return (false, FHEIF.REASON_NOT_YET_VALID, false);
        return (true, bytes32(0), false);
    }

    function _approver(DisclosureRequest storage request, address account) private view returns (bool) {
        Scope memory scope = _registry.scopeOf(request.scopeId);
        return _ask(
            request.scopeId,
            scope.policyVersion,
            account,
            FHEIF.CAP_APPROVE_DISCLOSURE,
            _objects[request.objectId].classId,
            request.viewId
        );
    }

    function _requiredApprovals(
        bytes32 scopeId,
        uint64 current,
        ProtectedObject storage object,
        bytes32 viewId,
        address audience
    ) private view returns (uint256 required) {
        required = IFHEIFAuthorizer(_registry.policyOf(scopeId, current).authorizer).requiredApprovals(
            scopeId, current, object.classId, viewId, audience
        );
        uint64 home = object.policyVersion;
        if (home != current) {
            Policy memory homePolicy = _registry.policyOf(scopeId, home);
            if (homePolicy.successorRight == SuccessorRight.NARROW_ONLY) {
                uint256 atHome = IFHEIFAuthorizer(homePolicy.authorizer).requiredApprovals(
                    scopeId, home, object.classId, viewId, audience
                );
                if (atHome > required) required = atHome;
            }
        }
    }

    // Internal: shared checks

    function _activeScope(bytes32 scopeId) private view returns (Scope memory scope) {
        scope = _registry.scopeOf(scopeId);
        if (scope.status != ScopeStatus.ACTIVE) revert ScopeNotActive(scopeId, scope.status);
    }

    function _requireCurrent(bytes32 scopeId, uint64 policyVersion, uint64 validUntil, bytes32 requestId) private view {
        Scope memory scope = _activeScope(scopeId);
        if (policyVersion != scope.policyVersion) revert PolicyVersionMismatch(policyVersion, scope.policyVersion);
        if (block.timestamp > validUntil) revert RequestExpired(requestId);
    }

    function _requireEpoch(bytes32 scopeId, bytes32 keyContextId, uint32 epoch, bool active) private view {
        if (!_registry.isKeyContextAdmitted(scopeId, keyContextId)) revert KeyContextNotAdmitted(scopeId, keyContextId);
        EpochStatus status = _registry.epochOf(keyContextId, epoch).status;
        if (status != EpochStatus.ACTIVE && (active || status != EpochStatus.RETIRED)) {
            revert EpochNotUsable(keyContextId, epoch, status);
        }
    }

    function _ask(bytes32 scopeId, uint64 version, address subject, bytes32 capability, bytes32 classId, bytes32 resource)
        private
        view
        returns (bool)
    {
        return IFHEIFAuthorizer(_registry.policyOf(scopeId, version).authorizer).isAuthorized(
            scopeId, version, subject, capability, classId, resource
        );
    }

    /// @dev Authority over an accepted object. A policy version later than the one the object was
    /// accepted under can only take authority away, unless that earlier version reserved otherwise.
    function _holds(
        bytes32 scopeId,
        uint64 current,
        ProtectedObject storage object,
        address subject,
        bytes32 capability,
        bytes32 resource
    ) private view returns (bool) {
        if (!_ask(scopeId, current, subject, capability, object.classId, resource)) return false;
        uint64 home = object.policyVersion;
        if (home == current) return true;
        Policy memory homePolicy = _registry.policyOf(scopeId, home);
        if (homePolicy.successorRight == SuccessorRight.GOVERN) return true;
        return IFHEIFAuthorizer(homePolicy.authorizer).isAuthorized(
            scopeId, home, subject, capability, object.classId, resource
        );
    }

    function _inRange(bytes32[] memory classes, bytes32 classId) private pure returns (bool) {
        uint256 count = classes.length;
        if (count == 0) return true;
        for (uint256 i = 0; i < count; ++i) {
            if (classes[i] == classId) return true;
        }
        return false;
    }

    // Internal: signatures

    function _separator() private view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this)));
    }

    /// @dev A signature is checked once, when the request it carries is admitted. An admitted
    /// request stands on the ledger's record and is not checked against the signer again.
    function _checkSignature(address signer, bytes32 digest, bytes calldata signature) private view {
        if (signature.length == 65) {
            bytes32 r = bytes32(signature[0:32]);
            bytes32 s = bytes32(signature[32:64]);
            uint8 v = uint8(signature[64]);
            if (uint256(s) <= _HALF_ORDER && (v == 27 || v == 28)) {
                address recovered = ecrecover(digest, v, r, s);
                if (recovered != address(0) && recovered == signer) return;
            }
        }
        if (signer.code.length != 0) {
            (bool success, bytes memory result) =
                signer.staticcall(abi.encodeWithSelector(_ERC1271_MAGIC, digest, signature));
            if (success && result.length >= 32 && abi.decode(result, (bytes32)) == bytes32(_ERC1271_MAGIC)) return;
        }
        revert InvalidSignature();
    }
}
