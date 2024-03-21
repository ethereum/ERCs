// SPDX-License-Identifier: Apache License 2.0

pragma solidity ^0.8.20;

// import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title EIP-721 Guarantor Role extension
///  Note: the EIP-165 identifier for this interface is


interface IEIP721Guarantee /*is IERC721*/{
    /// @notice           Emitted when `guarantee contract` is established for an NFT
    /// @param user       address of  guarantor
    /// @param value      The guarantee value provided by dao
    /// @param DAO        DAO organization providing guarantee
    /// @param tokenId    Guaranteed NFT (token ID),
    event GuaranteeIsEstablshed(
        address user,
        uint256 value,
        address DAO,
        uint256 indexed tokenId
    );

    /// @notice           Emitted when `guarantee contract` is canceled
    /// @dev              Some users in the closed DAO request a reduction in their guarantee share
    /// @param user       address of  guarantor
    /// @param value      The guarantee value provided by dao
    /// @param DAO        DAO organization providing guarantee
    /// @param tokenId    Guaranteed NFT (token ID),
    event GuaranteeIsCancel(
        address user,
        uint256 value,
        address DAO,
        uint256 indexed tokenId
    );

    /// @notice           Emitted when `Guarantee sequence` is established for an NFT
    /// @param userGuaranteed      address of guaranteed
    /// @param number  block.number of transaction,
    ///                and all DAOs established before this point will enter the guarantee sequence
    /// @param DAOs   DAO sequence providing guarantee
    /// @param tokenId Guaranteed NFT (token ID),
    event GuaranteeSequenceIsEstablshed(
        address userGuaranteed,
        uint256 number,
        address DAOs,
        uint256 indexed tokenId
    );

    /// @notice   A user's evaluation for an NFT (token ID)
    /// @dev      Set the guarantee information for one guarantor,
    /// Throws if `_tokenId` is not a valid NFT
    /// @param value  user's evaluation for  an NFT, the oledr value is canceled,
    /// @param user   address of guarantor
    /// @param weight guarantee weight for guarantor
    /// @param tokenId The NFT
    /// @return the error status of function execution
    function setNFTGuarantedInfo(
        uint256 value,
        address user,
        uint256 weight,
        uint256 tokenId
    ) external returns (uint256);

    /// @notice   Establish guarantee sequence for an NFT (token ID) and split the commission
    /// @dev      Each NFT(token ID) retains a current guarantee sequence,
    ///           and expired guarantee sequences are no longer valid,
    ///           Throws if `_tokenId` is not a valid NFT
    /// @param valueCommission Commission for a transactions
    /// @param userGuaranteed   address of guaranteed
    /// @param number  block.number of transaction,
    ///              and all DAOs established before this point will enter the guarantee sequence
    /// @param tokenId The NFT
    /// @return the error status of function execution
    function establishNFTGuarantee(
        uint256 valueCommission,
        address userGuaranteed,
        uint256 number,
        uint256 tokenId
    ) external returns (uint256);

    /// @notice   Transactions that fulfill the guarantee responsibility
    /// @dev      The new accountability transaction also requires
    ///           the construction of a new guarantee sequence
    ///           Throws if `_tokenId` is not a valid NFT or userGuaranteed is not right

    /// @param  userGuaranteed   address of guaranteed
    /// @param  tokenId The NFT
    /// @return the error status of function execution
    function FulfillGuaranteeTransfer(address userGuaranteed, uint256 tokenId)
        external
        returns (uint256);
}
