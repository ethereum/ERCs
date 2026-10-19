// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @title  ITrustAssertionRegistry — the subset of a know-your-agent trust-assertion registry used
///         by the assertion-level eligibility module: a subject is (type, ABI-encoded data), and
///         `check` answers whether the subject holds an unexpired, binding-satisfied assertion of at
///         least `minLevel` under `schemeId` from one of the listed issuers. Informative: the module,
///         not the swarm registry, depends on it.
interface ITrustAssertionRegistry {
    struct Subject {
        bytes32 subjectType;
        bytes   subjectData;
    }

    function check(Subject calldata subject, bytes32 schemeId, uint8 minLevel, address[] calldata issuers)
        external view returns (bool);
}
