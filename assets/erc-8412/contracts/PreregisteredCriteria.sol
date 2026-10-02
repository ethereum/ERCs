// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice ERC-165 interface detection.
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @title ERC-8412 Preregistered Acceptance Criteria — registry interface (§6)
interface IPreregisteredCriteria {
    enum Verdict { None, Satisfied, NotSatisfied, Indeterminate, ExpiredUnresolved }

    event CriteriaPreregistered(
        bytes32 indexed preregistrationId,
        address indexed author,
        bytes32 criteriaDigest,
        bytes32 indexed taskRef,
        uint16 obligationCount,
        bytes obligationFlags,
        uint64 expiry,
        address verifier,
        bytes32 supersedes
    );

    event OutcomeAttested(
        bytes32 indexed preregistrationId,
        address indexed verifier,
        bytes32 bundleDigest,
        bytes32 attestationDigest,
        Verdict verdict,
        bytes obligationOutcomes
    );

    event ExpiredResolved(bytes32 indexed preregistrationId, address indexed caller);

    function preregister(
        bytes32 criteriaDigest,
        bytes32 taskRef,
        uint16 obligationCount,
        bytes calldata obligationFlags,
        uint64 expiry,
        address verifier,
        bytes32 supersedes
    ) external returns (bytes32 preregistrationId);

    function attestOutcome(
        bytes32 preregistrationId,
        bytes32 bundleDigest,
        bytes32 attestationDigest,
        Verdict verdict,
        bytes calldata obligationOutcomes
    ) external;

    function resolveExpired(bytes32 preregistrationId) external;

    function getPreregistration(bytes32 preregistrationId) external view returns (
        address author, bytes32 criteriaDigest, bytes32 taskRef,
        uint16 obligationCount, bytes memory obligationFlags,
        uint64 expiry, uint64 registeredAt,
        address verifier, bytes32 supersedes, bytes32 supersededBy
    );

    function getAttestation(bytes32 preregistrationId) external view returns (
        address verifier, bytes32 bundleDigest, bytes32 attestationDigest,
        Verdict verdict, bytes memory obligationOutcomes, uint64 attestedAt
    );
}

/// @title ERC-8412 reference registry
/// @notice Minimal conforming implementation. Each custom error names the
///         invariant (§7) it enforces. Mirrors model/registry.py.
/// @dev Reference code: unaudited, not optimised for gas.
contract PreregisteredCriteria is IPreregisteredCriteria, IERC165 {
    // obligationFlags pair values (§5): bit 0 = required, bit 1 = waivable
    uint8 private constant REQUIRED = 1;
    uint8 private constant WAIVABLE = 2;
    // obligationOutcomes pair values (§5)
    uint8 private constant UNMET = 0;
    uint8 private constant MET = 1;
    uint8 private constant WAIVED = 2;
    uint8 private constant NOT_APPLICABLE = 3;

    struct Prereg {
        address author;
        uint16 obligationCount;
        uint64 expiry;
        uint64 registeredAt;
        address verifier;
        bytes32 criteriaDigest;
        bytes32 taskRef;
        bytes32 supersedes;
        bytes32 supersededBy;
        bytes obligationFlags;
    }

    struct Att {
        address verifier;
        uint64 attestedAt;
        Verdict verdict;
        bytes32 bundleDigest;
        bytes32 attestationDigest;
        bytes obligationOutcomes;
    }

    mapping(bytes32 => Prereg) private _preregs;
    mapping(bytes32 => Att) private _atts;

    error UnknownPreregistration();
    error DuplicatePreregistration();
    error E1_ExpiryNotInFuture();
    error E2_BadPackedLength();
    error E2_NonZeroPadBits();
    error E3_NotVerifier();
    error E4_RequiredNotMet(uint256 index);
    error E5_NotWaivable(uint256 index);
    error E6_NotApplicableOnRequired(uint256 index);
    error E7_PastExpiry();
    error E8_NotExpired();
    error E8_VerdictRecorded();
    error E8_Superseded();
    error E9_InvalidVerdict();
    error E10_VerdictFinal();
    error E11_NoUnmetObligation();
    error E12_UnknownPrior();
    error E12_DifferentAuthorOrTask();
    error E12_AlreadySuperseded();
    error E12_PriorFinal();
    error E13_Superseded();
    error E14_ZeroVerifier();
    error E14_AuthorIsVerifier();

    // ------------------------------------------------------------------ writes

    /// @inheritdoc IPreregisteredCriteria
    function preregister(
        bytes32 criteriaDigest,
        bytes32 taskRef,
        uint16 obligationCount,
        bytes calldata obligationFlags,
        uint64 expiry,
        address verifier,
        bytes32 supersedes
    ) external returns (bytes32 preregistrationId) {
        if (expiry <= block.timestamp) revert E1_ExpiryNotInFuture();
        _checkPacked(obligationFlags, obligationCount);
        if (verifier == address(0)) revert E14_ZeroVerifier();
        if (verifier == msg.sender) revert E14_AuthorIsVerifier();

        preregistrationId =
            keccak256(abi.encode(block.chainid, address(this), msg.sender, criteriaDigest, taskRef));
        if (_preregs[preregistrationId].registeredAt != 0) revert DuplicatePreregistration();

        if (supersedes != bytes32(0)) {
            _supersede(supersedes, taskRef, preregistrationId);
        }

        Prereg storage p = _preregs[preregistrationId];
        p.author = msg.sender;
        p.obligationCount = obligationCount;
        p.expiry = expiry;
        p.registeredAt = uint64(block.timestamp);
        p.verifier = verifier;
        p.criteriaDigest = criteriaDigest;
        p.taskRef = taskRef;
        p.supersedes = supersedes;
        p.obligationFlags = obligationFlags;

        _emitPreregistered(preregistrationId);
    }

    /// @inheritdoc IPreregisteredCriteria
    function attestOutcome(
        bytes32 preregistrationId,
        bytes32 bundleDigest,
        bytes32 attestationDigest,
        Verdict verdict,
        bytes calldata obligationOutcomes
    ) external {
        Prereg storage p = _preregs[preregistrationId];
        if (p.registeredAt == 0) revert UnknownPreregistration();
        if (msg.sender != p.verifier) revert E3_NotVerifier();
        if (p.supersededBy != bytes32(0)) revert E13_Superseded();
        if (_atts[preregistrationId].verdict != Verdict.None) revert E10_VerdictFinal();
        if (block.timestamp > p.expiry) revert E7_PastExpiry();
        if (verdict != Verdict.Satisfied && verdict != Verdict.NotSatisfied
            && verdict != Verdict.Indeterminate) revert E9_InvalidVerdict();
        _checkPacked(obligationOutcomes, p.obligationCount);
        _checkOutcomes(p.obligationFlags, obligationOutcomes, p.obligationCount, verdict);

        Att storage a = _atts[preregistrationId];
        a.verifier = msg.sender;
        a.attestedAt = uint64(block.timestamp);
        a.verdict = verdict;
        a.bundleDigest = bundleDigest;
        a.attestationDigest = attestationDigest;
        a.obligationOutcomes = obligationOutcomes;

        _emitAttested(preregistrationId);
    }

    /// @inheritdoc IPreregisteredCriteria
    function resolveExpired(bytes32 preregistrationId) external {
        Prereg storage p = _preregs[preregistrationId];
        if (p.registeredAt == 0) revert UnknownPreregistration();
        if (block.timestamp <= p.expiry) revert E8_NotExpired();
        if (_atts[preregistrationId].verdict != Verdict.None) revert E8_VerdictRecorded();
        if (p.supersededBy != bytes32(0)) revert E8_Superseded();

        _atts[preregistrationId].verdict = Verdict.ExpiredUnresolved;
        emit ExpiredResolved(preregistrationId, msg.sender);
    }

    // ------------------------------------------------------------------ views

    /// @inheritdoc IPreregisteredCriteria
    function getPreregistration(bytes32 preregistrationId) external view returns (
        address author, bytes32 criteriaDigest, bytes32 taskRef,
        uint16 obligationCount, bytes memory obligationFlags,
        uint64 expiry, uint64 registeredAt,
        address verifier, bytes32 supersedes, bytes32 supersededBy
    ) {
        Prereg storage p = _preregs[preregistrationId];
        author = p.author;
        criteriaDigest = p.criteriaDigest;
        taskRef = p.taskRef;
        obligationCount = p.obligationCount;
        obligationFlags = p.obligationFlags;
        expiry = p.expiry;
        registeredAt = p.registeredAt;
        verifier = p.verifier;
        supersedes = p.supersedes;
        supersededBy = p.supersededBy;
    }

    /// @inheritdoc IPreregisteredCriteria
    function getAttestation(bytes32 preregistrationId) external view returns (
        address verifier, bytes32 bundleDigest, bytes32 attestationDigest,
        Verdict verdict, bytes memory obligationOutcomes, uint64 attestedAt
    ) {
        Att storage a = _atts[preregistrationId];
        return (a.verifier, a.bundleDigest, a.attestationDigest, a.verdict,
                a.obligationOutcomes, a.attestedAt);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IPreregisteredCriteria).interfaceId
            || interfaceId == type(IERC165).interfaceId;
    }

    // ------------------------------------------------------------------ internals

    /// Events are emitted from storage in separate frames to stay within the
    /// 16-slot stack limit without requiring via-IR compilation.
    function _emitPreregistered(bytes32 id) private {
        Prereg storage p = _preregs[id];
        emit CriteriaPreregistered(
            id, p.author, p.criteriaDigest, p.taskRef, p.obligationCount,
            p.obligationFlags, p.expiry, p.verifier, p.supersedes
        );
    }

    function _emitAttested(bytes32 id) private {
        Att storage a = _atts[id];
        emit OutcomeAttested(
            id, a.verifier, a.bundleDigest, a.attestationDigest, a.verdict, a.obligationOutcomes
        );
    }

    /// E12: only the same author and taskRef, only once, only from no verdict or Indeterminate.
    function _supersede(bytes32 prior, bytes32 taskRef, bytes32 successor) private {
        Prereg storage q = _preregs[prior];
        if (q.registeredAt == 0) revert E12_UnknownPrior();
        if (q.author != msg.sender || q.taskRef != taskRef) revert E12_DifferentAuthorOrTask();
        if (q.supersededBy != bytes32(0)) revert E12_AlreadySuperseded();
        Verdict v = _atts[prior].verdict;
        if (v != Verdict.None && v != Verdict.Indeterminate) revert E12_PriorFinal();
        q.supersededBy = successor;
    }

    /// E2: exact length ceil(2n/8) and zero trailing pad bits.
    function _checkPacked(bytes calldata packed, uint256 n) private pure {
        if (packed.length != (2 * n + 7) / 8) revert E2_BadPackedLength();
        uint256 used = (2 * n) % 8;
        if (used != 0) {
            uint8 padMask = uint8((uint256(1) << (8 - used)) - 1);
            if (uint8(packed[packed.length - 1]) & padMask != 0) revert E2_NonZeroPadBits();
        }
    }

    /// 2-bit field i, most-significant bits first (§5).
    function _pair(bytes memory packed, uint256 i) private pure returns (uint8) {
        return (uint8(packed[i / 4]) >> uint8(6 - 2 * (i % 4))) & 3;
    }

    /// E4, E5, E6, E11.
    function _checkOutcomes(
        bytes memory flags,
        bytes memory outcomes,
        uint256 n,
        Verdict verdict
    ) private pure {
        bool anyUnmet;
        bool requiredShortfall;
        uint256 shortfallIndex;
        for (uint256 i = 0; i < n; i++) {
            uint8 flag = _pair(flags, i);
            uint8 out = _pair(outcomes, i);
            bool required = flag & REQUIRED != 0;
            if (out == NOT_APPLICABLE && required) revert E6_NotApplicableOnRequired(i);
            if (out == WAIVED && flag & WAIVABLE == 0) revert E5_NotWaivable(i);
            if (out == UNMET) anyUnmet = true;
            if (required && out != MET && out != WAIVED && !requiredShortfall) {
                requiredShortfall = true;
                shortfallIndex = i;
            }
        }
        if (verdict == Verdict.Satisfied && requiredShortfall) revert E4_RequiredNotMet(shortfallIndex);
        if ((verdict == Verdict.NotSatisfied || verdict == Verdict.Indeterminate) && !anyUnmet) {
            revert E11_NoUnmetObligation();
        }
    }
}
