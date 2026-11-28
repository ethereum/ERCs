// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {SubjectRef} from "./AAFTypes.sol";

/// @title Source of relations for a DERIVED list
/// @notice Names the objects a subject is related to under a relation type. The relation runs from
/// the origin, which may be listed, to the subject, which is the one being asked about.
interface IAAFRelationSource {
    /// @notice Same meaning as IAAFEvaluator.configHash.
    function configHash() external view returns (bytes32);

    /// @param relationType the relation named by the criteria
    /// @param subject the object being asked about
    /// @param evidence what the requester presents; its format is defined by the source
    /// @param index position in the enumeration of origins, from 0
    /// @return status 0: the source cannot tell. 1: `origin` is the origin at `index`.
    ///         2: there is no origin at `index` and the enumeration is complete
    /// @return origin an object the subject is related to
    /// @return since the time from which the relation has held; 0 if not known
    function originOf(bytes32 relationType, SubjectRef calldata subject, bytes calldata evidence, uint256 index)
        external
        view
        returns (uint8 status, SubjectRef memory origin, uint64 since);
}
