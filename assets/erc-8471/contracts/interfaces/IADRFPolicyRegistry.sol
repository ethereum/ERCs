// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";

/// @title  IADRFPolicyRegistry — Dispute Policy registry (reference v0.1)
/// @notice Policies are immutable, content-addressed procedure templates
///         (policyId = keccak256(abi.encode(PolicySpec))). Versions are linked through a policy
///         family whose update authority alone may publish the next version. Publishing a new
///         version never changes what an existing binding or case is bound to.
interface IADRFPolicyRegistry {
    /// ERC-165: implementers MUST report `type(IADRFPolicyRegistry).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    event PolicyRegistered(bytes32 indexed policyId, bytes32 indexed family, uint32 version, address indexed by);

    function policyIdOf(T.PolicySpec calldata spec) external pure returns (bytes32);
    function registerPolicy(T.PolicySpec calldata spec) external returns (bytes32 policyId);
    function policyExists(bytes32 policyId) external view returns (bool);
    function familyAuthority(bytes32 family) external view returns (address);
    function familyLatest(bytes32 family) external view returns (bytes32 policyId, uint32 version);

    function policyHeader(bytes32 policyId) external view returns (
        bytes32 family, uint32 version, bytes32 previous, address updateAuthority,
        bytes32 objectKind, T.StandingMode standing, bytes32 resultProfile,
        bytes32 economicDeclaration, bytes32 descriptorHash
    );
    function trackOf(bytes32 policyId) external view returns (T.Track memory);
    function methodCount(bytes32 policyId) external view returns (uint256);
    function methodOf(bytes32 policyId, uint32 index) external view returns (T.MethodBinding memory);
    /// First method binding whose obligation kind is 0 (any) or `obligationKind`, with the given type.
    function findMethod(bytes32 policyId, uint8 obligationKind, T.QuestionType qType)
        external view returns (bool found, T.MethodBinding memory binding);
    function effectCount(bytes32 policyId) external view returns (uint256);
    function effectOf(bytes32 policyId, uint32 index) external view returns (T.Effect memory);
    /// Category of a declared effect; `declared` is false when the policy does not declare the effect.
    function effectCategory(bytes32 policyId, bytes32 effectId) external view returns (bool declared, T.EffectCategory category);
}
