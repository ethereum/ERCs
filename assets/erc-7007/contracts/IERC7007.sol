// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @dev Required interface of an ERC7007 compliant contract.
 */
interface IERC7007 is IERC165, IERC721 {
    /**
     * @dev Emitted when `tokenId` token is minted.
     */
    event Mint(
        address indexed to,
        uint256 indexed tokenId,
        bytes indexed prompt,
        bytes aigcData,
        string uri,
        bytes proof
    );

    /**
     * @dev Mint token at `tokenId` given `to`, `prompt`, `aigcData`, `uri` and `proof`. `proof` means that we input the ZK proof when using zkML and byte zero when using opML as the verification method.
     *
     * Requirements:
     * - `tokenId` must not exist.'
     * - verify(`prompt`, `aigcData`, `proof`) must return true.
     *
     * Optional:
     * - `proof` should not include `aigcData` to save gas.
     */
    function mint(
        address to,
        bytes calldata prompt,
        bytes calldata aigcData,
        string calldata uri,
        bytes calldata proof
    ) external returns (uint256 tokenId);

    /**
     * @dev Verify the `prompt`, `aigcData` and `proof`.
     */
    function verify(
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata proof
    ) external view returns (bool success);
}
