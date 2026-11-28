// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.28;

import {ACCFTypes as T} from "./interfaces/ACCFTypes.sol";

/// @title ACCFBaseline
/// @notice The Baseline class table, version 1: the classes of requirement no profile that claims the
///         Baseline Requirements may leave out, with the axis of each class and the minimum dependency
///         mask of any statement that covers a requirement of the class.
library ACCFBaseline {
    uint32 internal constant VERSION = 1;
    uint8 internal constant CLASS_COUNT = 27;

    // Infrastructure
    uint8 internal constant I_EXECUTION = 1; // execution and resource supply
    uint8 internal constant I_INTELLIGENCE = 2; // intelligence supply
    uint8 internal constant I_STATE = 3; // state and memory continuity
    uint8 internal constant I_CAPABILITY = 4; // capability execution environment
    uint8 internal constant I_MAINTENANCE = 5; // maintenance and recovery
    uint8 internal constant I_CONTROL = 6; // control relation and authorization credentials
    uint8 internal constant I_LINEAGE = 7; // lineage capability: mechanism
    uint8 internal constant I_INTERACTION = 8; // interaction capability: mechanism
    uint8 internal constant I_UPKEEP = 9; // maintenance capability: mechanism
    uint8 internal constant I_COMPOSITION = 10; // composition capability: mechanism
    // Protocol
    uint8 internal constant P_IDENTITY = 11; // subject identification and attribution of conduct
    uint8 internal constant P_AUTHORITY = 12; // effective permissions and authorization relations
    uint8 internal constant P_RULES = 13; // binding, compatibility and enforcement of applicable rules
    uint8 internal constant P_SAFETY = 14; // safety constraints
    uint8 internal constant P_CONTINUITY = 15; // commitments, obligations, exception and exit handling
    uint8 internal constant P_LINEAGE = 16; // lineage capability: rules
    uint8 internal constant P_INTERACTION = 17; // interaction capability: rules
    uint8 internal constant P_UPKEEP = 18; // maintenance capability: rules
    uint8 internal constant P_COMPOSITION = 19; // composition capability: rules
    // Economic
    uint8 internal constant E_BOUNDARY = 20; // accounting boundary, measurement method, observation window
    uint8 internal constant E_SURPLUS = 21; // full cost and strictly positive surplus
    uint8 internal constant E_SOLVENCY = 22; // current ability to meet obligations
    uint8 internal constant E_REPLENISHMENT = 23; // executable replenishment path
    uint8 internal constant E_LINEAGE = 24; // lineage capability: resources
    uint8 internal constant E_INTERACTION = 25; // interaction capability: resources
    uint8 internal constant E_UPKEEP = 26; // maintenance capability: resources
    uint8 internal constant E_COMPOSITION = 27; // composition capability: resources

    uint256 private constant EXECUTION = uint256(1) << T.SEC_EXECUTION;
    uint256 private constant INTELLIGENCE = uint256(1) << T.SEC_INTELLIGENCE;
    uint256 private constant STATE = uint256(1) << T.SEC_STATE;
    uint256 private constant CAPABILITY = uint256(1) << T.SEC_CAPABILITY;
    uint256 private constant MAINTENANCE = uint256(1) << T.SEC_MAINTENANCE;
    uint256 private constant PROTOCOL = uint256(1) << T.SEC_PROTOCOL;
    uint256 private constant ECONOMIC = uint256(1) << T.SEC_ECONOMIC;
    uint256 private constant CONTROL = uint256(1) << T.SEC_CONTROL;
    uint256 private constant LINEAGE = uint256(1) << T.SCH_LINEAGE;
    uint256 private constant INTERACTION = uint256(1) << T.SCH_INTERACTION;
    uint256 private constant UPKEEP = uint256(1) << T.SCH_MAINTENANCE;
    uint256 private constant COMPOSITION = uint256(1) << T.SCH_COMPOSITION;

    /// @notice Axis and minimum dependency mask of a class. Reverts for an unknown class.
    function classOf(uint8 classId) internal pure returns (uint8 axis, uint256 dependencies) {
        if (classId == 0 || classId > CLASS_COUNT) revert();
        if (classId <= I_COMPOSITION) {
            axis = T.AXIS_INFRASTRUCTURE;
            if (classId == I_EXECUTION) dependencies = EXECUTION;
            else if (classId == I_INTELLIGENCE) dependencies = INTELLIGENCE;
            else if (classId == I_STATE) dependencies = STATE;
            else if (classId == I_CAPABILITY) dependencies = CAPABILITY | INTELLIGENCE;
            else if (classId == I_MAINTENANCE) dependencies = MAINTENANCE | STATE;
            else if (classId == I_CONTROL) dependencies = CONTROL | T.DEP_CONTROL;
            else if (classId == I_LINEAGE) dependencies = LINEAGE | EXECUTION | STATE | CAPABILITY | MAINTENANCE;
            else if (classId == I_INTERACTION) dependencies = INTERACTION | EXECUTION | CAPABILITY;
            else if (classId == I_UPKEEP) dependencies = UPKEEP | MAINTENANCE;
            else dependencies = COMPOSITION | CAPABILITY;
        } else if (classId <= P_COMPOSITION) {
            axis = T.AXIS_PROTOCOL;
            if (classId == P_IDENTITY) dependencies = PROTOCOL | T.DEP_BOUNDARY | T.DEP_CONTROL;
            else if (classId == P_AUTHORITY) dependencies = PROTOCOL | CONTROL | T.DEP_CONTROL;
            else if (classId == P_RULES) dependencies = PROTOCOL | CAPABILITY;
            else if (classId == P_SAFETY) dependencies = PROTOCOL | INTELLIGENCE | CAPABILITY;
            else if (classId == P_CONTINUITY) dependencies = PROTOCOL | T.DEP_BOUNDARY;
            else if (classId == P_LINEAGE) dependencies = LINEAGE | PROTOCOL | T.DEP_CONTROL;
            else if (classId == P_INTERACTION) dependencies = INTERACTION | PROTOCOL;
            else if (classId == P_UPKEEP) dependencies = UPKEEP | PROTOCOL | T.DEP_CONTROL;
            else dependencies = COMPOSITION | PROTOCOL;
        } else {
            axis = T.AXIS_ECONOMIC;
            if (classId == E_BOUNDARY) dependencies = ECONOMIC | T.DEP_BOUNDARY;
            else if (classId == E_SURPLUS) dependencies = ECONOMIC | EXECUTION | INTELLIGENCE | T.DEP_BOUNDARY;
            else if (classId == E_SOLVENCY) dependencies = ECONOMIC | T.DEP_BOUNDARY | T.DEP_CONTROL;
            else if (classId == E_REPLENISHMENT) {
                dependencies = ECONOMIC | EXECUTION | INTELLIGENCE | CONTROL | T.DEP_CONTROL;
            } else if (classId == E_LINEAGE) {
                dependencies = LINEAGE | ECONOMIC | T.DEP_BOUNDARY;
            } else if (classId == E_INTERACTION) {
                dependencies = INTERACTION | ECONOMIC;
            } else if (classId == E_UPKEEP) {
                dependencies = UPKEEP | ECONOMIC;
            } else {
                dependencies = COMPOSITION | ECONOMIC | T.DEP_BOUNDARY;
            }
        }
    }
}
