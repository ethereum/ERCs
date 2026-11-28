// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Match, SubjectRef} from "./AAFTypes.sol";

/// @title Resolver of standing
/// @notice Tells whether an account may act for a subject, and who controls the subject.
interface IAAFSubjectResolver {
    /// @return authorized MATCH: `presenter` may act for `subject`. NO_MATCH: it may not.
    ///         UNDETERMINED: the resolver cannot tell
    /// @return controller the account that controls the subject; zero if not established
    function standingOf(SubjectRef calldata subject, address presenter)
        external
        view
        returns (Match authorized, address controller);
}
