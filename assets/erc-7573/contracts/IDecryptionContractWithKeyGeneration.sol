// SPDX-License-Identifier: CC0-1.0
pragma solidity >=0.7.0;

import "./IDecryptionContract.sol";

/**
 * @title ERC-7573 Decryption Contract with asynchronous key generation.
 * @dev Extends IDecryptionContract with an inception method for transfers whose
 * encrypted success and failure keys are generated asynchronously.
 */
interface IDecryptionContractWithKeyGeneration is IDecryptionContract {

    /**
     * @notice Called from the receiver of the amount to initiate payment transfer
     * and asynchronous generation of the encrypted success and failure keys.
     * @dev TransferIncepted is emitted only after both generated keys have been
     * validated and stored. The returned commitment MUST be stored with the
     * pending inception and MUST NOT be reused for a later inception.
     * @param id the unique trade identifier. It MUST NOT have been used for an earlier inception.
     * @param amount the amount to be transferred.
     * @param from The address of the sender of the payment (the receiver ('to') is message.sender).
     * @param transaction The transaction specification used to generate the keys.
     * @return commitmentHash The inception-call commitment. It does not contain
     * the keys generated after this call.
     */
    function inceptTransfer(uint256 id, int amount, address from, bytes memory transaction) external returns (bytes32 commitmentHash);
}
