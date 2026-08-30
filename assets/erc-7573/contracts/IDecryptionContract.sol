// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

import {IDecryptionContractInceptionCallback} from "./IDecryptionContractInceptionCallback.sol";

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
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param transaction Immutable application-specific transfer data.
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     */
    event TransferIncepted(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes transaction,
        bytes keyEncryptedSuccess,
        bytes keyEncryptedFailure
    );

    /**
     * @dev Emitted when the transfer is confirmed.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param transaction Immutable application-specific transfer data.
     * @param callback The inception callback. MUST equal the stored asynchronous
     * callback, or address(0) for a synchronous inception.
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     */
    event TransferConfirmed(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes transaction,
        IDecryptionContractInceptionCallback callback,
        bytes keyEncryptedSuccess,
        bytes keyEncryptedFailure
    );

    /**
     * @dev Emitted when a transfer has been performed with a success or failure.
     * @param sender a sender. May provide information of the origin of this request.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param encryptedKey The encrypted key associated with the transaction status.
     */
    event TransferKeyRequested(address sender, uint256 id, bytes encryptedKey);

    /**
     * @dev Emitted when the decrypted key has been obtained.
     * @param sender the sender (oracle) that released the key. Note that some implementation may allow multiple oracles to perform (partial) decryptions.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param success a boolean indicating the status. True: success. False: failure.
     * @param key the decrypted key.
     */
    event TransferKeyReleased(address sender, uint256 id, bool success, bytes key);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice Initiates a payment transfer.
     * @dev The interface MUST NOT infer either participant from msg.sender. Implementations
     * MUST authorize the submitter separately from the explicit participant fields.
     * The success and failure references MUST identify distinct outcome keys.
     * Emits a {TransferIncepted}.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param transaction Immutable application-specific transfer data.
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     */
    function inceptTransfer(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        bytes memory keyEncryptedSuccess,
        bytes memory keyEncryptedFailure
    ) external;

    /**
     * @notice Confirms a payment transfer.
     * @dev Every argument MUST match the immutable completed inception. The interface
     * MUST NOT infer either participant from msg.sender. Implementations
     * MUST authorize the submitter separately from the explicit participant fields.
     * Emits a {TransferConfirmed}.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param transaction Immutable application-specific transfer data.
     * @param callback The inception callback. MUST equal the stored asynchronous
     * callback, or address(0) for a synchronous inception.
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     */
    function confirmTransfer(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback,
        bytes memory keyEncryptedSuccess,
        bytes memory keyEncryptedFailure
    ) external;

    /**
     * @notice Called by an authorized finalizer or operator to initiate completion of the payment transfer(s).
     *   Note: In case of a multi-party DvP there may be multiple incept/confirm pairs.
     *   In case of single DvP the previous confirmTransfer may directly call transferAndDecrypt.
     * @dev emits a {TransferKeyRequested} with keys depending on completion success.
     * @param id Lifetime-unique identifier of this transfer leg.
     */
    function transferAndDecrypt(uint256 id) external;

    /**
     * @notice Cancels a payment transfer and requests its failure key.
     * @dev Every argument MUST match the immutable completed inception. The interface
     * MUST NOT infer either participant from msg.sender. Implementations
     * MUST authorize the submitter separately from the explicit participant fields.
     * Emits a {TransferKeyRequested}.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment.
     * @param to The address of the receiver of the payment.
     * @param transaction Immutable application-specific transfer data.
     * @param callback The inception callback. MUST equal the stored asynchronous
     * callback, or address(0) for a synchronous inception.
     * @param keyEncryptedSuccess Encryption of the key that is emitted upon success.
     * @param keyEncryptedFailure Encryption of the key that is emitted upon failure.
     */
    function cancelAndDecrypt(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        IDecryptionContractInceptionCallback callback,
        bytes memory keyEncryptedSuccess,
        bytes memory keyEncryptedFailure
    ) external;

    /**
     * @notice Called from the (possibly external) decryption oracle.
     * @dev emits a {TransferKeyReleased} (if the call was eligible).
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param key Decrypted key.
     */
    function releaseKey(uint256 id, bytes memory key) external;
}
