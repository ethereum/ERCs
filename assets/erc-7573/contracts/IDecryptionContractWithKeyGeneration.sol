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
     * @notice Called from the receiver of the amount to initiate payment transfer
     * and asynchronous generation of the encrypted success and failure keys, with
     * an optional on-chain completion callback.
     * @dev TransferIncepted is emitted only after both generated keys have been
     * validated and stored and the confirmation hash defined by
     * IDecryptionContract has been derived. The returned inception hash MUST be
     * stored with the pending inception and MUST NOT be reused for a later inception.
     * The callback value is part of the canonical inception call and MUST always be
     * bound by inceptionHash, including when it is address(0).
     *
     * If callback is address(0), the implementation MUST skip callback delivery.
     * Otherwise, after the inception has been completed and
     * TransferIncepted has been emitted, the implementation MUST call
     * callback.onInceptionCompleted(id, inceptionHash, confirmationHash).
     * The callback MUST acknowledge with its function selector. A revert, invalid
     * return value, or insufficient callback gas MUST revert this completion attempt
     * and leave the inception pending so that completion can be retried.
     * @param id the DvP identifier. Multiple legs in one multi-party DvP MAY share it;
     * each individual inception MUST remain unambiguous in its participant context.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment (the receiver ('to') is message.sender).
     * @param transaction The transaction specification used to generate the keys.
     * @param callback The contract receiving the completed inception hashes, or
     * address(0) when no on-chain callback is required.
     * @return inceptionHash The hash of this canonical inception call,
     * including the callback value. It does not contain the keys generated after this call.
     */
    function inceptTransfer(
        uint256 id,
        int amount,
        address from,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback
    ) external returns (bytes32 inceptionHash);
}
