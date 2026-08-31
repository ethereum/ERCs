// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

import "./IDecryptionContract.sol";
import "./IDecryptionContractInceptionCallback.sol";

/**
 * @title ERC-7573 Decryption Contract with asynchronous key generation.
 * @dev Extends IDecryptionContract with an inception method for transfers whose
 * encrypted success and failure keys are generated asynchronously.
 */
interface IDecryptionContractWithKeyGeneration is IDecryptionContract {

    /**
     * @notice Initiates a payment transfer and asynchronous generation of the
     * encrypted success and failure keys, with an optional completion callback.
     * @dev TransferIncepted is emitted only after both generated keys have been
     * validated and stored. The id, amount, participants, transaction, and callback
     * MUST remain immutable. The generated success and failure material MUST identify
     * distinct outcome keys. The `from` and `to` participants MUST be supplied explicitly.
     * `msg.sender` identifies only the caller and MUST NOT, by itself, determine either
     * participant. Implementations MAY require `msg.sender` to be a participant or an
     * authorized operator.
     *
     * If callback is address(0), the implementation MUST skip callback delivery.
     * Otherwise, after the inception has been completed and
     * TransferIncepted has been emitted, the implementation MUST call
     * callback.onInceptionCompleted with the transfer id. The callback can
     * then read the immutable context and key material through the getters below.
     * The callback MUST acknowledge with its function selector. A revert, invalid
     * return value, or insufficient callback gas MUST revert this completion attempt
     * and leave the inception pending so that completion can be retried.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param transaction The transaction specification used to generate the keys.
     * @param callback The contract receiving the completed inception notification, or
     * address(0) when no on-chain callback is required.
     */
    function inceptTransfer(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback
    ) external;

    /**
     * @notice Returns the immutable context of an asynchronous inception.
     * @dev exists is an explicit existence signal; callers MUST NOT infer existence
     * from zero or empty returned values. The values MUST NOT change while exists is true.
     * @param id The lifetime-unique transfer-leg identifier.
     * @return exists True if the inception is known.
     * @return amount The payment amount supplied to inceptTransfer.
     * @return from The payment sender.
     * @return to The payment receiver.
     * @return transaction The transaction specification supplied to inceptTransfer.
     * @return callback The callback bound by the inception, including address(0).
     */
    function getInceptionContext(
        uint256 id
    ) external view returns (
        bool exists,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback
    );

    /**
     * @notice Returns immutable generated key material by transfer id.
     * @dev available is an explicit readiness signal; callers MUST NOT infer readiness
     * from zero or empty key values. Once available is true, every returned value MUST
     * remain immutable for the lifetime of the inception.
     * @param id The lifetime-unique transfer-leg identifier.
     * @return available True after all key material is final.
     * @return keyEncryptedSuccess Encryption of the key released on success.
     * @return keyHashedSuccess Hash or other locking representation of the success key.
     * @return keyEncryptedFailure Encryption of the key released on failure.
     * @return keyHashedFailure Hash or other locking representation of the failure key.
     */
    function getInceptionKeyMaterial(
        uint256 id
    ) external view returns (
        bool available,
        bytes memory keyEncryptedSuccess,
        bytes memory keyHashedSuccess,
        bytes memory keyEncryptedFailure,
        bytes memory keyHashedFailure
    );
}
