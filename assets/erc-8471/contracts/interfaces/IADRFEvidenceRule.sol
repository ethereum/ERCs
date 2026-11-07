// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ADRFTypes as T} from "../ADRFTypes.sol";

/// @title  IADRFEvidenceRule — method for EVIDENCED sub-questions
/// @notice Evaluates a proposition about an external fact against material supplied under the rule.
///         The rule decides what it accepts (attestations, signed statements, cross-checks) and reports
///         the support kinds of its finding; the registry records the finding and the rule that accepted it.
interface IADRFEvidenceRule {
    /// ERC-165: implementers MUST report `type(IADRFEvidenceRule).interfaceId`.
    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function evaluate(bytes32 caseId, uint32 subQuestion, bytes32 proposition, bytes32 params, bytes calldata bundle)
        external returns (T.Value value, bytes32 resultHash, uint8 supportKinds);
}
