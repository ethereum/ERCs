// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/**
 * @title ERC-7573 asynchronous inception completion callback.
 * @dev Optional callback implemented by a contract that must be notified when
 * asynchronous key generation has completed an inception.
 *
 * Implementations MUST validate msg.sender as the expected decryption contract
 * and MUST match id and every semantically corresponding context field to a pending
 * local operation before applying effects. Implementations MUST read and validate
 * the completed, immutable inception and key material from the calling decryption
 * contract before applying effects.
 * Returning the function selector acknowledges successful delivery.
 */
interface IDecryptionContractInceptionCallback {

    /**
     * @notice Called after the decryption contract has validated and stored all
     * generated key material, completed the inception, and emitted
     * TransferIncepted. The completed state and key material MUST be
     * available through IDecryptionContractWithKeyGeneration getters.
     * @param id The lifetime-unique transfer-leg identifier.
     * @return acknowledgement MUST equal
     * IDecryptionContractInceptionCallback.onInceptionCompleted.selector.
     */
    function onInceptionCompleted(uint256 id) external returns (bytes4 acknowledgement);
}
