// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC-7573 Decryption Oracle Callback Contract - the callback from an external decryption oracle.
 * @dev Interface specification for a smart contract that receives decryption/verification results
 *      (by bridging to an external oracle).
 *
 * Implementation guidance:
 * - Callback implementations SHOULD restrict who can call these methods (e.g. `require(msg.sender == oracleProxy)`).
 * - Callback implementations MUST validate a pending `(msg.sender, requestId)` of the expected operation kind
 *   and consume or mark it before applying callback effects.
 * - Callbacks SHOULD be cheap and should avoid reverting. If heavy work is required, store minimal state/events and
 *   perform the heavy logic in a separate pull/consume transaction initiated by the consumer.
 * - Callbacks MUST assume they may receive less than "all gas" (oracle may reserve headroom / cap forwarded gas).
 *
 * @author Christian Fries.
 * @notice See documentation for details.
 */
interface IKeyDecryptionOracleCallback {
    /**
     * @dev One generated or verified encrypted/hashed key and its semantic role.
     */
    struct EncryptedHashedKey {
        bytes32 keyId;
        bytes encryptedKey;
        bytes hashedKey;
    }

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /**
     * @dev Emitted when the decrypted key has been obtained.
     * @param sender The sender (oracle/proxy) that released the key.
     * @param requestId The oracle-assigned request identifier.
     * @param key The decrypted key.
     */
    event KeyReleased(address sender, uint256 requestId, bytes key);

    /**
     * @dev Emitted when the decryption of a key has been denied.
     * @param sender The sender (oracle/proxy).
     * @param requestId The oracle-assigned request identifier.
     */
    event DecryptionDenied(address sender, uint256 requestId);

    /**
     * @dev Emitted when verification of an atomic encrypted-key batch has completed.
     * @param sender The sender (oracle/proxy).
     * @param requestId The oracle-assigned request identifier.
     * @param verified True only if the complete batch was verified.
     * @param keys The complete requested key set, identified by keyId. On rejection,
     *        hashedKey values MAY be empty but keyId and encryptedKey MUST still echo the request.
     * @param receiverContract The common receiving contract, or address(0) on rejection.
     * @param transaction The common transaction, or empty bytes on rejection.
     */
    event EncryptedKeysVerificationCompleted(
        address sender,
        uint256 requestId,
        bool verified,
        EncryptedHashedKey[] keys,
        address receiverContract,
        bytes transaction
    );

    /**
     * @dev Emitted when a batch of encrypted/hashed keys has been obtained.
     * @param sender The sender (oracle/proxy).
     * @param requestId The oracle-assigned request identifier.
     * @param keys The generated keys, identified by keyId.
     * @param receiverContract The receiving contract.
     * @param transaction The transaction id.
     */
    event EncryptedHashedKeysGenerated(
        address sender,
        uint256 requestId,
        EncryptedHashedKey[] keys,
        address receiverContract,
        bytes transaction
    );

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice Called from the (possibly external) decryption oracle proxy.
     * @dev Implementations SHOULD emit {KeyReleased} (if eligible).
     * @param requestId The oracle-assigned request identifier.
     * @param key Decrypted key.
     */
    function onKeyReleased(uint256 requestId, bytes calldata key) external;

    /**
     * @notice Called from the (possibly external) decryption oracle proxy.
     * This method will only be called if a decryption request was illegal and denied.
     *
     * @dev Implementations SHOULD emit {DecryptionDenied}.
     * @param requestId The oracle-assigned request identifier.
     */
    function onKeyDenied(uint256 requestId) external;

    /**
     * @notice Called from the (possibly external) decryption oracle proxy after atomic
     * verification of an encrypted-key batch.
     * @dev Implementations MUST correlate the complete, role-tagged set to the pending
     * request and SHOULD emit {EncryptedKeysVerificationCompleted} (if eligible).
     * Implementations MUST use `verified`, rather than empty values, as the result status.
     * @param requestId The oracle-assigned request identifier.
     * @param verified True only if the complete batch was verified; partial success is forbidden.
     * @param keys The complete requested key set, identified by keyId. Array order has no meaning.
     * @param receiverContract The common receiving contract, or address(0) on rejection.
     * @param transaction The common transaction, or empty bytes on rejection.
     */
    function onEncryptedKeysVerificationCompleted(
        uint256 requestId,
        bool verified,
        EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external;

    /**
     * @notice Called from the decryption oracle proxy contract.
     * @dev Implementations SHOULD validate the complete batch and emit
     * {EncryptedHashedKeysGenerated} (if eligible).
     * @param requestId The oracle-assigned request identifier.
     * @param keys The generated keys, identified by keyId.
     * @param receiverContract The receiving contract.
     * @param transaction The transaction id.
     */
    function onEncryptedHashedKeysGenerated(
        uint256 requestId,
        EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external;
}
