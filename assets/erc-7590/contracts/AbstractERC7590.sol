// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.8.21;

import "./IERC7590.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error InvalidValue();
error InvalidAddress();
error InsufficientBalance();

abstract contract AbstractERC7590 is IERC7590 {
    mapping(uint256 tokenId => mapping(address erc20Address => uint256 balance))
        private _balances;
    mapping(uint256 tokenHolderId => uint256 nonce)
        private _erc20TransferOutNonce;

    /**
     * @inheritdoc IERC7590
     */
    function balanceOfERC20(
        address erc20Contract,
        uint256 tokenId
    ) external view returns (uint256) {
        return _balances[tokenId][erc20Contract];
    }

    /**
     * @notice Transfer ERC-20 tokens from a specific token
     * @dev The balance MUST be transferred from this smart contract.
     * @dev Implementers should validate that the `msg.sender` is either the token owner or approved to manage it before calling this.
     * @param erc20Contract The ERC-20 contract
     * @param tokenId The token to transfer from
     * @param amount The number of ERC-20 tokens to transfer
     * @param data Additional data with no specified format, to allow for custom logic
     */
    function _transferHeldERC20FromToken(
        address erc20Contract,
        uint256 tokenId,
        address to,
        uint256 amount,
        bytes memory data
    ) internal {
        if (amount == 0) {
            revert InvalidValue();
        }
        if (to == address(0) || erc20Contract == address(0)) {
            revert InvalidAddress();
        }
        if (_balances[tokenId][erc20Contract] < amount) {
            revert InsufficientBalance();
        }
        _beforeTransferHeldERC20FromToken(
            erc20Contract,
            tokenId,
            to,
            amount,
            data
        );
        _balances[tokenId][erc20Contract] -= amount;
        _erc20TransferOutNonce[tokenId]++;

        IERC20(erc20Contract).transfer(to, amount);

        emit TransferredERC20(erc20Contract, tokenId, to, amount);
        _afterTransferHeldERC20FromToken(
            erc20Contract,
            tokenId,
            to,
            amount,
            data
        );
    }

    /**
     * @inheritdoc IERC7590
     */
    function transferERC20ToToken(
        address erc20Contract,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) external {
        if (amount == 0) {
            revert InvalidValue();
        }
        if (erc20Contract == address(0)) {
            revert InvalidAddress();
        }
        _beforeTransferERC20ToToken(
            erc20Contract,
            tokenId,
            msg.sender,
            amount,
            data
        );
        IERC20(erc20Contract).transferFrom(msg.sender, address(this), amount);
        _balances[tokenId][erc20Contract] += amount;

        emit ReceivedERC20(erc20Contract, tokenId, msg.sender, amount);
        _afterTransferERC20ToToken(
            erc20Contract,
            tokenId,
            msg.sender,
            amount,
            data
        );
    }

    /**
     * @inheritdoc IERC7590
     */
    function erc20TransferOutNonce(
        uint256 tokenId
    ) external view returns (uint256) {
        return _erc20TransferOutNonce[tokenId];
    }

    /**
     * @notice Hook that is called before any transfer of ERC-20 tokens from a token
     * @param erc20Contract The ERC-20 contract
     * @param tokenId The token to transfer from
     * @param to The address to send the ERC-20 tokens to
     * @param amount The number of ERC-20 tokens to transfer
     * @param data Additional data with no specified format, to allow for custom logic
     */
    function _beforeTransferHeldERC20FromToken(
        address erc20Contract,
        uint256 tokenId,
        address to,
        uint256 amount,
        bytes memory data
    ) internal virtual {}

    /**
     * @notice Hook that is called after any transfer of ERC-20 tokens from a token
     * @param erc20Contract The ERC-20 contract
     * @param tokenId The token to transfer from
     * @param to The address to send the ERC-20 tokens to
     * @param amount The number of ERC-20 tokens to transfer
     * @param data Additional data with no specified format, to allow for custom logic
     */
    function _afterTransferHeldERC20FromToken(
        address erc20Contract,
        uint256 tokenId,
        address to,
        uint256 amount,
        bytes memory data
    ) internal virtual {}

    /**
     * @notice Hook that is called before any transfer of ERC-20 tokens to a token
     * @param erc20Contract The ERC-20 contract
     * @param tokenId The token to transfer from
     * @param from The address to send the ERC-20 tokens from
     * @param amount The number of ERC-20 tokens to transfer
     * @param data Additional data with no specified format, to allow for custom logic
     */
    function _beforeTransferERC20ToToken(
        address erc20Contract,
        uint256 tokenId,
        address from,
        uint256 amount,
        bytes memory data
    ) internal virtual {}

    /**
     * @notice Hook that is called after any transfer of ERC-20 tokens to a token
     * @param erc20Contract The ERC-20 contract
     * @param tokenId The token to transfer from
     * @param from The address to send the ERC-20 tokens from
     * @param amount The number of ERC-20 tokens to transfer
     * @param data Additional data with no specified format, to allow for custom logic
     */
    function _afterTransferERC20ToToken(
        address erc20Contract,
        uint256 tokenId,
        address from,
        uint256 amount,
        bytes memory data
    ) internal virtual {}

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return type(IERC7590).interfaceId == interfaceId;
    }
}
