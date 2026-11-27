// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {ITaskVerifier} from "../interfaces/ITaskVerifier.sol";

interface IUpdateAuthorityView {
    function updateAuthorityOf(uint256 tokenId) external view returns (address);
}

/// @title  HashlockVerifier — stock verifier for know-the-answer bounties
///         (profile: x-hashlock-v1). "Solve it and the vault pays" with no one
///         in the loop: the demander commits sha256(answer); the solver submits
///         a resultHash binding the answer to THEIR address, then settles by
///         revealing the answer as proof.
/// @notice Front-running posture: resultHash = sha256(answer ‖ fulfiller), so a
///         copied proof cannot settle a copied submission — the copier's own
///         commitment hashes differently. Residual risk: an observer who sees the
///         proof in the mempool can submit a fresh commitment for their own address
///         and settle in the same block; where that matters, harden with a minimum
///         submission age before settlement (see the standard's Security
///         Considerations). Set-once answers prevent the demander from moving the
///         goalposts after submissions exist.
contract HashlockVerifier is ITaskVerifier {
    // key = keccak256(taskContract, tokenId)
    mapping(bytes32 => bytes32) public answerHashOf;

    event AnswerCommitted(address indexed taskContract, uint256 indexed tokenId, bytes32 answerHash);

    function key(address taskContract, uint256 tokenId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(taskContract, tokenId));
    }

    /// @notice Commit the answer hash for a task. Only that task's update authority;
    ///         set-once (a changed answer would be a changed task — mint a new one).
    function commitAnswer(address taskContract, uint256 tokenId, bytes32 answerHash) external {
        require(answerHash != bytes32(0), "Hashlock: zero answer hash");
        require(
            msg.sender == IUpdateAuthorityView(taskContract).updateAuthorityOf(tokenId),
            "Hashlock: not update authority"
        );
        bytes32 k = key(taskContract, tokenId);
        require(answerHashOf[k] == bytes32(0), "Hashlock: answer already committed");
        answerHashOf[k] = answerHash;
        emit AnswerCommitted(taskContract, tokenId, answerHash);
    }

    /// @inheritdoc ITaskVerifier
    function verifyFulfillment(
        address taskContract,
        uint256 tokenId,
        uint256, /* submissionId */
        address fulfiller,
        bytes32 resultHash,
        bytes calldata proof
    ) external view returns (bool) {
        bytes32 committed = answerHashOf[key(taskContract, tokenId)];
        if (committed == bytes32(0)) return false;                       // no answer committed
        if (sha256(proof) != committed) return false;                    // wrong answer
        return resultHash == sha256(abi.encodePacked(proof, fulfiller)); // commitment bound to fulfiller
    }

    // ---- ERC-165: declares ITaskVerifier so task contracts enable settleFulfillment
    function supportsInterface(bytes4 id) external pure returns (bool) {
        return id == 0x01ffc9a7 || id == type(ITaskVerifier).interfaceId;
    }
}
