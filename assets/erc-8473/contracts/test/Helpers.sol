// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from 'forge-std/Test.sol';

/// @notice Shared test helpers
abstract contract Helpers is Test {
  /**
   * @notice A labelled address with code, so calls to it reach `vm.mockCall` and pass code-length checks
   * @param _label The label
   * @return _contract The address
   */
  function _mockContract(
    string memory _label
  ) internal returns (address _contract) {
    _contract = makeAddr(_label);
    vm.etch(_contract, hex'01');
  }

  /**
   * @notice Sorts a short list of addresses in ascending order, in place
   * @param _accounts The addresses
   * @return _sorted The same array, ascending
   */
  function _ascending(
    address[] memory _accounts
  ) internal pure returns (address[] memory _sorted) {
    for (uint256 _i = 1; _i < _accounts.length; ++_i) {
      for (uint256 _j = _i; _j > 0 && _accounts[_j - 1] > _accounts[_j]; --_j) {
        (_accounts[_j - 1], _accounts[_j]) = (_accounts[_j], _accounts[_j - 1]);
      }
    }
    _sorted = _accounts;
  }
}
