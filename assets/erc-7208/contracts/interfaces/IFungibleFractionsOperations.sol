// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Fungible Fractions Operations Interface
 * @notice Provides the operations of the FungibleFractionsDO to interact with
 *         fungible fractions tokens and their associated data
 */
interface IFungibleFractionsOperations {
    /**
     * @notice Operation used to get the balance of an account
     * @param account The account address
     * @param id The id of the token
     * @return The balance of the account
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @notice Operation used to get the balance of an account
     * @param account The account address
     * @param ids The ids of the tokens
     * @return The balance of the account
     */
    function balanceOfBatch(address account, uint256[] calldata ids) external view returns (uint256[] memory);

    /**
     * @notice Operation used to get the balance of multiple accounts
     * @param accounts The account addresses
     * @param ids The ids of the tokens
     * @return The balance of the accounts
     */
    function balanceOfBatchAccounts(address[] calldata accounts, uint256[] calldata ids) external view returns (uint256[] memory);

    /**
     * @notice Operation used to get the total supply of a token
     * @param id The id of the token
     * @return The total supply of the token
     */
    function totalSupply(uint256 id) external view returns (uint256);

    /**
     * @notice Operation used to get the total supply of all ids tokens
     * @return The total supply of all ids tokens
     */
    function totalSupplyAll() external view returns (uint256);

    /**
     * @notice Operation used to check if an id exists
     * @param id The id of the token
     * @return True if the id exists, false otherwise
     */
    function exists(uint256 id) external view returns (bool);

    /**
     * @notice Operation used to transfer tokens from one account to another
     * @param from The account to transfer from
     * @param to The account to transfer to
     * @param id The id of the token
     * @param value The amount of tokens to transfer
     */
    function transferFrom(address from, address to, uint256 id, uint256 value) external;

    /**
     * @notice Operation used to transfer tokens from one account to another
     * @param from The account to transfer from
     * @param to The account to transfer to
     * @param ids The ids of the tokens
     * @param values The amounts of tokens to transfer
     */
    function batchTransferFrom(address from, address to, uint256[] calldata ids, uint256[] calldata values) external;

    /**
     * @notice Operation used to mint tokens
     * @param to The account to mint to
     * @param id The id of the token
     * @param value The amount of tokens to mint
     */
    function mint(address to, uint256 id, uint256 value) external;

    /**
     * @notice Operation used to burn tokens
     * @param from The account to burn from
     * @param id The id of the token
     * @param value The amount of tokens to burn
     */
    function burn(address from, uint256 id, uint256 value) external;

    /**
     * @notice Operation used to mint tokens
     * @param to The account to mint to
     * @param ids The ids of the tokens
     * @param values The amounts of tokens to mint
     */
    function batchMint(address to, uint256[] calldata ids, uint256[] calldata values) external;

    /**
     * @notice Operation used to burn tokens
     * @param from The account to burn from
     * @param ids The ids of the tokens
     * @param values The amounts of tokens to burn
     */
    function batchBurn(address from, uint256[] calldata ids, uint256[] calldata values) external;
}
