// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IDiveLogTypes.sol";
import "../interfaces/IDiveLog.sol";
import "../interfaces/IDiveLogTypedData.sol";

contract SovereignDiveLog is IDiveLog {
    address public immutable owner;

    DiverProfile internal _profile;
    uint256 public diveCount;

    mapping(uint256 => DiveLog) private _dives;
    mapping(uint256 => VoidInfo) private _voids;
    mapping(uint256 => Attestation[]) private _attestations;
    mapping(uint256 => mapping(address => bool)) private _hasAttested;
    mapping(uint64 => uint256[]) private _divesByDate;
    mapping(address => uint256) private _attesterNonces;

    constructor(
        address _owner,
        string memory _name,
        uint8 _age,
        uint16 _height,
        uint16 _weight,
        BiologicalSex _sex,
        UnitSystem _units
    ) {
        owner = _owner;
        _profile = DiverProfile({
            name: _name,
            age: _age,
            height: _height,
            weight: _weight,
            sex: _sex,
            units: _units
        });
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IDiveLog).interfaceId;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function logDive(DiveInput calldata input) external onlyOwner returns (uint256) {
        if (input.data.maxDepth <= 0) revert InvalidDepth();
        if (input.data.bottomTimeMinutes == 0) revert InvalidTimes();

        uint256 diveId = ++diveCount;

        _dives[diveId] = DiveLog({
            id: diveId,
            diveDate: input.diveDate,
            units: input.units,
            data: input.data,
            env: input.env,
            decomp: input.decomp,
            gas: input.gas,
            remarks: input.remarks
        });

        _divesByDate[input.diveDate].push(diveId);

        emit DiveLogged(diveId, input.diveDate);
        return diveId;
    }

    function batchLogDives(DiveInput[] calldata inputs) external onlyOwner returns (uint256[] memory) {
        uint256 len = inputs.length;
        uint256[] memory ids = new uint256[](len);

        for (uint256 i; i < len; ) {
            if (inputs[i].data.maxDepth <= 0) revert InvalidDepth();
            if (inputs[i].data.bottomTimeMinutes == 0) revert InvalidTimes();

            uint256 diveId = ++diveCount;

            _dives[diveId] = DiveLog({
                id: diveId,
                diveDate: inputs[i].diveDate,
                units: inputs[i].units,
                data: inputs[i].data,
                env: inputs[i].env,
                decomp: inputs[i].decomp,
                gas: inputs[i].gas,
                remarks: inputs[i].remarks
            });

            _divesByDate[inputs[i].diveDate].push(diveId);
            ids[i] = diveId;

            emit DiveLogged(diveId, inputs[i].diveDate);

            unchecked { ++i; }
        }

        return ids;
    }

    function voidDive(
        uint256 diveId,
        uint256 supersededById,
        string calldata reason
    ) external onlyOwner {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        if (_voids[diveId].isVoided) revert DiveAlreadyVoided(diveId);
        if (supersededById != 0) {
            if (supersededById == diveId) revert InvalidSupersede(diveId, supersededById);
            if (supersededById > diveCount) revert InvalidSupersede(diveId, supersededById);
        }

        _voids[diveId] = VoidInfo({
            supersededById: supersededById,
            isVoided: true,
            voidedBy: msg.sender,
            voidedAt: uint64(block.timestamp),
            reason: reason
        });

        emit DiveVoided(diveId, supersededById, msg.sender, reason);
    }

    function attestDive(
        uint256 diveId,
        uint256 nonce,
        bytes calldata signature
    ) external {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        if (_voids[diveId].isVoided) revert DiveAlreadyVoided(diveId);

        bytes32 digest = DiveLogTypedData.attestationDigest(
            diveId,
            address(this),
            block.chainid,
            nonce
        );

        address attester = _recoverSigner(digest, signature);
        if (attester == address(0)) revert InvalidSignature();
        if (_attesterNonces[attester] != nonce) revert NonceMismatch(_attesterNonces[attester], nonce);
        if (_hasAttested[diveId][attester]) revert AlreadyAttested(diveId, attester);

        _attesterNonces[attester] = nonce + 1;
        _hasAttested[diveId][attester] = true;
        _attestations[diveId].push(Attestation({
            attester: attester,
            attestedAt: uint64(block.timestamp)
        }));

        emit DiveAttested(diveId, attester);
    }

    function getDive(uint256 diveId) external view returns (DiveLog memory) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _dives[diveId];
    }

    function getDivesByDate(uint64 date) external view returns (uint256[] memory) {
        return _divesByDate[date];
    }

    function getMultipleDives(uint256[] calldata diveIds) external view returns (DiveLog[] memory) {
        uint256 len = diveIds.length;
        DiveLog[] memory dives = new DiveLog[](len);
        for (uint256 i; i < len; ) {
            if (diveIds[i] == 0 || diveIds[i] > diveCount) revert DiveNotFound(diveIds[i]);
            dives[i] = _dives[diveIds[i]];
            unchecked { ++i; }
        }
        return dives;
    }

    function getAllDiveIds() external view returns (uint256[] memory) {
        uint256 total = diveCount;
        uint256[] memory ids = new uint256[](total);
        for (uint256 i; i < total; ) {
            ids[i] = i + 1;
            unchecked { ++i; }
        }
        return ids;
    }

    function getDiveCount() external view returns (uint256) {
        return diveCount;
    }

    function isDiveVoided(uint256 diveId) external view returns (bool) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _voids[diveId].isVoided;
    }

    function getVoidInfo(uint256 diveId) external view returns (VoidInfo memory) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _voids[diveId];
    }

    function getAttestations(uint256 diveId) external view returns (Attestation[] memory) {
        if (diveId == 0 || diveId > diveCount) revert DiveNotFound(diveId);
        return _attestations[diveId];
    }

    function profile() external view override returns (DiverProfile memory) {
        return _profile;
    }

    function attesterNonce(address attester) external view returns (uint256) {
        return _attesterNonces[attester];
    }

    function updateProfile(
        string calldata _name,
        uint8 _age,
        uint16 _height,
        uint16 _weight,
        BiologicalSex _sex,
        UnitSystem _units
    ) external onlyOwner {
        _profile = DiverProfile({
            name: _name,
            age: _age,
            height: _height,
            weight: _weight,
            sex: _sex,
            units: _units
        });
        emit ProfileUpdated();
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
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

        return ecrecover(digest, v, r, s);
    }
}
