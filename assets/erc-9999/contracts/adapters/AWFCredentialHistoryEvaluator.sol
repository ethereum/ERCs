// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {IAWFEvaluator} from "../interfaces/IAWFEvaluator.sol";
import {Match, SubjectRef, Request, KIND_ENTRY} from "../interfaces/AWFTypes.sol";

/// @dev The view of an assertion registry this adapter reads: the highest level a set of issuers
/// currently asserts for a subject under a scheme, with expiry, revocation and the binding of the
/// assertion to the subject's controller already applied by the registry.
interface IAssertionSource {
    struct Subject {
        bytes32 subjectType;
        bytes subjectData;
    }

    function resolve(Subject calldata subject, bytes32 schemeId, address[] calldata issuers)
        external
        view
        returns (uint8 level, uint64 expiresAt, bytes32 assertionId);
}

/// @dev The view of a task ledger this adapter reads: one submission of one task.
interface ITaskLedger {
    struct Submission {
        address fulfiller;
        bytes32 resultHash;
        uint64 taskVersion;
        uint64 submittedAt;
        bool machineSettled;
        uint8 status; // 0 pending, 1 accepted, 2 rejected
    }

    function submissionOf(uint256 tokenId, uint256 submissionId) external view returns (Submission memory);
}

/// @title Evaluator: a credential and a delivery history
/// @notice Example of a PREDICATE list. A registry entry (for instance an agent identity) is a
/// member while (1) an accepted issuer asserts at least `minLevel` for it under `schemeId`, and
/// (2) its current controller shows at least `minAccepted` accepted task submissions made within
/// `window` seconds. The credential is read from the assertion registry. The history is presented
/// by the requester as a list of submissions and each one is checked on the task ledger.
///
/// The configuration is immutable. Another threshold is another deployment and therefore another
/// version of the criteria.
contract AWFCredentialHistoryEvaluator is IAWFEvaluator {
    struct TaskRef {
        uint256 tokenId;
        uint256 submissionId;
    }

    bytes32 public constant SUBJECT_TYPE_ERC8004 = keccak256("erc8004");
    uint256 public constant MAX_REFS = 16;

    bytes32 internal constant R_CRITERIA_MET = "CRITERIA_MET";
    bytes32 internal constant R_RULE_UNKNOWN = "RULE_UNKNOWN";
    bytes32 internal constant R_SUBJECT_UNSUPPORTED = "SUBJECT_UNSUPPORTED";
    bytes32 internal constant R_CONTROLLER_UNKNOWN = "CONTROLLER_UNKNOWN";
    bytes32 internal constant R_SOURCE_UNAVAILABLE = "SOURCE_UNAVAILABLE";
    bytes32 internal constant R_CREDENTIAL_NOT_VALID = "CREDENTIAL_NOT_VALID";
    bytes32 internal constant R_EVIDENCE_NOT_PRESENTED = "EVIDENCE_NOT_PRESENTED";
    bytes32 internal constant R_EVIDENCE_MALFORMED = "EVIDENCE_MALFORMED";
    bytes32 internal constant R_HISTORY_INSUFFICIENT = "HISTORY_INSUFFICIENT";

    IAssertionSource public immutable assertions;
    ITaskLedger public immutable ledger;
    bytes32 public immutable schemeId;
    uint8 public immutable minLevel;
    uint32 public immutable minAccepted;
    uint64 public immutable window;
    address[] private _issuers;

    constructor(
        address assertions_,
        bytes32 schemeId_,
        uint8 minLevel_,
        address[] memory issuers_,
        address ledger_,
        uint32 minAccepted_,
        uint64 window_
    ) {
        require(issuers_.length != 0 && minAccepted_ != 0 && minAccepted_ <= MAX_REFS && window_ != 0, "config");
        assertions = IAssertionSource(assertions_);
        ledger = ITaskLedger(ledger_);
        schemeId = schemeId_;
        minLevel = minLevel_;
        minAccepted = minAccepted_;
        window = window_;
        _issuers = issuers_;
    }

    function issuers() external view returns (address[] memory) {
        return _issuers;
    }

    /// @notice Also the value criteria name as their rule.
    function configHash() public view returns (bytes32) {
        return keccak256(
            abi.encode(block.chainid, assertions, schemeId, minLevel, _issuers, ledger, minAccepted, window)
        );
    }

    function evaluate(bytes32, bytes32 rule, SubjectRef calldata subject, Request calldata request, bytes calldata evidence)
        external
        view
        returns (Match, bytes32, uint64, bytes32)
    {
        if (rule != configHash()) return (Match.UNDETERMINED, R_RULE_UNKNOWN, 0, 0);
        // Only what this chain can read is decided here.
        if (subject.kind != KIND_ENTRY || subject.chainId != block.chainid) {
            return (Match.UNDETERMINED, R_SUBJECT_UNSUPPORTED, 0, 0);
        }
        // The history counts for the account that controls the subject now.
        if (request.controller == address(0)) return (Match.UNDETERMINED, R_CONTROLLER_UNKNOWN, 0, 0);

        uint64 validUntil;
        bytes32 assertionId;
        {
            IAssertionSource.Subject memory s = IAssertionSource.Subject({
                subjectType: SUBJECT_TYPE_ERC8004,
                subjectData: abi.encode(subject.chainId, subject.namespace, uint256(subject.id))
            });
            try assertions.resolve(s, schemeId, _issuers) returns (uint8 level, uint64 expiresAt, bytes32 id) {
                if (id == bytes32(0) || level < minLevel) return (Match.NO_MATCH, R_CREDENTIAL_NOT_VALID, 0, 0);
                validUntil = expiresAt == 0 ? type(uint64).max : expiresAt - 1;
                assertionId = id;
            } catch {
                // Not being able to read the registry is not a finding about the subject.
                return (Match.UNDETERMINED, R_SOURCE_UNAVAILABLE, 0, 0);
            }
        }

        // These criteria make presenting the history a condition: without it the answer is no.
        if (evidence.length == 0) return (Match.NO_MATCH, R_EVIDENCE_NOT_PRESENTED, 0, assertionId);
        TaskRef[] memory refs = abi.decode(evidence, (TaskRef[]));
        if (refs.length > MAX_REFS) return (Match.UNDETERMINED, R_EVIDENCE_MALFORMED, 0, 0);

        uint256 counted;
        for (uint256 i; i < refs.length; ++i) {
            // Strictly ascending references: no submission is counted twice.
            if (
                i != 0
                    && (
                        refs[i].tokenId < refs[i - 1].tokenId
                            || (refs[i].tokenId == refs[i - 1].tokenId && refs[i].submissionId <= refs[i - 1].submissionId)
                    )
            ) return (Match.UNDETERMINED, R_EVIDENCE_MALFORMED, 0, 0);
            try ledger.submissionOf(refs[i].tokenId, refs[i].submissionId) returns (ITaskLedger.Submission memory sub) {
                if (
                    sub.status == 1 && sub.fulfiller == request.controller
                        && uint256(sub.submittedAt) + window > block.timestamp
                ) {
                    ++counted;
                    uint64 until = sub.submittedAt + window - 1;
                    if (until < validUntil) validUntil = until;
                }
            } catch {
                return (Match.UNDETERMINED, R_SOURCE_UNAVAILABLE, 0, 0);
            }
        }
        bytes32 basis = keccak256(abi.encode(assertionId, keccak256(evidence)));
        if (counted < minAccepted) return (Match.NO_MATCH, R_HISTORY_INSUFFICIENT, 0, basis);
        return (Match.MATCH, R_CRITERIA_MET, validUntil, basis);
    }
}
