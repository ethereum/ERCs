// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/*------------------------------------------- DESCRIPTION ---------------------------------------------------------------------------------------*/

/**
 * @title ERC-DVP ASSET Locking of assets and conditional decryption of release keys upon payment to allow secure stateless delivery-versus-payment.
 * @dev Interface specification for a smart contract that enables secure stateless delivery-versus-payment.
 *
 * The specification consists of two interface, one
 * is implemented by a smart contract on the "asset chain"
 * (the asset contract), the other is implemented by
 * a smart contract on the "payment chain" (the payment contract).
 *
 * This is the asset contracts interface.
 *
 * The rationale is that the asset is locked with with two encrypted keys
 * or a hashes of keys associated with two different adresses (buyer/seller).
 *
 * The asset in transfered to the address of the buyer, if the
 * buyer's key is presented.
 *
 * The asset in (re-)transfered to the address of the seller, if the
 * seller's key is presented.
 */
interface IDvPAsset {

    /*------------------------------------------- EVENTS ---------------------------------------------------------------------------------------*/

    /**
     * @dev Emitted  when the transfer for the asset is incepted
     * @param initiator is the address from which trade was incepted
     * @param id the trade ID
     */
    event AssetTransferIncepted(address initiator, uint id);

    /**
     * @dev Emitted  when the transfer for the asset is incepted
     * @param confirmer is the address from which trade was incepted
     * @param id the trade ID
     */
    event AssetTransferConfirmed(address confirmer, uint id);

    /**
     * @dev Emitted when a confirmed trade is set to active - e.g. when termination fee amounts are provided
     * @param id the trade ID
     * @param key the key that was used to claim the asset
     */
    event AssetClaimed(uint id, string key);

    /**
     * @dev Emitted when an active trade is terminated
     * @param id the trade ID
     * @param key the key that was used to claim the asset
     */
    event AssetReclaimed(uint id, string key);

    /*------------------------------------------- FUNCTIONALITY ---------------------------------------------------------------------------------------*/

    /**
     * @notice Called from the buyer of the asset to initiate asset transfer.
     * @dev emits a {AssetTransferIncepted}
     * @param id the trade identifier of the trade.
     * @param from The address of the seller (the address of the buyer is message.sender).
     * @param keyEncryptedSeller Encryption of the key that can be used by the seller to (re-)claim the asset.
     */
    function inceptTransfer(uint id, int amount, address from, string keyEncryptedSeller) external;

    /**
     * @notice Called from the seller of the asset to confirm asset transfer. Locks the asset.
     * @dev emits a {AssetTransferConfirmed}
     * @param id the trade identifier of the trade.
     * @param to The address of the buyer (the address of the seller is message.sender).
     * @param keyEncryptedBuyer Encryption of the key that can be used by the seller to claim the asset.
     */
    function confirmTransfer(uint id, int amount, address to, string keyEncryptedBuyer) external;

    /**
     * @notice Called from the buyer or seller to claim or (re-)claim the asset. Unlocks the asset.
     * @dev emits a {AssetClaimed} or {AssetReclaimed}
     * @param id the trade identifier of the trade.
     * @param key The key for which the hash or encryption matches either keyEncryptedBuyer (for transfer to buyer) or keyEncryptedSeller (for transfer to seller).
     */
    function transferWithKey(uint id, string key) external;
}
