// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "../interfaces/ACCFTypes.sol";
import {IACCFUnits} from "../interfaces/IACCFUnits.sol";
import {IACCFEvidenceAdapter} from "../interfaces/IACCFEvidenceAdapter.sol";

/// @dev The part of the ERC-8419 assertion registry this adapter reads.
interface IKYARegistryView {
    struct Assertion {
        bytes32 subjectKey;
        bytes32 schemeId;
        address issuer;
        uint8 level;
        bytes32 claimDigest;
        uint64 issuedAt;
        uint64 expiresAt;
        bytes32 evidenceHash;
        bytes32 anchor;
        bytes32 bindingWitness;
        uint8 status;
    }

    function getAssertion(bytes32 assertionId) external view returns (Assertion memory);
    function bindingStatus(bytes32 assertionId) external view returns (uint8);
}

/// @title ACCFAdapter8419
/// @notice Reads one ERC-8419 assertion.
/// @dev    Supports this proposition and no other: the assertion `recordId` of the registry `source` is about
///         the unit's subject key, is active and unexpired, belongs to the scheme `commitment` when one is
///         given, and its binding predicate holds now. It says nothing about whether the asserted claim is
///         true or whether the scheme fits a requirement; that is for the statement's assessor.
contract ACCFAdapter8419 is IACCFEvidenceAdapter {
    uint8 private constant STATUS_ACTIVE = 0;
    uint8 private constant BINDING_VIOLATED = 2;
    uint8 private constant BINDING_UNEVALUABLE = 3;

    function methodId() external pure returns (bytes32) {
        return keccak256("ACCF adapter: ERC-8419 assertion, version 1");
    }

    function probe(address units, bytes32 unitId, address source, bytes32 recordId, bytes32 commitment)
        external
        view
        returns (T.ProbeStatus, uint48)
    {
        if (source.code.length == 0) revert();
        T.Unit memory u = IACCFUnits(units).unitOf(unitId);
        IKYARegistryView.Assertion memory a;
        try IKYARegistryView(source).getAssertion(recordId) returns (IKYARegistryView.Assertion memory found) {
            a = found;
        } catch {
            return (T.ProbeStatus.NotSupported, 0);
        }
        if (a.subjectKey != u.subjectKey) return (T.ProbeStatus.NotSupported, 0);
        if (commitment != bytes32(0) && a.schemeId != commitment) return (T.ProbeStatus.NotSupported, 0);
        if (a.status != STATUS_ACTIVE) return (T.ProbeStatus.NotSupported, 0);
        if (a.expiresAt != 0 && a.expiresAt <= block.timestamp) return (T.ProbeStatus.NotSupported, 0);
        uint8 binding = IKYARegistryView(source).bindingStatus(recordId);
        if (binding == BINDING_VIOLATED) return (T.ProbeStatus.NotSupported, 0);
        if (binding == BINDING_UNEVALUABLE) return (T.ProbeStatus.Undetermined, 0);
        return (T.ProbeStatus.Supported, a.expiresAt > type(uint48).max ? type(uint48).max : uint48(a.expiresAt));
    }
}
