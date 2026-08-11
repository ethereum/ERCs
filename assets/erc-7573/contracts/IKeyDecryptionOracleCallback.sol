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
     * @dev One generated encrypted/hashed key and its semantic role.
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
     * @dev Emitted when the verification of an encrypted key has been obtained.
     * @param sender The sender (oracle/proxy).
     * @param requestId The oracle-assigned request identifier.
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hashed key, or empty if verification failed.
     * @param receiverContract The receiving contract, or empty if verification failed.
     * @param transaction The transaction id, or empty if verification failed.
     */
    event EncryptedKeyVerified(
        address sender,
        uint256 requestId,
        bytes encryptedKey,
        bytes hashedKey,
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
     * @notice Called from the (possibly external) decryption oracle proxy.
     * @dev Implementations SHOULD emit {EncryptedKeyVerified} (if eligible).
     * @param requestId The oracle-assigned request identifier.
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hashed key, or empty if verification failed.
     * @param receiverContract The receiving contract, or empty if verification failed.
     * @param transaction The transaction id, or empty if verification failed.
     */
    function onEncryptedKeyVerified(
        uint256 requestId,
        bytes calldata encryptedKey,
        bytes calldata hashedKey,
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
