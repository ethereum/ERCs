// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ITransferOracle} from "./interfaces/ITransferOracle.sol";
import {RiscZeroVerifier} from "./verifier/RiscZeroVerifier.sol"; // Import the RISC Zero verifier

/**
 * @title TransferOracle Contract
 * @notice Manages one-time transfer approvals based on ZK proofs derived from
 *         off-chain payment instruction data.
 * @dev Stores approvals keyed by a hash of issuer, sender, and recipient.
 *      Uses a RISC Zero verifier to validate proofs before storing approvals.
 *      Only the associated token contract can call `canTransfer`.
 */
contract TransferOracle is ITransferOracle, Ownable, ReentrancyGuard {
    using SafeCast for uint256;

    // --- Errors ---
    error TransferOracle__InvalidProof();
    error TransferOracle__CallerNotIssuer();
    error TransferOracle__CallerNotToken();
    error TransferOracle__NoApprovalFound();
    error TransferOracle__ApprovalExpired();
    error TransferOracle__AmountOutOfBounds();
    error TransferOracle__ApprovalAlreadyExists(); // Prevent overwriting or replay within approveTransfer
    error TransferOracle__ProofAlreadyUsed();
    error TransferOracle__InvalidPublicInputs();
    error TransferOracle__InvalidApprovalData();
    error TransferOracle__ProofVerificationFailed();
    error TransferOracle__InputDecodingFailed(); // Keep in case of future direct struct decoding attempts
    error TransferOracle__ScalingOverflow(); // For amount scaling

    // --- Constants ---

    // Scaling factor used for amounts in ZK proof compared to token amounts
    uint256 private constant AMOUNT_SCALING_FACTOR = 1000;

    // --- State Variables ---

    /**
     * @notice Address of the ZK verifier contract.
     */
    RiscZeroVerifier public immutable verifier;

    /**
     * @notice Address of the PermissionedERC20 token contract allowed to call `canTransfer`.
     */
    address public immutable permissionedToken;

    /**
     * @notice The entity authorized to submit new transfer approvals (e.g., the token issuer).
     * @dev Set during construction, can be transferred via Ownable.transferOwnership.
     *      We alias `owner()` from Ownable to represent the issuer for clarity.
     */
    address public immutable issuer;

    /**
     * @notice Mapping from a composite key to a list of approvals.
     * @dev Key: keccak256(abi.encode(issuer_address, sender_address, recipient_address))
     *      Value: Array of approvals valid for this triplet.
     *      We store an array because multiple approvals (e.g., different amounts/expiries)
     *      can exist for the same sender/recipient pair, initiated by the same issuer.
     */
    mapping(bytes32 => TransferApproval[]) private _approvals;

    /**
     * @notice Mapping to track used proof IDs to prevent replay attacks.
     * @dev proofId => consumed (true) or not (false/default)
     */
    mapping(bytes32 => bool) private _consumedProofIds;

    // --- Modifiers ---

    /**
     * @dev Ensures the caller is the designated issuer (owner).
     */
    modifier onlyIssuer() {
        if (msg.sender != owner()) revert TransferOracle__CallerNotIssuer();
        _;
    }

    /**
     * @dev Ensures the caller is the designated permissioned token contract.
     */
    modifier onlyToken() {
        if (msg.sender != permissionedToken) revert TransferOracle__CallerNotToken();
        _;
    }

    // --- Constructor ---

    /**
     * @notice Contract constructor.
     * @param _verifier Address of the deployed RISC Zero Verifier contract.
     * @param _token Address of the PermissionedERC20 token contract.
     * @param _initialIssuer Address of the entity authorized to approve transfers (owner).
     */
    constructor(address _verifier, address _token, address _initialIssuer)
        Ownable(_initialIssuer)
    {
        if (_verifier == address(0) || _token == address(0)) {
            revert("TransferOracle: Zero address for verifier or token");
        }
        verifier = RiscZeroVerifier(_verifier);
        permissionedToken = _token;
        issuer = _initialIssuer; // Store immutable issuer reference
    }

    // --- External Functions ---

    /**
     * @notice Stores a new transfer approval after verifying an associated ZK proof.
     * @dev See {ITransferOracle.approveTransfer}.
     *      Requires caller to be the issuer (owner).
     *      Validates the proof using the RISC Zero Verifier contract.
     *      Ensures the approval (by proofId) hasn't been used before.
     *      Validates consistency between `approval` struct data and `publicInputs`.
     */
    function approveTransfer(
        ITransferOracle.TransferApproval calldata approval,
        bytes calldata proof,
        bytes calldata publicInputs
    ) external override onlyIssuer nonReentrant returns (bytes32 proofId) {
        // 1. Decode public inputs for RISC Zero format
        // Expected format: [root, debtorHash, creditorHash, minAmt, maxAmt, currencyHash, expiry]
        (
            bytes32 rootFromProof,
            bytes32 proofDebtorHash,
            bytes32 proofCreditorHash,
            uint256 proofMinAmountScaled,
            uint256 proofMaxAmountScaled,
            bytes32 currencyHash,
            uint64 proofExpiry
        ) = abi.decode(publicInputs, (bytes32, bytes32, bytes32, uint256, uint256, bytes32, uint64));

        // 2. Validate consistency: Amounts & Expiry
        if (
            _scaleUp(approval.minAmt) != proofMinAmountScaled ||
            _scaleUp(approval.maxAmt) != proofMaxAmountScaled ||
            uint64(approval.expiry) != proofExpiry
        ) {
            revert TransferOracle__InvalidPublicInputs();
        }

        // 3. Validate approval data semantics
        if (
            approval.sender == address(0) ||
            approval.recipient == address(0) ||
            approval.minAmt > approval.maxAmt ||
            approval.expiry <= block.timestamp ||
            approval.expiry > type(uint256).max
        ) {
            revert TransferOracle__InvalidApprovalData();
        }

        // 4. Verify proofId consistency (EIP specified calculation)
        bytes32 calculatedProofId = keccak256(abi.encodePacked(rootFromProof, proofDebtorHash, proofCreditorHash));
        if (calculatedProofId != approval.proofId) {
            revert TransferOracle__InvalidPublicInputs(); // Or InvalidProofId
        }

        // 5. Check if proofId has already been used
        if (_consumedProofIds[approval.proofId]) {
            revert TransferOracle__ProofAlreadyUsed();
        }

        // 6. Verify the RISC Zero proof
        bytes32 journalHash = keccak256(publicInputs);
        bytes32 sealHash = keccak256(proof);
        bool success = verifier.verify(proof, journalHash, sealHash);
        if (!success) {
            revert TransferOracle__ProofVerificationFailed();
        }

        // 7. Store the approval
        bytes32 key = keccak256(abi.encode(owner(), approval.sender, approval.recipient));
        _approvals[key].push(
            TransferApproval({
                sender: approval.sender,
                recipient: approval.recipient,
                minAmt: approval.minAmt,
                maxAmt: approval.maxAmt,
                expiry: approval.expiry,
                proofId: approval.proofId
            })
        );

        // 8. Mark proofId as consumed
        _consumedProofIds[approval.proofId] = true;

        // 9. Emit event (matches your ITransferOracle event with uint256 expiry)
        emit TransferApproved(
            owner(),
            approval.sender,
            approval.recipient,
            approval.minAmt,
            approval.maxAmt,
            approval.expiry,
            approval.proofId
        );
        return approval.proofId;
    }

    /**
     * @notice Checks for and consumes a valid transfer approval.
     * @dev See {ITransferOracle.canTransfer}.
     *      Requires caller to be the permissionedToken address.
     *      Finds the *best* (smallest amount range) approval matching the criteria (sender, recipient, issuer)
     *      whose amount range includes the requested amount and is not expired.
     *      Consumes the approval by removing it from storage.
     */
    function canTransfer(
        address issuer,
        address sender,
        address recipient,
        uint256 amount
    )
        external
        override
        onlyToken
        nonReentrant
        returns (bytes32 proofId)
    {
        if (issuer != permissionedToken) {
            revert TransferOracle__CallerNotToken();
        }

        bytes32 key = keccak256(abi.encode(owner(), sender, recipient));
        TransferApproval[] storage approvalList = _approvals[key];
        uint256 listLength = approvalList.length;

        uint256 bestApprovalIndex = type(uint256).max;
        uint256 smallestRange = type(uint256).max;

        for (uint256 i = 0; i < listLength; ++i) {
            TransferApproval storage currentApproval = approvalList[i];

            if (currentApproval.expiry < block.timestamp) {
                continue;
            }
            if (amount >= currentApproval.minAmt && amount <= currentApproval.maxAmt) {
                uint256 currentRange = uint256(currentApproval.maxAmt) - uint256(currentApproval.minAmt);
                if (currentRange < smallestRange) {
                    smallestRange = currentRange;
                    bestApprovalIndex = i;
                }
            }
        }

        if (bestApprovalIndex == type(uint256).max) {
            revert TransferOracle__NoApprovalFound();
        }

        proofId = approvalList[bestApprovalIndex].proofId;

        if (bestApprovalIndex != listLength - 1) {
            approvalList[bestApprovalIndex] = approvalList[listLength - 1];
        }
        approvalList.pop();

        emit ApprovalConsumed(
            owner(),
            sender,
            recipient,
            amount,
            proofId
        );
        // Return proofId (already assigned)
    }

    // --- Internal Functions ---

    /**
     * @dev Scales an amount by the AMOUNT_SCALING_FACTOR.
     *      Reverts on overflow.
     */
    function _scaleUp(uint256 amount) private pure returns (uint256 scaledAmount) {
        scaledAmount = amount * AMOUNT_SCALING_FACTOR;
        // Check for overflow: if scaledAmount / factor != original amount
        // (Only needed if amount can be very large; multiplication is safe for typical token amounts)
        if (amount != 0 && scaledAmount / AMOUNT_SCALING_FACTOR != amount) {
            revert TransferOracle__ScalingOverflow();
        }
    }

    // --- View Functions ---

    /**
     * @notice Returns the current issuer address.
     * @dev Convenience function aliasing Ownable.owner().
     */
    function getIssuer() external view returns (address) {
        return owner();
    }

    /**
     * @notice Returns the number of currently active approvals for a given key.
     * @param _sender Sender address.
     * @param _recipient Recipient address.
     * @return count Number of active approvals.
     */
    function getApprovalCount(address _sender, address _recipient) external view returns (uint256 count) {
        bytes32 key = keccak256(abi.encode(owner(), _sender, _recipient));
        return _approvals[key].length;
    }

    /**
     * @notice Checks if a proof ID has already been used (consumed).
     * @param _proofId The proof ID to check.
     * @return bool True if the proof ID has been consumed, false otherwise.
     */
    function isProofUsed(bytes32 _proofId) external view returns (bool) {
        return _consumedProofIds[_proofId];
    }
} 