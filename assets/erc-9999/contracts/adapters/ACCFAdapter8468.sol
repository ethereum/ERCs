// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "../interfaces/ACCFTypes.sol";
import {IACCFUnits} from "../interfaces/IACCFUnits.sol";
import {IACCFEvidenceAdapter} from "../interfaces/IACCFEvidenceAdapter.sol";

/// @dev The part of the ERC-8468 binding registry this adapter reads.
interface IASFBindingRegistryView {
    struct Intervener {
        address account;
        uint8 rights;
    }

    struct Binding {
        address adopter;
        bytes32 subjectKey;
        bytes32 scopeKey;
        address specRegistry;
        bytes32 specId;
        uint32 version;
        bytes32 contentHash;
        bytes32 paramsHash;
        string paramsLocator;
        bytes32 authorityRef;
        uint16 enforcement;
        uint64 validFrom;
        uint64 validUntil;
        bytes32 parentBindingId;
        uint8 depth;
        uint64 createdAt;
        uint64 stateChangedAt;
        uint8 state;
        uint8 restrictions;
        bytes32 responseRef;
        address suspendedBy;
    }

    struct Clause {
        address specRegistry;
        bytes32 specId;
        uint32[] versions;
        address adopter;
        bytes32 subjectKey;
        bytes32 scopeKey;
        uint16 enforcement;
        Intervener[] interveners;
    }

    function bindingOf(bytes32 bindingId) external view returns (Binding memory);
    function checkBinding(bytes32 bindingId, Clause calldata clause)
        external
        view
        returns (uint8 verdict, uint8 reason, uint8 restrictions);
}

/// @title ACCFAdapter8468
/// @notice Reads one ERC-8468 Safety Binding.
/// @dev    Supports this proposition and no other: the binding `recordId` of the registry `source` was adopted
///         by the unit's controller or by an account inside the unit's boundary, is for the subject key
///         `commitment`, and the registry-level check of that binding is satisfied now (it exists, is active,
///         is inside its validity window, pins an existing specification version, and no ancestor fails).
///         It says nothing about whether the adopted arrangement is enforced on the unit's execution paths.
contract ACCFAdapter8468 is IACCFEvidenceAdapter {
    uint8 private constant STATE_NONE = 0;
    uint8 private constant VERDICT_SATISFIED = 1;
    uint8 private constant VERDICT_NOT_SATISFIED = 2;

    function methodId() external pure returns (bytes32) {
        return keccak256("ACCF adapter: ERC-8468 binding, version 1");
    }

    function probe(address units, bytes32 unitId, address source, bytes32 recordId, bytes32 commitment)
        external
        view
        returns (T.ProbeStatus, uint48)
    {
        if (source.code.length == 0) revert();
        T.Unit memory u = IACCFUnits(units).unitOf(unitId);
        IASFBindingRegistryView.Binding memory b;
        try IASFBindingRegistryView(source).bindingOf(recordId) returns (IASFBindingRegistryView.Binding memory found) {
            b = found;
        } catch {
            return (T.ProbeStatus.NotSupported, 0);
        }
        if (b.state == STATE_NONE) return (T.ProbeStatus.NotSupported, 0);
        if (b.adopter != u.controller && !IACCFUnits(units).isAccountOf(unitId, b.adopter)) {
            return (T.ProbeStatus.NotSupported, 0);
        }
        IASFBindingRegistryView.Clause memory clause;
        clause.specRegistry = b.specRegistry;
        clause.specId = b.specId;
        clause.adopter = b.adopter;
        clause.subjectKey = commitment;
        (uint8 verdict,,) = IASFBindingRegistryView(source).checkBinding(recordId, clause);
        if (verdict == VERDICT_SATISFIED) {
            return (T.ProbeStatus.Supported, b.validUntil > type(uint48).max ? type(uint48).max : uint48(b.validUntil));
        }
        if (verdict == VERDICT_NOT_SATISFIED) return (T.ProbeStatus.NotSupported, 0);
        return (T.ProbeStatus.Undetermined, 0);
    }
}
