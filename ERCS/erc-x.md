---
eip: x
title: Contract wallet management nft
description: Designed for all nft
author: Xiang (@wenzhenxiang), Ben77 (@ben2077), Mingshi S. (@newnewsms)
discussions-to: https://ethereum-magicians.org/t/erc-draft-contract-wallet-management-nft/16702
status: Draft
type: Standards Track
category: ERC
created: 2023-11-21
requires: 
---

## Abstract

A proposal to manage nft by the user's smart contract wallet, which provides a new way to manage assets, utilizes the programmability of the smart contract wallet, and also provides more playability.

## Motivation

EOA wallet has no state and code storage, and the smart contract wallet is different.

AA is a direction of the smart contract wallet, which works around abstract accounts.

The smart contract wallet allows the user’s own account to have state and code, bringing programmability to the wallet. We think there are more directions to expand. For example, NFT asset management, functional expansion of NFT transactions, etc.



## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.


```solidity
// SPDX-License-Identifier: GPL-3.0


/// @title ERC-X
/// @dev See https://eips.ethereum.org/EIPS/eip-x
pragma solidity ^0.8.20;

interface IERCX{

    /**
     * @notice Used to notify listeners that owner has granted approval to the user to manage one nft.
     * @param _asset Address of the nft
     * @param _owner Address of the account that has granted the approval for nft‘s assets
     * @param _operator Address of the operator
     * @param _tokenId The unique identifier of the NFT
     */
    event NftApproval(
        address indexed _asset,
        address indexed _owner, 
        address indexed _operator, 
        uint256 _tokenId
    );

    /**
     * @notice Used to notify listeners that owner has granted approval to the operator to manage all nft of one asset contract.
     * @param _asset Address of the nft
     * @param _owner Address of the account that has granted the approval for nft‘s assets
     * @param _operator Address of the operator
     * @param _approved approve all nft of one asset contract
     */
    event NftApprovalForOneAll(
        address indexed _asset,
        address indexed _owner, 
        address indexed _operator,
        bool _approved
    );

    /**
     * @notice Used to notify listeners that owner has granted approval to the operator to manage all nft .
     * @param _owner Address of the account that has granted the approval for nft‘s assets
     * @param _operator Address of the operator
     * @param _approved approve all nft
     */
    event NftApprovalForAllAll(
        address indexed _owner, 
        address indexed _operator,
        bool _approved
    );

    /**
     * @notice Approve nft
     * @dev Allows operator address to withdraw from your wallet one nft.
     * @dev Emits an {nftApproval} event.
     * @param _asset Address of the nft
     * @param _operator Address of the operator
     * @param _tokenId The unique identifier of the NFT
     */
    function nftApprove(address _asset, address _operator, uint256 _tokenId) external;

   

    /**
     * @notice Approve all nft of one asset
     * @dev Allows operator address to withdraw from your wallet all nft.
     * @dev Emits an {nftApprovalForOneAll} event.
    * @param _asset Address of the nft
     * @param _operator Address of the operator
     * @param _approved Approved all nfts of one asset
     */
    function nftApproveForOneAll(address _asset, address _operator, bool _approved) external;


     /**
     * @notice Approve all nft
     * @dev Allows operator address to withdraw from your wallet all nft.
     * @dev Emits an {nftApprovalForAllAll} event.
     * @param _operator Address of the operator
     * @param _approved Approved all nfts
     */
    function nftApproveForAllAll(address _operator, bool _approved) external;

    /**
     * @notice read operator approved
     * @param _asset Address of the nft
     * @param _operator Address of the operator
     * @param _tokenId The unique identifier of the NFT
     * @return _approved Whether to approved operator one nft
     */
    function nftGetApproved(address _asset, address _operator, uint256 _tokenId) 
        external
        view
        returns (bool _approved);

    /**
     * @notice read operator approved
     * @param _asset Address of the nft
     * @param _operator Address of the operator
     * @return _approved Whether to approved operator all nfts of this one asset
     */
    function nftIsApproveForOneAll(address _asset, address _operator) 
        external
        view
        returns (bool _approved);

    /**
     * @notice read operator approved
     * @param _operator Address of the operator
     * @return _approved Whether to approved operator all nfts
     */
    function nftIsApproveForAllAll(address _operator) 
        external
        view
        returns (bool _approved);

    /**
     * @notice Transfer nft
     * @dev must call nft asset transfer() inside the function
     * @dev If the caller is not wallet self, must verify the approve and update
     * @param _asset Address of the nft
     * @param _to Address of the receive
     * @param _tokenId The transaction amount
     * @return _success The bool value returns whether the transfer is successful
     */
    function nftTransfer(address _asset, address _to, uint256 _tokenId) 
        external 
        returns (bool _success); 


}
```


## Rationale

The proposal aims to achieve the following goals:

1. Assets are allocated and managed by the wallet itself or plugins. such as approve , which are configured by the user’s contract wallet, rather than controlled by the NFT asset contract, to avoid some existing [ERC-721](./erc-721) contract risks.

2. Add the nftTransfer function, the transaction initiated by the non-smart wallet itself or will verify the approves.

3. The user wallet itself supports approve. Add nftApprove,  nftGetApproved, Used to approve specify one asset under the nft contract.

4. add nftSetApprovalForOneAlll, nftIsApprovedForOneAll, Used to approve specify all assets under the nft contract.

5. add nftSetApprovalForAllAlllfunctions, nftIsApprovedForAllAll, Used approve for assets under all nft contracts.

6. The users can choose to add hook function before and after their nftTransfer to increase the user’s more playability

7. The user can choose to implement the nftReceive function




## Security Considerations

No security considerations were found.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
