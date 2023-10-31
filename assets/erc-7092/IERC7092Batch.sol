// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

interface IERC7092Batch {
    /**
    * @notice Authorizes multiple spender accounts to manage a specified `_amount` of the bondholder tokens
    * @param _spender array of accounts to be authorized by the bondholder
    * @param _amount array of amounts of bond tokens to approve
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect these values to be present. The method is used to improve usability.
    */
    function batchApprove(address[] calldata _spender, uint256[] calldata _amount) external returns(bool);

    /**
    * @notice Decreases the allowance of multiple spenders by corresponding amounts in `_amount`
    * @param _spender array of accounts to be authorized by the bondholder
    * @param _amount array of amounts of bond tokens to decrease the allowance from
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present. The method is used to decrease token allowance.
    */
    function batchDecreaseAllowance(address[] calldata _spender, uint256[] calldata _amount) external;

    /**
    * @notice Transfers multiple bonds with amounts specified in the array `_amount` to the corresponding accounts in the array `_to`, with the option to attach additional data
    * @param _to array of accounts to send the bonds to
    * @param _amount array of amounts of bond tokens to transfer
    * @param _data array of additional information provided by the token holder
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present.
    */
    function batchTransfer(address[] calldata _to, uint256[] calldata _amount, bytes[] calldata _data) external returns(bool);

    /**
    * @notice Transfers multiple bonds with amounts specified in the array `_amount` to the corresponding accounts in the array `_to` from an account that have been authorized by the `_from` account
    *         This method also allows to attach data to tokens that are being transferred
    * @param _from array of bondholder accounts
    * @param _to array of accounts to transfer bond tokens to
    * @param _amount array of amounts of bond tokens to transfer.
    * @param _data array of additional information provided by the token holder
    *
    ** OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present.
    */
    function batchTransferFrom(address[] calldata _from, address[] calldata _to, uint256[] calldata _amount, bytes[] calldata _data) external returns(bool);

    /**
    * @notice MUST be emitted when multiple bond tokens are transferred, issued or redeemed, with the exception being during contract creation
    * @param _from bondholder account
    * @param _to array of accounts to transfer bonds to
    * @param _amount array of amounts of bond tokens to be transferred
    *
    ** OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present. MUST be emitted in `batchTransfer` and `batchTransferFrom` functions
    */
    event TransferBatch(address _from, address[] _to, uint256[] _amount);

    /**
    * @notice MUST be emitted when multiple accounts are approved or when the allowance is decreased from multiple accounts
    * @param _owner bondholder account
    * @param _spender array of accounts to be allowed to spend bonds, or to decrase the allowance from
    * @param _amount array of amounts of bond tokens allowed by `_owner` to be spent by multiple accounts in `_spender`.
    *
    ** OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present. MUST be emitted in `batchApprove` and `batchDecreaseAllowance` functions
    */
    event ApprovalBatch(address _owner, address[] _spender, uint256[] _amount);
}
