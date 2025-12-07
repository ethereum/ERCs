// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

import "./IKeyDecryptionOracleCallback.sol";

/*------------------------------------------- DESCRIPTION ------------------------------------------------------------*/

/**
 * @title ERC-7573 Decryption Oracle Contract - a bridge to an external decryption oracle.
 * @dev Interface specification for a smart contract that performs decryption (by bridging to an external oracle).
 *
 * See documentation for details.
 */
interface IKeyDecryptionOracle {

    /*------------------------------------------- EVENTS -------------------------------------------------------------*/

    /**
     * @dev Emitted when a decryption is requested (issued by requestDecrypt).
     * @param sender Contract implementing this interface.
     * @param id General id (will be passed back to releaseKey of callback) - can be user by the requester as correlation id.
     * @param encryptedKey Encryption of a key for which decryption is requested.
     * @param callback Contract to be verified against the key.
     * @param transaction Transaction specification to be verified against the key.
     * @param requestId Correlation id for the fullfillmen
     */
    event DecryptionRequested(address indexed sender, uint256 id, bytes encryptedKey, IKeyDecryptionOracleCallback indexed callback, bytes transaction, uint256 indexed requestId);

    /**
     * @dev Emitted when a verification is requested (issued by requestVerifyEncryptedKey).
     * @param sender Contract implementing this interface.
     * @param id General id (will be passed back to releaseKey of callback) - can be user by the requester as correlation id.
     * @param encryptedKey Encryption of a key for which verification is requested.
     * @param callback Receiver of the verification.
     * @param requestId Correlation id for the fullfillmen
     */
    event VerificationRequested(address indexed sender, uint256 id, bytes encryptedKey, IKeyDecryptionOracleCallback indexed callback, uint256 indexed requestId);

    /**
     * @dev Emitted when a encrypted key generation is requested (issued by requestGenerateEncryptedHashedKey).
     * @param sender Contract implementing this interface.
     * @param id General id (will be passed back to releaseKey of callback) - can be user by the requester as correlation id.
     * @param callback Contract to be verified against the key.
     * @param receiverContract Contract that is elegible to request decryption.
     * @param transaction Transaction specification to be verified against the key.
     * @param requestId Correlation id for the fullfillmen
     */
    event EncryptedHashedKeyGenerationRequested(address indexed sender, uint256 id, IKeyDecryptionOracleCallback indexed callback, address receiverContract, bytes transaction, uint256 indexed requestId);

    /*------------------------------------------- FUNCTIONALITY: REQUESTS --------------------------------------------*/

    /**
     * @notice The functions performs a decryption of the given encryptedKey if and only if the caller is allowed to perform this request.
     * The decrypted key is passed to the callback contract's onKeyReleased function, if and only if the
     * the callback and the given transaction argument validate against the specification
     * given inside the decrypted key (see the specification of the key format).
     *
     * @dev emits a {DecryptionRequested} event.
     * @param id An id passed back to the releaseKey function (consumerId).
     * @param encryptedKey Encryption of a key
     * @param callback The callback contract. If validated the decrypted key will be passed to releaseKey function.
     * @param transaction General purpose transaction identifier.
     */
    function requestDecrypt(uint256 id, bytes memory encryptedKey, IKeyDecryptionOracleCallback callback, bytes memory transaction) external payable;

    /**
     * @notice The functions performs a verification of the given encryptedKey, that this
     * it perform a decryption of the encrypted key and extracts the associated contract and
     * transaction (see the specification of the key format) and calculated a hash
     * of the decrypted key. The tripple (hash, contract, tranaction) is passed
     * back to the callback contract onEncryptedKeyVerified without exposing the decrypted key.
     *
     * @dev emits a {VerificationRequested} event.
     * @param id An id passed back to the releaseKey function (consumerId).
     * @param encryptedKey Encryption of a key
     * @param callback The callback contract. If validated the decrypted key will be passed to releaseKey function.
     */
    function requestVerifyEncryptedKey(uint256 id, bytes memory encryptedKey, IKeyDecryptionOracleCallback callback) external payable;

    /**
     * @notice The functions performs a generation of an encryptedKey and a hash
     * internally assocated with the given contract (receiverContract) and the transaction.
     * The generated encryptedKey and hashedKey is passed to the callback contract's
     * onEncryptedHashedKeyGenerated method.
     *
     * @dev emits a {EncryptedHashedKeyGenerationRequested} event.
     * @param id An id passed back to the releaseKey function (consumerId).
     * @param callback The callback contract. If validated the decrypted key will be passed to releaseKey function.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction General purpose transaction identifier.
     */
    function requestGenerateEncryptedHashedKey(uint256 id, IKeyDecryptionOracleCallback callback, address receiverContract, bytes memory transaction) external payable;

    /*------------------------------------------- FUNCTIONALITY: FULFILLMENT (should be guarded by onlyOracle) -------*/

    /**
     * @dev Fulfillment of a decryption request (issued by requestDecrypt).
     * @param requestId Correlation id from the event.
     * @param key Decryption of the encrypted key, if the request was admissible, otherwise an empty string.
     */
    function fulfillDecryption(uint256 requestId, bytes memory key) external;

    /**
     * @dev Fulfillment of a verification request (issued by requestVerifyEncryptedKey).
     * @param requestId Correlation id from the event.
     * @param encryptedKey Encryption the key.
     * @param hashedKey Hash of the key.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction That is eligible to request decryption.
     */
    function fulfillVerification(uint256 requestId, bytes memory encryptedKey, bytes memory hashedKey, address receiverContract, bytes memory transaction) external;

    /**
     * @dev Fulfillment of a key generation request (issued by requestGenerateEncryptedHashedKey).
     * @param requestId Correlation id from the event.
     * @param encryptedKey Encryption the key.
     * @param hashedKey Hash of the key.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction That is eligible to request decryption.
     */
    function fulfillEncryptedHashedKeyGeneration(uint256 requestId, bytes memory encryptedKey, bytes memory hashedKey, address receiverContract, bytes memory transaction) external;
}
