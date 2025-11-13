// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITransferOracle} from "./interfaces/ITransferOracle.sol";

/**
 * @title PermissionedERC20 Token
 * @notice An ERC20 token where transfers require validation from a Transfer Oracle.
 * @dev Inherits standard ERC20 functionality and Ownable for minting/burning control.
 *      Calls the associated Transfer Oracle's `canTransfer` method before executing
 *      standard transfers (excluding mints and burns).
 */
contract PermissionedERC20 is ERC20, Ownable {
    // --- State Variables ---

    /**
     * @notice Address of the Transfer Oracle contract used for validating transfers.
     */
    ITransferOracle public immutable transferOracle;

    // --- Events ---

    /**
     * @notice Emitted when a transfer has been successfully validated by the oracle.
     * @param proofId The unique identifier of the proof associated with the consumed approval.
     */
    event TransferValidated(bytes32 indexed proofId);

    // --- Errors ---
    error PermissionedERC20__ZeroAddressOracle();

    // --- Constructor ---

    /**
     * @notice Contract constructor.
     * @param name_ The name of the token.
     * @param symbol_ The symbol of the token.
     * @param oracle_ The address of the TransferOracle contract.
     * @param initialOwner_ The initial owner (typically the deployer or issuer).
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address oracle_,
        address initialOwner_
    ) ERC20(name_, symbol_) Ownable(initialOwner_) {
        if (oracle_ == address(0)) {
            revert PermissionedERC20__ZeroAddressOracle();
        }
        transferOracle = ITransferOracle(oracle_);
    }

    // --- Hook Override ---

    /**
     * @notice Overrides the internal {ERC20-_update} function.
     * @dev Before calling the parent `_update`, this hook checks with the `transferOracle`
     *      if the transfer is permitted.
     *      Minting (from == address(0)) and burning (to == address(0)) bypass the oracle check.
     * @param from Sender address.
     * @param to Recipient address.
     * @param amount Amount to transfer.
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        if (from != address(0) && to != address(0)) {
            // This is a standard transfer, check with the oracle.
            bytes32 proofId = transferOracle.canTransfer(address(this), from, to, amount);
            super._update(from, to, amount);
            emit TransferValidated(proofId);
        } else {
            // For mints/burns, just call super
            super._update(from, to, amount);
        }
    }

    // --- Owner-only Functions ---

    /**
     * @notice Mints new tokens to a specified account.
     * @dev Only callable by the owner.
     *      Does not require oracle approval as it's a mint operation.
     * @param to The account to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burns tokens from a specified account.
     * @dev Only callable by the owner.
     *      Requires the owner to have sufficient allowance if burning from another account.
     *      Does not require oracle approval as it's a burn operation.
     * @param from The account to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function burnFrom(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
} 