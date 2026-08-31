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
 * The other contract performs a conditional decryption of keys, conditional to transfer success or failure: decryption contract.
 *
 * This is the locking contract's interface.
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
     * @dev Emitted when the transfer for the token is incepted.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller.
     * @param to The address of the buyer.
     * @param transaction Immutable application-specific transfer data.
     * @param keyHashedSeller Hashing (or, alternatively, encryption) of the key that can be used by the seller to (re-)claim the token.
     * @param keyEncryptedSeller Encryption of the key that can be used by the seller to (re-)claim the token, if it was provided to inceptTransfer.
     */
    event TransferIncepted(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes transaction,
        bytes keyHashedSeller,
        bytes keyEncryptedSeller
    );

    /**
     * @dev Emitted when the transfer for the token is confirmed.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller.
     * @param to The address of the buyer.
     * @param transaction Immutable application-specific transfer data.
     * @param keyHashedBuyer Hashing (or, alternatively, encryption) of the key that can be used by the buyer to claim the token.
     * @param keyEncryptedBuyer Encryption of the key that can be used by the buyer to claim the token, if it was provided to confirmTransfer.
     */
    event TransferConfirmed(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes transaction,
        bytes keyHashedBuyer,
        bytes keyEncryptedBuyer
    );

    /**
     * @dev Emitted when the token was successfully claimed (forwarded to the buyer).
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param key the key that was used to claim the asset
     */
    event TokenClaimed(uint256 id, bytes key);

    /**
     * @dev Emitted when the token was re-claimed (back to seller).
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param key the key that was used to claim the asset
     */
    event TokenReclaimed(uint256 id, bytes key);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice Initiates a token transfer.
     * @dev The `from` and `to` participants MUST be supplied explicitly. `msg.sender`
     * identifies only the caller and MUST NOT, by itself, determine either participant.
     * Implementations MAY require `msg.sender` to be a participant or an authorized operator.
     * Emits a {TransferIncepted}.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller.
     * @param to The address of the buyer.
     * @param transaction Immutable application-specific transfer data.
     * @param keyHashedSeller Hashing (or, alternatively, encryption) of the key that can be used by the seller to (re-)claim the token.
     * @param keyEncryptedSeller Encryption of the key that can be used by the seller to (re-)claim the token. This parameter is optional if keyHashedSeller and keyEncryptedSeller agree. If they do not agree, the method will emit both, to allow observing the pair.
     */
    function inceptTransfer(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        bytes memory keyHashedSeller,
        bytes memory keyEncryptedSeller
    ) external;

    /**
     * @notice Confirms the token transfer and locks the token.
     * @dev Every context argument MUST match the immutable inception. The `from` and `to`
     * participants MUST be supplied explicitly. `msg.sender` identifies only the caller
     * and MUST NOT, by itself, determine either participant. Implementations MAY require
     * `msg.sender` to be a participant or an authorized operator. The buyer and seller
     * outcome material MUST identify distinct keys where the representations are directly comparable.
     * Emits a {TransferConfirmed}.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller.
     * @param to The address of the buyer.
     * @param transaction Immutable application-specific transfer data.
     * @param keyHashedBuyer Hashing (or, alternatively, encryption) of the key that can be used by the buyer to claim the token.
     * @param keyEncryptedBuyer Encryption of the key that can be used by the buyer to claim the token. This parameter is optional if keyHashedBuyer and keyEncryptedBuyer agree. If they do not agree, the method will emit both, to allow observing the pair.
     */
    function confirmTransfer(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        bytes memory keyHashedBuyer,
        bytes memory keyEncryptedBuyer
    ) external;

    /**
     * @notice Cancels the token transfer before confirmation.
     * @dev Every argument MUST match the immutable inception. The `from` and `to`
     * participants MUST be supplied explicitly. `msg.sender` identifies only the caller
     * and MUST NOT, by itself, determine either participant. Implementations MAY require
     * `msg.sender` to be a participant or an authorized operator.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param amount the number of tokens to be transferred.
     * @param from The address of the seller.
     * @param to The address of the buyer.
     * @param transaction Immutable application-specific transfer data.
     * @param keyHashedSeller Hashing (or, alternatively, encryption) of the key that can be used by the seller to (re-)claim the token.
     * @param keyEncryptedSeller Encryption of the key that can be used by the seller to (re-)claim the token. This parameter is optional if keyHashedSeller and keyEncryptedSeller agree. If they do not agree, the method will emit both, to allow observing the pair.
     */
    function cancelTransfer(
        uint256 id,
        int amount,
        address from,
        address to,
        bytes memory transaction,
        bytes memory keyHashedSeller,
        bytes memory keyEncryptedSeller
    ) external;

    /**
     * @notice Presents a released key to claim or (re-)claim the token. Unlocks the token.
     * @dev The caller MAY be the buyer, seller, a decryption contract, or another relayer.
     * An implementation MAY restrict callers, but where the stored participants and matching
     * key determine the immutable destination, knowledge of the key can be the authorization.
     * Emits a {TokenClaimed} or {TokenReclaimed}.
     * @param id Lifetime-unique identifier of this transfer leg.
     * @param key The released key whose derived hash or other locking representation
     * matches the stored buyer or seller outcome value.
     */
    function transferWithKey(uint256 id, bytes memory key) external;
}
