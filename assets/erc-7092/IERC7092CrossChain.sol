// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.0;

interface IERC7092CrossChain {
    /**
    * @notice Authorizes the `_spender` account to manage a specified `_amount`of the bondholder bond tokens on the destination Chain
    * @param _spender account to be authorized by the bondholder
    * @param _amount amount of bond tokens to approve
    * @param _destinationChainID The unique ID that identifies the destination Chain.
    * @param _destinationContract The smart contract to interact with in the destination Chain
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present. The method is used to approve tokens in a different chain than the current chain
    */
    function crossChainApprove(address _spender, uint256 _amount, bytes32 _destinationChainID, address _destinationContract) external returns(bool);

    /**
    * @notice Authorizes multiple spender accounts in `_spender` to manage specified amounts in `_amount` of the bondholder tokens on the destination chain
    * @param _spender array of accounts to be authorized by the bondholder
    * @param _amount array of amounts of bond tokens to approve
    * @param _destinationChainID array of unique IDs that identifies the destination Chain.
    * @param _destinationContract array of smart contracts to interact with in the destination Chain in order to Deposit or Mint tokens that are transferred.
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present.
    */
    function crossChainBatchApprove(address[] calldata _spender, uint256[] calldata _amount, bytes32[] calldata _destinationChainID, address[] calldata _destinationContract) external returns(bool);

    /**
    * @notice Decreases the allowance of `_spender` by a specified `_amount` on the destination Chain
    * @param _spender the address to be authorized by the bondholder
    * @param _amount amount of bond tokens to remove from allowance
    * @param _destinationChainID The unique ID that identifies the destination Chain.
    * @param _destinationContract The smart contract to interact with in the destination Chain in order to Deposit or Mint tokens that are transferred.
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present.
    */
    function crossChainDecreaseAllowance(address _spender, uint256 _amount, bytes32 _destinationChainID, address _destinationContract) external;

    /**
    * @notice Decreases the allowance of multiple spenders in `_spender` by corresponding amounts specified in the array `_amount` on the destination chain
    * @param _spender array of accounts to be authorized by the bondholder
    * @param _amount array of amounts of bond tokens to decrease the allowance from
    * @param _destinationChainID array of unique IDs that identifies the destination Chain.
    * @param _destinationContract array of smart contracts to interact with in the destination Chain in order to Deposit or Mint tokens that are transferred.
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present.
    */
    function crossChainBatchDecreaseAllowance(address[] calldata _spender, uint256[] calldata _amount, bytes32[] calldata _destinationChainID, address[] calldata _destinationContract) external;

    /**
    * @notice Moves `_amount` bond tokens to the address `_to` from the current chain to another chain (e.g., moving tokens from Ethereum to Polygon).
    *         This methods also allows to attach data to the token that is being transferred
    * @param _to account to send bond tokens to
    * @param _amount amount of bond tokens to transfer
    * @param _data additional information provided by the bondholder
    * @param _destinationChainID The unique ID that identifies the destination Chain.
    * @param _destinationContract The smart contract to interact with in the destination Chain in order to Deposit or Mint bond tokens that are transferred.
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present.
    */
    function crossChainTransfer(address _to, uint256 _amount, bytes calldata _data, bytes32 _destinationChainID, address _destinationContract) external returns(bool);

    /**
    * @notice Transfers multiple bond tokens with amounts specified in the array `_amount` to the corresponding accounts in the array `_to` from the current chain to another chain (e.g., moving tokens from Ethereum to Polygon).
    *         This methods also allows to attach data to the token that is being transferred
    * @param _to array of accounts to send the bonds to
    * @param _amount array of amounts of bond tokens to transfer
    * @param _data array of additional information provided by the bondholder
    * @param _destinationChainID array of unique IDs that identify the destination Chains.
    * @param _destinationContract array of smart contracts to interact with in the destination Chains in order to Deposit or Mint bond tokens that are transferred.
    *
    * OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present.
    */
    function crossChainBatchTransfer(address[] calldata _to, uint256[] calldata _amount, bytes[] calldata _data, bytes32[] calldata _destinationChainID, address[] calldata _destinationContract) external returns(bool);

    /**
    * @notice Transfers `_amount` bond tokens from the `_from`account to the `_to` account from the current chain to another chain. The caller must be approved by the `_from` address.
    *         This methods also allows to attach data to the token that is being transferred
    * @param _from the bondholder address
    * @param _to the account to transfer bonds to
    * @param _amount amount of bond tokens to transfer
    * @param _data additional information provided by the token holder
    * @param _destinationChainID The unique ID that identifies the destination Chain.
    * @param _destinationContract The smart contract to interact with in the destination Chain in order to Deposit or Mint tokens that are transferred.
    *
    ** OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present
    */
    function crossChainTransferFrom(address _from, address _to, uint256 _amount, bytes calldata _data, bytes32 _destinationChainID, address _destinationContract) external returns(bool);

    /**
    * @notice Transfers several bond tokens with amounts specified in the array `_amount` from accounts in the array `_from` to accounts in the array `_to` from the current chain to another chain.
    *         The caller must be approved by the `_from` accounts to spend the corresponding amounts specified in the array `_amount`
    *         This methods also allows to attach data to the token that is being transferred
    * @param _from array of bondholder addresses
    * @param _to array of accounts to transfer bonds to
    * @param _amount array of amounts of bond tokens to transfer
    * @param _data array of additional information provided by the token holder
    * @param _destinationChainID array of unique IDs that identifies the destination Chain.
    * @param _destinationContract array of smart contracts to interact with in the destination Chain in order to Deposit or Mint tokens that are transferred.
    *
    ** OPTIONAL - interfaces and other contracts MUST NOT expect this function to be present
    */
    function crossChainBatchTransferFrom(address[] calldata _from, address[] calldata _to, uint256[] calldata _amount, bytes[] calldata _data, bytes32[] calldata _destinationChainID, address[] calldata _destinationContract) external returns(bool);

    /**
    * @notice MUST be emitted when bond tokens are transferred or redeemed in a cross-chain transaction
    * @param _from bondholder account
    * @param _to account the transfer bond tokens to
    * @param _amount amount of bond tokens to be transferred
    * @param _destinationChainID The unique ID that identifies the destination Chain
    */
    event CrossChainTransfer(address _from, address _to, uint256 _amount, bytes32 _destinationChainID);

    /**
    * @notice MUST be emitted when several bond tokens are transferred or redeemed in a cross-chain transaction
    * @param _from array of bondholders accounts
    * @param _to array of accounts that receive the bond
    * @param _amount array of amount of bond tokens to be transferred
    * @param _destinationChainID array of unique IDs that identify the destination Chain
    */
    event CrossChainTransferBatch(address[] _from, address[] _to, uint256[] _amount, bytes32[] _destinationChainID);

    /**
    * @notice MUST be emitted when an account is approved to spend the bondholder's tokens in a different chain than the current chain
    * @param _owner the bondholder account
    * @param _spender the account to be allowed to spend bonds
    * @param _amount amount of bond tokens allowed by `_owner` to be spent by `_spender`
    * @param _destinationChainID The unique ID that identifies the destination Chain
    */
    event CrossChainApproval(address _owner, address _spender, uint256 _amount, bytes32 _destinationChainID);

    /**
    * @notice MUST be emitted when multiple accounts in the array `_spender` are approved or when the allowances of multiple accounts in the array `_spender` are reduced on the destination chain which MUST be different than the current chain
    * @param _owner bond token's owner
    * @param _spender array of accounts to be allowed to spend bonds
    * @param _amount array of amount of bond tokens allowed by _owner to be spent by _spender
    * @param _destinationChainID array of unique IDs that identify the destination Chain
    */
    event CrossChainApprovalBatch(address _owner, address[] _spender, uint256[] _amount, bytes32[] _destinationChainID);
}
