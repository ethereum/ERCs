// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";

/// @title  IADRFVerifier — method for FORMAL sub-questions
/// @notice A deterministic function of the proposition, the method parameters and the pinned inputs.
///         The finding it produces carries SUPPORT_COMPUTED: the proposition holds (or not) under the bound
///         rule and the given inputs; nothing is said about whether the inputs describe reality.
interface IADRFVerifier {
    /// ERC-165: implementers MUST report `type(IADRFVerifier).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function verify(bytes32 proposition, bytes32 params, bytes calldata inputs)
        external view returns (T.Value value, bytes32 resultHash);
}
