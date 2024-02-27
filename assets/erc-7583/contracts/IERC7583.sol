// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @title ERC-7583 Inscription Standard in Smart Contracts
interface IERC7583 is IERC20, IERC165 {
    /**
     * @dev Emitted when `value` fungible tokens are moved from one inscription (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event TransferInsToIns(uint256 indexed fromIns, uint256 indexed toIns, uint256 value);

	/**
     * @dev Emitted when `inscriptionId` token is transferred from `from` to `to`.
     */
    event TransferIns(address indexed from, address indexed to, uint256 indexed inscriptionId);

	/**
     * @dev Emitted when `owner` enables `approved` to manage the `insId` inscription.
     */
    event ApprovalIns(address indexed owner, address indexed approved, uint256 indexed insId);

	/**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the amount of inscriptions owned by `account`.
     */
    function insBalance(address account) external view returns (uint256);

	/**
     * @dev Returns the value of fungible tokens in the inscription(`indId`).
     */
    function balanceOfIns(uint256 insId) external view returns (uint256);

	/**
     * @dev Returns the owner of the `insId` token.
     *
     * Requirements:
     *
     * - `insId` must exist.
     */
    function ownerOf(uint256 insId) external view returns (address owner);

	/**
     * @dev Gives permission to `to` to transfer `insId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `insId` must exist.
     *
     * Emits an {ApprovalIns} event.
     */
    function approveIns(address to, uint256 insId) external returns (bool);

	/**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFromIns} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the address zero.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool approved) external;

	/**
     * @dev Returns the account approved for `insId` token.
     *
     * Requirements:
     *
     * - `insId` must exist.
     */
    function getApproved(uint256 insId) external view returns (address operator);

	/**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

	/**
     * @dev Transfers `insId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving inscription
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `insId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approveIns} or {setApprovalForAll}.
     *
     * Emits a {TransferIns} event.
     */
    function transferInsFrom(address from, address to, uint256 insId) external;

    /**
     * @dev Transfers `amount` FTs from inscription `from` to address `to`.
     *
     * Requirements:
     *
     * - msg.sender MUST be the owner of inscription `from`.
     * - `to` cannot be the zero address.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {TransferInsToIns} event.
     */
    function transferFTIns(uint256 from, address to, uint256 amount) external returns (bool);

    /**
     * @dev Moves a `value` amount of FTs from inscription `from` to address `to`
     *
     * Requirements:
     *
     * - If the caller is not the owner of inscription `from`, it must have been allowed to move this inscription by either {approveIns} or {setApprovalForAll}.
     * - `to` cannot be the zero address.
     *
     * Emits a {TransferInsToIns} event.
     */
    function transferFTInsFrom(uint256 from, address to, uint256 amount) external returns (bool);

    /**
     * @dev Safely transfers `insId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC7583 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `insId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approveIns} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC7583Receiver-onERC7583Received}, which is called upon
     *   a safe transfer.
     *
     * Emits a {TransferIns} event.
     */
    function safeTransferFrom(address from, address to, uint256 insId) external;
}