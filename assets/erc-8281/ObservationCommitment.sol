// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

import "./IObservationCommitment.sol";

/// @title  ObservationCommitment — ERC-8281 reference implementation
/// @notice Minimal conforming deployment. The contract enforces no constraints
///         on the digest content, the committer identity, or the observation
///         semantics; these are the responsibility of the caller (see the
///         Rationale section of ERC-8281).
///
///         The Recorded event signature is `Recorded(bytes32,address)`:
///         topic-0 = keccak256("Recorded(bytes32,address)")
///                 = 0xdca60c2087041cbb12d9a57628c6cad28ecbd0437e47c7ab6c3aa6e162bf4497
///
///         ERC-165 is implemented as RECOMMENDED by the spec so relying
///         parties can discover conforming deployments on-chain:
///         type(IObservationCommitment).interfaceId == 0xb5c645bd
///         (single-function interface; the ID is the record(bytes32) selector).
contract ObservationCommitment is IObservationCommitment {
    /// @inheritdoc IObservationCommitment
    function record(bytes32 digest) external {
        emit Recorded(digest, msg.sender);
    }

    /// @notice ERC-165 interface detection.
    /// @param interfaceId The interface identifier, per ERC-165.
    /// @return True for the IObservationCommitment interface ID (0xb5c645bd)
    ///         and the ERC-165 interface ID itself (0x01ffc9a7).
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IObservationCommitment).interfaceId || // 0xb5c645bd
            interfaceId == 0x01ffc9a7;                                 // ERC-165
    }
}
