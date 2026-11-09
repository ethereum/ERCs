// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPBasis
/// @notice Basis kinds of a role binding: on what grounds the roles were granted.
library AIFPBasis {
    uint8 internal constant MANAGER_GRANT = 0; // granted by the channel authority or an admission manager
    uint8 internal constant ALLOWLIST = 1; // granted because the subject is on a declared roster
    uint8 internal constant PREDICATE = 2; // acquired through the permissionless admission path
    uint8 internal constant DECISION = 3; // a collective decision referenced by basisRef
    uint8 internal constant EXTERNAL_EVIDENCE = 4; // evidence referenced by basisRef, asserted by the grantor
    uint8 internal constant MAX_KIND = 4;
}
