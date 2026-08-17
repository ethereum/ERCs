// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

/**
 * @title ERC-7573 asynchronous inception completion callback.
 * @dev Optional callback implemented by a contract that must be notified when
 * asynchronous key generation has completed an inception.
 *
 * Implementations MUST validate msg.sender as the expected decryption contract
 * and MUST match inceptionHash to a pending local operation before applying
 * effects. Returning the function selector acknowledges successful delivery.
 */
interface IDecryptionContractInceptionCallback {

    /**
     * @notice Called after the decryption contract has validated and stored both
     * generated keys, derived confirmationHash, completed the inception,
     * and emitted TransferIncepted.
     * @param id The consumer-defined DvP identifier.
     * @param inceptionHash The hash returned by the asynchronous
     * inceptTransfer call.
     * @param confirmationHash The hash of the completed inception
     * and its immutable success and failure keys.
     * @return acknowledgement MUST equal
     * IDecryptionContractInceptionCallback.onInceptionCompleted.selector.
     */
    function onInceptionCompleted(
        uint256 id,
        bytes32 inceptionHash,
        bytes32 confirmationHash
    ) external returns (bytes4 acknowledgement);
}
