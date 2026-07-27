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
     * @dev Emitted when a batch of encrypted/hashed keys has been obtained.
     * @param sender The sender (oracle/proxy).
     * @param id The id that was passed in the request (user data).
     * @param keys The generated keys, identified by keyId.
     * @param receiverContract The receiving contract.
     * @param transaction The transaction id.
     */
    event EncryptedHashedKeysGenerated(
        address sender,
        uint256 id,
        EncryptedHashedKey[] keys,
        address receiverContract,
        bytes transaction
    );

    /**
     * @dev Emitted when the verification of an encrypted key has been obtained.
     * @param sender The sender (oracle/proxy).
     * @param id The id that was passed in the request (user data).
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hashed key, or empty if verification failed.
     * @param receiverContract The receiving contract, or empty if verification failed.
     * @param transaction The transaction id, or empty if verification failed.
     */
    event EncryptedKeyVerified(
        address sender,
        uint256 id,
        bytes encryptedKey,
        bytes hashedKey,
        address receiverContract,
        bytes transaction
    );

    /**
     * @dev Emitted when the decrypted key has been obtained.
     * @param sender The sender (oracle/proxy) that released the key.
     * @param id The id that was passed in the request (user data).
     * @param key The decrypted key.
     */
    event KeyReleased(address sender, uint256 id, bytes key);

    /**
     * @dev Emitted when the decryption of a key has been denied.
     * @param sender The sender (oracle/proxy).
     * @param id The id that was passed in the request (user data).
     */
    event DecryptionDenied(address sender, uint256 id);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice Called from the decryption oracle proxy contract.
     * @dev Implementations SHOULD validate the complete batch and emit
     * {EncryptedHashedKeysGenerated} (if eligible).
     * @param id The id that was passed in the request (user data).
     * @param keys The generated keys, identified by keyId.
     * @param receiverContract The receiving contract.
     * @param transaction The transaction id.
     */
    function onEncryptedHashedKeysGenerated(
        uint256 id,
        EncryptedHashedKey[] calldata keys,
        address receiverContract,
        bytes calldata transaction
    ) external;

    /**
     * @notice Called from the (possibly external) decryption oracle proxy.
     * @dev Implementations SHOULD emit {EncryptedKeyVerified} (if eligible).
     * @param id The id that was passed in the request (user data).
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hashed key, or empty if verification failed.
     * @param receiverContract The receiving contract, or empty if verification failed.
     * @param transaction The transaction id, or empty if verification failed.
     */
    function onEncryptedKeyVerified(
        uint256 id,
        bytes calldata encryptedKey,
        bytes calldata hashedKey,
        address receiverContract,
        bytes calldata transaction
    ) external;

    /**
     * @notice Called from the (possibly external) decryption oracle proxy.
     * @dev Implementations SHOULD emit {KeyReleased} (if eligible).
     * @param id The id that was passed in the request (user data).
     * @param key Decrypted key.
     */
    function onKeyReleased(uint256 id, bytes calldata key) external;

    /**
     * @notice Called from the (possibly external) decryption oracle proxy.
     * This method will only be called if a decryption request was illegal and denied.
     *
     * @dev Implementations SHOULD emit {DecryptionDenied}.
     * @param id The id that was passed in the request (user data).
     */
    function onKeyDenied(uint256 id) external;
}
