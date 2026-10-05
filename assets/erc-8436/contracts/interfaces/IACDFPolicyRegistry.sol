// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ACDFTypes as T} from "../ACDFTypes.sol";

/// @title  IACDFPolicyRegistry — Decision Policy registry (reference v0.2)
/// @notice Policies are immutable, content-addressed templates (policyId = keccak256 of the
///         ABI-encoded PolicySpec). Versions are linked through a policy family whose
///         update authority alone may publish the next version. Publishing a new version
///         never changes what an existing issue or standing acceptance is bound to.
interface IACDFPolicyRegistry {
    /// ERC-165: implementers MUST report `type(IACDFPolicyRegistry).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    event PolicyRegistered(bytes32 indexed policyId, bytes32 indexed family, uint32 version, address indexed by);

    struct Timing {
        uint32           maxAppeals;
        uint64           appealWindow;
        uint8            appealable;
        T.AppealStanding appealStanding;
        uint64           maxTotalDuration;
        uint64           ackWindow;
        bool             allowAdvisory;
        uint64           roundDuration;
    }

    function policyIdOf(T.PolicySpec calldata spec) external pure returns (bytes32);
    function registerPolicy(T.PolicySpec calldata spec) external returns (bytes32 policyId);
    function policyExists(bytes32 policyId) external view returns (bool);
    function familyAuthority(bytes32 family) external view returns (address);
    function familyLatest(bytes32 family) external view returns (bytes32 policyId, uint32 version);
    function roundDurationOf(bytes32 policyId) external view returns (uint64);
    function timingOf(bytes32 policyId) external view returns (Timing memory);
    function policyHeader(bytes32 policyId) external view returns (
        bytes32 family, uint32 version, bytes32 previous, address updateAuthority, bytes32 descriptorHash
    );
    function bodyCount(bytes32 policyId) external view returns (uint256);
    function bodyOf(bytes32 policyId, uint32 body) external view returns (T.BodySpec memory);
    function nodeCount(bytes32 policyId) external view returns (uint256);
    function nodeOf(bytes32 policyId, uint32 node) external view returns (T.Node memory);
}
