// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.8.0 <0.9.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC-7573 Decryption Oracle Callback Contract - the callback from an external decryption oracle.
 * @dev Interface specification for a smart contract that performs decryption (by bridging to an external oracle).
 * @author Christian Fries.
 * @notice See documentation for details.
 */
interface IKeyDecryptionOracleCallback {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /**
     * @dev Emitted when the decrypted key has been obtained.
     * @param sender the sender (oracle) that released the key. Note that some implementation may allow multiple oracles to perform (partial) decryptions.
     * @param id The id that was passed in the request (user data)
     * @param key the decrypted key.
     */
    event KeyReleased(address sender, uint256 id, bytes key);

    /**
     * @dev Emitted when the decryption of a key has been denied.
     * @param sender a sender. May provide information of the origin of this request.
     * @param id The id that was passed in the request (user data)
     */
    event DecryptionDenied(address sender, uint256 id);

    /**
     * @dev Emitted when the verification of an encrypted key has been obtained.
     * @param sender the sender (oracle) that released the key. Note that some implementation may allow multiple oracles to perform (partial) decryptions.
     * @param id The id that was passed in the request (user data)
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hashed key, or empty if verification failed.
     * @param receiverContract the recieving contract, or empty if verification failed.
     * @param transaction the transaction id, or empty if verification failed.
     */
    event EncryptedKeyVerified(address sender, uint256 id, bytes encryptedKey, bytes hashedKey, address receiverContract, bytes transaction);

    /**
     * @dev Emitted when the an encrypted/hashed key has been obtained.
     * @param sender the sender (oracle) that released the key. Note that some implementation may allow multiple oracles to perform (partial) decryptions.
     * @param id The id that was passed in the request (user data)
     * @param encryptedKey the encrypted key.
     * @param hashedKey the hashed key.
     * @param receiverContract the recieving contract.
     * @param transaction the transaction id.
     */
    event EncryptedHashedKeyGenerated(address sender, uint256 id, bytes encryptedKey, bytes hashedKey, address receiverContract, bytes transaction);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /*+
     * @notice Called from the (possibly external) decryption oracle.
     * @dev emits a {KeyReleased} (if the call was eligible).
     * @param id The id that was passed in the request (user data)
     * @param key Decrypted key.
     */
    function onKeyReleased(uint256 id, bytes memory key) external;

    /*+
     * @notice Called from the (possibly external) decryption oracle.
     * This method will only be called if a decryption request was illegal and denied
     *
     * @dev emits a {DecryptionDenied}
     * @param id The id that was passed in the request (user data)
     */
    function onKeyDenied(uint256 id) external;

    /*+
     * @notice Called from the (possibly external) decryption oracle.
     * @dev emits a {EncryptedKeyVerified} (if the call was eligible).
     * @param id The id that was passed in the request (user data)
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hashed key, or empty if verification failed.
     * @param receiverContract the recieving contract, or empty if verification failed.
     * @param transaction the transaction id, or empty if verification failed.
     */
    function onEncryptedKeyVerified(uint256 id, bytes memory encryptedKey, bytes memory hashedKey, address receiverContract, bytes memory transaction) external;

    /*+
     * @notice Called from the decryption oracle contract.
     * @dev emits a {EncryptedHashedKeyGenerated} (if the call was eligible).
     * @param id The id that was passed in the request (user data)
     * @param encryptedKey Encrypted key.
     * @param hashedKey Hashed key.
     * @param receiverContract the recieving contract.
     * @param transaction the transaction id.
     */
    function onEncryptedHashedKeyGenerated(uint256 id, bytes memory encryptedKey, bytes memory hashedKey, address receiverContract, bytes memory transaction) external;
}
