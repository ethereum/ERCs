// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

import {IDiveLogTypes} from "./interfaces/IDiveLogTypes.sol";
import {IDiveLog} from "./interfaces/IDiveLog.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {DiveLogTypedData} from "./interfaces/IDiveLogTypedData.sol";

/// @title ERC-8260 reference implementation: a sovereign, append-only dive logbook.
/// @notice One owner account logs thin, self-sufficient dive headers that bind a
///         required SHA-256 content hash of the exact attested UDDF 3.x file.
///         Attestations are optional EIP-712 signatures over that hash. SHA-256 is
///         not computed on-chain; the owner supplies the hash. Corrections use
///         void/supersede; headers are never mutated or deleted.
contract SovereignDiveLog is IDiveLog {
    // secp256k1n / 2 — upper bound for canonical (non-malleable) s values (EIP-2)
    uint256 private constant _HALF_N = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    /// @notice Maximum dives accepted per `batchLogDives` call.
    uint256 public constant MAX_BATCH_SIZE = 100;

    address public immutable owner;

    uint256 public diveCount;

    /// @dev Packed storage record; the `id` is the mapping key, filled on read.
    struct DiveRecord {
        // slot 1 (30 bytes)
        uint32 diveDate;
        uint64 startTime;
        uint32 maxDepth;
        uint32 durationSeconds;
        uint32 bottomTimeSeconds;
        IDiveLogTypes.DiveMode mode;
        IDiveLogTypes.UnitSystem units;
        uint16 o2Bps;
        uint16 heBps;
        // slot 2 (26 bytes)
        bytes16 tableSchedule;
        uint32 surfaceIntervalSeconds;
        bytes1 repetitiveGroup;
        bytes1 repetitiveGroupAfterSI;
        bytes4 coarseGeohash;
        // slot 3
        bytes32 contentHash;
        // slot 4 (only when non-empty)
        string profileURI;
    }

    mapping(uint256 => DiveRecord) private _dives;
    mapping(uint256 => IDiveLogTypes.VoidInfo) private _voids;
    mapping(uint256 => IDiveLogTypes.Attestation[]) private _attestations;
    mapping(uint256 => mapping(address => bool)) private _hasAttested;
    mapping(address => uint256) private _attesterNonces;

    constructor(address _owner) {
        owner = _owner;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IDiveLog).interfaceId;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ---------------------------------------------------------------- logging

    function logDive(IDiveLogTypes.DiveInput calldata input) external onlyOwner returns (uint256) {
        _validate(input);
        uint256 diveId = ++diveCount;
        _dives[diveId] = _toRecord(input);
        emit DiveLogged(diveId, input.diveDate, input.contentHash);
        return diveId;
    }

    function batchLogDives(IDiveLogTypes.DiveInput[] calldata inputs) external onlyOwner returns (uint256[] memory) {
        uint256 len = inputs.length;
        if (len == 0 || len > MAX_BATCH_SIZE) revert InvalidBatchSize(len);
        uint256[] memory ids = new uint256[](len);
        for (uint256 i; i < len;) {
            _validate(inputs[i]);
            uint256 diveId = ++diveCount;
            _dives[diveId] = _toRecord(inputs[i]);
            ids[i] = diveId;
            emit DiveLogged(diveId, inputs[i].diveDate, inputs[i].contentHash);
            unchecked {
                ++i;
            }
        }
        return ids;
    }

    // ------------------------------------------------------------- corrective

    function voidDive(uint256 diveId, uint256 supersededById, string calldata reason) external onlyOwner {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        if (_voids[diveId].isVoided) revert DiveAlreadyVoided(diveId);
        if (supersededById != 0) {
            if (supersededById == diveId || supersededById > diveCount) {
                revert InvalidSupersede(diveId, supersededById);
            }
            if (_voids[supersededById].isVoided) revert InvalidSupersede(diveId, supersededById);
        }
        _voids[diveId] = IDiveLogTypes.VoidInfo({
            supersededById: supersededById,
            isVoided: true,
            voidedBy: msg.sender,
            voidedAt: uint64(block.timestamp),
            reason: reason
        });
        emit DiveVoided(diveId, supersededById, msg.sender, reason);
    }

    // ------------------------------------------------------------ attestations

    function attestDive(uint256 diveId, bytes32 contentHash, uint256 nonce, bytes calldata signature) external {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        if (_voids[diveId].isVoided) revert DiveAlreadyVoided(diveId);
        if (contentHash != _dives[diveId].contentHash) revert InvalidContentHash();

        bytes32 digest = DiveLogTypedData.attestationDigest(diveId, contentHash, address(this), block.chainid, nonce);
        address attester = _recoverSigner(digest, signature);
        if (attester == address(0)) revert InvalidSignature();
        if (_attesterNonces[attester] != nonce) revert NonceMismatch(_attesterNonces[attester], nonce);
        if (_hasAttested[diveId][attester]) revert AlreadyAttested(diveId, attester);

        _attesterNonces[attester] = nonce + 1;
        _hasAttested[diveId][attester] = true;
        _attestations[diveId].push(IDiveLogTypes.Attestation({attester: attester, attestedAt: uint64(block.timestamp), nonce: nonce}));

        emit DiveAttested(diveId, attester, contentHash);
    }

    function cancelAttestationNonce() external {
        uint256 newNonce = _attesterNonces[msg.sender] + 1;
        _attesterNonces[msg.sender] = newNonce;
        emit AttestationNonceCancelled(msg.sender, newNonce);
    }

    // ------------------------------------------------------------------- reads

    function getDive(uint256 diveId) external view returns (IDiveLogTypes.DiveHeader memory) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _toHeader(diveId, _dives[diveId]);
    }

    function getDiveCount() external view returns (uint256) {
        return diveCount;
    }

    function isDiveVoided(uint256 diveId) external view returns (bool) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _voids[diveId].isVoided;
    }

    function getVoidInfo(uint256 diveId) external view returns (IDiveLogTypes.VoidInfo memory) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _voids[diveId];
    }

    function attestationCount(uint256 diveId) external view returns (uint256) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _attestations[diveId].length;
    }

    function getAttestation(uint256 diveId, uint256 index) external view returns (IDiveLogTypes.Attestation memory) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        if (index >= _attestations[diveId].length) revert InvalidAttestationIndex(index);
        return _attestations[diveId][index];
    }

    function attesterNonce(address attester) external view returns (uint256) {
        return _attesterNonces[attester];
    }

    // -------------------------------------------------------------- validation

    /// @dev All behavior requirements for `logDive`/`batchLogDives`, applied per item.
    function _validate(IDiveLogTypes.DiveInput calldata input) private pure {
        if (input.maxDepth == 0) revert InvalidDepth();
        if (input.durationSeconds == 0) revert InvalidTimes();
        if (input.bottomTimeSeconds != 0 && input.bottomTimeSeconds > input.durationSeconds) revert InvalidTimes();
        if (input.contentHash == bytes32(0)) revert InvalidContentHash();
        if ((input.o2Bps | input.heBps) != 0 && uint256(input.o2Bps) + input.heBps > 10000) revert InvalidGasMix();
        if (!_isValidDate(input.diveDate)) revert InvalidDate();
        if (input.startTime == 0 || _dateFromTimestamp(input.startTime) != input.diveDate) revert InvalidDate();
        if (!_isValidTableSchedule(input.tableSchedule)) revert InvalidTableSchedule();

        bytes1 rg = input.repetitiveGroup;
        bytes1 rgAfter = input.repetitiveGroupAfterSI;
        bool rgOk = rg == 0x00 || (rg >= 0x41 && rg <= 0x5A);
        bool rgAfterOk = rgAfter == 0x00 || (rgAfter >= 0x41 && rgAfter <= 0x5A);
        if (!rgOk || !rgAfterOk) revert InvalidRepetitiveGroup();
        if (rg != 0x00 || rgAfter != 0x00) {
            if (input.tableSchedule == bytes16(0)) revert InvalidRepetitiveGroup();
            if (rgAfter != 0x00 && input.surfaceIntervalSeconds == 0) revert InvalidRepetitiveGroup();
        }
    }

    /// @dev `bytes16(0)` = not recorded; otherwise right-NUL-padded printable
    ///      ASCII whose first token is in the normative set, with no interior NULs.
    function _isValidTableSchedule(bytes16 ts) private pure returns (bool) {
        if (ts == bytes16(0)) return true;
        bool seenNul = false;
        uint256 tokenLen = 0;
        bool tokenDone = false;
        for (uint256 i; i < 16; ++i) {
            bytes1 b = ts[i];
            if (b == 0x00) {
                seenNul = true;
                continue;
            }
            if (seenNul) return false; // data after a NUL (interior NUL / left-NUL padding)
            if (b < 0x20 || b > 0x7E) return false; // non-printable
            if (b == 0x20) {
                tokenDone = true;
            } else if (!tokenDone) {
                tokenLen++;
            }
        }
        if (tokenLen == 0) return false;
        bytes memory token = new bytes(tokenLen);
        for (uint256 i; i < tokenLen; ++i) {
            token[i] = ts[i];
        }
        bytes32 h = keccak256(token);
        return h == keccak256("USN") || h == keccak256("PADI") || h == keccak256("NAUI") || h == keccak256("BSAC")
            || h == keccak256("BUEHL") || h == keccak256("DCIEM") || h == keccak256("CSMD")
            || h == keccak256("COMEX") || h == keccak256("OTHER");
    }

    /// @dev Valid Gregorian YYYYMMDD with year >= 1970 (leap years included).
    function _isValidDate(uint32 date) private pure returns (bool) {
        uint256 y = date / 10000;
        uint256 m = (date / 100) % 100;
        uint256 d = date % 100;
        if (y < 1970 || m < 1 || m > 12 || d < 1 || d > _daysInMonth(y, m)) return false;
        return true;
    }

    function _daysInMonth(uint256 y, uint256 m) private pure returns (uint256) {
        if (m == 4 || m == 6 || m == 9 || m == 11) return 30;
        if (m == 2) return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
        return 31;
    }

    /// @dev UTC calendar date (YYYYMMDD) of a Unix timestamp (civil-from-days).
    function _dateFromTimestamp(uint64 ts) private pure returns (uint32) {
        uint256 z = uint256(ts) / 86400 + 719468;
        uint256 era = z / 146097;
        uint256 doe = z - era * 146097;
        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        uint256 y = yoe + era * 400;
        uint256 doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;
        uint256 d = doy - (153 * mp + 2) / 5 + 1;
        uint256 m = mp < 10 ? mp + 3 : mp - 9;
        if (m <= 2) ++y;
        return uint32(y * 10000 + m * 100 + d);
    }

    // ---------------------------------------------------------------- helpers

    function _toRecord(IDiveLogTypes.DiveInput calldata input) private pure returns (DiveRecord memory r) {
        r.diveDate = input.diveDate;
        r.startTime = input.startTime;
        r.maxDepth = input.maxDepth;
        r.durationSeconds = input.durationSeconds;
        r.bottomTimeSeconds = input.bottomTimeSeconds;
        r.mode = input.mode;
        r.units = input.units;
        r.o2Bps = input.o2Bps;
        r.heBps = input.heBps;
        r.tableSchedule = input.tableSchedule;
        r.surfaceIntervalSeconds = input.surfaceIntervalSeconds;
        r.repetitiveGroup = input.repetitiveGroup;
        r.repetitiveGroupAfterSI = input.repetitiveGroupAfterSI;
        r.coarseGeohash = input.coarseGeohash;
        r.contentHash = input.contentHash;
        r.profileURI = input.profileURI;
    }

    function _toHeader(uint256 id, DiveRecord storage r) private view returns (IDiveLogTypes.DiveHeader memory h) {
        h.id = id;
        h.diveDate = r.diveDate;
        h.startTime = r.startTime;
        h.maxDepth = r.maxDepth;
        h.durationSeconds = r.durationSeconds;
        h.bottomTimeSeconds = r.bottomTimeSeconds;
        h.mode = r.mode;
        h.units = r.units;
        h.o2Bps = r.o2Bps;
        h.heBps = r.heBps;
        h.tableSchedule = r.tableSchedule;
        h.surfaceIntervalSeconds = r.surfaceIntervalSeconds;
        h.repetitiveGroup = r.repetitiveGroup;
        h.repetitiveGroupAfterSI = r.repetitiveGroupAfterSI;
        h.coarseGeohash = r.coarseGeohash;
        h.contentHash = r.contentHash;
        h.profileURI = r.profileURI;
    }

    /// @dev 65-byte `r ‖ s ‖ v` with v in {27, 28}; rejects high-`s` (EIP-2) and
    ///      failed recoveries by returning address(0).
    function _recoverSigner(bytes32 digest, bytes calldata signature) private pure returns (address) {
        if (signature.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        if (v < 27) v += 27;
        if (v != 27 && v != 28) return address(0);
        if (uint256(s) > _HALF_N) return address(0);
        return ecrecover(digest, v, r, s);
    }
}
