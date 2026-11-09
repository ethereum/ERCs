// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.20;

/// @title AIFPEvents
/// @notice Action and relation vocabularies of information events (see IAIFPEventAnchor).
library AIFPEvents {
    uint8 internal constant ACTION_PUBLISH = 0;
    uint8 internal constant ACTION_SUBMIT = 1;
    uint8 internal constant ACTION_RESPOND = 2;
    uint8 internal constant ACTION_MODIFY = 3;
    uint8 internal constant ACTION_FORWARD = 4;
    uint8 internal constant ACTION_DERIVE = 5;
    uint8 internal constant ACTION_SYNTHESIZE = 6;
    uint8 internal constant ACTION_SUPERSEDE = 7;
    uint8 internal constant ACTION_RETRACT = 8;
    uint8 internal constant MAX_ACTION = 8;

    uint8 internal constant REL_REPLY_TO = 0;
    uint8 internal constant REL_FORWARDS = 1;
    uint8 internal constant REL_DERIVES_FROM = 2;
    uint8 internal constant REL_SYNTHESIZES = 3;
    uint8 internal constant REL_REFERENCES = 4;
    uint8 internal constant REL_SUPERSEDES = 5;
    uint8 internal constant REL_RETRACTS = 6;
    uint8 internal constant MAX_RELATION = 6;
}
