// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC-7573 Locking Contract - Conditional unlocking of tokens, conditional to the presentation of a key.
 * @dev Interface specification for a smart contract that enables secure stateless delivery-versus-payment.
 *
 * The specification consists of two interfaces,
 * one is implemented by a smart contract on one chain (e.g. the "asset chain" - the asset contract), the other is implemented by
 * a smart contract on another chain (e.g. the "payment chain" - the payment contract).
 * One contract performs a locking, where a transfer is conditional on a presented key: locking contract.
 * The other contract performs a condition decryption of keys, conditional to transfer success or failure: decryption contract.
 *
 * This is the locking contracts interface.
 *
 * The rationale is that the token is locked with two encrypted keys
 * or hashes of keys associated with two different addresses (buyer/seller).
 *
 * The asset is transferred to the address of the buyer, if the buyer's key is presented.
 *
 * The asset in (re-)transferred to the address of the seller, if the seller's key is presented.
 */
interface ILockingContract {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /**
     * @dev Emitted  when the transfer for the token is incepted
     * @param id the trade identifier of the trade.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller.
     * @param to The address of the buyer.
     * @param keyHashedSeller Hashing (or, alternatively, encryption) of the key that can be used by the seller to (re-)claim the token.
     * @param keyEncryptedSeller Encryption of the key that can be used by the seller to (re-)claim the token, if it was provided to inceptTransfer.
     */
    event TransferIncepted(uint256 id, int amount, address from, address to, string keyHashedSeller, string keyEncryptedSeller);

    /**
     * @dev Emitted  when the transfer for the token is confirmed
     * @param id the trade identifier of the trade.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller.
     * @param to The address of the buyer.
     * @param keyHashedBuyer Hashing (or, alternatively, encryption) of the key that can be used by the buyer to claim the token.
     * @param keyEncryptedBuyer Encryption of the key that can be used by the buyer to claim the token, if it was provided to confirmTransfer.
     */
    event TransferConfirmed(uint256 id, int amount, address from, address to, string keyHashedBuyer, string keyEncryptedBuyer);

    /**
     * @dev Emitted when the token was successfully claimed (forwarded to the buyer).
     * @param id the trade ID
     * @param key the key that was used to claim the asset
     */
    event TokenClaimed(uint256 id, string key);

    /**
     * @dev Emitted when the token was re-claimed (back to seller).
     * @param id the trade ID
     * @param key the key that was used to claim the asset
     */
    event TokenReclaimed(uint256 id, string key);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice Called from the buyer of the token to initiate the token transfer.
     * @dev emits a {TransferIncepted}
     * @param id the trade identifier of the trade.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller (the address of the buyer is message.sender).
     * @param keyHashedSeller Hashing (or, alternatively, encryption) of the key that can be used by the seller to (re-)claim the token.
     * @param keyEncryptedSeller Encryption of the key that can be used by the seller to (re-)claim the token. This parameter is optional if keyHashedSeller and keyEncryptedSeller agree. If they not agree, the method will emit both, to allow observing the pair.
     */
    function inceptTransfer(uint256 id, int amount, address from, string memory keyHashedSeller, string memory keyEncryptedSeller) external;

    /**
     * @notice Called from the seller of the token to confirm the token transfer. Locks the token.
     * @dev emits a {TransferConfirmed}
     * @param id the trade identifier of the trade.
     * @param amount the number of tokens to be transferred.
     * @param to The address of the buyer (the address of the seller is message.sender).
     * @param keyHashedBuyer Hashing (or, alternatively, encryption) of the key that can be used by the buyer to claim the token.
     * @param keyEncryptedBuyer Encryption of the key that can be used by the buyer to claim the token. This parameter is optional if keyHashedSeller and keyEncryptedSeller agree. If they not agree, the method will emit both, to allow observing the pair.
     */
    function confirmTransfer(uint256 id, int amount, address to, string memory keyHashedBuyer, string memory keyEncryptedBuyer) external;

    /**
     * @notice Called from the buyer of the token to cancel token transfer (cancels the incept transfer).
     * @dev emits a {TransferKeyRequested}
     * @param id the trade identifier of the trade.
     * @param amount the number of tokens to be transfered.
     * @param from The address of the seller (the address of the buyer is message.sender).
     * @param keyHashedSeller Hashing (or, alternatively, encryption) of the key that can be used by the seller to (re-)claim the token.
     * @param keyEncryptedSeller Encryption of the key that can be used by the seller to (re-)claim the token. This parameter is optional if keyHashedSeller and keyEncryptedSeller agree. If they not agree, the method will emit both, to allow observing the pair.
     */
    function cancelTransfer(uint256 id, int amount, address from, string memory keyHashedSeller, string memory keyEncryptedSeller) external;

    /**
     * @notice Called from the buyer or seller to claim or (re-)claim the token. Unlocks the token.
     * @dev emits a {TokenClaimed} or {TokenReclaimed}
     * @param id the trade identifier of the trade.
     * @param key The key for which the hash or encryption matches either keyEncryptedBuyer (for transfer to the buyer) or keyEncryptedSeller (for transfer to the seller).
     */
    function transferWithKey(uint256 id, string memory key) external;
}
