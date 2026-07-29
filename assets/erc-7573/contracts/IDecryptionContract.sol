// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC-7573 Decryption Contract - Conditional decryption of keys, conditional to transfer success.
 * @dev Interface specification for a smart contract that enables secure stateless delivery-versus-payment.
 *
 * The specification consists of two interfaces,
 * one is implemented by a smart contract on one chain (e.g. the "asset chain" - the asset contract), the other is implemented by
 * a smart contract on another chain (e.g. the "payment chain" - the payment contract).
 * One contract performs a locking, where a transfer is conditional on a presented key: locking contract.
 * The other contract performs a conditional decryption of keys, conditional to transfer success or failure: decryption contract.
 *
 * This is the decryption contract's interface.
 *
 * The rationale is that a transfer is set up with two encrypted keys, the encryptedSuccessKey and the encryptedFailureKey.
 * Upon transfer, a conditional decryption of one of the encrypted keys is performed.
 *
 * The exact decryption method is an implementation detail, however, the key format should
 * ensure that the key is decrypted only if it is associated with the requesting contract.
 *
 * Decryption may be distributed among different trusted decryption oracle (threshold decryption).
 *
 * See documentation for details.
 */
interface IDecryptionContract {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /**
     * @dev Emitted when the transfer is incepted.
     * @param id the trade identifier of the trade.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     */
    event TransferIncepted(uint256 id, int amount, address from, address to, bytes keyEncryptedSuccess, bytes keyEncryptedFailure);

    /**
     * @dev Emitted when the transfer is confirmed.
     * @param id the trade identifier of the trade.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     */
    event TransferConfirmed(uint256 id, int amount, address from, address to, bytes keyEncryptedSuccess, bytes keyEncryptedFailure);

    /**
     * @dev Emitted when a transfer has been performed with a success or failure.
     * @param sender a sender. May provide information of the origin of this request.
     * @param id the trade ID.
     * @param encryptedKey The encrypted key associated with the transaction status.
     */
    event TransferKeyRequested(address sender, uint256 id, bytes encryptedKey);

    /**
     * @dev Emitted when the decrypted key has been obtained.
     * @param sender the sender (oracle) that released the key. Note that some implementation may allow multiple oracles to perform (partial) decryptions.
     * @param id the trade ID.
     * @param success a boolean indicating the status. True: success. False: failure.
     * @param key the decrypted key.
     */
    event TransferKeyReleased(address sender, uint256 id, bool success, bytes key);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice Called from the receiver of the amount to initiate payment transfer.
     * @dev emits a {TransferIncepted}. The returned inception hash MUST be stored
     * with the inception and MUST NOT be reused for a later inception.
     * @param id the DvP identifier. Multiple legs in one multi-party DvP MAY share it;
     * each individual inception MUST remain unambiguous in its participant context.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment (the receiver ('to') is message.sender).
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     * @return inceptionHash The hash of the canonical inception call.
     */
    function inceptTransfer(uint256 id, int amount, address from, bytes memory keyEncryptedSuccess, bytes memory keyEncryptedFailure) external returns (bytes32 inceptionHash);

    /**
     * @notice Called by the sender of the amount to confirm the payment transfer.
     * @dev The confirmation hash MUST be calculated as
     * keccak256(abi.encode(inceptionHash, keyEncryptedSuccess, keyEncryptedFailure))
     * after both encrypted keys have been validated and made immutable.
     * Emits a {TransferConfirmed}.
     * @param id the trade identifier of the trade.
     * @param confirmationHash The stored hash of the completed inception,
     * including its encrypted success and failure keys.
     */
    function confirmTransfer(uint256 id, bytes32 confirmationHash) external;

    /**
     * @notice Called by the sender of the first confirmTransfer to initiate completion of the payment transfer(s).
     *   Note: In case of a multi-party DvP there may be multiple incept/confirm pairs.
     *   In case of single DvP the previous confirmTransfer may directly call transferAndDecrypt.
     * @dev emits a {TransferKeyRequested} with keys depending on completion success.
     * @param id the trade identifier of the trade.
     */
    function transferAndDecrypt(uint256 id) external;

    /**
     * @notice Called from the receiver of the amount to cancel payment transfer (cancels the incept transfer).
     * @dev emits a {TransferKeyRequested}
     * @param id the trade identifier of the trade.
     * @param inceptionHash The stored hash returned by the matching inceptTransfer call.
     */
    function cancelAndDecrypt(uint256 id, bytes32 inceptionHash) external;

    /*+
     * @notice Called from the (possibly external) decryption oracle.
     * @dev emits a {TransferKeyReleased} (if the call was eligible).
     * @param id the trade identifier of the trade.
     * @param key Decrypted key.
     */
    function releaseKey(uint256 id, bytes memory key) external;
}
