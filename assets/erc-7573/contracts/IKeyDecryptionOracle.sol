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
 *
 * Request correlation:
 * Each request method MUST allocate and return a requestId that is unique within the oracle proxy.
 * The proxy MUST pass that requestId to the callback. The caller-supplied id is consumer context
 * retained in the request event; it is not the callback correlation identifier.
 * Request methods MUST return before attempting the corresponding callback.
 * Before invoking a callback, the proxy MUST make that request unavailable to another fulfillment.
 * A best-effort implementation MAY restore it to pending after a failed callback so it can be retried.
 */
interface IKeyDecryptionOracle {
    /*------------------------------------------- EVENTS -------------------------------------------------------------*/

    /**
     * @dev Emitted when a decryption is requested (issued by requestDecrypt).
     * @param sender The requester (msg.sender) that issued the request.
     * @param id Consumer-defined context emitted with the request.
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
     * @param id Consumer-defined context emitted with the request.
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
     * @dev Emitted when encrypted key generation is requested (issued by requestGenerateEncryptedHashedKeys).
     * @param sender The requester (msg.sender) that issued the request.
     * @param id Consumer-defined context emitted with the request.
     * @param callback Callback contract to be invoked on fulfillment.
     * @param receiverContract Contract that is eligible to request decryption.
     * @param transaction Transaction specification to be verified against the key.
     * @param keyIds Unique semantic identifiers for the keys to generate.
     * @param requestId Correlation id for the fulfillment.
     */
    event EncryptedHashedKeysGenerationRequested(
        address indexed sender,
        uint256 id,
        IKeyDecryptionOracleCallback indexed callback,
        address receiverContract,
        bytes transaction,
        bytes32[] keyIds,
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
     * @param id Consumer-defined context emitted with the request.
     * @param encryptedKey Encryption of a key.
     * @param callback The callback contract.
     * @param transaction General purpose transaction identifier.
     * @return requestId Oracle-assigned correlation identifier passed to the callback.
     */
    function requestDecrypt(
        uint256 id,
        bytes calldata encryptedKey,
        IKeyDecryptionOracleCallback callback,
        bytes calldata transaction
    ) external payable returns (uint256 requestId);

    /**
     * @notice Performs a verification of the given encryptedKey:
     * decrypts and extracts associated contract/transaction (see key format), and calculates a hash
     * of the decrypted key. The tuple (hash, contract, transaction) is passed back to the callback
     * without exposing the decrypted key.
     *
     * @dev Emits a {VerificationRequested} event.
     * @param id Consumer-defined context emitted with the request.
     * @param encryptedKey Encryption of a key.
     * @param callback The callback contract.
     * @return requestId Oracle-assigned correlation identifier passed to the callback.
     */
    function requestVerifyEncryptedKey(
        uint256 id,
        bytes calldata encryptedKey,
        IKeyDecryptionOracleCallback callback
    ) external payable returns (uint256 requestId);

    /**
     * @notice Generates a batch of encrypted keys and hashes internally associated with the given
     * contract (receiverContract) and transaction. The generated keys are passed to the callback contract.
     *
     * @dev Emits an {EncryptedHashedKeysGenerationRequested} event.
     * Implementations MUST reject an empty `keyIds` array and duplicate identifiers.
     * @param id Consumer-defined context emitted with the request.
     * @param callback The callback contract.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction General purpose transaction identifier.
     * @param keyIds Unique semantic identifiers for the keys to generate. A single-element batch is valid.
     * @return requestId Oracle-assigned correlation identifier passed to the callback.
     */
    function requestGenerateEncryptedHashedKeys(
        uint256 id,
        IKeyDecryptionOracleCallback callback,
        address receiverContract,
        bytes calldata transaction,
        bytes32[] calldata keyIds
    ) external payable returns (uint256 requestId);

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
     * Best-effort + calldata fallback: see fulfillDecryption.
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
     * @dev Fulfillment of a key generation request (issued by requestGenerateEncryptedHashedKeys).
     * Implementations MUST reject a receiver or transaction that differs from the request,
     * and MUST reject duplicate, missing, or unrequested keyIds. Array order has no semantic
     * meaning. A successful fulfillment MUST deliver the complete batch in one callback;
     * partial callbacks are forbidden. Best-effort + calldata fallback: see fulfillDecryption.
     *
     * @param requestId Correlation id from the request event.
     * @param keys Generated keys, identified by keyId.
     * @param receiverContract Contract that is eligible to receive the decryption.
     * @param transaction Transaction that is eligible to request decryption.
     */
    function fulfillEncryptedHashedKeysGeneration(
        uint256 requestId,
        IKeyDecryptionOracleCallback.EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external;
}
