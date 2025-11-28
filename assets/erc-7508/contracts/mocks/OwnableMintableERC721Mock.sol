// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.21;

/// @dev This mock smart contract is intended to be used with `@defi-wonderland/smock` and doesn't need any business
///  logic.
contract OwnableMintableERC721Mock {
    address private _mockOwner;
    address private _mockOwnerOf;

    constructor(address mockOwner, address mockOwnerOf) {
        _mockOwner = mockOwner;
        _mockOwnerOf = mockOwnerOf;
    }

    function owner() public view returns (address) {
        return _mockOwner;
    }

    function ownerOf(uint256) public view returns (address) {
        return _mockOwnerOf;
    }
}
