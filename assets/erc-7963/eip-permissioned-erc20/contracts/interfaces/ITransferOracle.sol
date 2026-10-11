// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ITransferOracle Interface
 * @notice Defines the interface for the Transfer Oracle, responsible for approving
 *         permissioned transfers based on off-chain verified proofs.
 */
interface ITransferOracle {
    /**
     * @notice Emitted when a transfer approval is successfully verified and stored.
     * @param issuer The address of the token contract (or designated issuer entity).
     * @param sender The approved sender address.
     * @param recipient The approved recipient address.
     * @param minAmt The minimum transfer amount approved.
     * @param maxAmt The maximum transfer amount approved.
     * @param expiry The Unix timestamp when the approval expires.
     * @param proofId A unique identifier for the proof used to generate this approval.
     */
    event TransferApproved(
        address indexed issuer,
        address indexed sender,
        address indexed recipient,
        uint256 minAmt,
        uint256 maxAmt,
        uint256 expiry,
        bytes32 proofId
    );

    /**
     * @notice Emitted when a previously stored approval is consumed by a transfer.
     * @param issuer The address of the token contract (or designated issuer entity).
     * @param sender The sender address of the transfer.
     * @param recipient The recipient address of the transfer.
     * @param amount The amount transferred.
     * @param proofId The unique identifier of the proof associated with the consumed approval.
     */
    event ApprovalConsumed(
        address indexed issuer,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        bytes32 proofId
    );

    /**
     * @notice Stores a new transfer approval after verifying an associated ZK proof.
     * @dev The implementation MUST verify the `proof` against `publicInputs` using a
     *      Groth16 Verifier contract before storing the approval details.
     * @param approval The details of the transfer to approve.
     * @param proof The ZK-SNARK proof data (Groth16).
     * @param publicInputs The public inputs used for proof verification.
     */
    function approveTransfer(
        TransferApproval calldata approval,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external returns (bytes32 proofId);

    /**
     * @notice Called by the permissioned token contract before a transfer occurs.
     * @dev Checks if a valid, unexpired approval exists for the given parameters,
     *      consumes the smallest applicable approval, and returns its proof ID.
     *      Reverts if no suitable approval is found or if the caller is not the
     *      designated token contract.
     * @param issuer The address of the token contract (or designated issuer entity).
     * @param sender The sender address of the proposed transfer.
     * @param recipient The recipient address of the proposed transfer.
     * @param amount The amount of the proposed transfer.
     * @return proofId The unique identifier of the proof associated with the consumed approval.
     */
    function canTransfer(
        address issuer,
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bytes32 proofId);

    /**
     * @dev Structure defining the details of a transfer approval.
     */
    struct TransferApproval {
        address sender;
        address recipient;
        uint256 minAmt;
        uint256 maxAmt;
        uint256 expiry;
        bytes32 proofId;
    }
} 