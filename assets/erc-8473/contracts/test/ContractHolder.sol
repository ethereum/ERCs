// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC1271} from '@openzeppelin/contracts/interfaces/IERC1271.sol';

/// @notice A contract wallet that holds tokens: it answers ERC-1271 for the digests it approved, or reverts when told to
contract ContractHolder is IERC1271 {
  error ContractHolder_Failure();

  mapping(bytes32 _hash => bool _approved) public approved;
  bool public reverts;

  function approve(
    bytes32 _hash
  ) external {
    approved[_hash] = true;
  }

  function setReverts(
    bool _reverts
  ) external {
    reverts = _reverts;
  }

  function isValidSignature(
    bytes32 _hash,
    bytes memory
  ) external view returns (bytes4 _magicValue) {
    if (reverts) revert ContractHolder_Failure();
    if (approved[_hash]) _magicValue = IERC1271.isValidSignature.selector;
  }
}
