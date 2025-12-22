// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

import "./IKeyDecryptionOracleCallback.sol";

/*------------------------------------------- DESCRIPTION ------------------------------------------------------------*/

/**
 * @title ERC-7573 Decryption Oracle Contract - a bridge to an external decryption oracle.
 * @dev Interface specification for a smart contract that performs decryption (by bridging to an external oracle).
 * @author Christian Fries.
 * @notice See documentation for details.
 *
 * Semantics note (best-effort routing):
 * Implementations MAY attempt the callback in a best-effort fashion and MUST NOT assume that
 * callback execution success is equivalent to tx success (`receipt.status == 1`).
 * Implementations SHOULD provide an explicit on-chain signal of callback outcome (e.g. CallbackSucceeded/CallbackFailed events).
 */
interface IKeyDecryptionOracle {
    /*------------------------------------------- EVENTS -------------------------------------------------------------*/

    /**
     * @dev Emitted when a decryption is requested (issued by requestDecrypt).
     * @param sender The requester (msg.sender) that issued the request.
     * @param id General id (will be passed back to callback) - can be used by the requester as correlation id.
     * @param encryptedKey Encryption of a key for which decryption is requested.
     * @param callback Callback contract to be invoked on fulfillment.
     * @param transaction Transaction specification to be verified against the key.
     * @param requestId Correlation id for the fulfillment.
     */
    event DecryptionRequested(
        address indexed sender,
        uint256 id,
        bytes encryptedKey,
        IKeyDecryptionOracleCallback indexed callback,
        bytes transaction,
        uint256 indexed requestId
    );

    /**
     * @dev Emitted when a verification is requested (issued by requestVerifyEncryptedKey).
     * @param sender The requester (msg.sender) that issued the request.
     * @param id General id (will be passed back to callback) - can be used by the requester as correlation id.
     * @param encryptedKey Encryption of a key for which verification is requested.
     * @param callback Receiver of the verification.
     * @param requestId Correlation id for the fulfillment.
     */
    event VerificationRequested(
        address indexed sender,
        uint256 id,
        bytes encryptedKey,
        IKeyDecryptionOracleCallback indexed callback,
        uint256 indexed requestId
    );

    /**
     * @dev Emitted when an encrypted key generation is requested (issued by requestGenerateEncryptedHashedKey).
     * @param sender The requester (msg.sender) that issued the request.
     * @param id General id (will be passed back to callback) - can be used by the requester as correlation id.
     * @param callback Callback contract to be invoked on fulfillment.
     * @param receiverContract Contract that is eligible to request decryption.
     * @param transaction Transaction specification to be verified against the key.
     * @param requestId Correlation id for the fulfillment.
     */
    event EncryptedHashedKeyGenerationRequested(
        address indexed sender,
        uint256 id,
        IKeyDecryptionOracleCallback indexed callback,
        address receiverContract,
        bytes transaction,
        uint256 indexed requestId
    );

    /**
     * @dev Optional but recommended: emitted by the oracle proxy after attempting the callback.
     * Off-chain services SHOULD use these events to decide whether a fulfillment needs retry.
     *
     * selector identifies which callback method was attempted.
     */
    event CallbackSucceeded(
        uint256 indexed requestId,
        address indexed callback,
        bytes4 indexed selector,
        uint256 consumerId
    );

    /**
     * @dev Optional but recommended: emitted by the oracle proxy after attempting the callback.
     * Off-chain services SHOULD use these events to decide whether a fulfillment needs retry.
     *
     * selector identifies which callback method was attempted.
     */
    event CallbackFailed(
        uint256 indexed requestId,
        address indexed callback,
        bytes4 indexed selector,
        uint256 consumerId
    );

    /*------------------------------------------- FUNCTIONALITY: REQUESTS --------------------------------------------*/

    /**
     * @notice Performs a decryption of the given encryptedKey if and only if the caller is allowed to perform this request.
     * The decrypted key is passed to the callback contract's onKeyReleased function, if and only if
     * the callback and the given transaction argument validate against the specification given
     * inside the decrypted key (see the specification of the key format).
     *
     * @dev Emits a {DecryptionRequested} event.
     * @param id An id passed back to the callback function (consumerId).
     * @param encryptedKey Encryption of a key.
     * @param callback The callback contract.
     * @param transaction General purpose transaction identifier.
     */
    function requestDecrypt(
        uint256 id,
        bytes calldata encryptedKey,
        IKeyDecryptionOracleCallback callback,
        bytes calldata transaction
    ) external payable;

    /**
     * @notice Performs a verification of the given encryptedKey:
     * decrypts and extracts associated contract/transaction (see key format), and calculates a hash
     * of the decrypted key. The tuple (hash, contract, transaction) is passed back to the callback
     * without exposing the decrypted key.
     *
     * @dev Emits a {VerificationRequested} event.
     * @param id An id passed back to the callback function (consumerId).
     * @param encryptedKey Encryption of a key.
     * @param callback The callback contract.
     */
    function requestVerifyEncryptedKey(
        uint256 id,
        bytes calldata encryptedKey,
        IKeyDecryptionOracleCallback callback
    ) external payable;

    /**
     * @notice Performs a generation of an encryptedKey and a hash internally associated with the given
     * contract (receiverContract) and the transaction. The generated encryptedKey and hashedKey are passed
     * to the callback contract.
     *
     * @dev Emits a {EncryptedHashedKeyGenerationRequested} event.
     * @param id An id passed back to the callback function (consumerId).
     * @param callback The callback contract.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction General purpose transaction identifier.
     */
    function requestGenerateEncryptedHashedKey(
        uint256 id,
        IKeyDecryptionOracleCallback callback,
        address receiverContract,
        bytes calldata transaction
    ) external payable;

    /*------------------------------------------- FUNCTIONALITY: FULFILLMENT (should be guarded by onlyOracle) -------*/

    /**
     * @dev Fulfillment of a decryption request (issued by requestDecrypt).
     *
     * Best-effort + calldata fallback:
     * - Implementations MAY attempt to call the consumer callback and MAY NOT revert if the callback fails (incl. OOG).
     *   In such cases the implementation SHOULD signal failure via {CallbackFailed} and allow the off-chain oracle to retry.
     * - The fulfillment payload (e.g., `key`) is always present in the transaction calldata of this fulfill call.
     *   Off-chain systems can use the emitted log's `transactionHash` to fetch and decode tx input calldata using this ABI.
     * - Practical caveat: some RPC providers prune old transaction bodies; store decoded payload off-chain if needed.
     *
     * @param requestId Correlation id from the request event.
     * @param key Decrypted key if admissible, otherwise empty bytes.
     */
    function fulfillDecryption(uint256 requestId, bytes calldata key) external;

    /**
     * @dev Fulfillment of a verification request (issued by requestVerifyEncryptedKey).
     * Best-effort + calldata fallback: see fulfillDecryption @dev.
     *
     * @param requestId Correlation id from the request event.
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hash of the key.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction Transaction that is eligible to request decryption.
     */
    function fulfillVerification(
        uint256 requestId,
        bytes calldata encryptedKey,
        bytes calldata hashedKey,
        address receiverContract,
        bytes calldata transaction
    ) external;

    /**
     * @dev Fulfillment of a key generation request (issued by requestGenerateEncryptedHashedKey).
     * Best-effort + calldata fallback: see fulfillDecryption @dev.
     *
     * @param requestId Correlation id from the request event.
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hash of the key.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction Transaction that is eligible to request decryption.
     */
    function fulfillEncryptedHashedKeyGeneration(
        uint256 requestId,
        bytes calldata encryptedKey,
        bytes calldata hashedKey,
        address receiverContract,
        bytes calldata transaction
    ) external;
}
