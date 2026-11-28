// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {
    InputSubmission,
    OutputSubmission,
    ProtectedObject,
    OperationRequest,
    Operation,
    DisclosureRequest,
    Disclosure,
    Evidence,
    Anchor,
    ScopeStatus,
    EpochStatus
} from "./FHEIFTypes.sol";

/// @title FHE Interaction Framework: ledger of protected objects, operations, disclosures and evidence
interface IFHEIFLedger {
    event InputSubmitted(
        bytes32 indexed objectId,
        bytes32 indexed scopeId,
        address indexed submitter,
        bytes32 classId,
        bytes32 keyContextId,
        uint32 keyEpoch,
        bytes32 commitment,
        string locator
    );
    event OperationAdmitted(
        bytes32 indexed operationId, bytes32 indexed scopeId, address indexed requester, bytes32 programHash, bytes32 viewId
    );
    event ResultSubmitted(bytes32 indexed operationId, address indexed executor, bytes32[] outputs);
    event OutputProposed(bytes32 indexed objectId, bytes32 indexed operationId, bytes32 commitment, string locator);
    event ResultAccepted(bytes32 indexed operationId, address indexed acceptedBy);
    event ResultRejected(bytes32 indexed operationId, address indexed rejectedBy, bytes32 reason);
    event OperationFailed(bytes32 indexed operationId, address indexed reportedBy, bytes32 reason);
    event OperationCancelled(bytes32 indexed operationId);
    event OperationExpired(bytes32 indexed operationId, bytes32 reason);
    event DisclosureRequested(
        bytes32 indexed disclosureId,
        bytes32 indexed scopeId,
        bytes32 indexed objectId,
        bytes32 viewId,
        address audience,
        address requester,
        uint256 approvalsRequired
    );
    event DisclosureApproved(bytes32 indexed disclosureId, address indexed approver, uint256 approvals);
    event DisclosureAuthorized(bytes32 indexed disclosureId);
    event ReleaseAttested(bytes32 indexed disclosureId, address indexed holder, uint256 attestations);
    event DisclosureReleased(bytes32 indexed disclosureId);
    event DisclosureRefused(bytes32 indexed disclosureId, address indexed refusedBy, bytes32 reason);
    event DisclosureExpired(bytes32 indexed disclosureId);
    event EvidenceRecorded(
        bytes32 indexed subjectId,
        bytes32 indexed proposition,
        bytes32 indexed mechanism,
        address attester,
        bytes32 payloadHash,
        string uri,
        uint256 index
    );
    event RecordAnchored(
        bytes32 indexed commitment, bytes32 indexed scopeId, bytes32 indexed recordKind, address anchoredBy
    );

    error ScopeNotActive(bytes32 scopeId, ScopeStatus status);
    error PolicyVersionMismatch(uint64 named, uint64 current);
    error KeyContextNotAdmitted(bytes32 scopeId, bytes32 keyContextId);
    error EpochNotUsable(bytes32 keyContextId, uint32 epoch, EpochStatus status);
    error ConversionNotDeclared(bytes32 keyContextId, uint32 inputEpoch, uint32 outputEpoch);
    error NotAuthorized(address subject, bytes32 capability);
    error ObjectExists(bytes32 objectId);
    error ObjectNotAccepted(bytes32 objectId);
    error ObjectScopeMismatch(bytes32 objectId);
    error KeyContextMismatch(bytes32 objectId);
    error ViewMismatch(bytes32 viewId);
    error InputOutOfRange(bytes32 objectId, bytes32 viewId);
    error RequestAlreadyUsed(bytes32 requestId);
    error RequestExpired(bytes32 requestId);
    error InvalidRequest();
    error InvalidSignature();
    error InvalidState(bytes32 id);
    error NotRequester(address caller);
    error NotDesignatedExecutor(address caller);
    error NotKeyHolder(address caller);
    error AlreadyRecorded(address caller);
    error NotReleasable(bytes32 disclosureId, bytes32 reason);
    error StillReleasable(bytes32 disclosureId);
    error NotExpired(bytes32 id);
    error RecordModeMismatch(bytes32 scopeId);
    error UnknownSubject(bytes32 subjectId);

    /// @notice The registry this ledger reads scopes, key contexts and views from.
    function registry() external view returns (address);

    /// @notice The EIP-712 domain separator of this ledger.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The identifier of an operation request: its EIP-712 digest under this ledger's domain.
    function hashOperationRequest(OperationRequest calldata request) external view returns (bytes32);

    /// @notice The identifier of a disclosure request: its EIP-712 digest under this ledger's domain.
    function hashDisclosureRequest(DisclosureRequest calldata request) external view returns (bytes32);

    // Protected objects

    /// @notice Registers an input as a protected object of a scope. It is accepted on registration.
    function submitInput(InputSubmission calldata submission) external returns (bytes32 objectId);

    function objectOf(bytes32 objectId) external view returns (ProtectedObject memory);

    // Operations

    /// @notice Admits an operation requested by the caller.
    function requestOperation(OperationRequest calldata request) external returns (bytes32 operationId);

    /// @notice Admits an operation on a signature of `request.requester` over the request.
    function requestOperationWithSignature(OperationRequest calldata request, bytes calldata signature)
        external
        returns (bytes32 operationId);

    /// @notice Records the outputs an executor proposes for an admitted operation.
    function submitResult(bytes32 operationId, OutputSubmission[] calldata outputs)
        external
        returns (bytes32[] memory objectIds);

    /// @notice Accepts a submitted result. Its outputs become accepted objects of the scope.
    function acceptResult(bytes32 operationId) external;

    function rejectResult(bytes32 operationId, bytes32 reason) external;

    /// @notice Reports that an admitted operation cannot be carried out.
    function failOperation(bytes32 operationId, bytes32 reason) external;

    function cancelOperation(bytes32 operationId) external;

    /// @notice Ends an operation that can no longer be completed.
    function expireOperation(bytes32 operationId) external;

    function operationOf(bytes32 operationId) external view returns (Operation memory);

    // Disclosures

    /// @notice Records a disclosure request of the caller.
    function requestDisclosure(DisclosureRequest calldata request) external returns (bytes32 disclosureId);

    /// @notice Records a disclosure request on a signature of `request.requester` over the request.
    function requestDisclosureWithSignature(DisclosureRequest calldata request, bytes calldata signature)
        external
        returns (bytes32 disclosureId);

    function approveDisclosure(bytes32 disclosureId) external;

    /// @notice Records that a key holder contributes to the release, after checking again that the
    /// release is authorized now. The disclosure is released when the epoch's quorum has attested.
    function attestRelease(bytes32 disclosureId) external;

    function refuseDisclosure(bytes32 disclosureId, bytes32 reason) external;

    function expireDisclosure(bytes32 disclosureId) external;

    /// @notice Whether a release could proceed now, and if not, why.
    function isReleasable(bytes32 disclosureId) external view returns (bool releasable, bytes32 reason);

    function disclosureOf(bytes32 disclosureId) external view returns (Disclosure memory);

    function hasApproved(bytes32 disclosureId, address approver) external view returns (bool);

    function hasAttested(bytes32 disclosureId, address holder) external view returns (bool);

    // Evidence

    /// @notice Records evidence of the caller about an object, an operation, a disclosure or an anchor.
    function recordEvidence(
        bytes32 subjectId,
        bytes32 proposition,
        bytes32 mechanism,
        bytes32 payloadHash,
        string calldata uri
    ) external returns (uint256 index);

    function evidenceCount(bytes32 subjectId) external view returns (uint256);

    function evidenceAt(bytes32 subjectId, uint256 index) external view returns (Evidence memory);

    // Committed records

    /// @notice Anchors the commitment of a record that is kept off the ledger.
    function anchorRecord(bytes32 scopeId, bytes32 recordKind, bytes32 commitment) external;

    function anchorOf(bytes32 commitment) external view returns (Anchor memory);

    /// @notice Whether `commitment` opens to `recordHash` with `salt`.
    function verifyRecordOpening(bytes32 commitment, bytes32 recordHash, bytes32 salt) external pure returns (bool);

    /// @notice Whether `leaf` is a member of the batch committed by `root`.
    function verifyBatchMembership(bytes32 root, bytes32 leaf, bytes32[] calldata proof) external pure returns (bool);
}
