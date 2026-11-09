// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPBindings
/// @notice Constants for channel bindings and disclosure records (see IAIFPChannelRegistry).
library AIFPBindings {
    // Binding kinds.
    uint8 internal constant KIND_TRANSPORT = 0;
    uint8 internal constant KIND_GOVERNANCE_RULES = 1; // e.g. a collective decision registry
    uint8 internal constant KIND_GOVERNANCE_DISPUTE = 2; // e.g. a dispute resolution registry
    uint8 internal constant KIND_GOVERNANCE_SAFETY = 3; // e.g. a safety specification registry
    uint8 internal constant KIND_ECONOMIC = 4; // stake / pay-to-read / bounty / metered profile
    uint8 internal constant MAX_KIND = 4;

    // Transport capability bits (BindingDecl.capabilities).
    uint32 internal constant CAP_IDENTITY = 1 << 0;
    uint32 internal constant CAP_RULE_ASSOCIATION = 1 << 1;
    uint32 internal constant CAP_PUSH = 1 << 2;
    uint32 internal constant CAP_PULL = 1 << 3;
    uint32 internal constant CAP_STREAM = 1 << 4;
    uint32 internal constant CAP_BATCH = 1 << 5;
    uint32 internal constant CAP_DELIVERY_RECORDS = 1 << 6;
    uint32 internal constant CAP_HISTORY_RETENTION = 1 << 7;
    uint32 internal constant CAP_LATE_JOIN_HISTORY = 1 << 8;
    uint32 internal constant CAP_PAYLOAD_PROTECTION = 1 << 9;
    uint32 internal constant CAP_METADATA_PROTECTION = 1 << 10;
    uint32 internal constant CAP_MEMBERSHIP_PRIVACY = 1 << 11;
    uint32 internal constant CAP_TOTAL_ORDER = 1 << 12;
    uint32 internal constant CAP_ABSENCE_DETECTION = 1 << 13;

    // Governance effect bits (BindingDecl.effectScope).
    uint32 internal constant EFFECT_RULES = 1 << 0; // may adopt paradigm versions
    uint32 internal constant EFFECT_PARTICIPATION = 1 << 1; // may grant, suspend, revoke role bindings
    uint32 internal constant EFFECT_DISCLOSURE = 1 << 2; // may record disclosures and restrictions

    // Adoption modes for governance results.
    uint8 internal constant ADOPTION_AUTOMATIC = 0; // the target executes directly
    uint8 internal constant ADOPTION_CONFIRMED = 1; // the channel authority confirms each result

    // Disclosure record kinds.
    uint8 internal constant DISCLOSURE_DISCLOSED = 0; // the audience was authorized to observe the object(s)
    uint8 internal constant DISCLOSURE_RESTRICTED = 1; // future provision to the audience was withdrawn

    function toTarget(address a) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function targetAddress(bytes32 target) internal pure returns (address) {
        return address(uint160(uint256(target)));
    }
}
