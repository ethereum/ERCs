// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "../interfaces/ACCFTypes.sol";
import {IACCFUnits} from "../interfaces/IACCFUnits.sol";
import {IACCFEvidenceAdapter} from "../interfaces/IACCFEvidenceAdapter.sol";

/// @dev The part of the ERC-8490 registry this adapter reads.
interface IAgentMeditationView {
    struct Head {
        bool enrolled;
        address controller;
        uint8 controllerRights;
        uint32 policyVersion;
        uint32 floorVersion;
        uint64 stateVersion;
        uint64 recordCount;
        bytes32 root;
        uint48 enrolledAt;
        uint48 lastSignalAt;
        uint48 nextPlannedAt;
        uint48 lastCycleEndedAt;
    }

    struct Requirements {
        uint8 supportedLayers;
        uint8 requiredLayers;
        uint48 dueWindow;
        uint48 pulseInterval;
        uint48[4] maxInterval;
    }

    function headOf(address subject) external view returns (Head memory);
    function rootAt(address subject, uint64 stateVersion) external view returns (bytes32);
    function requirementsOf(address subject) external view returns (Requirements memory);
    function layerStatus(address subject, uint8 layer)
        external
        view
        returns (uint8 status, uint48 deadline, bool neverCompleted);
}

/// @title ACCFAdapter8490
/// @notice Reads the self-maintenance record of one ERC-8490 subject.
/// @dev    `recordId` packs the subject address in its low 160 bits and a state version in the next 64 bits;
///         `commitment` is the state root expected at that version. Supports this proposition and no other:
///         the subject is the unit's controller or an account inside the unit's boundary, it is enrolled, it
///         registered that root at that state version, and none of its required layers is overdue now.
///         It says nothing about whether the maintenance the records describe took place off chain.
contract ACCFAdapter8490 is IACCFEvidenceAdapter {
    uint8 private constant STATUS_OVERDUE = 5;

    function methodId() external pure returns (bytes32) {
        return keccak256("ACCF adapter: ERC-8490 maintenance record, version 1");
    }

    /// @notice The `recordId` for a subject and a state version.
    function recordIdOf(address subject, uint64 stateVersion) external pure returns (bytes32) {
        return bytes32((uint256(stateVersion) << 160) | uint256(uint160(subject)));
    }

    function probe(address units, bytes32 unitId, address source, bytes32 recordId, bytes32 commitment)
        external
        view
        returns (T.ProbeStatus, uint48)
    {
        if (source.code.length == 0) revert();
        if (uint256(recordId) >> 224 != 0) revert();
        address subject = address(uint160(uint256(recordId)));
        uint64 stateVersion = uint64(uint256(recordId) >> 160);
        T.Unit memory u = IACCFUnits(units).unitOf(unitId);
        if (subject != u.controller && !IACCFUnits(units).isAccountOf(unitId, subject)) {
            return (T.ProbeStatus.NotSupported, 0);
        }
        IAgentMeditationView registry = IAgentMeditationView(source);
        if (!registry.headOf(subject).enrolled) return (T.ProbeStatus.NotSupported, 0);
        if (commitment == bytes32(0) || registry.rootAt(subject, stateVersion) != commitment) {
            return (T.ProbeStatus.NotSupported, 0);
        }
        uint8 required = registry.requirementsOf(subject).requiredLayers;
        uint48 earliest;
        for (uint8 layer = 0; layer < 4; ++layer) {
            if ((required >> layer) & 1 == 0) continue;
            (uint8 status, uint48 deadline,) = registry.layerStatus(subject, layer);
            if (status == STATUS_OVERDUE) return (T.ProbeStatus.NotSupported, 0);
            if (deadline != 0 && (earliest == 0 || deadline < earliest)) earliest = deadline;
        }
        return (T.ProbeStatus.Supported, earliest);
    }
}
